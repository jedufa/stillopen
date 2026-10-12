import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:stillopen/main.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/incoming_share/incoming_share_ingestor.dart';
import 'package:stillopen/src/incoming_share/ios_pending_share_store.dart';
import 'package:stillopen/src/models.dart';

void main() {
  testWidgets('starts empty and shows lifecycle tabs', (tester) async {
    final controller = StillOpenController(store: FakeStore());

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('StillOpen'), findsOneWidget);
    expect(find.text('0 open · 0 draft'), findsOneWidget);
    expect(find.text('Nothing is still open.'), findsOneWidget);
    expect(find.text('Open 0'), findsOneWidget);
    expect(find.text('Draft 0'), findsOneWidget);
    expect(find.text('Done 0'), findsOneWidget);
  });

  testWidgets('startup paints home while reminder sync is still pending', (
    tester,
  ) async {
    final store = FakeStore();
    store.values['stillopen_items_v1'] = jsonEncode([
      StillOpenItem(
        id: 12,
        title: 'Visible before reminder sync',
        state: ItemState.open,
        category: Category.other,
        reminderText: 'Tomorrow 20:00',
      ).toJson(),
    ]);
    final reminderScheduler = BlockingReminderScheduler();
    final controller = StillOpenController(
      store: store,
      reminderScheduler: reminderScheduler,
    );

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pump();
    await tester.pump();

    expect(reminderScheduler.permissionRequested, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('StillOpen'), findsOneWidget);
    expect(find.text('Visible before reminder sync'), findsOneWidget);

    reminderScheduler.release();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'row action delete removes task while reminder cancel is pending',
    (tester) async {
      final reminderScheduler = BlockingCancelReminderScheduler();
      final controller = StillOpenController(
        store: FakeStore(),
        reminderScheduler: reminderScheduler,
      );
      await controller.load();
      await controller.quickAdd(title: 'Delete from row menu');

      await tester.pumpWidget(StillOpenApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Delete from row menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete task'));
      await tester.pumpAndSettle();
      expect(controller.items, isNotEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pump();

      expect(reminderScheduler.cancelStarted, isTrue);
      expect(controller.items, isEmpty);

      reminderScheduler.release();
      await tester.pumpAndSettle();
      expect(find.text('Delete from row menu'), findsNothing);
      expect(find.text('Nothing is still open.'), findsOneWidget);
    },
  );

  testWidgets('quick add creates an inferred shopping item', (tester) async {
    final controller = StillOpenController(store: FakeStore());

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quick_add_title')),
      'Refund return order',
    );
    await tester.tap(find.byKey(const Key('quick_add_save')));
    await tester.pumpAndSettle();

    expect(controller.items.first.category.name, 'shopping');
    expect(controller.items.first.title, 'Refund return order');
  });

  testWidgets('incoming shared text appears in Draft', (tester) async {
    final controller = StillOpenController(store: FakeStore());

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();
    await controller.addSharedText('Shared loose end');
    await tester.pumpAndSettle();

    expect(controller.selectedTab, HomeTab.draft);
    expect(find.text('Draft 1'), findsOneWidget);
    expect(find.text('Shared loose end'), findsOneWidget);
  });

  testWidgets('initial incoming share waits for stored state load', (
    tester,
  ) async {
    final store = DelayedFakeStore();
    store.values['stillopen_items_v1'] = jsonEncode([
      StillOpenItem(
        id: 7,
        title: 'Stored item',
        state: ItemState.open,
        category: Category.documents,
      ).toJson(),
    ]);
    final controller = StillOpenController(store: store);
    final shareSource = FakeIncomingShareSource(
      initialMedia: [
        SharedMediaFile(
          path: 'Shared startup note',
          type: SharedMediaType.text,
          mimeType: 'text/plain',
        ),
      ],
    );

    await tester.pumpWidget(
      StillOpenApp(controller: controller, incomingShareSource: shareSource),
    );
    await tester.pump();
    expect(controller.loaded, isFalse);
    expect(controller.items, isEmpty);

    store.release();
    await tester.pumpAndSettle();

    expect(controller.items.map((item) => item.title), contains('Stored item'));
    expect(
      controller.items.map((item) => item.title),
      contains('Shared startup note'),
    );
    expect(controller.items.length, 2);
    expect(controller.selectedItem!.title, 'Shared startup note');
    expect(controller.selectedItem!.state, ItemState.draft);
    expect(controller.selectedTab, HomeTab.draft);
    expect(shareSource.resetCalls, 1);
  });

  testWidgets('initial and stream duplicate incoming share creates one draft', (
    tester,
  ) async {
    final attachmentDirectory = Directory.systemTemp.createTempSync(
      'stillopen-widget-mixed-duplicate',
    );
    final file = File('${attachmentDirectory.parent.path}/duplicate-share.pdf')
      ..writeAsStringSync('pdf bytes');
    final media = [
      SharedMediaFile(
        path: 'Duplicate shared note with file',
        type: SharedMediaType.text,
        mimeType: 'text/plain',
      ),
      SharedMediaFile(
        path: file.path,
        type: SharedMediaType.file,
        mimeType: 'application/pdf',
      ),
    ];
    final controller = StillOpenController(
      store: FakeStore(),
      attachmentDirectoryProvider: () async => attachmentDirectory,
    );
    final shareSource = FakeIncomingShareSource(
      initialMedia: media,
      streamMedia: [media],
    );

    await tester.pumpWidget(
      StillOpenApp(controller: controller, incomingShareSource: shareSource),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(
      controller.items
          .where((item) => item.title == 'Duplicate shared note with file')
          .length,
      1,
    );
    expect(controller.selectedItem!.title, 'Duplicate shared note with file');
    expect(controller.selectedTab, HomeTab.draft);
    expect(controller.selectedDetails!.attachments, hasLength(1));
  });

  testWidgets('ios pending share appears after startup and preserves items', (
    tester,
  ) async {
    final store = FakeStore();
    store.values['stillopen_items_v1'] = jsonEncode([
      StillOpenItem(
        id: 4,
        title: 'Existing local item',
        state: ItemState.open,
        category: Category.other,
      ).toJson(),
    ]);
    final controller = StillOpenController(store: store);
    final ingestor = _StartupTestIngestor(controller: controller);

    await tester.pumpWidget(
      StillOpenApp(
        controller: controller,
        incomingShareSource: FakeIncomingShareSource(),
        incomingShareIngestor: ingestor,
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pumpAndSettle();

    expect(ingestor.calls, greaterThan(0));
    expect(
      controller.items.map((item) => item.title),
      contains('Existing local item'),
    );
    expect(
      controller.items.map((item) => item.title),
      contains('iOS widget pending share'),
    );
    expect(controller.selectedItem!.title, 'iOS widget pending share');
    expect(controller.selectedTab, HomeTab.draft);
    expect(find.text('Draft 1'), findsOneWidget);
  });

  testWidgets('search filters the visible list', (tester) async {
    final controller = StillOpenController(store: FakeStore());

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();
    await controller.quickAdd(title: 'Math homework from WebUntis');
    await controller.quickAdd(title: 'Doctor invoice');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search_field')), 'WebUntis');
    await tester.pumpAndSettle();

    expect(find.text('Math homework from WebUntis'), findsOneWidget);
    expect(find.text('Doctor invoice'), findsNothing);
  });

  testWidgets('settings expose theme and backup controls', (tester) async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.quickAdd(title: 'Passport renewal');

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('System theme'), findsOneWidget);

    await tester.ensureVisible(find.text('Appearance'));
    await tester.pumpAndSettle();
    final appearanceRow = find.ancestor(
      of: find.text('Appearance'),
      matching: find.byType(InkWell),
    );
    await tester.tap(appearanceRow.first);
    await tester.pumpAndSettle();
    expect(controller.themePreference, AppThemePreference.light);
    expect(find.text('Light theme'), findsOneWidget);

    await tester.ensureVisible(find.text('Export / import'));
    await tester.pumpAndSettle();
    final exportRow = find.ancestor(
      of: find.text('Export / import'),
      matching: find.byType(InkWell),
    );
    await tester.tap(exportRow.first);
    await tester.pumpAndSettle();
    expect(find.text('Export backup file'), findsOneWidget);
    expect(find.text('Import backup file'), findsOneWidget);
  });

  testWidgets(
    'detail dialog edits title category waiting reminder and note attachment',
    (tester) async {
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      await controller.quickAdd(title: 'Doctor invoice reimbursement');

      await tester.pumpWidget(StillOpenApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doctor invoice reimbursement'));
      await tester.pumpAndSettle();

      expect(find.text('Next'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Book appointment'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Mark Done'), findsOneWidget);
      await tester.tap(find.text('Doctor invoice reimbursement').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Updated doctor invoice',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(controller.items.first.title, 'Updated doctor invoice');

      await tester.tap(find.text('Updated doctor invoice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(of: find.text('Category'), matching: find.byType(InkWell))
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose category'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await controller.setCategory(controller.selectedItem!, Category.medical);
      expect(controller.selectedItem!.category, Category.medical);

      await controller.setWaitingOn(controller.selectedItem!, 'Insurance');
      expect(controller.selectedItem!.waitingOn, 'Insurance');

      await controller.setReminderToday(controller.selectedItem!);
      await tester.pumpAndSettle();
      expect(controller.selectedItem!.reminderText, startsWith('Today'));

      await tester.tap(find.text('Attachments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Attachment note body',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.attachments.single.label, 'Attachment note body');
    },
  );

  testWidgets(
    'row action menus and smart capture exercise production actions',
    (tester) async {
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      await controller.quickAdd(title: 'Draft candidate');
      await controller.moveBackward(controller.selectedItem!);

      await tester.pumpWidget(StillOpenApp(controller: controller));
      await tester.pumpAndSettle();
      controller.selectTab(HomeTab.draft);
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Draft candidate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make Open'));
      await tester.pumpAndSettle();
      expect(controller.items.single.state, ItemState.open);

      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'School trip permission',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(controller.selectedItem!.category, Category.school);
      expect(find.text('School trip permission'), findsWidgets);
    },
  );

  testWidgets('filter and sort dialog updates the visible item set', (
    tester,
  ) async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.quickAdd(title: 'Doctor claim');
    await controller.setCategory(controller.selectedItem!, Category.medical);
    await controller.quickAdd(title: 'School permission');
    await controller.setCategory(controller.selectedItem!, Category.school);

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All domains'));
    await tester.pumpAndSettle();
    expect(find.text('Filter items'), findsOneWidget);
    expect(find.text('All · current'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    await _tapActionRow(tester, 'Medical');
    await tester.pumpAndSettle();
    expect(controller.domainFilter, DomainFilter.medical);
    expect(find.text('Doctor claim'), findsOneWidget);
    expect(find.text('School permission'), findsNothing);

    await tester.tap(find.text('Medical'));
    await tester.pumpAndSettle();
    await _tapActionRow(tester, 'Category');
    expect(controller.sortMode, SortMode.category);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(controller.domainFilter, DomainFilter.all);
  });

  testWidgets('settings dialogs cover reminders info export import and clear', (
    tester,
  ) async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.quickAdd(title: 'Passport renewal');

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    await _tapSettingsRow(tester, 'Reminders');
    expect(find.text('Reminder defaults'), findsOneWidget);
    await tester.tap(find.text('Next week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.defaultReminderPreset, 'Next week');

    await _tapSettingsRow(tester, 'How StillOpen works');
    expect(find.text('How StillOpen works'), findsWidgets);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await _tapSettingsRow(tester, 'Export / import');
    expect(find.text('Export backup file'), findsOneWidget);
    expect(find.text('Import backup file'), findsOneWidget);
    expect(find.text('Replace local data on import'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Diagnostics'), findsOneWidget);
    await _tapSettingsRow(tester, 'Privacy');
    expect(find.text('Privacy'), findsWidgets);
    expect(find.textContaining('StillOpen stores items'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await _tapSettingsRow(tester, 'Clear local data');
    expect(find.text('Clear local data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.items, isNotEmpty);
    await _tapSettingsRow(tester, 'Clear local data');
    await tester.tap(find.text('Clear data'));
    await tester.pumpAndSettle();
    expect(controller.items, isEmpty);
  });

  testWidgets('key icon controls expose production semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.quickAdd(title: 'Attachment audit');
    await controller.addNoteAttachment(controller.selectedItem!, 'Local note');

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Search'), findsOneWidget);
    expect(find.bySemanticsLabel('Add from camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Create item'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect(find.bySemanticsLabel('Add item'), findsOneWidget);

    await tester.tap(find.text('Attachment audit'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Mark Done'), findsOneWidget);

    await tester.tap(find.text('Attachments'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Open attachment'), findsOneWidget);
    expect(find.bySemanticsLabel('Delete attachment'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await _tapSettingsRow(tester, 'Export / import');
    expect(find.text('Export backup file'), findsOneWidget);
    expect(find.text('Import backup file'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Export backup file')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Import backup file')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('opening and saving a note attachment does not crash', (
    tester,
  ) async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.quickAdd(title: 'Note attachment crash');
    await controller.addNoteAttachment(
      controller.selectedItem!,
      'Original note',
    );

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note attachment crash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attachments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open attachment'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note attachment'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('attachment_note_edit_input')),
      'Edited note',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(controller.attachments.single.label, 'Edited note');
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text renders core screens without overflow', (
    tester,
  ) async {
    for (final scale in [1.3, 1.6, 2.0]) {
      await _pumpAccessibleApp(
        tester,
        StillOpenController(store: FakeStore()),
        textScaleFactor: scale,
        size: const Size(390, 844),
      );
      await _exerciseCoreScreens(tester);
      final exception = tester.takeException();
      expect(exception?.toString(), isNull);
    }
  });

  testWidgets('compact phone sizes render core screens without overflow', (
    tester,
  ) async {
    for (final size in [const Size(360, 640), const Size(390, 844)]) {
      await _pumpAccessibleApp(
        tester,
        StillOpenController(store: FakeStore()),
        size: size,
      );
      await _exerciseCoreScreens(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('dark mode renders home detail settings and export dialog', (
    tester,
  ) async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.setThemePreference(AppThemePreference.dark);
    await controller.quickAdd(title: 'Dark mode invoice');

    await _pumpAccessibleApp(tester, controller, size: const Size(390, 844));
    expect(find.text('Dark mode invoice'), findsOneWidget);
    await tester.tap(find.text('Dark mode invoice'));
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _tapSettingsRow(tester, 'Export / import');
    expect(find.text('Export backup file'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture menu creates the expanded template types', (
    tester,
  ) async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();

    for (final label in [
      'Home / warranty',
      'Shopping / return',
      'Money / bill',
      'Document',
      'Other',
    ]) {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await _tapActionRow(tester, 'More templates');
      expect(find.text(label), findsOneWidget);
      await _tapActionRow(tester, label);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    expect(
      controller.items.map((item) => item.templateType).toSet(),
      containsAll([
        TemplateType.home,
        TemplateType.shoppingReturn,
        TemplateType.money,
        TemplateType.document,
        TemplateType.other,
      ]),
    );
  });

  testWidgets(
    'detail primary actions cover normal medical long term and done',
    (tester) async {
      final controller = StillOpenController(store: FakeStore());
      await controller.load();
      await controller.quickAdd(title: 'Normal task');
      final normal = controller.selectedItem!;
      await controller.createFromTemplate(TemplateType.medicalClaim);
      final medical = controller.selectedItem!;
      await controller.createFromTemplate(TemplateType.longTerm);
      final longTerm = controller.selectedItem!;

      await tester.pumpWidget(StillOpenApp(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text(normal.title));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Set reminder'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Mark Done'), findsOneWidget);
      await _tapButton(tester, 'Mark Done');
      await tester.pumpAndSettle();
      expect(
        controller.items.firstWhere((item) => item.id == normal.id).state,
        ItemState.done,
      );
      expect(find.text('OK'), findsNothing);

      await tester.tap(find.text('Done 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(normal.title));
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Reopen');
      await tester.pumpAndSettle();
      expect(
        controller.items.firstWhere((item) => item.id == normal.id).state,
        ItemState.open,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await controller.addSharedText('Draft from capture');
      final draft = controller.selectedItem!;
      await tester.pumpAndSettle();
      await tester.tap(find.text(draft.title));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Make Open'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Keep Draft'), findsOneWidget);
      await _tapButton(tester, 'Make Open');
      await tester.pumpAndSettle();
      expect(
        controller.items.firstWhere((item) => item.id == draft.id).state,
        ItemState.open,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(medical.title));
      await tester.drag(find.byType(ListView).first, const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(find.text(medical.title));
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Book appointment');
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Have the appointment');
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Mark submitted');
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Response received');
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Forward private');
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Private response');
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Mark Done');
      await tester.pumpAndSettle();
      expect(
        controller.items.firstWhere((item) => item.id == medical.id).state,
        ItemState.done,
      );
      expect(find.text('OK'), findsNothing);

      await controller.reopen(medical);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('far_future_toggle')));
      await tester.drag(find.byType(ListView).first, const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('far_future_toggle')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(longTerm.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(longTerm.title));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Mark booked'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Complete cycle'),
        findsOneWidget,
      );
      expect(find.text('Repeat: Every 6 months'), findsOneWidget);
      await _tapButton(tester, 'Mark booked');
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(OutlinedButton, 'Change reminder'),
        findsOneWidget,
      );
      await _tapButton(tester, 'Complete cycle');
      await tester.pumpAndSettle();
      expect(find.text('Set next reminder?'), findsNothing);
      expect(
        controller.items
            .firstWhere((item) => item.id == longTerm.id)
            .reminderText,
        contains('20:00'),
      );
      expect(
        controller.items.firstWhere((item) => item.id == longTerm.id).state,
        ItemState.open,
      );
    },
  );

  testWidgets('detail date reminder waiting and share dialogs handle actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': clipboardText};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.quickAdd(title: 'Insurance reimbursement');

    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insurance reimbursement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    await _tapActionRow(tester, 'Due date');
    expect(find.text('Due date'), findsWidgets);
    await _tapActionRow(tester, 'Tomorrow');
    expect(controller.selectedItem!.dueText, startsWith('Tomorrow'));

    await _tapActionRow(tester, 'Reminder');
    await _tapActionRow(tester, 'Tomorrow 20:00');
    expect(controller.selectedItem!.reminderText, startsWith('Tomorrow'));

    await _tapActionRow(tester, 'Waiting on');
    await _tapActionRow(tester, 'Insurance');
    expect(controller.selectedItem!.waitingOn, 'Insurance');

    await _tapButton(tester, 'Share item');
    expect(clipboardText, contains('Insurance reimbursement'));
    expect(clipboardText, contains('Waiting on: Insurance'));
  });

  testWidgets('long-term repeat is visible and yearly completion stays open', (
    tester,
  ) async {
    final controller = StillOpenController(store: FakeStore());
    await controller.load();
    await controller.createFromTemplate(TemplateType.longTerm);
    final id = controller.selectedItem!.id;
    await tester.pumpWidget(StillOpenApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('far_future_toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book dentist check'));
    await tester.pumpAndSettle();
    expect(find.text('Repeat: Every 6 months'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit_recurrence')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('recurrence_custom_input')),
      'Before season',
    );
    await _tapButton(tester, 'Save recurrence');
    await tester.pumpAndSettle();
    expect(
      find.text('Use Every N days, weeks, months, or years'),
      findsWidgets,
    );
    expect(controller.selectedItem!.recurrenceHint, 'Every 6 months');
    await _tapActionRow(tester, 'Yearly');
    expect(controller.selectedItem!.recurrenceHint, 'Yearly');
    expect(controller.selectedItem!.nextCycleAt, contains('20:00'));
    await tester.pumpAndSettle();
    expect(find.text('Repeat: Yearly'), findsOneWidget);
    await _tapButton(tester, 'Complete cycle');
    await tester.pumpAndSettle();
    expect(controller.items.single.id, id);
    expect(controller.items.single.state, ItemState.open);
    expect(controller.items.single.completedCycles, 1);
    expect(find.text('Open 1'), findsOneWidget);
  });
}

Future<void> _tapSettingsRow(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title).first);
  await tester.pump(const Duration(milliseconds: 100));
  final row = find.ancestor(
    of: find.text(title).first,
    matching: find.byType(InkWell),
  );
  await tester.tap(row.first);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tapActionRow(WidgetTester tester, String label) async {
  final text = find.text(label);
  await tester.ensureVisible(text.last);
  await tester.pumpAndSettle();
  final row = find.ancestor(of: text.last, matching: find.byType(InkWell));
  await tester.tap(row.last);
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = [
    find.widgetWithText(FilledButton, label),
    find.widgetWithText(OutlinedButton, label),
    find.widgetWithText(TextButton, label),
    find.text(label),
  ].firstWhere((finder) => finder.evaluate().isNotEmpty);
  await tester.ensureVisible(button.last);
  await tester.pumpAndSettle();
  await tester.tap(button.last);
  await tester.pumpAndSettle();
}

Future<void> _pumpAccessibleApp(
  WidgetTester tester,
  StillOpenController controller, {
  double textScaleFactor = 1.0,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.binding.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(() async {
    tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.binding.setSurfaceSize(null);
  });
  await controller.load();
  if (controller.items.isEmpty) {
    await controller.quickAdd(title: 'Responsive audit item');
    await controller.addSharedText('Incoming draft text');
  }
  await tester.pumpWidget(StillOpenApp(controller: controller));
  await tester.pumpAndSettle();
}

Future<void> _exerciseCoreScreens(WidgetTester tester) async {
  expect(find.text('StillOpen'), findsOneWidget);
  _expectNoFlutterException(tester, 'home');
  await tester.tap(find.text('Draft 1'));
  await tester.pumpAndSettle();
  expect(find.text('Incoming draft text'), findsOneWidget);
  _expectNoFlutterException(tester, 'draft tab');
  await tester.tap(find.text('Open 1'));
  await tester.pumpAndSettle();
  _expectNoFlutterException(tester, 'open tab');
  await tester.tap(find.text('Responsive audit item'));
  await tester.pumpAndSettle();
  expect(find.text('Next'), findsOneWidget);
  _expectNoFlutterException(tester, 'detail');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  _expectNoFlutterException(tester, 'detail close');
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  expect(find.text('Settings'), findsOneWidget);
  _expectNoFlutterException(tester, 'settings');
  await _tapSettingsRow(tester, 'Export / import');
  expect(find.text('Export backup file'), findsOneWidget);
  _expectNoFlutterException(tester, 'export import');
  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();
  _expectNoFlutterException(tester, 'export close');
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
  _expectNoFlutterException(tester, 'settings close');
}

void _expectNoFlutterException(WidgetTester tester, String stage) {
  final exception = tester.takeException();
  expect(exception?.toString(), isNull, reason: stage);
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

class _StartupTestIngestor extends IncomingShareIngestor {
  _StartupTestIngestor({required super.controller})
    : super(store: DirectoryPendingShareStore(Directory.systemTemp));

  int calls = 0;

  @override
  Future<int> ingestPendingShares() async {
    calls += 1;
    final saved = await controller.addSharedText('iOS widget pending share');
    return saved ? 1 : 0;
  }
}

class DelayedFakeStore extends FakeStore {
  final Completer<void> _loadGate = Completer<void>();

  void release() {
    if (!_loadGate.isCompleted) _loadGate.complete();
  }

  @override
  Future<String?> getString(String key) async {
    await _loadGate.future;
    return super.getString(key);
  }
}

class BlockingReminderScheduler implements ReminderScheduler {
  final Completer<void> _release = Completer<void>();
  bool permissionRequested = false;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> requestPermissions() async {
    permissionRequested = true;
    await _release.future;
  }

  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async {}

  @override
  Future<void> cancel(int itemId) async {}

  @override
  Future<void> cancelAll() async {}
}

class BlockingCancelReminderScheduler implements ReminderScheduler {
  final Completer<void> _release = Completer<void>();
  bool cancelStarted = false;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async {}

  @override
  Future<void> cancel(int itemId) async {
    cancelStarted = true;
    await _release.future;
  }

  @override
  Future<void> cancelAll() async {}
}

class FakeIncomingShareSource implements IncomingShareSource {
  FakeIncomingShareSource({
    this.initialMedia = const [],
    this.streamMedia = const [],
    this.initialExtras = const [],
    this.streamExtras = const [],
  });

  final List<SharedMediaFile> initialMedia;
  final List<List<SharedMediaFile>> streamMedia;
  final List<IncomingShareExtra> initialExtras;
  final List<List<IncomingShareExtra>> streamExtras;
  final StreamController<List<SharedMediaFile>> _controller =
      StreamController<List<SharedMediaFile>>.broadcast();
  final StreamController<List<IncomingShareExtra>> _extraController =
      StreamController<List<IncomingShareExtra>>.broadcast();
  int resetCalls = 0;

  @override
  Future<List<SharedMediaFile>> getInitialMedia() async => initialMedia;

  @override
  Future<List<IncomingShareExtra>> getInitialExtras() async => initialExtras;

  @override
  Stream<List<SharedMediaFile>> getMediaStream() {
    for (final media in streamMedia) {
      scheduleMicrotask(() {
        if (!_controller.isClosed) _controller.add(media);
      });
    }
    return _controller.stream;
  }

  @override
  Stream<List<IncomingShareExtra>> getExtraStream() {
    for (final extras in streamExtras) {
      scheduleMicrotask(() {
        if (!_extraController.isClosed) _extraController.add(extras);
      });
    }
    return _extraController.stream;
  }

  @override
  Future<void> reset() async {
    resetCalls += 1;
  }
}
