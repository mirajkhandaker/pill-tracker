import 'package:flutter/foundation.dart';

import 'database/database_helper.dart';
import 'models/dose_log.dart';
import 'models/medicine.dart';
import 'models/schedule.dart';
import 'repositories/dose_log_repository.dart';
import 'repositories/schedule_repository.dart';

/// One scheduled occurrence of a dose for today, with any logged outcome.
@immutable
class TodayDose {
  const TodayDose({
    required this.medicine,
    required this.schedule,
    required this.time,
    this.log,
  });

  final Medicine medicine;
  final Schedule schedule;
  final DateTime time;
  final DoseLog? log;

  String get status => log?.status ?? DoseLog.statusPending;
  bool get isPending => log == null || log!.isPending;
  bool get isTaken => log?.isTaken ?? false;
  bool get isPast => time.isBefore(DateTime.now());
}

/// Today's scheduled doses (past + upcoming) for active, non-PRN medicines,
/// sorted by time, each matched to its logged outcome if any.
///
/// Plain function (no Riverpod) so both the UI and the background
/// notification isolate (which refreshes the home-screen widget) share it.
Future<List<TodayDose>> loadTodayDoses(
  DatabaseHelper db, {
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final start = DateTime(at.year, at.month, at.day);
  final end = DateTime(start.year, start.month, start.day + 1);

  final pairs = await ScheduleRepository(db).getAllActiveWithMedicine(now: at);
  final logs = await DoseLogRepository(db)
      .getByDateRange(start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
  return buildTodayDoses(pairs, logs, at);
}

/// Pure core of [loadTodayDoses].
List<TodayDose> buildTodayDoses(
  List<ScheduleWithMedicine> pairs,
  List<DoseLog> todaysLogs,
  DateTime now,
) {
  final doses = <TodayDose>[];
  for (final pair in pairs) {
    final s = pair.schedule;
    if (!s.days.contains(now.weekday)) continue;
    final time = DateTime(now.year, now.month, now.day, s.hour, s.minute);

    DoseLog? match;
    for (final l in todaysLogs) {
      if (l.scheduleId == s.id) {
        match = l;
        break;
      }
    }
    doses.add(
      TodayDose(medicine: pair.medicine, schedule: s, time: time, log: match),
    );
  }
  doses.sort((a, b) => a.time.compareTo(b.time));
  return doses;
}
