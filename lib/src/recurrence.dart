enum RecurrenceUnit { day, week, month, year }

class RecurrenceRule {
  const RecurrenceRule(this.count, this.unit);

  final int count;
  final RecurrenceUnit unit;

  static RecurrenceRule? parse(String value) {
    final text = value.trim().toLowerCase();
    switch (text) {
      case 'daily':
        return const RecurrenceRule(1, RecurrenceUnit.day);
      case 'weekly':
        return const RecurrenceRule(1, RecurrenceUnit.week);
      case 'monthly':
        return const RecurrenceRule(1, RecurrenceUnit.month);
      case 'quarterly':
        return const RecurrenceRule(3, RecurrenceUnit.month);
      case 'yearly':
        return const RecurrenceRule(1, RecurrenceUnit.year);
    }
    final match = RegExp(
      r'^every\s+(\d+)\s+(day|week|month|year)s?$',
    ).firstMatch(text);
    if (match == null) return null;
    final count = int.tryParse(match.group(1)!);
    if (count == null || count < 1 || count > 100) return null;
    return RecurrenceRule(count, switch (match.group(2)!) {
      'day' => RecurrenceUnit.day,
      'week' => RecurrenceUnit.week,
      'month' => RecurrenceUnit.month,
      _ => RecurrenceUnit.year,
    });
  }

  DateTime after(DateTime date) {
    final months = switch (unit) {
      RecurrenceUnit.month => count,
      RecurrenceUnit.year => count * 12,
      _ => 0,
    };
    if (months == 0) {
      final days = unit == RecurrenceUnit.week ? count * 7 : count;
      return DateTime(
        date.year,
        date.month,
        date.day + days,
        date.hour,
        date.minute,
      );
    }
    final monthIndex = date.year * 12 + date.month - 1 + months;
    final year = monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      date.day.clamp(1, lastDay),
      date.hour,
      date.minute,
    );
  }
}
