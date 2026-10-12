import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/diagnostics.dart';
import 'package:stillopen/src/incoming_share/incoming_share_ingestor.dart';
import 'package:stillopen/src/incoming_share/ios_pending_share_store.dart';
import 'package:stillopen/src/models.dart';

void main() {
  test(
    'quick add infers category, opens tab, persists, and clears search',
    () async {
      final store = FakeStore();
      final controller = StillOpenController(store: store);
      await controller.load();
      controller.setQuery('homework');

      final saved = await controller.quickAdd(
        title: 'Refund return order',
        tomorrow: true,
        highPriority: true,
      );

      expect(saved, isTrue);
      expect(controller.items.first.title, 'Refund return order');
      expect(controller.items.first.category, Category.shopping);
      expect(controller.items.first.priority, Priority.high);
      expect(controller.items.first.dueText, 'Tomorrow');
      expect(controller.selectedTab, HomeTab.open);
      expect(controller.selectedItem?.title, 'Refund return order');
      expect(controller.query, isEmpty);
      expect(store.values, contains('stillopen_snapshot_v2'));
    },
  );

  test(
    'template creation selects detail and medical actions follow Android stages',
    () async {
      final controller = StillOpenController(store: FakeStore());
      await controller.load();

      await controller.createFromTemplate(TemplateType.medicalClaim);
      var item = controller.selectedItem!;
      expect(item.title, 'Doctor invoice');
      expect(item.templateType, TemplateType.medicalClaim);
      expect(item.claimStage, 'Plan booking appointment');
      expect(
        controller.selectedDetails!.steps.map((step) => step.title).first,
        'Invoice saved',
      );

      await controller.markMedicalAppointmentBooked(item);
      item = controller.selectedItem!;
      expect(item.state, ItemState.waiting);
      expect(item.claimStage, 'Waiting for appointment');
      expect(item.waitingOn, 'Appointment / provider');

      await controller.markMedicalAppointmentDone(item);
      item = controller.selectedItem!;
      expect(item.state, ItemState.open);
      expect(item.claimStage, 'Appointment done');

      await controller.markMedicalSubmitted(item);
      item = controller.selectedItem!;
      expect(item.state, ItemState.waiting);
      expect(item.claimStage, 'Waiting for insurance response');
      expect(item.waitingOn, 'Insurance');

      await controller.markMedicalResponseReceived(item);
      item = controller.selectedItem!;
      expect(item.state, ItemState.open);
      expect(item.claimStage, 'Response received');

      await controller.markMedicalReimbursed(item);
      item = controller.selectedItem!;
      expect(item.state, ItemState.done);
      expect(item.closureReason, ClosureReason.reimbursed);
      expect(controller.selectedTab, HomeTab.done);
    },
  );

  test(
    'general lifecycle actions move open draft done and preserve details',
    () async {
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      await controller.quickAdd(title: 'Call school office');
      final item = controller.items.first;
      controller.openDetails(item.id);

      await controller.moveForward(item);
      expect(controller.selectedItem!.state, ItemState.done);
      expect(controller.selectedTab, HomeTab.done);

      await controller.reopen(controller.selectedItem!);
      expect(controller.selectedItem!.state, ItemState.open);

      await controller.moveBackward(controller.selectedItem!);
      expect(controller.selectedItem!.state, ItemState.draft);
      expect(controller.selectedTab, HomeTab.draft);
    },
  );

  test('loads persisted items and can clear local data', () async {
    final store = FakeStore();
    var controller = StillOpenController(store: store);
    await controller.load();
    await controller.quickAdd(title: 'Office client meeting at work');

    controller = StillOpenController(store: store);
    await controller.load();
    expect(controller.items.first.title, 'Office client meeting at work');
    expect(controller.items.first.category, Category.work);

    await controller.clearAllData();
    expect(controller.items, isEmpty);
    expect(controller.attachments, isEmpty);
  });

  test('mark done persists across app restart', () async {
    final store = FakeStore();
    var controller = StillOpenController(store: store);
    await controller.load();
    await controller.quickAdd(title: 'Close the loop');

    await controller.markDone(controller.selectedItem!);

    controller = StillOpenController(store: store);
    await controller.load();
    expect(controller.items.single.state, ItemState.done);
    expect(controller.countForTab(HomeTab.open), 0);
    expect(controller.countForTab(HomeTab.done), 1);
  });

  test('mark done persists even when reminder cancellation fails', () async {
    final store = FakeStore();
    final scheduler = ThrowingCancelReminderScheduler();
    var controller = StillOpenController(
      store: store,
      reminderScheduler: scheduler,
    );
    await controller.load();
    await controller.quickAdd(title: 'Close despite reminder failure');
    final itemId = controller.selectedItem!.id;

    await controller.markDone(controller.selectedItem!);

    expect(controller.items.single.state, ItemState.done);
    expect(scheduler.cancelled, contains(itemId));
    controller = StillOpenController(store: store);
    await controller.load();
    expect(controller.items.single.state, ItemState.done);
    expect(controller.countForTab(HomeTab.open), 0);
    expect(controller.countForTab(HomeTab.done), 1);
  });

  test('clear local data removes app-local attachment files', () async {
    final attachmentDirectory = Directory.systemTemp.createTempSync(
      'stillopen-clear-attachments',
    );
    final source = File('${attachmentDirectory.parent.path}/clear-source.txt')
      ..writeAsStringSync('clear me');
    final controller = StillOpenController(
      store: FakeStore(),
      attachmentDirectoryProvider: () async => attachmentDirectory,
    );
    await controller.load();
    await controller.quickAdd(title: 'Attachment cleanup');
    await controller.addAttachment(
      item: controller.selectedItem!,
      uri: source.path,
      label: 'cleanup.txt',
      sourceType: SourceType.pdf,
    );
    final copied = File(controller.attachments.single.uri);
    expect(copied.existsSync(), isTrue);

    await controller.clearAllData();

    expect(controller.items, isEmpty);
    expect(controller.attachments, isEmpty);
    expect(copied.existsSync(), isFalse);
    expect(attachmentDirectory.listSync(), isEmpty);
  });

  test(
    'date pickers and attachments persist Android-style detail state',
    () async {
      final store = FakeStore();
      var controller = StillOpenController(store: store);
      await controller.load();
      await controller.quickAdd(title: 'Insurance receipt');
      final item = controller.selectedItem!;

      await controller.setPickedDueDateTime(
        item,
        DateTime(2030, 6, 4),
        hour: 9,
        minute: 5,
      );
      await controller.addNoteAttachment(
        controller.selectedItem!,
        'Receipt note\nSecond line',
      );
      final receipt = File(
        '${Directory.systemTemp.createTempSync('stillopen-receipt').path}/receipt.pdf',
      )..writeAsStringSync('receipt');
      await controller.addAttachment(
        item: controller.selectedItem!,
        uri: receipt.path,
        label: 'receipt.pdf',
        sourceType: SourceType.pdf,
      );

      expect(controller.selectedItem!.dueText, 'Jun 4, 2030 09:05');
      expect(controller.selectedDetails!.attachments, hasLength(2));

      controller = StillOpenController(store: store);
      await controller.load();
      controller.openDetails(controller.items.first.id);
      expect(controller.selectedDetails!.attachments, hasLength(2));
      expect(
        controller.selectedDetails!.attachments.map((item) => item.label),
        containsAll(['Receipt note', 'receipt.pdf']),
      );
    },
  );

  test(
    'settings persist and backup import can replace or merge data',
    () async {
      final store = FakeStore();
      var controller = StillOpenController(store: store);
      await controller.load();
      await controller.setThemePreference(AppThemePreference.dark);
      await controller.setNotificationsEnabled(false);
      await controller.setTemplateShortcutsVisible(false);
      await controller.setDefaultReminder('Today', 7, 30);
      await controller.quickAdd(title: 'Medical bill');
      await controller.addNoteAttachment(
        controller.selectedItem!,
        'Private note with Umlaut äöüß',
      );

      final backup = controller.exportBackupJson();
      expect(backup, contains('stillopen_backup_v1'));
      expect(backup, contains('Medical bill'));

      controller = StillOpenController(store: store);
      await controller.load();
      expect(controller.themePreference, AppThemePreference.dark);
      expect(controller.notificationsEnabled, isFalse);
      expect(controller.showTemplateShortcuts, isFalse);
      expect(controller.defaultReminderHour, 7);

      final otherStore = FakeStore();
      final imported = StillOpenController(store: otherStore);
      await imported.load();
      final replaced = await imported.importBackupJson(backup, replace: true);
      expect(replaced, 1);
      expect(imported.items.single.title, 'Medical bill');
      expect(imported.items.single.category, Category.medical);
      expect(
        imported.attachments.single.label,
        'Private note with Umlaut äöüß',
      );
      expect(
        utf8.decode(
          base64Url.decode(
            Uri.parse(imported.attachments.single.uri).queryParameters['data']!,
          ),
        ),
        'Private note with Umlaut äöüß',
      );
      expect(imported.themePreference, AppThemePreference.dark);

      await imported.importBackupJson(backup);
      expect(imported.items, hasLength(2));
      expect(imported.attachments, hasLength(2));
      expect(imported.items.map((item) => item.id).toSet(), hasLength(2));
    },
  );

  test(
    'backup import preserves display-style categories and attachment files',
    () async {
      final sourceFile = File(
        '${Directory.systemTemp.createTempSync('stillopen-backup-test').path}/receipt.txt',
      )..writeAsStringSync('receipt bytes');
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      await controller.quickAdd(
        title: 'Manual category',
        category: Category.other,
        categoryEdited: true,
      );
      await controller.setCategory(controller.selectedItem!, Category.longTerm);
      await controller.addAttachment(
        item: controller.selectedItem!,
        uri: sourceFile.path,
        label: 'Receipt proof',
        sourceType: SourceType.pdf,
      );
      expect(controller.attachments.single.uri, isNot(sourceFile.path));
      expect(
        File(controller.attachments.single.uri).readAsStringSync(),
        'receipt bytes',
      );

      final decoded =
          jsonDecode(controller.exportBackupJson()) as Map<String, Object?>;
      final items = (decoded['items']! as List).cast<Map<String, Object?>>();
      items.single['category'] = 'Long-term';
      final attachments = (decoded['attachments']! as List)
          .cast<Map<String, Object?>>();
      expect(attachments.single['contentBase64'], isNotEmpty);

      final imported = StillOpenController(store: FakeStore());
      await imported.load();
      await imported.importBackupJson(jsonEncode(decoded), replace: true);

      expect(imported.items.single.category, Category.longTerm);
      expect(imported.attachments.single.label, 'Receipt proof');
      final restored = File(imported.attachments.single.uri);
      expect(restored.existsSync(), isTrue);
      expect(restored.readAsStringSync(), 'receipt bytes');
    },
  );

  test('small attachment export includes bytes and report counts it', () async {
    final sourceFile = File(
      '${Directory.systemTemp.createTempSync('stillopen-export-small').path}/small.txt',
    )..writeAsStringSync('small bytes');
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.quickAdd(title: 'Small export');
    await controller.addAttachment(
      item: controller.selectedItem!,
      uri: sourceFile.path,
      label: 'small.txt',
      sourceType: SourceType.pdf,
    );

    final decoded =
        jsonDecode(controller.exportBackupJson()) as Map<String, Object?>;
    final attachments = (decoded['attachments']! as List)
        .cast<Map<String, Object?>>();

    expect(
      attachments.single['contentBase64'],
      base64Encode(utf8.encode('small bytes')),
    );
    expect(controller.lastBackupExportReport!.attachmentsIncluded, 1);
    expect(controller.lastBackupExportReport!.attachmentsSkippedLarge, 0);
  });

  test('large and total-limited attachments export as metadata only', () async {
    final temp = Directory.systemTemp.createTempSync('stillopen-export-limits');
    final large = File('${temp.path}/large-private-name.pdf')
      ..writeAsBytesSync(List.filled(12, 1));
    final first = File('${temp.path}/first.txt')
      ..writeAsBytesSync(List.filled(6, 2));
    final second = File('${temp.path}/second.txt')
      ..writeAsBytesSync(List.filled(6, 3));
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.quickAdd(title: 'Large export');
    await controller.addAttachment(
      item: controller.selectedItem!,
      uri: large.path,
      label: 'large-private-name.pdf',
      sourceType: SourceType.pdf,
    );
    await controller.addAttachment(
      item: controller.selectedItem!,
      uri: first.path,
      label: 'first.txt',
      sourceType: SourceType.pdf,
    );
    await controller.addAttachment(
      item: controller.selectedItem!,
      uri: second.path,
      label: 'second.txt',
      sourceType: SourceType.pdf,
    );

    final decoded =
        jsonDecode(
              controller.exportBackupJson(
                maxPerAttachmentBytes: 10,
                maxTotalAttachmentBytes: 10,
              ),
            )
            as Map<String, Object?>;
    final attachments = (decoded['attachments']! as List)
        .cast<Map<String, Object?>>();

    expect(
      attachments.where(
        (attachment) => attachment.containsKey('contentBase64'),
      ),
      hasLength(1),
    );
    expect(controller.lastBackupExportReport!.attachmentsIncluded, 1);
    expect(controller.lastBackupExportReport!.attachmentsSkippedLarge, 2);
    final diagnostics = controller.exportDiagnosticsJson();
    expect(diagnostics, isNot(contains(large.path)));
    expect(diagnostics, isNot(contains('large-private-name.pdf')));
  });

  test('missing attachment export skips without crashing', () async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.importBackupJson(
      jsonEncode({
        'schema_version': 'stillopen_backup_v1',
        'items': [
          StillOpenItem(
            id: 1,
            title: 'Missing export',
            state: ItemState.open,
            category: Category.other,
            createdAt: 1,
            updatedAt: 1,
          ).toJson(),
        ],
        'attachments': [
          ItemAttachment(
            id: 1,
            itemId: 1,
            uri: '/definitely/missing/stillopen-file.txt',
            label: 'Missing',
            sourceType: SourceType.pdf,
            createdAt: 1,
          ).toJson(),
        ],
      }),
      replace: true,
    );

    final backup = controller.exportBackupJson();

    expect(backup, contains('stillopen_backup_v1'));
    expect(controller.lastBackupExportReport!.attachmentsSkippedMissing, 1);
  });

  test(
    'replace import deletes stale files cancels old reminders and syncs imported reminders',
    () async {
      final attachmentDirectory = Directory.systemTemp.createTempSync(
        'stillopen-replace-import',
      );
      final source = File('${attachmentDirectory.parent.path}/old.txt')
        ..writeAsStringSync('old bytes');
      final scheduler = FakeReminderScheduler();
      final controller = StillOpenController(
        store: FakeStore(),
        reminderScheduler: scheduler,
        attachmentDirectoryProvider: () async => attachmentDirectory,
      );
      await controller.load();
      await controller.quickAdd(title: 'Old reminder');
      await controller.setReminderTomorrow(controller.selectedItem!);
      await controller.addAttachment(
        item: controller.selectedItem!,
        uri: source.path,
        label: 'old.txt',
        sourceType: SourceType.pdf,
      );
      final staleFile = File(controller.attachments.single.uri);
      expect(staleFile.existsSync(), isTrue);

      final backup = jsonEncode({
        'schema_version': 'stillopen_backup_v1',
        'items': [
          StillOpenItem(
            id: 10,
            title: 'Imported reminder',
            state: ItemState.open,
            category: Category.other,
            reminderText: 'Tomorrow 20:00',
            createdAt: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ).toJson(),
        ],
        'attachments': const [],
      });
      await controller.importBackupJson(backup, replace: true);

      expect(staleFile.existsSync(), isFalse);
      expect(scheduler.cancelAllCount, 1);
      expect(scheduler.scheduled.keys, contains(10));
      expect(controller.items.single.title, 'Imported reminder');
    },
  );

  test(
    'backup import persists and shows imported data when reminder plugin fails',
    () async {
      final store = FakeStore();
      final scheduler = ThrowingReminderScheduler();
      final controller = StillOpenController(
        store: store,
        reminderScheduler: scheduler,
      );
      await controller.load();
      await controller.quickAdd(title: 'Existing hidden item');
      controller.selectDomainFilter(DomainFilter.medical);
      controller.setQuery('will hide imports');

      final imported = await controller.importBackupJson(
        jsonEncode({
          'schema_version': 'stillopen_backup_v1',
          'items': [
            StillOpenItem(
              id: 41,
              title: 'Imported draft is visible',
              state: ItemState.draft,
              category: Category.other,
              reminderText: 'Tomorrow 20:00',
              createdAt: 41,
              updatedAt: 41,
            ).toJson(),
          ],
          'attachments': const [],
        }),
        replace: true,
      );

      expect(imported, 1);
      expect(scheduler.cancelAllCount, 1);
      expect(scheduler.permissionRequests, greaterThanOrEqualTo(1));
      expect(controller.items.single.title, 'Imported draft is visible');
      expect(controller.selectedTab, HomeTab.draft);
      expect(controller.domainFilter, DomainFilter.all);
      expect(controller.query, isEmpty);
      expect(controller.visibleItems.single.title, 'Imported draft is visible');
      expect(store.values['stillopen_snapshot_v2'], contains('Imported draft'));
    },
  );

  test(
    'merge import remaps attachment IDs before restoring bytes and avoids collisions',
    () async {
      final attachmentDirectory = Directory.systemTemp.createTempSync(
        'stillopen-merge-collision',
      );
      final existingSource = File('${attachmentDirectory.parent.path}/same.pdf')
        ..writeAsStringSync('existing bytes');
      final controller = StillOpenController(
        store: FakeStore(),
        attachmentDirectoryProvider: () async => attachmentDirectory,
      );
      await controller.load();
      await controller.quickAdd(title: 'Existing item');
      await controller.addAttachment(
        item: controller.selectedItem!,
        uri: existingSource.path,
        label: 'same.pdf',
        sourceType: SourceType.pdf,
      );
      final existingAttachment = controller.attachments.single;
      final existingFile = File(existingAttachment.uri);
      expect(existingAttachment.id, 1);

      await controller.importBackupJson(
        jsonEncode({
          'schema_version': 'stillopen_backup_v1',
          'items': [
            StillOpenItem(
              id: 1,
              title: 'Imported item',
              state: ItemState.open,
              category: Category.other,
              createdAt: 1,
              updatedAt: 1,
            ).toJson(),
          ],
          'attachments': [
            ItemAttachment(
                id: 1,
                itemId: 1,
                uri: 'same.pdf',
                label: 'same.pdf',
                sourceType: SourceType.pdf,
                createdAt: 1,
              ).toJson()
              ..['contentBase64'] = base64Encode(utf8.encode('import bytes'))
              ..['fileName'] = 'same.pdf',
          ],
        }),
      );

      expect(existingFile.readAsStringSync(), 'existing bytes');
      final importedAttachment = controller.attachments.firstWhere(
        (attachment) => attachment.id != existingAttachment.id,
      );
      expect(importedAttachment.id, isNot(existingAttachment.id));
      expect(importedAttachment.itemId, isNot(1));
      expect(File(importedAttachment.uri).readAsStringSync(), 'import bytes');
    },
  );

  test('replace diagnostics ignore stale old files', () async {
    final attachmentDirectory = Directory.systemTemp.createTempSync(
      'stillopen-replace-diagnostics',
    );
    final source = File('${attachmentDirectory.parent.path}/stale.txt')
      ..writeAsStringSync('stale bytes');
    final controller = StillOpenController(
      store: FakeStore(),
      attachmentDirectoryProvider: () async => attachmentDirectory,
    );
    await controller.load();
    await controller.quickAdd(title: 'Old item');
    await controller.addAttachment(
      item: controller.selectedItem!,
      uri: source.path,
      label: 'stale.txt',
      sourceType: SourceType.pdf,
    );

    await controller.importBackupJson(
      jsonEncode({
        'schema_version': 'stillopen_backup_v1',
        'items': const [],
        'attachments': const [],
      }),
      replace: true,
    );
    final diagnostics =
        jsonDecode(controller.exportDiagnosticsJson()) as Map<String, Object?>;
    final counts = diagnostics['counts'] as Map<String, Object?>;

    expect(counts['attachments'], 0);
    expect(counts['readable_attachment_files'], 0);
    expect(counts['missing_attachment_files'], 0);
  });

  test(
    'shared text url and files create draft items without diagnostics leaks',
    () async {
      final attachmentDirectory = Directory.systemTemp.createTempSync(
        'stillopen-shared',
      );
      final image = File('${attachmentDirectory.parent.path}/shared-secret.png')
        ..writeAsStringSync('image bytes');
      final pdf = File('${attachmentDirectory.parent.path}/shared.pdf')
        ..writeAsStringSync('pdf bytes');
      final controller = StillOpenController(
        store: FakeStore(),
        attachmentDirectoryProvider: () async => attachmentDirectory,
      );
      await controller.load();

      expect(
        await controller.addSharedText(
          'https://example.com/private\nsecond',
          isUrl: true,
        ),
        isTrue,
      );
      expect(controller.selectedItem!.state, ItemState.draft);
      expect(controller.selectedTab, HomeTab.draft);
      expect(controller.selectedItem!.title, 'https://example.com/private');
      expect(controller.selectedItem!.sourceCaptureType, SourceCaptureType.url);
      expect(
        await controller.addSharedText(
          'https://example.com/private\nsecond',
          isUrl: true,
        ),
        isFalse,
      );

      expect(
        await controller.addSharedFiles([
          IncomingSharedFile(
            path: image.path,
            mimeType: 'image/png',
            name: 'shared-secret.png',
            isImage: true,
          ),
          IncomingSharedFile(
            path: pdf.path,
            mimeType: 'application/pdf',
            name: 'shared.pdf',
          ),
        ]),
        isTrue,
      );
      expect(controller.selectedItem!.title, 'Shared files');
      expect(controller.selectedItem!.state, ItemState.draft);
      final sharedAttachments = controller.selectedDetails!.attachments;
      expect(sharedAttachments, hasLength(2));
      expect(
        sharedAttachments.every(
          (attachment) => File(attachment.uri).existsSync(),
        ),
        isTrue,
      );
      expect(
        sharedAttachments.map((attachment) => attachment.uri),
        isNot(contains(image.path)),
      );
      expect(
        sharedAttachments.map((attachment) => attachment.uri),
        isNot(contains(pdf.path)),
      );

      final diagnostics = controller.exportDiagnosticsJson();
      expect(diagnostics, isNot(contains('https://example.com/private')));
      expect(diagnostics, isNot(contains(image.path)));
      expect(diagnostics, isNot(contains('shared-secret.png')));
    },
  );

  test(
    'mixed text and image share creates one draft with attachment',
    () async {
      final attachmentDirectory = Directory.systemTemp.createTempSync(
        'stillopen-mixed-image',
      );
      final image = File('${attachmentDirectory.parent.path}/mixed-secret.png')
        ..writeAsStringSync('image bytes');
      final controller = StillOpenController(
        store: FakeStore(),
        attachmentDirectoryProvider: () async => attachmentDirectory,
      );
      await controller.load();

      expect(
        await controller.addSharedContent(
          text: 'Remember this screenshot',
          files: [
            IncomingSharedFile(
              path: image.path,
              mimeType: 'image/png',
              name: 'mixed-secret.png',
              isImage: true,
            ),
          ],
        ),
        isTrue,
      );

      expect(controller.items, hasLength(1));
      expect(controller.selectedItem!.state, ItemState.draft);
      expect(controller.selectedItem!.title, 'Remember this screenshot');
      expect(controller.selectedItem!.notes, 'Remember this screenshot');
      expect(controller.selectedTab, HomeTab.draft);
      expect(controller.selectedDetails!.attachments, hasLength(1));
      expect(
        File(controller.selectedDetails!.attachments.single.uri).existsSync(),
        isTrue,
      );
      expect(
        controller.selectedDetails!.attachments.single.uri,
        isNot(image.path),
      );
    },
  );

  test('mixed url and pdf share creates one draft with attachment', () async {
    final attachmentDirectory = Directory.systemTemp.createTempSync(
      'stillopen-mixed-pdf',
    );
    final pdf = File('${attachmentDirectory.parent.path}/private-invoice.pdf')
      ..writeAsStringSync('pdf bytes');
    final controller = StillOpenController(
      store: FakeStore(),
      attachmentDirectoryProvider: () async => attachmentDirectory,
    );
    await controller.load();

    expect(
      await controller.addSharedContent(
        text: 'https://example.com/private/invoice',
        isUrl: true,
        files: [
          IncomingSharedFile(
            path: pdf.path,
            mimeType: 'application/pdf',
            name: 'private-invoice.pdf',
          ),
        ],
      ),
      isTrue,
    );

    expect(controller.items, hasLength(1));
    expect(
      controller.selectedItem!.title,
      'https://example.com/private/invoice',
    );
    expect(
      controller.selectedItem!.notes,
      'https://example.com/private/invoice',
    );
    expect(controller.selectedItem!.sourceCaptureType, SourceCaptureType.url);
    expect(controller.selectedDetails!.attachments, hasLength(1));
    expect(
      File(controller.selectedDetails!.attachments.single.uri).existsSync(),
      isTrue,
    );
  });

  test('duplicate mixed share event creates only one draft', () async {
    final attachmentDirectory = Directory.systemTemp.createTempSync(
      'stillopen-mixed-duplicate',
    );
    final pdf = File('${attachmentDirectory.parent.path}/duplicate.pdf')
      ..writeAsStringSync('pdf bytes');
    final controller = StillOpenController(
      store: FakeStore(),
      attachmentDirectoryProvider: () async => attachmentDirectory,
    );
    await controller.load();
    final files = [
      IncomingSharedFile(
        path: pdf.path,
        mimeType: 'application/pdf',
        name: 'duplicate.pdf',
      ),
    ];

    expect(
      await controller.addSharedContent(text: 'Duplicate share', files: files),
      isTrue,
    );
    expect(
      await controller.addSharedContent(text: 'Duplicate share', files: files),
      isFalse,
    );

    expect(controller.items, hasLength(1));
    expect(controller.attachments, hasLength(1));
  });

  test('unsupported future backup schema fails clearly', () async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();

    expect(
      () => controller.importBackupJson(
        jsonEncode({
          'schema_version': 'stillopen_backup_v999',
          'items': const [],
        }),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported backup schema'),
        ),
      ),
    );
  });

  test('corrupt attachment bytes import as metadata only', () async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    final imported = await controller.importBackupJson(
      jsonEncode({
        'schema_version': 'stillopen_backup_v1',
        'items': [
          StillOpenItem(
            id: 1,
            title: 'Imported',
            state: ItemState.open,
            category: Category.other,
            priority: Priority.normal,
            createdAt: 1,
            updatedAt: 1,
          ).toJson(),
        ],
        'attachments': [
          ItemAttachment(
            id: 1,
            itemId: 1,
            uri: 'missing.pdf',
            label: 'Missing PDF',
            sourceType: SourceType.pdf,
            createdAt: 1,
          ).toJson()..['contentBase64'] = 'not-base64',
        ],
      }),
      replace: true,
    );

    expect(imported, 1);
    expect(controller.attachments.single.label, 'Missing PDF');
    expect(controller.lastImportReport!.attachmentsMetadataOnly, 1);
  });

  test(
    'diagnostics export is redacted and includes operational counts',
    () async {
      final sourceFile = File(
        '${Directory.systemTemp.createTempSync('stillopen-diagnostics').path}/secret-receipt.txt',
      )..writeAsStringSync('secret bytes');
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      await controller.quickAdd(title: 'Very private title');
      await controller.setNote(controller.selectedItem!, 'Sensitive note text');
      await controller.addAttachment(
        item: controller.selectedItem!,
        uri: sourceFile.path,
        label: 'Secret attachment',
        sourceType: SourceType.pdf,
      );

      final diagnostics = controller.exportDiagnosticsJson(
        runtimeDiagnostics: {
          'recent_errors': [
            {'message': 'redacted runtime sample'},
          ],
        },
      );
      final decoded = jsonDecode(diagnostics) as Map<String, Object?>;
      final counts = decoded['counts'] as Map<String, Object?>;

      expect(decoded['schema_version'], 'stillopen_diagnostics_v1');
      expect(counts['items'], 1);
      expect(counts['attachments'], 1);
      expect(diagnostics, isNot(contains('Very private title')));
      expect(diagnostics, isNot(contains('Sensitive note text')));
      expect(diagnostics, isNot(contains(sourceFile.path)));
      expect(diagnostics, isNot(contains('secret bytes')));
    },
  );

  test('diagnostics redacts uri paths filenames and long messages', () async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    final diagnostics = controller.exportDiagnosticsJson(
      runtimeDiagnostics: {
        'recent_errors': [
          {
            'message':
                'content://downloads/private/secret-invoice.pdf file:///tmp/private-photo.png C:\\Users\\me\\Downloads\\tax-return.pdf secret-name.jpg ${List.filled(900, 'x').join()}',
          },
        ],
      },
    );

    expect(diagnostics, isNot(contains('content://downloads')));
    expect(diagnostics, isNot(contains('file:///tmp')));
    expect(diagnostics, isNot(contains('C:\\Users')));
    expect(diagnostics, isNot(contains('secret-invoice.pdf')));
    expect(diagnostics, isNot(contains('private-photo.png')));
    expect(diagnostics, isNot(contains('tax-return.pdf')));
    expect(diagnostics, isNot(contains('secret-name.jpg')));
    expect(diagnostics, contains('[uri]'));
    expect(diagnostics, contains('[path]'));
    expect(diagnostics, contains('[file]'));
    expect(diagnostics.length, lessThan(2500));
  });

  test(
    'diagnostics redacts shared text and filenames from incoming share errors',
    () async {
      StillOpenDiagnostics.instance.clearForTests();
      StillOpenDiagnostics.instance.recordError(
        source: 'incoming_share_stream',
        message:
            'Failed for shared text My private errand content://app/private/medical-bill.pdf and shared-secret.png',
      );
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      final diagnostics = controller.exportDiagnosticsJson(
        runtimeDiagnostics: StillOpenDiagnostics.instance.toJson(),
      );

      expect(diagnostics, contains('incoming_share_stream'));
      expect(diagnostics, isNot(contains('My private errand')));
      expect(diagnostics, isNot(contains('content://app')));
      expect(diagnostics, isNot(contains('medical-bill.pdf')));
      expect(diagnostics, isNot(contains('shared-secret.png')));
    },
  );

  test('invalid backup json reports a format problem', () async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();

    expect(
      () => controller.importBackupJson('"not an object"'),
      throwsFormatException,
    );
  });

  test('reminders are scheduled cancelled and restored from imports', () async {
    final scheduler = FakeReminderScheduler();
    final controller = StillOpenController(
      store: FakeStore(),
      reminderScheduler: scheduler,
    );
    await controller.load();
    await controller.quickAdd(title: 'Reminder item');
    final item = controller.selectedItem!;

    await controller.setReminderTomorrow(item);
    expect(scheduler.permissionRequests, 1);
    expect(scheduler.scheduled[item.id], isNotNull);

    await controller.clearReminder(controller.selectedItem!);
    expect(scheduler.cancelled, contains(item.id));

    await controller.setReminderTomorrow(controller.selectedItem!);
    final backup = controller.exportBackupJson();
    final importedScheduler = FakeReminderScheduler();
    final imported = StillOpenController(
      store: FakeStore(),
      reminderScheduler: importedScheduler,
    );
    await imported.load();
    await imported.importBackupJson(backup, replace: true);
    expect(
      importedScheduler.scheduled.keys,
      contains(imported.items.single.id),
    );
    expect(importedScheduler.cancelAllCount, 1);

    await imported.setNotificationsEnabled(false);
    expect(importedScheduler.cancelAllCount, 2);
  });

  test('templates create Android-like defaults for every start type', () async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();

    final expected = {
      TemplateType.medicalClaim: (
        'Doctor invoice',
        Category.medical,
        ItemState.open,
      ),
      TemplateType.schoolHomework: (
        'Math homework',
        Category.school,
        ItemState.dueSoon,
      ),
      TemplateType.school: ('School form', Category.school, ItemState.dueSoon),
      TemplateType.longTerm: (
        'Book dentist check',
        Category.longTerm,
        ItemState.open,
      ),
      TemplateType.home: (
        'Home / warranty item',
        Category.home,
        ItemState.open,
      ),
      TemplateType.shoppingReturn: (
        'Shopping return',
        Category.shopping,
        ItemState.waiting,
      ),
      TemplateType.money: ('Money / bill', Category.money, ItemState.dueSoon),
      TemplateType.document: (
        'Documents / proof',
        Category.documents,
        ItemState.draft,
      ),
      TemplateType.other: ('Open item', Category.other, ItemState.open),
    };

    for (final entry in expected.entries) {
      await controller.createFromTemplate(entry.key);
      final item = controller.selectedItem!;
      expect(item.title, entry.value.$1);
      expect(item.category, entry.value.$2);
      expect(item.state, entry.value.$3);
      expect(controller.selectedDetails!.steps, isNotEmpty);
    }
  });

  test(
    'edits categories dates reminders waiting notes attachments and deletion',
    () async {
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      expect(await controller.quickAdd(title: ''), isFalse);
      await controller.quickAdd(title: 'Call doctor');
      var item = controller.selectedItem!;

      await controller.renameItem(item, '');
      expect(controller.selectedItem!.title, 'Call doctor');
      await controller.renameItem(item, 'Passport renewal');
      item = controller.selectedItem!;
      expect(item.title, 'Passport renewal');
      expect(item.category, Category.longTerm);

      await controller.setCategory(item, Category.documents);
      item = controller.selectedItem!;
      expect(item.categoryUserEdited, isTrue);
      expect(item.category, Category.documents);

      await controller.setDateToday(item);
      expect(controller.selectedItem!.dueText, startsWith('Today'));
      await controller.setDateTomorrow(controller.selectedItem!);
      expect(controller.selectedItem!.dueText, startsWith('Tomorrow'));
      await controller.setDateThisWeekend(controller.selectedItem!);
      expect(controller.selectedItem!.dueText, contains('20:00'));
      await controller.setReminderToday(controller.selectedItem!);
      expect(controller.selectedItem!.reminderText, startsWith('Today'));
      await controller.clearReminder(controller.selectedItem!);
      expect(controller.selectedItem!.reminderText, isEmpty);
      await controller.clearDate(controller.selectedItem!);
      expect(controller.selectedItem!.dueText, isEmpty);

      await controller.setWaitingOn(controller.selectedItem!, 'Provider');
      item = controller.selectedItem!;
      expect(item.state, ItemState.waiting);
      expect(item.waitingOn, 'Provider');
      await controller.setWaitingOn(item, '');
      expect(controller.selectedItem!.state, ItemState.open);

      await controller.setNote(controller.selectedItem!, '  useful note  ');
      expect(controller.selectedItem!.notes, 'useful note');
      await controller.addAttachment(
        item: controller.selectedItem!,
        uri: '',
        label: 'empty',
        sourceType: SourceType.image,
      );
      expect(controller.attachments, isEmpty);
      final image = File(
        '${Directory.systemTemp.createTempSync('stillopen-image').path}/a.png',
      )..writeAsStringSync('image-bytes');
      await controller.addAttachment(
        item: controller.selectedItem!,
        uri: image.path,
        label: '',
        sourceType: SourceType.image,
      );
      var attachment = controller.attachments.single;
      expect(attachment.label, 'Image');
      expect(attachment.uri, isNot(image.path));
      final localImage = File(attachment.uri);
      expect(localImage.readAsStringSync(), 'image-bytes');
      await controller.renameAttachment(attachment, 'Renamed image');
      attachment = controller.attachments.single;
      expect(attachment.label, 'Renamed image');
      await controller.renameAttachment(attachment, '');
      expect(controller.attachments.single.label, 'Renamed image');
      await controller.deleteAttachment(attachment);
      expect(controller.attachments, isEmpty);
      expect(localImage.existsSync(), isFalse);

      await controller.addNoteAttachment(
        controller.selectedItem!,
        'Original note attachment äöüß',
      );
      expect(controller.attachments.single.uri, isNot(contains('äöüß')));
      await controller.updateNoteAttachment(
        controller.attachments.single,
        'Updated note attachment äöüß',
      );
      expect(
        controller.attachments.single.label,
        'Updated note attachment äöüß',
      );
      final noteUri = Uri.parse(controller.attachments.single.uri);
      expect(noteUri.queryParameters['encoding'], 'utf8-base64url');
      expect(
        utf8.decode(base64Url.decode(noteUri.queryParameters['data']!)),
        'Updated note attachment äöüß',
      );
      await controller.deleteAttachment(controller.attachments.single);

      await controller.addAttachment(
        item: controller.selectedItem!,
        uri: image.path,
        label: 'delete with item',
        sourceType: SourceType.image,
      );
      final itemAttachmentFile = File(controller.attachments.single.uri);
      expect(itemAttachmentFile.existsSync(), isTrue);

      await controller.deleteItem(controller.selectedItem!);
      expect(controller.items, isEmpty);
      expect(controller.attachments, isEmpty);
      expect(controller.selectedItem, isNull);
      expect(itemAttachmentFile.existsSync(), isFalse);
    },
  );

  test('delete item persists even when reminder cancellation fails', () async {
    final store = FakeStore();
    final scheduler = ThrowingCancelReminderScheduler();
    final controller = StillOpenController(
      store: store,
      reminderScheduler: scheduler,
    );
    await controller.load();
    await controller.quickAdd(title: 'Delete despite reminder failure');
    final itemId = controller.selectedItem!.id;

    await controller.deleteItem(controller.selectedItem!);

    expect(controller.items, isEmpty);
    expect(controller.selectedItem, isNull);
    expect(
      (jsonDecode(store.values['stillopen_snapshot_v2']!) as Map)['items'],
      isEmpty,
    );
    expect(scheduler.cancelled, contains(itemId));
  });

  test(
    'medical long-term and lifecycle edge actions update selected state',
    () async {
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      await controller.createFromTemplate(TemplateType.medicalClaim);
      await controller.markMedicalForwarded(controller.selectedItem!);
      expect(controller.selectedItem!.waitingOn, 'Private insurance');
      await controller.markMedicalPrivateResponseReceived(
        controller.selectedItem!,
      );
      expect(controller.selectedItem!.claimStage, 'Private response received');
      await controller.markMedicalSubmitted(controller.selectedItem!);
      await controller.markMedicalReimbursed(controller.selectedItem!);
      expect(controller.selectedItem!.state, ItemState.done);

      await controller.createFromTemplate(TemplateType.longTerm);
      await controller.setRecurrenceHint(controller.selectedItem!, 'Monthly');
      expect(controller.selectedItem!.recurrenceHint, 'Monthly');
      await controller.setLongTermNextReminderFromRecurrence(
        controller.selectedItem!,
      );
      expect(controller.selectedItem!.nextCycleAt, contains('20:00'));
      expect(controller.selectedItem!.state, ItemState.open);
      await controller.markLongTermBooked(controller.selectedItem!);
      expect(controller.selectedItem!.state, ItemState.waiting);
      await controller.setLongTermNextReminder(
        controller.selectedItem!,
        '6 months',
      );
      expect(controller.selectedItem!.state, ItemState.open);
      expect(controller.selectedItem!.nextCycleAt, contains('20:00'));
      expect(controller.selectedItem!.completedCycles, 2);
      await controller.ignoreDraft(controller.selectedItem!);
      expect(controller.selectedItem!.state, ItemState.ignored);

      controller.closeDetails();
      expect(controller.selectedItem, isNull);
      controller.selectPersonFilter(PersonFilter.kids);
      controller.selectDomainFilter(DomainFilter.school);
      controller.selectSort(SortMode.category);
      await controller.cycleFarFutureThreshold();
      expect(controller.personFilter, PersonFilter.kids);
      expect(controller.domainFilter, DomainFilter.school);
      expect(controller.sortMode, SortMode.category);
      expect(controller.farFutureThreshold, FarFutureThreshold.threeMonths);
      controller.clearSnackbar();
      expect(controller.snackbarMessage, isNull);
    },
  );

  test('ios pending share text url and files create draft items', () async {
    final root = Directory.systemTemp.createTempSync('stillopen-ios-pending');
    final attachments = Directory.systemTemp.createTempSync(
      'stillopen-ios-local',
    );
    final sharedFile = File('${root.path}/shared-image.png')
      ..writeAsStringSync('image bytes');
    _writePendingShare(root, {
      'id': 'ios-mixed-1',
      'createdAt': 1,
      'source': 'iosShareExtension',
      'url': 'https://example.com/private-ios-share',
      'text': 'Private iOS share note',
      'files': [
        {
          'path': sharedFile.path,
          'originalName': 'shared-image.png',
          'mimeType': 'image/png',
          'uti': 'public.image',
          'size': sharedFile.lengthSync(),
          'available': true,
        },
      ],
    });
    final controller = StillOpenController(
      store: FakeStore(),
      attachmentDirectoryProvider: () async => attachments,
    );
    await controller.load();
    final ingestor = IncomingShareIngestor(
      controller: controller,
      store: DirectoryPendingShareStore(root),
    );

    final count = await ingestor.ingestPendingShares();

    expect(count, 1);
    expect(controller.selectedTab, HomeTab.draft);
    expect(
      controller.selectedItem!.title,
      'https://example.com/private-ios-share',
    );
    expect(controller.selectedItem!.notes, contains('Private iOS share note'));
    expect(controller.attachments, hasLength(1));
    expect(File(controller.attachments.single.uri).existsSync(), isTrue);
    expect(
      File(controller.attachments.single.uri).path,
      contains(attachments.path),
    );
    expect(sharedFile.existsSync(), isFalse);
    expect(_pendingManifestCount(root), 0);
  });

  test(
    'ios pending share duplicate and processed entries are not reprocessed',
    () async {
      final root = Directory.systemTemp.createTempSync('stillopen-ios-dupe');
      _writePendingShare(root, {
        'id': 'dupe-event',
        'createdAt': 1,
        'source': 'iosShareExtension',
        'text': 'Duplicate iOS text',
        'files': <Object?>[],
      });
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      final ingestor = IncomingShareIngestor(
        controller: controller,
        store: DirectoryPendingShareStore(root),
      );

      expect(await ingestor.ingestPendingShares(), 1);
      _writePendingShare(root, {
        'id': 'dupe-event',
        'createdAt': 2,
        'source': 'iosShareExtension',
        'text': 'Duplicate iOS text',
        'files': <Object?>[],
      });
      expect(await ingestor.ingestPendingShares(), 0);

      expect(
        controller.items.where((item) => item.title == 'Duplicate iOS text'),
        hasLength(1),
      );
    },
  );

  test('ios pending share corrupt and missing file paths are safe', () async {
    StillOpenDiagnostics.instance.clearForTests();
    final root = Directory.systemTemp.createTempSync('stillopen-ios-corrupt');
    final pending = Directory('${root.path}/pending_shares')
      ..createSync(recursive: true);
    File('${pending.path}/corrupt.json').writeAsStringSync('{not json');
    _writePendingShare(root, {
      'id': 'missing-file',
      'createdAt': 1,
      'source': 'iosShareExtension',
      'files': [
        {
          'path': '${root.path}/secret-invoice.pdf',
          'originalName': 'secret-invoice.pdf',
          'mimeType': 'application/pdf',
          'uti': 'com.adobe.pdf',
          'available': false,
        },
      ],
    });
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    final ingestor = IncomingShareIngestor(
      controller: controller,
      store: DirectoryPendingShareStore(root),
    );

    expect(await ingestor.ingestPendingShares(), 1);

    expect(controller.items.single.title, 'Shared file unavailable');
    expect(
      controller.attachments.single.uri,
      startsWith('stillopen-metadata-only:'),
    );
    final diagnostics = jsonEncode(controller.exportDiagnosticsJson());
    expect(diagnostics, isNot(contains('secret-invoice.pdf')));
    expect(diagnostics, isNot(contains(root.path)));
  });
}

