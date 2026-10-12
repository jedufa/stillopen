import 'package:clock/clock.dart';

/// Calendar offsets are not elapsed 24-hour periods across daylight saving.
DateTime calendarDayAfter(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// Calendar interpretation shared by persistence, reminders, and list pressure.
/// Relative legacy labels are anchored to their last saved edit, never reload.
DateTime? parseStillOpenDate(
  String label, {
  DateTime? anchor,
  int defaultHour = 20,
  int defaultMinute = 0,
}) {
  final value = label.trim();
  if (value.isEmpty) return null;
  final base = anchor ?? clock.now();
  final time = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(value);
  final hour = time == null ? defaultHour : int.tryParse(time.group(1)!);
  final minute = time == null ? defaultMinute : int.tryParse(time.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  DateTime at(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);
  final lower = value.toLowerCase();
  if (lower.startsWith('today')) return at(base);
  if (lower.startsWith('tomorrow')) {
    return at(DateTime(base.year, base.month, base.day + 1));
  }
  if (lower.startsWith('this weekend')) {
    final delta = (DateTime.saturday - base.weekday + 7) % 7;
    return at(DateTime(base.year, base.month, base.day + delta));
  }
  final interval = RegExp(
    r'^(\d+)\s+(day|week|month|year)s?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (interval != null) {
    final count = int.parse(interval.group(1)!);
    if (count < 1 || count > 100) return null;
    return switch (interval.group(2)!.toLowerCase()) {
      'day' => at(DateTime(base.year, base.month, base.day + count)),
      'week' => at(DateTime(base.year, base.month, base.day + 7 * count)),
      'month' => _shiftMonth(base, count, hour, minute),
      _ => _shiftMonth(base, count * 12, hour, minute),
    };
  }
  const weekdays = {
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };
  final weekday = weekdays[lower.split(' ').first];
  if (weekday != null) {
    return at(
      DateTime(
        base.year,
        base.month,
        base.day + (weekday - base.weekday + 7) % 7,
      ),
    );
  }
  final match = RegExp(
    r'^([A-Za-z]+)\s+(\d{1,2})(?:,\s*(\d{4}))?',
  ).firstMatch(value);
  if (match == null) return null;
  const months = {
    'jan': 1,
    'january': 1,
    'feb': 2,
    'february': 2,
    'mar': 3,
    'march': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'jun': 6,
    'june': 6,
    'jul': 7,
    'july': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'sept': 9,
    'september': 9,
    'oct': 10,
    'october': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'december': 12,
  };
  final month = months[match.group(1)!.toLowerCase()];
  if (month == null) return null;
  final day = int.parse(match.group(2)!);
  final year = int.tryParse(match.group(3) ?? '') ?? base.year;
  final result = DateTime(year, month, day, hour, minute);
  return result.month == month && result.day == day ? result : null;
}

DateTime _shiftMonth(DateTime base, int count, int hour, int minute) {
  final first = DateTime(base.year, base.month + count, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(
    first.year,
    first.month,
    base.day.clamp(1, lastDay),
    hour,
    minute,
  );
}

String displayStillOpenDate(String label, int? epoch, {DateTime? today}) {
  if (label.isEmpty || epoch == null) return label;
  final date = DateTime.fromMillisecondsSinceEpoch(epoch);
  final now = today ?? clock.now();
  final base = DateTime.utc(now.year, now.month, now.day);
  final target = DateTime.utc(date.year, date.month, date.day);
  final delta = target.difference(base).inDays;
  final datePart = switch (delta) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ =>
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.day}, ${date.year}',
  };
  final hasTime = RegExp(r'\d{1,2}:\d{2}').hasMatch(label);
  final timePart = hasTime
      ? ' ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
      : '';
  return '$datePart$timePart';
}

int? stillOpenDateEpoch(
  String label, {
  DateTime? anchor,
  int defaultHour = 20,
  int defaultMinute = 0,
}) => parseStillOpenDate(
  label,
  anchor: anchor,
  defaultHour: defaultHour,
  defaultMinute: defaultMinute,
)?.millisecondsSinceEpoch;
