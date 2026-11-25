import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../../data/adherence.dart';
import '../../../data/models/dose_log.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/schedule.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/today_doses.dart';
import '../../../services/notification_service.dart';
import '../../../services/widget_service.dart';
import '../../prescriptions/providers/prescription_providers.dart';

export '../../../data/today_doses.dart' show TodayDose;

const _uuid = Uuid();

/// Outcome of logging a taken dose.
@immutable
class DoseResult {
  const DoseResult({
    required this.covered,
    this.lowStock,
    this.alreadyLogged = false,
  });

  /// False when stock couldn't cover the dose (inventory clamped to empty).
  final bool covered;

  /// True when nothing was recorded because this dose had already been
  /// logged (e.g. a double tap, or "Taken" on the notification first).
  final bool alreadyLogged;

  /// The medicine, when it is now at/under its refill threshold.
  final Medicine? lowStock;
}

/// All active medicines, sorted by name.
final activeMedicinesProvider = FutureProvider<List<Medicine>>(
  (ref) => ref.watch(medicineRepositoryProvider).getActive(),
);

/// Every medicine ever added, including soft-deleted ones (for history names).
final allMedicinesProvider = FutureProvider<List<Medicine>>(
  (ref) => ref.watch(medicineRepositoryProvider).getAll(),
);

/// A single medicine by id (null once hard-deleted).
final medicineByIdProvider = FutureProvider.family<Medicine?, String>(
  (ref, id) => ref.watch(medicineRepositoryProvider).getById(id),
);

/// As-needed (PRN) medicines only.
final prnMedicinesProvider = FutureProvider<List<Medicine>>((ref) async {
  final all = await ref.watch(activeMedicinesProvider.future);
  return all.where((m) => m.isPrn).toList();
});

/// All active, scheduled medicines (non-PRN).
final scheduledMedicinesProvider = FutureProvider<List<Medicine>>((ref) async {
  final all = await ref.watch(activeMedicinesProvider.future);
  return all.where((m) => !m.isPrn).toList();
});

/// Active schedules joined to their medicine.
final allSchedulesWithMedicineProvider =
    FutureProvider<List<ScheduleWithMedicine>>(
      (ref) => ref.watch(scheduleRepositoryProvider).getAllActiveWithMedicine(),
    );

/// Schedules for a single medicine.
final schedulesForMedicineProvider =
    FutureProvider.family<List<Schedule>, String>(
      (ref, medicineId) =>
          ref.watch(scheduleRepositoryProvider).getByMedicineId(medicineId),
    );

/// Recent dose logs for a medicine, over the last [days] days.
final medicineLogsProvider =
    FutureProvider.family<List<DoseLog>, ({String medicineId, int days})>((
      ref,
      args,
    ) {
      final since = DateTime.now()
          .subtract(Duration(days: args.days))
          .millisecondsSinceEpoch;
      return ref
          .watch(doseLogRepositoryProvider)
          .getByMedicine(args.medicineId, since);
    });

/// Today's scheduled doses (past + upcoming), each with its logged status.
final todayDosesProvider = FutureProvider<List<TodayDose>>(
  (ref) => loadTodayDoses(ref.watch(databaseHelperProvider)),
);

/// Current and best "every dose taken" streaks.
typedef Streak = ({int current, int longest});

/// Computes the current streak over the last year and persists a new best.
final streakProvider = FutureProvider<Streak>((ref) async {
  final db = ref.watch(databaseHelperProvider);
  final now = DateTime.now();
  final days = await loadDailyAdherence(db, days: 365, to: now, cutoff: now);
  final current = currentStreak(days);

  final settings = ref.watch(settingsRepositoryProvider);
  var longest = await settings.getInt(SettingsRepository.longestStreakKey);
  if (current > longest) {
    longest = current;
    await settings.setInt(SettingsRepository.longestStreakKey, longest);
  }
  return (current: current, longest: longest);
});

