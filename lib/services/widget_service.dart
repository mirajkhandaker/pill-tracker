import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../data/database/database_helper.dart';
import '../data/today_doses.dart';

/// One row on the home-screen widget.
@immutable
class WidgetDoseRow {
  const WidgetDoseRow({
    required this.name,
    required this.timeLabel,
    required this.doseText,
    required this.timeMs,
  });

  final String name;
  final String timeLabel;
  final String doseText;

  /// Scheduled time, so the native side can tell "due" from "upcoming" on its
  /// own periodic redraws without the app running.
  final int timeMs;
}

/// Everything the widget renders, flattened to string key/values.
@immutable
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.dateKey,
    required this.dateLabel,
    required this.rows,
    required this.moreCount,
    required this.emptyLabel,
  });

  /// yyyy-MM-dd the data was computed for; the widget treats any other day as
  /// stale rather than showing yesterday's doses.
  final String dateKey;
  final String dateLabel;
  final List<WidgetDoseRow> rows;

  /// Pending doses beyond the rows shown.
  final int moreCount;

  /// Shown when [rows] is empty.
  final String emptyLabel;

  /// Values are all strings to avoid Int/Long ambiguity in Android
  /// SharedPreferences.
  Map<String, String> toData() => {
    'date_key': dateKey,
    'date_label': dateLabel,
    'dose_count': '${rows.length}',
    'more_count': '$moreCount',
    'empty_label': emptyLabel,
    for (var i = 0; i < rows.length; i++) ...{
      'dose_${i}_name': rows[i].name,
      'dose_${i}_time': rows[i].timeLabel,
      'dose_${i}_dose': rows[i].doseText,
      'dose_${i}_time_ms': '${rows[i].timeMs}',
    },
  };
}

/// Builds the widget content: up to [maxRows] still-pending doses for today
/// (overdue first, since doses are time-sorted).
WidgetSnapshot buildWidgetSnapshot(
  List<TodayDose> doses,
  DateTime now, {
  int maxRows = 3,
}) {
  final pending = doses.where((d) => d.isPending).toList();
  final rows = [
    for (final d in pending.take(maxRows))
      WidgetDoseRow(
        name: d.medicine.name,
        timeLabel: DateFormat('h:mm a').format(d.time),
        doseText: d.schedule.isVariableDose
            ? 'Enter amount'
            : d.medicine.doseText(d.schedule.doseAmount),
        timeMs: d.time.millisecondsSinceEpoch,
      ),
  ];
  return WidgetSnapshot(
    dateKey: DateFormat('yyyy-MM-dd').format(now),
    dateLabel: DateFormat('EEE d MMM').format(now),
    rows: rows,
    moreCount: pending.length - rows.length,
    emptyLabel: doses.isEmpty
        ? 'No doses scheduled today'
        : 'All done for today',
  );
}

/// Pushes today's pending doses to the Android home-screen widget.
///
/// Safe to call from the background notification isolate. Android only for
/// now — the iOS widget is a post-launch item (Phase 11).
class WidgetService {
  WidgetService._();
  static final WidgetService instance = WidgetService._();

  static const _androidProvider =
      'com.pilltrack.app.pilltrack.PillWidgetProvider';

  Future<void> updateWidget({DatabaseHelper? db}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final now = DateTime.now();
    final doses = await loadTodayDoses(db ?? DatabaseHelper.instance, now: now);
    final snapshot = buildWidgetSnapshot(doses, now);

    for (final entry in snapshot.toData().entries) {
      await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
  }
}
