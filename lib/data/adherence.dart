import 'package:flutter/foundation.dart';

import 'database/database_helper.dart';
import 'models/dose_log.dart';
import 'repositories/dose_log_repository.dart';
import 'repositories/schedule_repository.dart';

/// Scheduled vs. taken doses for one calendar day.
@immutable
class DayAdherence {
  const DayAdherence({
    required this.day,
    required this.expected,
    required this.taken,
  });

  /// Local midnight of the day.
  final DateTime day;

  /// Scheduled doses due on this day (up to the cutoff).
  final int expected;

  /// Of those, how many were logged as taken (never more than [expected]).
  final int taken;

  bool get hasDoses => expected > 0;
  bool get complete => hasDoses && taken >= expected;
}

/// Per-day adherence for every day in [from, to] (inclusive, local days).
///
/// A dose occurrence counts as expected when its scheduled time is at or
/// before [cutoff] and not before its medicine was added. Taken doses are
/// matched per medicine per day rather than by schedule id, because editing a
/// medicine recreates its schedule rows with new ids and history must survive
/// that. PRN logs (no schedule) never count.
///
/// Uses the medicines' *current* schedules; past schedule changes aren't
/// versioned, so this is a close approximation for edited medicines.
List<DayAdherence> dailyAdherence({
  required List<ScheduleWithMedicine> pairs,
  required List<DoseLog> logs,
  required DateTime from,
  required DateTime to,
  required DateTime cutoff,
}) {
  // taken[(dayKey, medicineId)] = count
  final taken = <(int, String), int>{};
  for (final l in logs) {
    if (!l.isTaken || l.scheduleId == null) continue;
    final t = DateTime.fromMillisecondsSinceEpoch(l.scheduledTime);
    final key = (_dayKey(t), l.medicineId);
    taken[key] = (taken[key] ?? 0) + 1;
  }

  final result = <DayAdherence>[];
  for (
    var day = _midnight(from);
    !day.isAfter(_midnight(to));
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    // Per medicine: doses due after it was added are required; doses due
    // before (e.g. this morning's dose for a medicine added tonight) are
    // optional — they count only if the user logged them, so adding a
    // medicine late in the day can raise adherence but never lower it.
    final required = <String, int>{};
    final optional = <String, int>{};
    for (final p in pairs) {
      final s = p.schedule;
      if (!s.days.contains(day.weekday)) continue;
      if (!p.medicine.isOngoingOn(day)) continue; // after the course ended
      final at = DateTime(day.year, day.month, day.day, s.hour, s.minute);
      if (at.isAfter(cutoff)) continue;
      final bucket = at.millisecondsSinceEpoch < p.medicine.createdAt
          ? optional
          : required;
      bucket[p.medicine.id] = (bucket[p.medicine.id] ?? 0) + 1;
    }

    var expected = 0;
    var takenCount = 0;
    for (final medicineId in {...required.keys, ...optional.keys}) {
      final req = required[medicineId] ?? 0;
      final all = req + (optional[medicineId] ?? 0);
      final t = taken[(_dayKey(day), medicineId)] ?? 0;
      final counted = t < all ? t : all;
      takenCount += counted;
      expected += counted > req ? counted : req;
    }
    result.add(DayAdherence(day: day, expected: expected, taken: takenCount));
  }
  return result;
}

/// Consecutive days, ending today, on which every due dose was taken.
///
/// Today counts only once all of today's doses so far are taken; an
/// incomplete today doesn't break the streak (there's still time). Days with
/// no scheduled doses are skipped without breaking it. [days] must be in
/// chronological order and end with today.
int currentStreak(List<DayAdherence> days) {
  var streak = 0;
  for (var i = days.length - 1; i >= 0; i--) {
    final d = days[i];
    final isToday = i == days.length - 1;
    if (!d.hasDoses) continue;
    if (d.complete) {
      streak++;
    } else if (!isToday) {
      break;
    }
  }
  return streak;
}

/// Totals across [days].
({int taken, int expected}) totals(Iterable<DayAdherence> days) {
  var taken = 0;
  var expected = 0;
  for (final d in days) {
    taken += d.taken;
    expected += d.expected;
  }
  return (taken: taken, expected: expected);
}

/// Minimum days of use before asking for a store review.
const reviewPromptMinDays = 7;

/// Minimum adherence over the last [reviewPromptMinDays] days.
const reviewPromptMinAdherence = 0.8;

/// Whether to show the one-time review prompt: in use for at least
/// [reviewPromptMinDays] days, with doses scheduled in [recentDays] and at
/// least [reviewPromptMinAdherence] of them taken.
bool qualifiesForReviewPrompt({
  required DateTime firstUse,
  required DateTime now,
  required List<DayAdherence> recentDays,
}) {
  if (now.difference(firstUse) < const Duration(days: reviewPromptMinDays)) {
    return false;
  }
  final t = totals(recentDays);
  return t.expected > 0 && t.taken / t.expected >= reviewPromptMinAdherence;
}

/// The next weekly-summary time — Sunday 20:00 local — strictly after [now].
DateTime nextWeeklySummaryTime(DateTime now) {
  final daysUntilSunday = (DateTime.sunday - now.weekday) % 7;
  var candidate = DateTime(now.year, now.month, now.day + daysUntilSunday, 20);
  if (!candidate.isAfter(now)) {
    candidate = DateTime(
      candidate.year,
      candidate.month,
      candidate.day + 7,
      20,
    );
  }
  return candidate;
}

/// Loads schedules and logs and computes [dailyAdherence] for the [days] days
/// ending on [to]'s date, counting doses due up to [cutoff].
Future<List<DayAdherence>> loadDailyAdherence(
  DatabaseHelper db, {
  required int days,
  required DateTime to,
  required DateTime cutoff,
}) async {
  final end = _midnight(to);
  final start = DateTime(end.year, end.month, end.day - (days - 1));
  final pairs = await ScheduleRepository(db).getAllActiveWithMedicine();
  final logs = await DoseLogRepository(db).getByDateRange(
    start.millisecondsSinceEpoch,
    DateTime(end.year, end.month, end.day + 1).millisecondsSinceEpoch,
  );
  return dailyAdherence(
    pairs: pairs,
    logs: logs,
    from: start,
    to: end,
    cutoff: cutoff,
  );
}

DateTime _midnight(DateTime t) => DateTime(t.year, t.month, t.day);

int _dayKey(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
