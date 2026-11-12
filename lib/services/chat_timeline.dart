// lib/services/chat_timeline.dart
//
// Day separators in a conversation ("Today", "Yesterday", "Saturday",
// "Nov 3"). Pure functions of the dates, so they are unit-tested without a
// widget or a clock.

// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;

/// The label of the separator above the first message of [message]'s day,
/// as seen at [now] (both local time).
///
/// Days are calendar days, not 24-hour spans: a message from 11 pm is
/// "Yesterday" at 1 am. The past week shows the weekday (that is how people
/// say it: "on Tuesday"); anything older shows the date, with the year only
/// when it isn't this year. A message dated after today (a phone clock a bit
/// ahead) shows its date rather than a misleading "Today".
String chatDayLabel(DateTime message, DateTime now) {
  final daysAgo = _calendarDaysBetween(message, now);
  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo > 1 && daysAgo < 7) return _weekday.format(message);
  if (message.year == now.year) return _monthDay.format(message);
  return _monthDayYear.format(message);
}

// Built once (on first use) instead of per separator: a DateFormat parses
// its pattern when created, and the chat list asks for a label while
// scrolling. The app never changes its locale at runtime, so the locale
// these capture on first use stays right.
final DateFormat _weekday = DateFormat.EEEE();
final DateFormat _monthDay = DateFormat.MMMd();
final DateFormat _monthDayYear = DateFormat.yMMMd();

/// True when [message] needs a day separator above it: it is the oldest
/// message loaded ([older] is null) or [older], the message shown just above
/// it, was sent on a different local calendar day.
bool startsNewDay(DateTime message, DateTime? older) {
  if (older == null) return true;
  return message.year != older.year ||
      message.month != older.month ||
      message.day != older.day;
}

/// Whole calendar days from [from] to [to] (negative when [from] is later).
///
/// Counted on UTC dates built from the local year/month/day, so a daylight
/// saving change (a 23- or 25-hour day) can't turn one day into zero or two.
int _calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}