/// Invalidates every provider derived from medicine / schedule / log data so
/// screens re-read from the database.
void invalidateMedicineData(Ref ref) {
  ref.invalidate(allMedicinesProvider);
  ref.invalidate(activeMedicinesProvider);
  ref.invalidate(medicineByIdProvider);
  ref.invalidate(allSchedulesWithMedicineProvider);
  ref.invalidate(schedulesForMedicineProvider);
  ref.invalidate(medicineLogsProvider);
  ref.invalidate(todayDosesProvider);
  ref.invalidate(streakProvider);
  // Medicine edits change what each prescription contains.
  invalidatePrescriptionData(ref);
}

/// Imperative actions that mutate data and refresh dependent state.
final medicineActionsProvider = Provider<MedicineActions>(
  (ref) => MedicineActions(ref),
);

class MedicineActions {
  MedicineActions(this._ref);
  final Ref _ref;

  void _invalidate() => invalidateMedicineData(_ref);

  /// Re-read everything (e.g. after the background isolate changed the DB).
  void refreshAll() => _invalidate();

  /// Sync reminders + widget with the DB without changing any data.
  Future<void> resync() => _refreshSchedulingAndWidget();

  /// Re-syncs OS reminders and the home widget. Failures here (e.g. a plugin
  /// error or missing permission) are logged, never allowed to fail the save.
  Future<void> _refreshSchedulingAndWidget() async {
    try {
      await NotificationService.instance.syncFromDatabase(
        _ref.read(databaseHelperProvider),
      );
    } catch (e) {
      AppLogger.warn('Reminder sync failed', e);
    }
    await _updateWidget();
  }

  Future<void> _updateWidget() async {
    try {
      await WidgetService.instance.updateWidget(
        db: _ref.read(databaseHelperProvider),
      );
    } catch (e) {
      AppLogger.warn('Widget update failed', e);
    }
  }

  /// After a dose is logged, skipped, corrected or removed. Dismisses the
  /// dose's reminder (and any snooze of it) if it is showing, then re-syncs:
  /// a dose logged early gets no reminder later, a removed log gets its
  /// reminder back, and the weekly summary's numbers (fixed when scheduled)
  /// are refreshed.
  Future<void> _afterLog(DoseLog log) async {
    final scheduleId = log.scheduleId;
    if (scheduleId != null) {
      try {
        await NotificationService.instance.clearDose(
          log.medicineId,
          scheduleId,
          log.scheduledTime,
        );
      } catch (e) {
        AppLogger.warn('Clearing the dose reminder failed', e);
      }
    }
    await _refreshSchedulingAndWidget();
  }

  /// Marks a fixed-dose scheduled dose taken at its scheduled amount.
  Future<DoseResult> markTaken(TodayDose dose) =>
      logScheduledDose(dose, dose.schedule.doseAmount);

  /// Logs a scheduled dose as taken with [amount] (the user's entry for
  /// variable doses) and decrements inventory.
  ///
  /// Amounts are already in the medicine's base unit (ml for liquids).
  Future<DoseResult> logScheduledDose(TodayDose dose, double amount) =>
      recordDose(
        DoseLog(
          id: _uuid.v4(),
          medicineId: dose.medicine.id,
          scheduleId: dose.schedule.id,
          scheduledTime: dose.time.millisecondsSinceEpoch,
          actionTime: DateTime.now().millisecondsSinceEpoch,
          doseAmount: amount,
          status: DoseLog.statusTaken,
        ),
      );

  /// Re-reads the medicine after a log to report stock problems.
  Future<DoseResult> _afterDose(DoseLog log, bool covered) async {
    final medicineId = log.medicineId;
    final medicine = await _ref
        .read(medicineRepositoryProvider)
        .getById(medicineId);
    final schedules = await _ref
        .read(scheduleRepositoryProvider)
        .getByMedicineId(medicineId);
    _invalidate();
    await _afterLog(log);
    return DoseResult(
      covered: covered,
      lowStock: medicine != null && medicine.needsRefill(schedules)
          ? medicine
          : null,
    );
  }

