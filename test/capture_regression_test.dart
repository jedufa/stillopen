import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/controller.dart';

// Regressions converted from the frozen user-impact audit.
class CaptureStore implements StillOpenStore {
  final values = <String, String>{};
  bool failNextWrite = false;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const FileSystemException('Synthetic storage failure');
    }
    values[key] = value;
  }
}

void main() {
  test('CAP-01 failed share save can be retried in the same session', () async {
    final store = CaptureStore();
    final controller = StillOpenController(store: store);
    addTearDown(controller.dispose);
    await controller.load();
    store.failNextWrite = true;
    await expectLater(
      controller.addSharedContent(text: 'Synthetic retryable loose end'),
      throwsA(isA<FileSystemException>()),
    );
    final retry = await controller.addSharedContent(
      text: 'Synthetic retryable loose end',
    );
    expect(
      retry,
      isTrue,
      reason: 'A failed save must not poison deduplication.',
    );
    final restarted = StillOpenController(store: store);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.items, hasLength(1));
  });

  test(
    'CAP-02 unavailable shared file is not reported as fully saved',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'stillopen-audit-missing-',
      );
      addTearDown(() => root.delete(recursive: true));
      final controller = StillOpenController(
        store: CaptureStore(),
        attachmentDirectoryProvider: () async =>
            Directory('${root.path}/local'),
      );
      addTearDown(controller.dispose);
      await controller.load();
      final saved = await controller.addSharedContent(
        files: [
          IncomingSharedFile(
            path: '${root.path}/missing.pdf',
            name: 'Synthetic missing.pdf',
          ),
        ],
      );
      expect(saved, isFalse);
      expect(controller.items, isEmpty);
      expect(controller.attachments, isEmpty);
      expect(
        controller.snackbarMessage,
        'Could not save shared file locally',
        reason: 'The only source file is absent; capture must expose the gap.',
      );
    },
  );

  test(
    'CAP-03 overlapping file shares retain distinct items and bytes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'stillopen-audit-concurrent-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = File('${root.path}/one.txt')
        ..writeAsStringSync('source one');
      final second = File('${root.path}/two.txt')
        ..writeAsStringSync('source two');
      final controller = StillOpenController(
        store: CaptureStore(),
        attachmentDirectoryProvider: () async =>
            Directory('${root.path}/local'),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await Future.wait([
        controller.addSharedContent(
          text: 'Synthetic first share',
          files: [IncomingSharedFile(path: first.path, name: 'document.txt')],
        ),
        controller.addSharedContent(
          text: 'Synthetic second share',
          files: [IncomingSharedFile(path: second.path, name: 'document.txt')],
        ),
      ]);
      expect(controller.items, hasLength(2));
      expect(
        controller.items.map((item) => item.id).toSet(),
        hasLength(2),
        reason: 'Overlapping capture must allocate unique item identities.',
      );
      expect(
        controller.attachments.map((attachment) => attachment.id).toSet(),
        hasLength(2),
      );
      expect(
        controller.attachments
            .map((attachment) => File(attachment.uri).readAsStringSync())
            .toSet(),
        {'source one', 'source two'},
      );
    },
  );

  test(
    'CAP-CONTROL 1000 synthetic items survive export and fresh import',
    () async {
      final controller = StillOpenController(store: CaptureStore());
      addTearDown(controller.dispose);
      await controller.load();
      final input = jsonEncode({
        'schema_version': 'stillopen_backup_v1',
        'items': List.generate(
          1000,
          (index) => {
            'id': index + 1,
            'title': 'Synthetic loose end $index',
            'state': 'open',
            'notes': 'Synthetic context $index',
          },
        ),
      });
      final clock = Stopwatch()..start();
      await controller.importBackupJson(input);
      final backup = controller.exportBackupJson();
      final imported = StillOpenController(store: CaptureStore());
      addTearDown(imported.dispose);
      await imported.load();
      await imported.importBackupJson(backup);
      clock.stop();
      expect(imported.items, hasLength(1000));
      expect(imported.items.map((item) => item.title).toSet(), hasLength(1000));
      // Host timing is diagnostic evidence, not a phone performance guarantee.
      // ignore: avoid_print
      print(
        'AUDIT_HOST_TIMING 1000-item import/export/import: ${clock.elapsedMilliseconds} ms; ${backup.length} JSON characters',
      );
    },
  );
}
