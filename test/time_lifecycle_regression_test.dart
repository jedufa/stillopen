// Regressions converted from the frozen user-impact audit.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/date_logic.dart';
import 'package:stillopen/src/diagnostics.dart';
import 'package:stillopen/src/models.dart';
import 'package:stillopen/src/rules.dart';

void main() {
  setUp(() => StillOpenDiagnostics.instance.clearForTests());

  test(
    'TIME-01 next-cycle completion keeps its future reminder scheduled',
    () async {
      final scheduler = AuditReminderScheduler();
      final controller = StillOpenController(
        store: AuditTimeStore(),
        reminderScheduler: scheduler,
      );
      await controller.load();
      await controller.createFromTemplate(TemplateType.longTerm);
      final id = controller.selectedItem!.id;
      final nextYear = DateTime.now().year + 1;

      await controller.setLongTermNextReminder(
        controller.selectedItem!,
        'Jun 4, $nextYear 09:05',
      );

      expect(controller.selectedItem!.state, ItemState.open);
      expect(controller.selectedItem!.completedCycles, 1);
      expect(controller.snackbarMessage, 'Cycle complete · next reminder set');
      expect(
        scheduler.scheduled[id],
        DateTime(nextYear, 6, 4, 9, 5),
        reason:
            'Completing this cycle must leave the promised next cycle reminder active.',
      );
    },
  );

  test('TIME-01 weekly next-cycle reminder survives restart', () async {
    final scheduler = AuditReminderScheduler();
    final store = AuditTimeStore();
    final controller = StillOpenController(
      store: store,
      reminderScheduler: scheduler,
    );
    await controller.load();
    await controller.createFromTemplate(TemplateType.longTerm);
    await controller.setRecurrenceHint(controller.selectedItem!, 'Weekly');
    await controller.setLongTermNextReminderFromRecurrence(
      controller.selectedItem!,
    );
    expect(controller.selectedItem!.reminderText, contains('20:00'));
    expect(controller.selectedItem!.state, ItemState.open);
    expect(
      scheduler.scheduled,
      contains(controller.selectedItem!.id),
      reason: 'Cycle completion must leave the next weekly reminder scheduled.',
    );
    final restoredScheduler = AuditReminderScheduler();
    final restored = StillOpenController(
      store: store,
      reminderScheduler: restoredScheduler,
    );
    await restored.load();
    expect(
      restoredScheduler.scheduled[controller.selectedItem!.id],
      scheduler.scheduled[controller.selectedItem!.id],
      reason: 'A restart must not move or lose the saved next cycle.',
    );
  });

  test(
    'TIME-02 reload does not move an expired saved Tomorrow into the future',
    () async {
      final now = DateTime.now();
      final savedOn = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 3));
      // Persisted shape produced by setReminderTomorrow: a relative display label
      // and an update timestamp, with no absolute reminder timestamp.
      final saved = auditItem(
        id: 42,
        reminderText: 'Tomorrow 09:05',
        createdAt: savedOn.millisecondsSinceEpoch,
        updatedAt: savedOn.millisecondsSinceEpoch,
      );
      final store = AuditTimeStore.withItems([saved]);
      final scheduler = AuditReminderScheduler();
      final controller = StillOpenController(
        store: store,
        reminderScheduler: scheduler,
      );

      await controller.load();

      expect(controller.items.single.reminderText, 'Tomorrow 09:05');
      expect(
        scheduler.scheduled,
        isEmpty,
        reason:
            'Tomorrow selected three days ago has expired; reloading must not schedule tomorrow anew.',
      );
    },
  );

  test(
    'TIME-02 quick-add Tomorrow retains its original date when time advances',
    () async {
      final controller = StillOpenController(store: AuditTimeStore());
      await controller.load();
      await controller.quickAdd(title: 'Return borrowed book', tomorrow: true);
      final item = controller.selectedItem!;
      final created = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
      final originalRank = sortDateRank(item, today: created);
      final laterRank = sortDateRank(
        item,
        today: created.add(const Duration(days: 7)),
      );

      expect(
        laterRank,
        originalRank,
        reason:
            'Advancing the comparison clock must not advance a saved due date.',
      );
    },
  );

  test('TIME-02 display stops calling a saved old due date Tomorrow', () async {
    final controller = StillOpenController(store: AuditTimeStore());
    addTearDown(controller.dispose);
    await controller.load();
    await controller.quickAdd(title: 'Stable due date', tomorrow: true);
    final item = controller.selectedItem!;
    final later = DateTime.fromMillisecondsSinceEpoch(
      item.createdAt,
    ).add(const Duration(days: 7));
    final display = displayStillOpenDate(
      item.dueText,
      item.dueAt,
      today: later,
    );
    expect(display, isNot('Tomorrow'));
    expect(
      display,
      contains('${DateTime.fromMillisecondsSinceEpoch(item.dueAt!).year}'),
    );
  });

  test('TIME-01 completed cycle schedules again after restart', () async {
    final store = AuditTimeStore();
    final first = StillOpenController(
      store: store,
      reminderScheduler: AuditReminderScheduler(),
    );
    addTearDown(first.dispose);
    await first.load();
    await first.createFromTemplate(TemplateType.longTerm);
    await first.setLongTermNextReminder(first.selectedItem!, '1 month');
    final expected = first.selectedItem!.nextCycleAtEpoch;
    expect(expected, isNotNull);
    final scheduler = AuditReminderScheduler();
    final restarted = StillOpenController(
      store: store,
      reminderScheduler: scheduler,
    );
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(
      scheduler.scheduled[restarted.items.single.id]?.millisecondsSinceEpoch,
      expected,
    );
  });

  test('TIME-01 monthly recurrence clamps a month-end calendar date', () {
    expect(
      parseStillOpenDate('1 month', anchor: DateTime(2028, 1, 31)),
      DateTime(2028, 2, 29, 20),
    );
  });

  test('TIME-03 date sorting honors the explicitly persisted year', () {
    final thisDecember = auditItem(id: 1, dueText: 'Dec 30, 2030 09:00');
    final nextJanuary = auditItem(id: 2, dueText: 'Jan 2, 2031 09:00');

    final sorted = sortForMode(
      [thisDecember, nextJanuary],
      SortMode.date,
      today: DateTime(2030, 12, 29),
    );

    expect(
      sorted.map((item) => item.id).toList(),
      [1, 2],
      reason:
          'December 2030 precedes January 2031; sorting must not treat both as 2030.',
    );
  });

  test('TIME-04 a past due date is not presented as Not due yet', () async {
    final controller = StillOpenController(store: AuditTimeStore());
    await controller.load();
    await controller.quickAdd(title: 'Old unresolved obligation');
    // The actual UI date picker allows dates from 2020 through 2100.
    await controller.setPickedDueDateTime(
      controller.selectedItem!,
      DateTime(2021, 1, 2),
      hour: 9,
      minute: 5,
    );

    expect(controller.selectedItem!.dueText, 'Jan 2, 2021 09:05');
    expect(
      minimalStatusSentence(controller.selectedItem!),
      'Overdue',
      reason:
          'A real date years in the past must receive date-pressure presentation.',
    );
  });

  test(
    'TIME-04 a waiting follow-up with a past calendar date is overdue',
    () async {
      final controller = StillOpenController(store: AuditTimeStore());
      await controller.load();
      await controller.quickAdd(title: 'Wait for response');
      await controller.setWaitingOn(controller.selectedItem!, 'Provider');
      await controller.setPickedReminder(
        controller.selectedItem!,
        DateTime(2021, 1, 2),
        hour: 9,
        minute: 5,
      );

      expect(controller.selectedItem!.followUpText, 'Jan 2, 2021 09:05');
      expect(
        followUpOverdue(controller.selectedItem!),
        isTrue,
        reason:
            'Follow-up pressure must compare dates, not require the label to contain yesterday or overdue.',
      );
    },
  );

  test(
    'TIME-05 failed scheduling does not leave an unqualified success message',
    () async {
      final scheduler = AuditReminderScheduler(failSchedule: true);
      final controller = StillOpenController(
        store: AuditTimeStore(),
        reminderScheduler: scheduler,
      );
      await controller.load();
      await controller.quickAdd(title: 'Important future reminder');
      await controller.setPickedReminder(
        controller.selectedItem!,
        DateTime(DateTime.now().year + 1, 6, 4),
        hour: 9,
        minute: 5,
      );

      expect(scheduler.attempts, 1);
      expect(scheduler.scheduled, isEmpty);
      expect(
        StillOpenDiagnostics.instance.toJson()['recent_errors'],
        isNotEmpty,
      );
      expect(
        controller.snackbarMessage,
        isNot('Reminder set'),
        reason:
            'Saving an item may succeed, but the user needs notice that the promised reminder failed.',
      );
    },
  );

  test(
    'TIME-CONTROL future absolute reminder schedules and ordinary Done cancels it',
    () async {
      final scheduler = AuditReminderScheduler();
      final controller = StillOpenController(
        store: AuditTimeStore(),
        reminderScheduler: scheduler,
      );
      await controller.load();
      await controller.quickAdd(title: 'Control task');
      final date = DateTime(DateTime.now().year + 1, 6, 4, 9, 5);
      await controller.setPickedReminder(
        controller.selectedItem!,
        date,
        hour: date.hour,
        minute: date.minute,
      );
      expect(scheduler.scheduled[controller.selectedItem!.id], date);
      await controller.markDone(controller.selectedItem!);
      expect(scheduler.scheduled, isEmpty);
      await controller.reopen(controller.selectedItem!);
      expect(scheduler.scheduled[controller.selectedItem!.id], date);
      expect(controller.selectedItem!.closureReason, ClosureReason.none);
    },
  );

  test(
    'TIME-CONTROL terminal filtering and case-insensitive note search preserve items',
    () {
      final open = auditItem(id: 1, notes: 'Invoice reference UNIQUE-27');
      final done = auditItem(id: 2, state: ItemState.done);
      final draft = auditItem(id: 3, state: ItemState.draft);
      final items = [open, done, draft];
      expect(filterForTab(items, HomeTab.open), [open]);
      expect(filterForTab(items, HomeTab.done), [done]);
      expect(filterForTab(items, HomeTab.draft), [draft]);
      expect(filterSearch(items, 'unique-27'), [open]);
    },
  );
}

StillOpenItem auditItem({
  int id = 1,
  String notes = '',
  ItemState state = ItemState.open,
  String dueText = '',
  String reminderText = '',
  int createdAt = 0,
  int updatedAt = 0,
}) => StillOpenItem(
  id: id,
  title: 'Audit task $id',
  notes: notes,
  state: state,
  category: Category.other,
  dueText: dueText,
  reminderText: reminderText,
  createdAt: createdAt,
  updatedAt: updatedAt,
);

class AuditTimeStore implements StillOpenStore {
  AuditTimeStore();

  AuditTimeStore.withItems(List<StillOpenItem> items) {
    values['stillopen_items_v1'] = jsonEncode(
      items.map((item) => item.toJson()).toList(),
    );
  }

  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

class AuditReminderScheduler implements ReminderScheduler {
  AuditReminderScheduler({this.failSchedule = false});

  final bool failSchedule;
  final scheduled = <int, DateTime>{};
  int attempts = 0;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> schedule(StillOpenItem item, DateTime when) async {
    attempts += 1;
    if (failSchedule) throw StateError('Synthetic scheduler rejection');
    scheduled[item.id] = when;
  }

  @override
  Future<void> cancel(int itemId) async {
    scheduled.remove(itemId);
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();
}
