import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/app_logger.dart';
import '../data/database/database_helper.dart';
import '../data/models/dose_log.dart';
import '../data/models/medicine.dart';
import '../data/models/schedule.dart';
import '../data/repositories/dose_log_repository.dart';
import '../data/repositories/medicine_repository.dart';
import '../data/repositories/schedule_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'notification_service.dart';
import 'widget_service.dart';

/// Background isolate entry point for notification actions. Must be a top-level
/// function annotated for AOT retention.
///
/// This runs in a separate isolate when the app is backgrounded or killed, so
/// it cannot touch UI or the app's providers. It opens its own DB connection
/// via [DatabaseHelper.instance] — in a background isolate the static singleton
/// is constructed fresh and opens its own connection to the same database file.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  NotificationActionHandler.handle(response);
}

class NotificationActionHandler {
  const NotificationActionHandler._();

  static const _uuid = Uuid();

  /// Applies a notification action. Safe to call from either the foreground or
  /// the background isolate.
  static Future<void> handle(NotificationResponse response) async {
    // Ensure plugin channels (sqflite, timezone) are wired in a background
    // isolate before any DB access.
    DartPluginRegistrant.ensureInitialized();

    final payload = response.payload;
    if (payload == null) return;
    final parts = payload.split('|');
    if (parts.length < 3) return;

    final medicineId = parts[0];
    final scheduleId = parts[1].isEmpty ? null : parts[1];
    final scheduledMs =
        int.tryParse(parts[2]) ?? DateTime.now().millisecondsSinceEpoch;
    final action = response.actionId ?? '';
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final db = DatabaseHelper.instance;
    final medRepo = MedicineRepository(db);
    final schedRepo = ScheduleRepository(db);
    final logRepo = DoseLogRepository(db);

    switch (action) {
      case NotificationService.actionSkip:
        // A no-op when the dose was already logged (e.g. in the app).
        await logRepo.addLog(
          DoseLog(
            id: _uuid.v4(),
            medicineId: medicineId,
            scheduleId: scheduleId,
            scheduledTime: scheduledMs,
            actionTime: nowMs,
            doseAmount: 0,
            status: DoseLog.statusSkipped,
          ),
        );
        await _afterLog(db, medicineId, scheduleId, scheduledMs);

      case NotificationService.actionSnooze:
        await _snooze(medRepo, schedRepo, medicineId, scheduleId, scheduledMs);

      case NotificationService.actionTaken:
        await _logTaken(
          medRepo,
          schedRepo,
          logRepo,
          medicineId,
          scheduleId,
          scheduledMs,
          nowMs,
        );
        await _afterLog(db, medicineId, scheduleId, scheduledMs);

      case NotificationService.actionLogDose:
        // Variable dose: the amount-entry dialog is shown by the foreground UI
        // (the action brings the app to the front). Nothing to do here.
        break;

      default:
        // Body tap with no action id: UI handles navigation.
        break;
    }
  }

  /// After a dose is logged while the app is closed: keeps the home-screen
  /// widget current, dismisses any other notification for the same dose (the
  /// original or a snooze of it), and re-syncs reminders, which also drops a
  /// pending snooze of it and refreshes the weekly summary. Never lets a
  /// failure here undo or block the logged dose.
  static Future<void> _afterLog(
    DatabaseHelper db,
    String medicineId,
    String? scheduleId,
    int scheduledMs,
  ) async {
    try {
      await WidgetService.instance.updateWidget(db: db);
    } catch (e) {
      AppLogger.warn('Widget refresh from notification failed', e);
    }
    try {
      final service = NotificationService.instance;
      await service.init();
      if (scheduleId != null) {
        await service.clearDose(medicineId, scheduleId, scheduledMs);
      }
      await service.syncFromDatabase(db);
    } catch (e) {
      AppLogger.warn('Reminder sync after notification action failed', e);
    }
  }

  static Future<Schedule?> _findSchedule(
    ScheduleRepository schedRepo,
    String medicineId,
    String? scheduleId,
  ) async {
    if (scheduleId == null) return null;
    final schedules = await schedRepo.getByMedicineId(medicineId);
    for (final s in schedules) {
      if (s.id == scheduleId) return s;
    }
    return null;
  }

  static Future<void> _logTaken(
    MedicineRepository medRepo,
    ScheduleRepository schedRepo,
    DoseLogRepository logRepo,
    String medicineId,
    String? scheduleId,
    int scheduledMs,
    int nowMs,
  ) async {
    final medicine = await medRepo.getById(medicineId);
    if (medicine == null) return;

    final schedules = await schedRepo.getByMedicineId(medicineId);
    final schedule = scheduleId == null
        ? null
        : schedules.where((s) => s.id == scheduleId).firstOrNull;
    // Schedule amounts are already in the medicine's base unit.
    final amount = schedule?.doseAmount ?? 0;

    // Logs and uses up stock in one step, unless the dose was already logged
    // (e.g. "Mark Taken" in the app before the reminder arrived).
    final result = await logRepo.addLog(
      DoseLog(
        id: _uuid.v4(),
        medicineId: medicineId,
        scheduleId: scheduleId,
        scheduledTime: scheduledMs,
        actionTime: nowMs,
        doseAmount: amount,
        status: DoseLog.statusTaken,
      ),
    );
    if (!result.added) return;
    final covered = result.covered;
    final refreshed = await medRepo.getById(medicineId);
    final needsRefill = refreshed?.needsRefill(schedules) ?? false;

    if (!covered || needsRefill) {
      await _fireRefillWarning(refreshed ?? medicine);
    }
  }

  static Future<void> _snooze(
    MedicineRepository medRepo,
    ScheduleRepository schedRepo,
    String medicineId,
    String? scheduleId,
    int scheduledMs,
  ) async {
    final medicine = await medRepo.getById(medicineId);
    if (medicine == null) return;
    final schedule = await _findSchedule(schedRepo, medicineId, scheduleId);

    final minutes = await SettingsRepository(DatabaseHelper.instance).getInt(
      SettingsRepository.snoozeMinutesKey,
      defaultValue: NotificationService.defaultSnoozeMinutes,
    );
    await NotificationService.instance.init();
    NotificationService.instance.snoozeMinutes = minutes;
    final when = DateTime.now().add(Duration(minutes: minutes));
    await NotificationService.instance.scheduleReminder(
      // One snooze per dose: snoozing again replaces the earlier one.
      id: NotificationService.snoozeKey(medicineId, scheduleId, scheduledMs),
      medicineName: medicine.name,
      doseText: _doseText(medicine, schedule),
      time: when,
      // Marked as a snooze so a later reminder re-sync keeps it.
      payload: NotificationService.snoozePayload(
        medicineId,
        scheduleId,
        scheduledMs,
      ),
      isVariableDose: schedule?.isVariableDose ?? false,
    );
  }

  static String _doseText(Medicine medicine, Schedule? schedule) {
    return medicine.doseText(schedule?.doseAmount ?? 1);
  }

  static Future<void> _fireRefillWarning(Medicine medicine) async {
    await NotificationService.instance.init();
    await NotificationService.instance.showImmediate(
      id: 'refill|${medicine.id}',
      title: 'Running low on ${medicine.name}',
      body: "You're running low — ${medicine.remainingLabel}",
      payload: '${medicine.id}||0',
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
