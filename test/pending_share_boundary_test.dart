import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/incoming_share/incoming_share_ingestor.dart';
import 'package:stillopen/src/incoming_share/ios_pending_share_store.dart';

import 'support/contract_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late Directory queueRoot;
  setUp(() {
    sandbox = Directory.systemTemp.createTempSync(
      'stillopen-pending-contract-',
    );
    queueRoot = Directory('${sandbox.path}/queue')..createSync();
    Directory('${queueRoot.path}/pending_shares').createSync();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    sandbox.deleteSync(recursive: true);
  });

  File manifest(String filePath) =>
      File('${queueRoot.path}/pending_shares/event.json')..writeAsStringSync(
        jsonEncode({
          'schema_version': 'stillopen_pending_share_v1',
          'id': 'event',
          'createdAt': 1,
          'source': 'iosShareExtension',
          'text': 'Synthetic pending capture',
          'files': [
            {
              'path': filePath,
              'originalName': 'proof.pdf',
              'mimeType': 'application/pdf',
              'available': true,
            },
          ],
        }),
      );

  test(
    'QUEUE-01 acknowledgement happens only after durable item and copied proof exist',
    () async {
      final source = File('${queueRoot.path}/proof.pdf')
        ..writeAsStringSync('synthetic proof');
      final pending = manifest(source.path);
      final store = _GatedStore();
      final controller = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async =>
            Directory('${sandbox.path}/app-proofs'),
      );
      addTearDown(controller.dispose);
      await controller.load();
      final ingestor = IncomingShareIngestor(
        controller: controller,
        store: DirectoryPendingShareStore(queueRoot),
      );
      final ingest = ingestor.ingestPendingShares();
      await store.writeStarted.future;
      expect(source.existsSync(), isTrue);
      expect(pending.existsSync(), isTrue);
      expect(await ingestor.ingestPendingShares(), 0);
      store.release.complete();
      expect(await ingest, 1);
      expect(pending.existsSync(), isFalse);
      expect(source.existsSync(), isFalse);
      final restarted = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async =>
            Directory('${sandbox.path}/app-proofs'),
      );
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.items.single.title, 'Synthetic pending capture');
      expect(
        File(restarted.attachments.single.uri).readAsStringSync(),
        'synthetic proof',
      );
    },
  );

  for (final escape in ['traversal', 'symlink']) {
    test(
      'QUEUE-02 $escape cannot make acknowledgement delete outside the queue',
      () async {
        final outside = File('${sandbox.path}/outside.pdf')
          ..writeAsStringSync('must survive');
        final path = escape == 'traversal'
            ? '${queueRoot.path}/../outside.pdf'
            : '${queueRoot.path}/linked.pdf';
        if (escape == 'symlink') Link(path).createSync(outside.path);
        manifest(path);
        final store = DirectoryPendingShareStore(queueRoot);
        await store.markProcessed((await store.listPendingManifests()).single);
        expect(outside.readAsStringSync(), 'must survive');
      },
    );
  }

  test(
    'QUEUE-03 iOS channel missing group, native failure and valid path remain distinct',
    () async {
      const channel = MethodChannel('stillopen/ios_pending_shares');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await MethodChannelPendingShareStore.create(), isNull);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      Object? response;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getAppGroupPendingShareDirectory');
        if (response is Exception) throw response;
        return response;
      });
      expect(await MethodChannelPendingShareStore.create(), isNull);
      response = '  ';
      expect(await MethodChannelPendingShareStore.create(), isNull);
      response = PlatformException(code: 'group_unavailable');
      await expectLater(
        MethodChannelPendingShareStore.create(),
        throwsA(isA<PlatformException>()),
      );
      response = queueRoot.path;
      final store = await MethodChannelPendingShareStore.create();
      expect(store!.directory.path, queueRoot.path);
    },
  );
}

class _GatedStore extends MemoryContractStore {
  final writeStarted = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> setString(String key, String value) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await release.future;
    await super.setString(key, value);
  }
}
