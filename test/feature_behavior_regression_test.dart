// User-feature regressions from the October 2026 functional audit.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:clock/clock.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/main.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/models.dart';
import 'package:stillopen/src/rules.dart';

class MemoryStore implements StillOpenStore {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

class EmptySource implements IncomingShareSource {
  @override
  Stream<List<SharedMediaFile>> getMediaStream() => const Stream.empty();
  @override
  Future<List<SharedMediaFile>> getInitialMedia() async => [];
  @override
  Stream<List<IncomingShareExtra>> getExtraStream() => const Stream.empty();
  @override
  Future<List<IncomingShareExtra>> getInitialExtras() async => [];
  @override
  Future<void> reset() async {}
}

Future<void> pump(WidgetTester tester, StillOpenController controller) async {
  await tester.pumpWidget(
    StillOpenApp(controller: controller, incomingShareSource: EmptySource()),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(FilledButton, label).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> loadRoboto(WidgetTester tester) async {
  await tester.runAsync(() async {
    final config =
        jsonDecode(await File('.dart_tool/package_config.json').readAsString())
            as Map<String, dynamic>;
    final flutter = (config['packages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((package) => package['name'] == 'flutter');
    final sdkRoot = Directory.fromUri(
      Uri.parse(flutter['rootUri'] as String),
    ).parent.parent;
    final bytes = await File(
      '${sdkRoot.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    ).readAsBytes();
    for (final family in ['Roboto', 'Ahem']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
}

void main() {
  testWidgets('FEATURE-01 medical private response advances to reimbursed', (
    tester,
  ) async {
    final controller = StillOpenController(store: MemoryStore());
    await controller.load();
    await controller.createFromTemplate(TemplateType.medicalClaim);
    await pump(tester, controller);
    await tapText(tester, 'Doctor invoice');
    for (final action in [
      'Book appointment',
      'Have the appointment',
      'Mark submitted',
      'Response received',
      'Forward private',
      'Private response',
    ]) {
      await tapButton(tester, action);
    }
    expect(controller.selectedItem!.claimStage, 'Private response received');
    expect(find.widgetWithText(FilledButton, 'Reimbursed'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Forward private'), findsNothing);
    await tapButton(tester, 'Reimbursed');
    expect(controller.selectedItem!.state, ItemState.done);
    expect(controller.selectedItem!.closureReason, ClosureReason.reimbursed);
  });

  testWidgets('FEATURE-02 newly saved cross-domain item remains discoverable', (
    tester,
  ) async {
    final controller = StillOpenController(store: MemoryStore());
    await controller.load();
    await controller.quickAdd(
      title: 'Existing medical claim',
      category: Category.medical,
      categoryEdited: true,
    );
    controller.selectDomainFilter(DomainFilter.medical);
    await pump(tester, controller);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tapText(tester, 'Quick note');
    await tester.enterText(
      find.byKey(const Key('quick_add_title')),
      'Return a parcel',
    );
    await tester.tap(find.byKey(const Key('quick_add_save')));
    await tester.pumpAndSettle();
    final saved = controller.selectedItem!;
    expect(saved.category, Category.shopping);
    expect(
      find.text('Return a parcel'),
      findsWidgets,
    ); // Detail and the newly visible row.
    await tapText(tester, 'OK');
    expect(controller.items.any((item) => item.id == saved.id), isTrue);
    expect(controller.visibleItems.any((item) => item.id == saved.id), isTrue);
    expect(find.text('Return a parcel'), findsOneWidget);
    expect(controller.domainFilter, DomainFilter.all);
  });

  testWidgets('FEATURE-03 search finds note body beyond the attachment label', (
    tester,
  ) async {
    final controller = StillOpenController(store: MemoryStore());
    await controller.load();
    await controller.quickAdd(title: 'Call the supplier');
    await pump(tester, controller);
    await tapText(tester, 'Call the supplier');
    await tapText(tester, 'Attachments');
    await tapText(tester, 'Note');
    await tester.enterText(
      find.byType(TextField).last,
      'Long introduction without the lookup value that exceeds forty characters.\nReference code ORCHID-49372',
    );
    await tapText(tester, 'Save');
    expect(controller.attachments.single.uri, startsWith('stillopen-note:'));
    await tapText(tester, 'Close');
    await tapText(tester, 'OK');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('search_field')),
      'ORCHID-49372',
    );
    await tapText(tester, 'Done');
    expect(find.text('No matching items'), findsNothing);
    expect(controller.visibleItems.single.title, 'Call the supplier');
    expect(
      controller.attachments.single.label,
      isNot(contains('ORCHID-49372')),
    );
    expect(find.text('Call the supplier'), findsOneWidget);
  });

  testWidgets(
    'FEATURE-04 timeline displays real dates and retains completion history',
    (tester) async {
      final store = MemoryStore();
      store.values['stillopen_items_v1'] = jsonEncode([
        StillOpenItem(
          id: 1,
          title: 'Old item',
          state: ItemState.open,
          category: Category.other,
          createdAt: DateTime(2024, 1, 1).millisecondsSinceEpoch,
          updatedAt: DateTime(2024, 1, 1).millisecondsSinceEpoch,
        ).toJson(),
      ]);
      final controller = StillOpenController(store: store);
      await controller.load();
      controller.openDetails(1);
      await controller.markDone(controller.selectedItem!);
      await controller.reopen(controller.selectedItem!);
      final events = controller.selectedDetails!.timeline;
      expect(events.length, greaterThanOrEqualTo(3));
      expect(events.first.createdAt, isNonZero);
      expect(events.any((event) => event.label.contains('Done')), isTrue);
      expect(events.any((event) => event.label.contains('Reopened')), isTrue);
      await pump(tester, controller);
      await tapText(tester, 'Old item');
      await tapText(tester, 'More');
      await tester.ensureVisible(find.text('Timeline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2024'), findsWidgets);
      expect(find.text('Just now'), findsNothing);
    },
  );

  testWidgets('FEATURE-05 home shortcut setting changes actionable controls', (
    tester,
  ) async {
    final controller = StillOpenController(store: MemoryStore());
    await controller.load();
    await pump(tester, controller);
    final shortcut = find.byKey(const Key('template_shortcut_medicalClaim'));
    expect(shortcut, findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Show template shortcuts');
    await tapText(tester, 'Done');
    expect(shortcut, findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Show template shortcuts');
    await tapText(tester, 'Done');
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(controller.selectedItem!.templateType, TemplateType.medicalClaim);
    expect(
      find.widgetWithText(FilledButton, 'Book appointment'),
      findsOneWidget,
    );
  });

  testWidgets(
    'FEATURE-06 future collapse expands and Never keeps future items visible',
    (tester) async {
      final store = MemoryStore();
      final controller = StillOpenController(store: store);
      await controller.load();
      await controller.createFromTemplate(TemplateType.longTerm);
      controller.closeDetails();
      await pump(tester, controller);
      expect(find.text('Book dentist check'), findsNothing);
      expect(find.byKey(const Key('far_future_toggle')), findsOneWidget);
      await tester.tap(find.byKey(const Key('far_future_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Book dentist check'), findsOneWidget);
      await tester.tap(find.byKey(const Key('far_future_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Book dentist check'), findsNothing);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      while (controller.farFutureThreshold != FarFutureThreshold.never) {
        await tapText(tester, 'Collapse items more than');
      }
      await tapText(tester, 'Done');
      expect(find.text('Book dentist check'), findsOneWidget);
      expect(find.byKey(const Key('far_future_toggle')), findsNothing);
      final restored = StillOpenController(store: store);
      await restored.load();
      expect(restored.farFutureThreshold, FarFutureThreshold.never);
      controller.setQuery('dentist');
      expect(controller.visibleItems.single.title, 'Book dentist check');
    },
  );

  testWidgets(
    'FEATURE-07 overdue ordinary item needs attention on home and detail',
    (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 10, 6, 21)), () async {
        final controller = StillOpenController(store: MemoryStore());
        await controller.load();
        await withClock(Clock.fixed(DateTime(2026, 10, 6, 19)), () async {
          await controller.quickAdd(
            title: 'Pay the ordinary invoice',
            category: Category.other,
            categoryEdited: true,
          );
          await controller.setDateToday(controller.selectedItem!);
        });
        expect(
          controller.selectedItem!.dueAt,
          lessThan(clock.now().millisecondsSinceEpoch),
        );
        expect(minimalStatusSentence(controller.selectedItem!), 'Overdue');
        await pump(tester, controller);
        expect(find.text('Later'), findsNothing);
        expect(find.text('Needs attention'), findsOneWidget);
        expect(find.text('Overdue'), findsOneWidget);
        await tapText(tester, 'Pay the ordinary invoice');
        expect(find.text('Overdue'), findsWidgets);
      });
    },
  );

  testWidgets(
    'FEATURE-08 reminder defaults remain reachable at compact 200 percent text',
    (tester) async {
      final controller = StillOpenController(store: MemoryStore());
      await controller.load();
      await pump(tester, controller);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Reminders');
      await loadRoboto(tester);
      final errors = <String>[];
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) =>
          errors.add(details.exceptionAsString());
      await tester.binding.setSurfaceSize(const Size(320, 568));
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(() async {
        FlutterError.onError = previousErrorHandler;
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpAndSettle();
      FlutterError.onError = previousErrorHandler;
      expect(errors, isEmpty);
      await tester.ensureVisible(
        find.byKey(const Key('reminder_default_minute')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reminder_default_minute')));
      await tester.pumpAndSettle();
      await tapText(tester, 'Save');
      expect(find.text('Reminder defaults'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'FEATURE-09 elapsed reminder and terminal controls use consistent attention',
    () {
      withClock(Clock.fixed(DateTime(2026, 10, 6, 21)), () {
        final past = StillOpenItem(
          id: 1,
          title: 'Reminder only',
          state: ItemState.open,
          category: Category.other,
          reminderText: 'Oct 6, 2026 20:00',
          reminderAt: DateTime(2026, 10, 6, 20).millisecondsSinceEpoch,
        );
        expect(statusLabel(past), 'Reminder due');
        expect(
          minimalFollowUpLine(
            past.copyWith(
              reminderText: 'Tomorrow 20:00',
              reminderAt: DateTime(2026, 10, 5, 20).millisecondsSinceEpoch,
            ),
          ),
          'Reminder Oct 5, 2026 20:00',
        );
        expect(minimalStatusSentence(past), 'Reminder due');
        expect(itemNeedsAttention(past), isTrue);
        expect(
          itemNeedsAttention(past.copyWith(state: ItemState.done)),
          isFalse,
        );
        expect(
          itemNeedsAttention(past.copyWith(state: ItemState.draft)),
          isFalse,
        );
        final future = past.copyWith(
          reminderAt: DateTime(2026, 10, 7, 20).millisecondsSinceEpoch,
        );
        expect(statusLabel(future), 'Reminder set');
        expect(itemNeedsAttention(future), isFalse);
      });
    },
  );

  test('FEATURE-10 waiting age comes from its timestamp as time advances', () {
    final item = StillOpenItem(
      id: 1,
      title: 'Waiting claim',
      state: ItemState.waiting,
      category: Category.medical,
      waitingSinceText: 'Just now',
      waitingSinceAt: DateTime(2026, 9, 1).millisecondsSinceEpoch,
    );
    withClock(
      Clock.fixed(DateTime(2026, 9, 10)),
      () => expect(waitingTooLong(item), isFalse),
    );
    withClock(Clock.fixed(DateTime(2026, 9, 20)), () {
      expect(waitingTooLong(item), isTrue);
      expect(minimalFollowUpLine(item), contains('September 1, 2026'));
      expect(minimalFollowUpLine(item), isNot(contains('Just now')));
      expect(
        minimalFollowUpLine(item.copyWith(clearWaitingSinceAt: true)),
        contains('Waiting start not recorded'),
      );
    });
  });

  testWidgets(
    'FEATURE-11 blocked notifications stay explicit and refresh on resume',
    (tester) async {
      final reminders = AvailabilityReminders();
      final controller = StillOpenController(
        store: MemoryStore(),
        reminderScheduler: reminders,
      );
      await controller.load();
      await controller.quickAdd(title: 'Keep this visible');
      await controller.setReminderTomorrow(controller.selectedItem!);
      await pump(tester, controller);
      expect(find.text('Notifications blocked'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Notifications');
      expect(
        find.descendant(
          of: find.byKey(const Key('notifications_enabled_switch')),
          matching: find.text('Blocked in device settings'),
        ),
        findsWidgets,
      );
      expect(
        find.byKey(const Key('notifications_enabled_switch')),
        findsOneWidget,
      );
      await tapText(tester, 'Open device settings');
      expect(reminders.settingsOpened, 1);
      reminders.allowed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('notifications_enabled_switch')),
          matching: find.text('Enabled on this device'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('notifications_enabled_switch')));
      await tester.pumpAndSettle();
      expect(controller.notificationsEnabled, isFalse);
      expect(
        find.descendant(
          of: find.byKey(const Key('notifications_enabled_switch')),
          matching: find.text('Off on this device'),
        ),
        findsOneWidget,
      );
    },
  );

  test(
    'FEATURE-12 unknown notification permission does not claim Enabled',
    () async {
      final controller = StillOpenController(store: MemoryStore());
      await controller.load();
      expect(
        notificationAvailabilityLabel(controller),
        'Device permission not verified',
      );
    },
  );

  testWidgets(
    'FEATURE-13 compact large-text attachment controls remain reachable',
    (tester) async {
      await loadRoboto(tester);
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() async {
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
      });
      final controller = StillOpenController(store: MemoryStore());
      await controller.load();
      await controller.quickAdd(title: 'Keep the supplier response');
      await controller.addNoteAttachment(
        controller.selectedItem!,
        'Supplier response and return reference\nReference ORCHID-49372',
      );
      await pump(tester, controller);
      await tapText(tester, 'Keep the supplier response');
      await tapText(tester, 'Attachments');

      for (final scale in [1.0, 2.0]) {
        tester.binding.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final action in [
          'Open attachment',
          'Rename attachment',
          'Delete attachment',
        ]) {
          final button = find.byTooltip(action);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          final size = tester.getSize(button);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
      }

      Future<void> tapAction(String tooltip) async {
        final button = find.byTooltip(tooltip);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await tapAction('Open attachment');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('attachment_note_edit_input')),
            )
            .controller!
            .text,
        contains('ORCHID-49372'),
      );
      await tapText(tester, 'Cancel');
      await tapAction('Rename attachment');
      await tester.enterText(
        find.byKey(const Key('attachment_rename_input')),
        'Supplier reference',
      );
      await tapText(tester, 'Save');
      expect(controller.attachments.single.label, 'Supplier reference');
      expect(find.text('Supplier reference'), findsOneWidget);
      await tapAction('Delete attachment');
      await tapText(tester, 'Delete');
      expect(controller.attachments, isEmpty);
      expect(find.text('No attachments yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class AvailabilityReminders implements ReminderScheduler, ReminderAvailability {
  bool allowed = false;
  int settingsOpened = 0;
  @override
  Future<bool?> notificationsAllowed() async => allowed;
  @override
  Future<void> openNotificationSettings() async {
    settingsOpened++;
  }

  @override
  Future<void> requestPermissions() async {}
  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async {}
  @override
  Future<void> cancel(int itemId) async {}
  @override
  Future<void> cancelAll() async {}
}
