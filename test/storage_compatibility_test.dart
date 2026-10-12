import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/models.dart';

import 'support/contract_fakes.dart';

void main() {
  late Directory sandbox;
  late Directory attachments;
  late FileContractStore store;
  StillOpenController fresh() => StillOpenController(
    store: FileContractStore(store.directory),
    attachmentDirectoryProvider: () async => attachments,
  );
  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('stillopen-contract-');
    attachments = Directory('${sandbox.path}/attachments')..createSync();
    store = FileContractStore(Directory('${sandbox.path}/preferences'));
  });
  tearDown(() => sandbox.deleteSync(recursive: true));

  test(
    'STORE-01 legacy split records migrate with proof and settings intact',
    () async {
      final proof = File('${attachments.path}/historical.txt')
        ..writeAsStringSync('proof A\n');
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/legacy_split_v1.json',
                ).readAsStringSync().replaceAll('@LOCAL_PROOF@', proof.path),
              )
              as Map;
      for (final section in ['items', 'attachments', 'settings']) {
        await store.setString(
          'stillopen_${section}_v1',
          jsonEncode(fixture[section]),
        );
      }
      final controller = fresh();
      await controller.load();
      expect(controller.items.single.id, 501);
      expect(
        controller.items.single.reminderAt,
        DateTime(2027, 6, 4, 9, 5).millisecondsSinceEpoch,
      );
      expect(controller.themePreference, AppThemePreference.dark);
      expect(controller.notificationsEnabled, isFalse);
      expect(controller.defaultReminderMinute, 5);
      await controller.renameItem(
        controller.items.single,
        'Edited after upgrade',
      );
      controller.dispose();
      final restarted = fresh();
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.items.single.title, 'Edited after upgrade');
      expect(restarted.attachments.single.itemId, 501);
      expect(
        File(restarted.attachments.single.uri).readAsStringSync(),
        'proof A\n',
      );
      expect(restarted.themePreference, AppThemePreference.dark);
      expect(restarted.showTemplateShortcuts, isFalse);
    },
  );

  for (final replace in [false, true]) {
    test(
      'STORE-02 portable historical backup ${replace ? "replace" : "merge"} survives restart',
      () async {
        final controller = fresh();
        await controller.load();
        await controller.quickAdd(title: 'Existing responsibility');
        await controller.importBackupJson(
          File('test/fixtures/portable_backup_v1.json').readAsStringSync(),
          replace: replace,
        );
        controller.dispose();
        final restarted = fresh();
        addTearDown(restarted.dispose);
        await restarted.load();
        expect(restarted.items.length, replace ? 1 : 2);
        final imported = restarted.items.singleWhere(
          (i) => i.title == 'Historical annual check',
        );
        expect(imported.notes, 'Keep the original receipt');
        expect(restarted.attachments.single.itemId, imported.id);
        expect(
          File(restarted.attachments.single.uri).readAsBytesSync(),
          utf8.encode('proof A\n'),
        );
        expect(restarted.themePreference, AppThemePreference.dark);
        expect(restarted.notificationsEnabled, isFalse);
      },
    );
  }

  test(
    'STORE-03 second proof write failure preserves the old graph and removes staging',
    () async {
      final controller = fresh();
      addTearDown(controller.dispose);
      await controller.load();
      await controller.quickAdd(title: 'Only local original');
      final original = File('${sandbox.path}/original.txt')
        ..writeAsStringSync('original bytes');
      await controller.addAttachment(
        item: controller.items.single,
        uri: original.path,
        label: 'Proof',
        sourceType: SourceType.pdf,
      );
      original.deleteSync();
      final before = await store.getString('stillopen_snapshot_v2');
      final backup =
          jsonDecode(
                File(
                  'test/fixtures/portable_backup_v1.json',
                ).readAsStringSync(),
              )
              as Map;
      (backup['attachments'] as List).add({
        'id': 802,
        'itemId': 501,
        'uri': '/old/second',
        'label': 'Second proof',
        'sourceType': 'pdf',
        'contentBase64': 'cHJvb2YgQg==',
        'fileName': 'x' * 400,
      });
      await expectLater(
        controller.importBackupJson(jsonEncode(backup), replace: true),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.getString('stillopen_snapshot_v2'), before);
      final restarted = fresh();
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.items.single.title, 'Only local original');
      expect(
        File(restarted.attachments.single.uri).readAsStringSync(),
        'original bytes',
      );
      expect(attachments.listSync().whereType<Directory>(), isEmpty);
    },
  );

  test(
    'STORE-04 truncated snapshot is rejected without overwriting recoverable bytes',
    () async {
      const broken = '{"schema_version":"stillopen_snapshot_v2","items":[';
      await store.setString('stillopen_snapshot_v2', broken);
      final controller = fresh();
      addTearDown(controller.dispose);
      await expectLater(controller.load(), throwsFormatException);
      expect(controller.loaded, isFalse);
      expect(await store.getString('stillopen_snapshot_v2'), broken);
    },
  );

  test(
    'STORE-05 seeded edit lifecycle and failed-save sequence agrees after every restart',
    () async {
      final random = Random(27491);
      final expected = <int, (String, ItemState)>{};
      final controller = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async => attachments,
      );
      addTearDown(controller.dispose);
      await controller.load();
      for (var step = 0; step < 32; step++) {
        if (expected.isEmpty || random.nextBool()) {
          await controller.quickAdd(title: 'Synthetic responsibility $step');
          final item = controller.selectedItem!;
          expected[item.id] = (item.title, ItemState.open);
        } else {
          final id = expected.keys.elementAt(random.nextInt(expected.length));
          final item = controller.items.singleWhere((i) => i.id == id);
          if (step % 5 == 0) {
            store.failNextWrite = true;
            await expectLater(
              controller.renameItem(item, 'Uncommitted title'),
              throwsA(isA<FileSystemException>()),
            );
          } else if (step % 3 == 0) {
            await controller.deleteItem(item);
            expected.remove(id);
          } else if (item.state == ItemState.done) {
            await controller.reopen(item);
            expected[id] = (item.title, ItemState.open);
          } else {
            await controller.markDone(item);
            expected[id] = (item.title, ItemState.done);
          }
        }
        final restarted = fresh();
        await restarted.load();
        expect(
          {for (final i in restarted.items) i.id: (i.title, i.state)},
          expected,
          reason: 'Durable state after seed 27491 step $step',
        );
        expect({
          for (final i in controller.items) i.id: (i.title, i.state),
        }, expected);
        restarted.dispose();
      }
    },
  );
}