  /// Records a scheduled dose as skipped (a no-op if it was already logged).
  Future<void> skip(TodayDose dose) async {
    await recordDose(
      DoseLog(
        id: _uuid.v4(),
        medicineId: dose.medicine.id,
        scheduleId: dose.schedule.id,
        scheduledTime: dose.time.millisecondsSinceEpoch,
        actionTime: DateTime.now().millisecondsSinceEpoch,
        doseAmount: 0,
        status: DoseLog.statusSkipped,
      ),
    );
  }

  /// Saves a corrected dose log (status, amount or time). Stock is adjusted by
  /// the difference in amount taken.
  Future<void> editDoseLog(DoseLog original, DoseLog updated) async {
    await _ref.read(doseLogRepositoryProvider).updateLog(original, updated);
    _invalidate();
    await _afterLog(updated);
  }

  /// Logs a dose (taken or skipped). A scheduled dose that is already logged
  /// for that day is left as it is and reported as [DoseResult.alreadyLogged].
  Future<DoseResult> recordDose(DoseLog log) async {
    final result = await _ref.read(doseLogRepositoryProvider).addLog(log);
    if (!result.added) {
      _invalidate(); // show the log that got there first
      return const DoseResult(covered: true, alreadyLogged: true);
    }
    return _afterDose(log, result.covered);
  }

  /// Removes a logged dose; a scheduled dose becomes pending again and any
  /// stock it used is returned.
  Future<void> removeDoseLog(DoseLog log) async {
    await _ref.read(doseLogRepositoryProvider).deleteLog(log);
    _invalidate();
    await _afterLog(log);
  }

  /// Logs an as-needed dose of [amount] (in the medicine's dose unit).
  Future<DoseResult> logPrn(Medicine medicine, double amount) async {
    final result = await _ref
        .read(doseLogRepositoryProvider)
        .logPrnDose(medicine.id, medicine.doseAmountInBaseUnit(amount));
    return _afterDose(result.log, result.covered);
  }

  /// Refill by a number of units (no pack size needed).
  Future<void> addUnits(String medicineId, double amount) async {
    await _ref.read(medicineRepositoryProvider).addUnits(medicineId, amount);
    _invalidate();
    await _updateWidget();
  }

  Future<void> addPackages(String medicineId, int count) async {
    await _ref.read(medicineRepositoryProvider).addPackages(medicineId, count);
    _invalidate();
    await _updateWidget();
  }

  /// Atomically upserts a medicine and replaces its schedules, then refreshes
  /// notifications and the widget.
  Future<void> saveMedicine(Medicine medicine, List<Schedule> schedules) async {
    final db = await _ref.read(databaseHelperProvider).getDb();
    await db.transaction((txn) async {
      // Update in place, insert only when new. Never INSERT OR REPLACE: it
      // deletes the old row first, and the ON DELETE CASCADE from dose_logs
      // would wipe the medicine's whole dose history on every edit.
      final updated = await txn.update(
        'medicines',
        medicine.toMap(),
        where: 'id = ?',
        whereArgs: [medicine.id],
      );
      if (updated == 0) await txn.insert('medicines', medicine.toMap());
      await txn.delete(
        'schedules',
        where: 'medicine_id = ?',
        whereArgs: [medicine.id],
      );
      for (final s in schedules) {
        await txn.insert('schedules', s.toMap());
      }
    });
    _invalidate();
    _ref.invalidate(schedulesForMedicineProvider(medicine.id));
    await _refreshSchedulingAndWidget();
  }

  Future<void> deleteMedicine(String medicineId) async {
    await _ref.read(medicineRepositoryProvider).softDelete(medicineId);
    _invalidate();
    await _refreshSchedulingAndWidget();
  }
}