void _writePendingShare(Directory root, Map<String, Object?> json) {
  final pending = Directory('${root.path}/pending_shares')
    ..createSync(recursive: true);
  final id = json['id'] as String;
  File('${pending.path}/$id.json').writeAsStringSync(
    jsonEncode({'schema_version': 'stillopen_pending_share_v1', ...json}),
  );
}

int _pendingManifestCount(Directory root) {
  final pending = Directory('${root.path}/pending_shares');
  if (!pending.existsSync()) return 0;
  return pending.listSync().whereType<File>().length;
}

class FakeStore implements StillOpenStore {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

class FakeReminderScheduler implements ReminderScheduler {
  int permissionRequests = 0;
  int cancelAllCount = 0;
  final scheduled = <int, DateTime>{};
  final cancelled = <int>[];

  @override
  Future<void> requestPermissions() async {
    permissionRequests += 1;
  }

  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async {
    scheduled[item.id] = when;
  }

  @override
  Future<void> cancel(int itemId) async {
    cancelled.add(itemId);
    scheduled.remove(itemId);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount += 1;
    scheduled.clear();
  }
}

class ThrowingCancelReminderScheduler extends FakeReminderScheduler {
  @override
  Future<void> cancel(int itemId) async {
    cancelled.add(itemId);
    throw StateError('notification plugin unavailable');
  }
}

class ThrowingReminderScheduler extends FakeReminderScheduler {
  @override
  Future<void> requestPermissions() async {
    permissionRequests += 1;
    throw StateError('notification plugin unavailable');
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount += 1;
    throw StateError('notification plugin unavailable');
  }
}
