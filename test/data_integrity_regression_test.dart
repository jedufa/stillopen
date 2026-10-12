// Regressions converted from the frozen user-impact audit.
import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/models.dart';

const _snapshotKey = 'stillopen_snapshot_v2';

void main() {
  late Directory sandbox;
  late Directory attachmentDirectory;
  late _FailingStore store;
  late StillOpenController controller;

  setUp(() async {
    sandbox = Directory.systemTemp.createTempSync('stillopen-data-audit-');
    attachmentDirectory = Directory('${sandbox.path}/attachments');
    store = _FailingStore();
    controller = StillOpenController(
      store: store,
      attachmentDirectoryProvider: () async => attachmentDirectory,
    );
    await controller.load();
    await controller.quickAdd(title: 'Existing local responsibility');
  });

  tearDown(() {
    controller.dispose();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test(
    'DATA-01 failed second write must not persist a partial import',
    () async {
      final priorItems = store.values[_snapshotKey];
      store.failNextKey = _snapshotKey;
      await expectLater(
        controller.importBackupJson(
          _backup(
            items: [_item(30, 'Imported item with proof')],
            attachments: [_attachment(40, 30, content: 'import proof')],
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );

      final restarted = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async => attachmentDirectory,
      );
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.attachments, isEmpty);
      expect(
        store.values[_snapshotKey],
        priorItems,
        reason:
            'A failed import must preserve the previously committed graph. '
            'The imported item currently survives restart without its proof.',
      );
    },
  );

  test(
    'DATA-02 failed replacement must preserve old attachment bytes',
    () async {
      final source = File('${sandbox.path}/original.txt')
        ..writeAsStringSync('only recoverable original proof');
      await controller.addAttachment(
        item: controller.items.single,
        uri: source.path,
        label: 'Original proof',
        sourceType: SourceType.pdf,
      );
      final originalLocalFile = File(controller.attachments.single.uri);
      source.deleteSync();
      final priorItems = store.values[_snapshotKey];
      store.failNextKey = _snapshotKey;

      await expectLater(
        controller.importBackupJson(
          _backup(items: [_item(20, 'Replacement')]),
          replace: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.values[_snapshotKey], priorItems);
      final restarted = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async => attachmentDirectory,
      );
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.items.single.title, 'Existing local responsibility');
      expect(restarted.attachments.single.uri, originalLocalFile.path);
      expect(
        originalLocalFile.existsSync(),
        isTrue,
        reason:
            'Replacement failed before even the item write, but the old '
            'durable attachment record now points to a deleted file.',
      );
    },
  );

  test('DATA-01 concurrent queued saves abort after a failed write', () async {
    final delayed = _BlockingFailStore();
    final worker = StillOpenController(store: delayed);
    addTearDown(worker.dispose);
    await worker.load();
    final first = worker.quickAdd(title: 'First pending item');
    await delayed.entered.future;
    final second = worker.quickAdd(title: 'Second pending item');
    final firstAssertion = expectLater(
      first,
      throwsA(isA<FileSystemException>()),
    );
    final secondAssertion = expectLater(second, throwsA(isA<StateError>()));
    delayed.release.complete();
    await Future.wait([firstAssertion, secondAssertion]);
    expect(worker.items, isEmpty);
    expect(delayed.values, isEmpty);
  });

  test(
    'DATA-03 unrelated JSON object must not erase data on replace',
    () async {
      Object? error;
      try {
        await controller.importBackupJson('{}', replace: true);
      } on Object catch (caught) {
        error = caught;
      }
      expect(
        controller.items.map((item) => item.title),
        ['Existing local responsibility'],
        reason:
            'An object with no item list or backup schema is not a valid '
            'empty backup and must be rejected before replacing local data.',
      );
      expect(error, isA<FormatException>());
    },
  );

  test(
    'DATA-04 orphan import must not attach proof to an existing item',
    () async {
      final localItemId = controller.items.single.id;
      try {
        await controller.importBackupJson(
          _backup(
            items: [_item(50, 'Imported responsibility')],
            attachments: [
              _attachment(60, localItemId, content: 'unrelated imported proof'),
            ],
          ),
        );
      } on FormatException {
        // Rejecting the invalid association is a valid safe outcome.
      }
      controller.openDetails(localItemId);
      expect(
        controller.selectedDetails!.attachments,
        isEmpty,
        reason:
            'An attachment whose owner is absent from the backup must not '
            'fall back to an unrelated pre-existing local item ID.',
      );
    },
  );

  test(
    'DATA-05 duplicate source IDs must not collide in merge output',
    () async {
      try {
        await controller.importBackupJson(
          _backup(
            items: [
              _item(7, 'Duplicate A'),
              _item(7, 'Duplicate B'),
              _item(8, 'Distinct C'),
            ],
          ),
        );
      } on FormatException {
        // Rejecting ambiguous identity before import is also correct.
      }
      expect(
        controller.items.map((item) => item.id).toSet().length,
        controller.items.length,
        reason:
            'Distinct imported rows must never share an internal item ID; '
            'opening, editing, and deleting are all keyed by that identity.',
      );
    },
  );

  test('DATA-05 duplicate replacement IDs must not delete two items', () async {
    try {
      await controller.importBackupJson(
        _backup(items: [_item(7, 'First'), _item(7, 'Second')]),
        replace: true,
      );
    } on FormatException {
      return;
    }
    final countBeforeDelete = controller.items.length;
    await controller.deleteItem(controller.items.first);
    expect(
      controller.items.length,
      countBeforeDelete - 1,
      reason:
          'Deleting the selected responsibility must not also delete '
          'another row accepted with the same imported ID.',
    );
  });

  test(
    'DATA-CONTROL locally copied proof survives source deletion and reload',
    () async {
      final source = File('${sandbox.path}/source.txt')
        ..writeAsStringSync('original proof bytes');
      await controller.addAttachment(
        item: controller.items.single,
        uri: source.path,
        label: 'Evidence',
        sourceType: SourceType.pdf,
      );
      final copiedPath = controller.attachments.single.uri;
      expect(copiedPath, isNot(source.path));
      source.deleteSync();
      final restarted = StillOpenController(
        store: store,
        attachmentDirectoryProvider: () async => attachmentDirectory,
      );
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(
        File(restarted.attachments.single.uri).readAsStringSync(),
        'original proof bytes',
      );
      final exported = jsonDecode(restarted.exportBackupJson()) as Map;
      final exportedAttachment =
          (exported['attachments'] as List).single as Map;
      expect(
        utf8.decode(
          base64Decode(exportedAttachment['contentBase64'] as String),
        ),
        'original proof bytes',
      );
    },
  );
}

Map<String, Object?> _item(int id, String title) => StillOpenItem(
  id: id,
  title: title,
  state: ItemState.open,
  category: Category.other,
).toJson();

Map<String, Object?> _attachment(
  int id,
  int itemId, {
  required String content,
}) =>
    ItemAttachment(
        id: id,
        itemId: itemId,
        uri: 'foreign-device-proof.txt',
        label: 'Proof',
        sourceType: SourceType.pdf,
      ).toJson()
      ..['fileName'] = 'proof.txt'
      ..['contentBase64'] = base64Encode(utf8.encode(content));

String _backup({
  required List<Map<String, Object?>> items,
  List<Map<String, Object?>> attachments = const [],
}) => jsonEncode({
  'schema_version': 'stillopen_backup_v1',
  'items': items,
  'attachments': attachments,
});

class _FailingStore implements StillOpenStore {
  final values = <String, String>{};
  String? failNextKey;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    if (key == failNextKey) {
      failNextKey = null;
      throw FileSystemException('Injected storage exhaustion before $key');
    }
    values[key] = value;
  }
}

class _BlockingFailStore implements StillOpenStore {
  final values = <String, String>{};
  final entered = Completer<void>();
  final release = Completer<void>();
  bool _failed = false;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    if (!_failed) {
      _failed = true;
      entered.complete();
      await release.future;
      throw const FileSystemException('Synthetic interrupted first save');
    }
    values[key] = value;
  }
}
