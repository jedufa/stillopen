import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stillopen/src/controller.dart';
import 'package:stillopen/src/date_logic.dart';
import 'package:stillopen/src/models.dart';
import 'package:stillopen/src/rules.dart';

import 'support/contract_fakes.dart';

void main() {
  for (final now in [
    DateTime(2026, 3, 28, 23, 30),
    DateTime(2026, 10, 25, 0, 30),
  ]) {
    test(
      'CLOCK-01 Tomorrow is the next calendar day at DST boundary ${now.month}',
      () async {
        await withClock(Clock.fixed(now), () async {
          final reminders = RecordingReminders();
          final controller = StillOpenController(
            store: MemoryContractStore(),
            reminderScheduler: reminders,
          );
          addTearDown(controller.dispose);
          await controller.load();
          await controller.quickAdd(title: 'Calendar boundary');
          final expected = DateTime(now.year, now.month, now.day + 1, 20);
          await controller.setReminderTomorrow(controller.selectedItem!);
          expect(reminders.scheduled.values.single, expected);
          await controller.setDateTomorrow(controller.selectedItem!);
          expect(
            controller.selectedItem!.dueAt,
            expected.millisecondsSinceEpoch,
          );
          expect(reminders.scheduled.values.single, expected);
        });
      },
    );
  }

  test(
    'CLOCK-02 a saved reminder becomes overdue without moving at midnight',
    () async {
      var now = DateTime(2026, 12, 31, 19);
      await withClock(Clock(() => now), () async {
        final store = MemoryContractStore();
        final reminders = RecordingReminders();
        var controller = StillOpenController(
          store: store,
          reminderScheduler: reminders,
        );
        await controller.load();
        await controller.quickAdd(title: 'Year end');
        await controller.setDateToday(controller.selectedItem!);
        final epoch = controller.selectedItem!.dueAt;
        controller.dispose();
        now = DateTime(2027, 1, 1, 1);
        controller = StillOpenController(
          store: store,
          reminderScheduler: reminders,
        );
        addTearDown(controller.dispose);
        await controller.load();
        expect(controller.items.single.dueAt, epoch);
        expect(minimalStatusSentence(controller.items.single), 'Overdue');
        expect(
          reminders.scheduled.values.single.millisecondsSinceEpoch,
          epoch,
          reason:
              'Reconciliation must leave an overdue inexact alarm pending for Android to deliver.',
        );
        await controller.clearReminder(controller.items.single);
        expect(reminders.scheduled, isEmpty);
        expect(
          displayStillOpenDate('Today 20:00', epoch),
          'Dec 31, 2026 20:00',
        );
      });
    },
  );

  test(
    'CLOCK-03 repeating completion advances once and ordinary stop removes scheduling',
    () async {
      await withClock(Clock.fixed(DateTime(2028, 2, 29, 10)), () async {
        final reminders = RecordingReminders();
        final controller = StillOpenController(
          store: MemoryContractStore(),
          reminderScheduler: reminders,
        );
        addTearDown(controller.dispose);
        await controller.load();
        await controller.createFromTemplate(TemplateType.longTerm);
        await controller.setRecurrenceHint(controller.selectedItem!, 'Yearly');
        await controller.completeLongTermCycle(controller.selectedItem!);
        expect(reminders.scheduled.values.single, DateTime(2029, 2, 28, 20));
        expect(controller.selectedItem!.completedCycles, 1);
        await controller.stopLongTermRecurrence(controller.selectedItem!);
        expect(reminders.scheduled, isEmpty);
        expect(controller.selectedItem!.nextCycleAtEpoch, isNull);
      });
    },
  );
}
