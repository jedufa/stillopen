import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/attachment_paths.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/models.dart';

import 'support/contract_fakes.dart';

void main() {
  late Directory sandbox;
  setUp(
    () =>
        sandbox = Directory.systemTemp.createTempSync('stillopen-relocation-'),
  );
  tearDown(() => sandbox.deleteSync(recursive: true));

  test(
    'STORE-06 canonical proof references survive full container relocation and rollback',
    () async {
      final store = MemoryContractStore();
      var container = Directory('${sandbox.path}/original-container')
        ..createSync();
      Directory proofs() => Directory('${container.path}/attachments');
      var controller = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async => proofs(),
      );
      await controller.load();
      await controller.importBackupJson(
        File('test/fixtures/portable_backup_v1.json').readAsStringSync(),
      );
      final before = jsonDecode(store.values['stillopen_snapshot_v2']!) as Map;
      final locator = (before['attachments'] as List).single as Map;
      expect(locator['localPath'], isA<String>());
      expect((locator['localPath'] as String).startsWith('/'), isFalse);
      final oldPath = controller.attachments.single.uri;
      controller.dispose();
      container = container.renameSync('${sandbox.path}/relocated-container');
      expect(File(oldPath).existsSync(), isFalse);
      controller = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async => proofs(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(
        File(controller.attachments.single.uri).readAsStringSync(),
        'proof A\n',
      );
      store.failNextWrite = true;
      await expectLater(
        controller.renameItem(controller.items.single, 'Uncommitted'),
        throwsA(isA<FileSystemException>()),
      );
      expect(controller.items.single.title, 'Historical annual check');
      expect(
        File(controller.attachments.single.uri).readAsStringSync(),
        'proof A\n',
      );
      final backup = jsonDecode(controller.exportBackupJson()) as Map;
      expect(
        ((backup['attachments'] as List).single as Map)['contentBase64'],
        'cHJvb2YgQQo=',
      );
      await controller.deleteAttachment(controller.attachments.single);
      expect(proofs().listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );

  test(
    'STORE-07 legacy iOS absolute proof is recovered only from its exact current relative location',
    () async {
      final proofs = Directory('${sandbox.path}/attachments')..createSync();
      final proof = File('${proofs.path}/historical.txt')
        ..writeAsStringSync('proof A\n');
      const old =
          '/var/mobile/Containers/Data/Application/OLD-CONTAINER/Documents/attachments/historical.txt';
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/legacy_split_v1.json',
                ).readAsStringSync().replaceAll('@LOCAL_PROOF@', old),
              )
              as Map;
      final store = MemoryContractStore();
      for (final section in ['items', 'attachments', 'settings']) {
        store.values['stillopen_${section}_v1'] = jsonEncode(fixture[section]);
      }
      final controller = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async => proofs,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.attachments.single.uri, proof.path);
      await controller.renameItem(
        controller.items.single,
        'Recovered existing proof',
      );
      final snapshot =
          jsonDecode(store.values['stillopen_snapshot_v2']!) as Map;
      expect(
        ((snapshot['attachments'] as List).single as Map)['localPath'],
        'historical.txt',
      );
      final paths = AttachmentPaths(proofs);
      final missing = ItemAttachment(
        id: 802,
        itemId: 501,
        uri: old.replaceFirst('historical.txt', 'missing.txt'),
        label: 'Missing',
        sourceType: SourceType.pdf,
      );
      expect(paths.decode(missing.toJson()).uri, missing.uri);
      final foreign = missing.copyWith(
        uri: '${sandbox.path}/foreign/historical.txt',
      );
      expect(
        paths.decode(foreign.toJson()).uri,
        foreign.uri,
        reason: 'Do not match arbitrary files by basename',
      );
    },
  );

  test(
    'STORE-08 invalid canonical paths cannot escape the attachment root or overwrite recovery bytes',
    () async {
      for (final invalid in [
        '',
        '../proof',
        '/absolute',
        'a/../../proof',
        'a//proof',
        './proof',
        'a\\proof',
        'C:/proof',
        'bad\u0000path',
        42,
      ]) {
        final store = MemoryContractStore();
        final raw = jsonEncode({
          'schema_version': 'stillopen_snapshot_v2',
          'items': [
            StillOpenItem(
              id: 1,
              title: 'Synthetic',
              state: ItemState.open,
              category: Category.other,
            ).toJson(),
          ],
          'attachments': [
            {
              'id': 1,
              'itemId': 1,
              'uri': '/old/proof',
              'localPath': invalid,
              'label': 'Proof',
              'sourceType': 'pdf',
            },
          ],
          'settings': <String, Object?>{},
        });
        store.values['stillopen_snapshot_v2'] = raw;
        final controller = StillOpenController(
          store: store,
          attachmentDirectoryProvider: () async => sandbox,
        );
        await expectLater(
          controller.load(),
          throwsFormatException,
          reason: '$invalid',
        );
        expect(controller.loaded, isFalse);
        expect(store.values['stillopen_snapshot_v2'], raw);
        controller.dispose();
      }
    },
  );

  test(
    'STORE-08 non-file references remain unchanged and local file URIs retain nested paths',
    () {
      final paths = AttachmentPaths(sandbox);
      final proof = File('${sandbox.path}/nested/proof with spaces.pdf');
      final item = ItemAttachment(
        id: 1,
        itemId: 1,
        uri: proof.uri.toString(),
        label: 'Synthetic proof',
        sourceType: SourceType.pdf,
      );
      final stored = paths.encode(item);
      expect(stored['localPath'], 'nested/proof with spaces.pdf');
      expect(paths.decode(stored).uri, proof.path);
      for (final uri in [
        'stillopen-note:example',
        'stillopen-metadata-only:1',
        'https://example.invalid/proof',
        'relative.pdf',
        'http://[invalid',
      ]) {
        final attachment = item.copyWith(uri: uri);
        expect(paths.encode(attachment).containsKey('localPath'), isFalse);
        expect(paths.decode(attachment.toJson()).uri, uri);
      }
    },
  );
}
