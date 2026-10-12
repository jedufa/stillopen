import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/models.dart';
import 'package:stillopen/src/recurrence.dart';
import 'package:stillopen/src/rules.dart';

void main() {
  test('calendar recurrence clamps month ends and leap days', () {
    expect(
      RecurrenceRule.parse('Monthly')!.after(DateTime(2026, 1, 31, 20)),
      DateTime(2026, 2, 28, 20),
    );
    expect(
      RecurrenceRule.parse('Yearly')!.after(DateTime(2024, 2, 29, 20)),
      DateTime(2025, 2, 28, 20),
    );
    expect(
      RecurrenceRule.parse('Every 4 years')!.after(DateTime(2024, 2, 29)),
      DateTime(2028, 2, 29),
    );
    expect(
      RecurrenceRule.parse('Every 2 weeks')!.after(DateTime(2026, 9, 14)),
      DateTime(2026, 9, 28),
    );
    expect(RecurrenceRule.parse('Every 0 years'), isNull);
    expect(RecurrenceRule.parse('Before season'), isNull);
  });

  test('choosing yearly reschedules template and survives restart', () async {
    final store = _Store();
    final scheduler = _Scheduler();
    var controller = StillOpenController(
      store: store,
      reminderScheduler: scheduler,
    );
    await controller.load();
    await controller.createFromTemplate(TemplateType.longTerm);
    final id = controller.selectedItem!.id;
    expect(scheduler.scheduled[id], isNotNull);
    expect(controller.selectedItem!.recurrenceHint, 'Every 6 months');

    await controller.setRecurrenceHint(controller.selectedItem!, 'Yearly');
    final next = scheduler.scheduled[id]!;
    expect(next.year, DateTime.now().year + 1);
    expect(next.month, DateTime.now().month);
    expect(controller.selectedItem!.nextCycleAt, contains('${next.year}'));
    expect(controller.selectedItem!.reminderAt, next.millisecondsSinceEpoch);

    final restoredScheduler = _Scheduler();
    controller = StillOpenController(
      store: store,
      reminderScheduler: restoredScheduler,
    );
    await controller.load();
    expect(controller.selectedItem, isNull);
    expect(controller.items.single.recurrenceHint, 'Yearly');
    expect(restoredScheduler.scheduled[id], next);
  });

  test(
    'picked first date is kept, then completion advances and stop cancels',
    () async {
      final scheduler = _Scheduler();
      final store = _Store();
      final controller = StillOpenController(
        store: store,
        reminderScheduler: scheduler,
      );
      await controller.load();
      await controller.createFromTemplate(TemplateType.longTerm);
      final picked = DateTime(DateTime.now().year + 2, 5, 15, 9, 30);
      await controller.setPickedReminder(
        controller.selectedItem!,
        picked,
        hour: 9,
        minute: 30,
      );
      await controller.setRecurrenceHint(controller.selectedItem!, 'Yearly');
      final id = controller.selectedItem!.id;
      expect(scheduler.scheduled[id], picked);

      await controller.markLongTermBooked(controller.selectedItem!);
      await controller.markDone(controller.selectedItem!);
      final active = controller.selectedItem!;
      expect(active.state, ItemState.open);
      expect(active.completedCycles, 1);
      expect(active.lastCycleCompletedAt, isNotEmpty);
      expect(active.waitingOn, isEmpty);
      expect(active.dateUserEdited, isFalse);
      expect(controller.countForTab(HomeTab.open), 1);
      expect(controller.countForTab(HomeTab.done), 0);
      expect(
        scheduler.scheduled[id],
        DateTime.fromMillisecondsSinceEpoch(active.reminderAt!),
      );
      expect(scheduler.scheduled[id]!.year, DateTime.now().year + 1);

      await controller.stopLongTermRecurrence(active);
      expect(controller.selectedItem!.state, ItemState.done);
      expect(controller.selectedItem!.recurrenceHint, isEmpty);
      expect(controller.selectedItem!.reminderAt, isNull);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelled, contains(id));
      final backup =
          jsonDecode(controller.exportBackupJson()) as Map<String, dynamic>;
      expect((backup['items'] as List).single['completedCycles'], 1);

      await controller.setRecurrenceHint(controller.selectedItem!, 'Monthly');
      expect(controller.selectedItem!.state, ItemState.open);
      expect(controller.selectedTab, HomeTab.open);
      expect(scheduler.scheduled[id], isNotNull);
    },
  );

  test(
    'unsupported cadence is rejected without changing the scheduled item',
    () async {
      final scheduler = _Scheduler();
      final controller = StillOpenController(
        store: _Store(),
        reminderScheduler: scheduler,
      );
      await controller.load();
      await controller.createFromTemplate(TemplateType.longTerm);
      final before = controller.selectedItem!;
      final date = scheduler.scheduled[before.id];
      await expectLater(
        controller.setRecurrenceHint(before, 'Before season'),
        throwsFormatException,
      );
      expect(controller.selectedItem!.recurrenceHint, before.recurrenceHint);
      expect(scheduler.scheduled[before.id], date);
      await controller.setRecurrenceHint(before, '');
      expect(controller.selectedItem!.recurrenceHint, isEmpty);
      expect(scheduler.scheduled[before.id], date);
      await controller.markDone(controller.selectedItem!);
      expect(controller.selectedItem!.state, ItemState.done);
      expect(scheduler.scheduled, isEmpty);
    },
  );

  test(
    'legacy next-cycle reminders reopen while final Done stays Done',
    () async {
      final anchor = DateTime(2025, 4, 15, 11);
      final store = _Store();
      store.values['stillopen_items_v1'] = jsonEncode([
        StillOpenItem(
          id: 1,
          title: 'Annual checkup',
          state: ItemState.done,
          category: Category.longTerm,
          templateType: TemplateType.longTerm,
          recurrenceHint: 'Yearly',
          reminderText: '1 year',
          nextCycleAt: '1 year',
          closureReason: ClosureReason.completedThisCycle,
          updatedAt: anchor.millisecondsSinceEpoch,
        ).toJson(),
        StillOpenItem(
          id: 2,
          title: 'Finished for good',
          state: ItemState.done,
          category: Category.longTerm,
          templateType: TemplateType.longTerm,
          recurrenceHint: 'Yearly',
        ).toJson(),
      ]);
      final controller = StillOpenController(store: store);
      await controller.load();
      final active = controller.items.first;
      expect(active.state, ItemState.open);
      expect(
        active.reminderAt,
        DateTime(2026, 4, 15, 20).millisecondsSinceEpoch,
      );
      expect(active.completedCycles, 1);
      expect(recurringReminderDue(active, now: DateTime(2026, 4, 16)), isTrue);
      expect(controller.items.last.state, ItemState.done);
      final restored = StillOpenController(store: store);
      await restored.load();
      expect(restored.items.first.reminderAt, active.reminderAt);
      expect(restored.items.first.completedCycles, 1);
    },
  );

  test('overdue recurrence stays due until completed', () {
    final item = StillOpenItem(
      title: 'Vaccination',
      state: ItemState.open,
      category: Category.longTerm,
      templateType: TemplateType.longTerm,
      recurrenceHint: 'Yearly',
      reminderAt: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      reminderText: 'Jan 1, 2025 20:00',
    );
    expect(recurringReminderDue(item, now: DateTime(2026, 1, 1)), isTrue);
    expect(minimalStatusSentence(item), 'Due for follow-up');
    expect(recurringReminderDue(item, now: DateTime(2024, 1, 1)), isFalse);
  });

  test(
    'older ISO reminder timestamps migrate without shifting the date',
    () async {
      final target = DateTime(2027, 6, 4, 9, 5);
      final legacy = StillOpenItem(
        id: 9,
        title: 'Annual renewal',
        state: ItemState.open,
        category: Category.longTerm,
        templateType: TemplateType.longTerm,
        recurrenceHint: 'Yearly',
        reminderText: 'Jun 4, 2027 09:05',
      ).toJson();
      legacy['reminderAt'] = target.toIso8601String();
      final store = _Store();
      store.values['stillopen_items_v1'] = jsonEncode([legacy]);
      final scheduler = _Scheduler();
      final controller = StillOpenController(
        store: store,
        reminderScheduler: scheduler,
      );
      await controller.load();
      expect(controller.items.single.reminderAt, target.millisecondsSinceEpoch);
      expect(scheduler.scheduled[9], target);
      expect(
        controller.items.single.toJson()['reminderAt'],
        target.millisecondsSinceEpoch,
      );
    },
  );

  test('removing a recurring reminder also removes the cadence', () async {
    final scheduler = _Scheduler();
    final controller = StillOpenController(
      store: _Store(),
      reminderScheduler: scheduler,
    );
    await controller.load();
    await controller.createFromTemplate(TemplateType.longTerm);
    expect(scheduler.scheduled, isNotEmpty);
    await controller.clearReminder(controller.selectedItem!);
    expect(controller.selectedItem!.recurrenceHint, isEmpty);
    expect(controller.selectedItem!.reminderAt, isNull);
    expect(scheduler.scheduled, isEmpty);
  });
}

class _Store implements StillOpenStore {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

class _Scheduler implements ReminderScheduler {
  final scheduled = <int, DateTime>{};
  final cancelled = <int>[];
  @override
  Future<void> requestPermissions() async {}
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
  Future<void> cancelAll() async => scheduled.clear();
}
