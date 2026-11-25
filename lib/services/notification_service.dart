import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/app_logger.dart';
import '../data/adherence.dart';
import '../data/database/database_helper.dart';
import '../data/models/dose_log.dart';
import '../data/models/medicine.dart';
import '../data/models/schedule.dart';
import '../data/repositories/dose_log_repository.dart';
import '../data/repositories/medicine_repository.dart';
import '../data/repositories/schedule_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'notification_action_handler.dart';

/// Parsed contents of a notification action the user triggered.
@immutable
class NotificationEvent {
  const NotificationEvent({
    required this.actionId,
    required this.medicineId,
    this.scheduleId,
    required this.scheduledTimeMs,
  });

  final String actionId;
  final String medicineId;
  final String? scheduleId;
  final int scheduledTimeMs;

  static NotificationEvent? fromResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return null;
    final parts = payload.split('|');
    if (parts.length < 3) return null;
    return NotificationEvent(
      actionId: response.actionId ?? '',
      medicineId: parts[0],
      scheduleId: parts[1].isEmpty ? null : parts[1],
      scheduledTimeMs: int.tryParse(parts[2]) ?? 0,
    );
  }
}

/// Singleton wrapper around flutter_local_notifications: scheduling reminders,
/// rescheduling, and routing taps/actions.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'reminders';
  static const String _channelName = 'Medication reminders';
  static const String _channelDescription =
      'Reminders to take your medication on time';

  // Action button ids (also used by the background handler).
  static const String actionTaken = 'taken';
  static const String actionSkip = 'skip';
  static const String actionSnooze = 'snooze';
  static const String actionLogDose = 'log_dose';

  static const int defaultSnoozeMinutes = 10;

  /// How many days ahead rescheduleAll materializes notifications.
  static const int horizonDays = 7;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Snooze length shown on the action button; refreshed from settings by
  /// [syncFromDatabase].
  int snoozeMinutes = defaultSnoozeMinutes;

  /// Foreground action events, for the UI to react (e.g. open the dose dialog
  /// or refresh lists). Emitted after the action's DB work has completed.
  static final StreamController<NotificationEvent> _actionController =
      StreamController<NotificationEvent>.broadcast();
  static Stream<NotificationEvent> get actionStream => _actionController.stream;

  /// The notification that cold-started the app, if any. Consumed once by the
  /// home screen via [takeLaunchEvent].
  NotificationEvent? _launchEvent;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    try {
      final localName = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (e) {
      AppLogger.warn('Local timezone lookup failed; using UTC', e);
      // Fall back to UTC if the platform channel is unavailable.
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: darwin);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await _createAndroidChannel();

    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
      _launchEvent = NotificationEvent.fromResponse(response);
    }

    _initialized = true;
  }

  /// Returns (and clears) the event that launched the app from a notification.
  NotificationEvent? takeLaunchEvent() {
    final e = _launchEvent;
    _launchEvent = null;
    return e;
  }

  Future<void> _createAndroidChannel() async {
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
      ),
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  /// Whether the app may post notifications right now.
  Future<bool> notificationsAllowed() async {
    final android = _android;
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _ios;
    if (ios != null) {
      return (await ios.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  /// Whether reminders can fire at the exact minute. Always true below
  /// Android 12 and on iOS; on Android 12+ the user controls it under
  /// "Alarms & reminders" (otherwise reminders fall back to inexact alarms).
  Future<bool> exactAlarmsAllowed() async =>
      await _android?.canScheduleExactNotifications() ?? true;

  /// Asks for notification permission. Once Android has stopped showing the
  /// prompt (the user denied it twice), opens the app's notification settings
  /// instead so the button never silently does nothing.
  Future<bool> requestNotificationPermission() async {
    final android = _android;
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;
      if (!granted) await android.openAppNotificationSettings();
      return granted;
    }
    return await _ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  /// Opens Android's "Alarms & reminders" screen for this app (12+).
  Future<void> requestExactAlarmPermission() async {
    await _android?.requestExactAlarmsPermission();
  }

  static Future<void> _onForegroundResponse(
    NotificationResponse response,
  ) async {
    // Apply any DB mutation first so listeners see fresh data.
    await NotificationActionHandler.handle(response);
    final event = NotificationEvent.fromResponse(response);
    if (event != null) _actionController.add(event);
  }

  AndroidNotificationDetails _androidDetails({required bool isVariableDose}) {
    final actions = <AndroidNotificationAction>[
      if (isVariableDose)
        const AndroidNotificationAction(
          actionLogDose,
          'Log dose',
          showsUserInterface: true,
        )
      else
        const AndroidNotificationAction(actionTaken, 'Taken'),
      const AndroidNotificationAction(actionSkip, 'Skip'),
      AndroidNotificationAction(actionSnooze, 'Snooze $snoozeMinutes min'),
    ];
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      actions: actions,
    );
  }

  /// Schedules a single reminder at [time]. Uses an exact alarm when allowed;
  /// if the OS refuses exact alarms (permission revoked on Android 12+), falls
  /// back to an inexact alarm rather than dropping the reminder.
  Future<void> scheduleReminder({
    required String id,
    required String medicineName,
    required String doseText,
    required DateTime time,
    required String payload,
    bool isVariableDose = false,
  }) async {
    final body = isVariableDose
        ? 'Time to take $medicineName — tap to enter amount'
        : 'Time to take $doseText';
    await _scheduleAt(
      id: id,
      title: medicineName,
      body: body,
      time: time,
      details: NotificationDetails(
        android: _androidDetails(isVariableDose: isVariableDose),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  /// Zoned schedule with an exact alarm, falling back to inexact when the OS
  /// refuses exact alarms (permission revoked on Android 12+).
  Future<void> _scheduleAt({
    required String id,
    required String title,
    required String body,
    required DateTime time,
    required NotificationDetails details,
    String? payload,
  }) async {
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: _idFor(id),
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(time, tz.local),
      notificationDetails: details,
      androidScheduleMode: mode,
      payload: payload,
    );

    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      AppLogger.warn('Exact alarm refused (${e.code}); using inexact alarm');
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  static const _weeklySummaryId = 'weekly_summary';

  /// Schedules (or refreshes) Sunday 8 PM's "You took X% of your doses this
  /// week". A local notification's text is fixed when scheduled, so this is
  /// recomputed after every dose log and sync: expected counts all of the
  /// week's doses up to Sunday 8 PM, and taken counts what's logged so far —
  /// if nothing else gets logged, the numbers are already final.
  Future<void> refreshWeeklySummary(DatabaseHelper db) async {
    await cancelReminder(_weeklySummaryId);
    final enabled = await SettingsRepository(
      db,
    ).getBool(SettingsRepository.notificationsEnabledKey, defaultValue: true);
    if (!enabled) return;

    final at = nextWeeklySummaryTime(DateTime.now());
    final week = await loadDailyAdherence(db, days: 7, to: at, cutoff: at);
    final t = totals(week);
    if (t.expected == 0) return;
    final pct = (t.taken * 100 / t.expected).round();

    await _scheduleAt(
      id: _weeklySummaryId,
      title: 'Your week with PillTrack',
      body:
          'You took $pct% of your doses this week '
          '(${t.taken} of ${t.expected}).',
      time: at,
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> cancelReminder(String id) => _plugin.cancel(id: _idFor(id));

  Future<void> cancelAll() => _plugin.cancelAll();

  /// Shows a one-off notification immediately (e.g. a refill warning).
  Future<void> showImmediate({
    required String id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      id: _idFor(id),
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// Removes the reminder for one dose occurrence — and any snooze of it —
  /// whether it is still pending or already showing. Called once the dose
  /// is logged so a reminder for it never arrives or lingers.
  Future<void> clearDose(
    String medicineId,
    String scheduleId,
    int scheduledMs,
  ) async {
    final t = DateTime.fromMillisecondsSinceEpoch(scheduledMs);
    final day = DateTime(t.year, t.month, t.day);
    await cancelReminder(_occurrenceKey(medicineId, scheduleId, day));
    await cancelReminder(snoozeKey(medicineId, scheduleId, scheduledMs));
  }

  /// Notification key of the snooze of one dose occurrence. Fixed per
  /// occurrence, so snoozing again replaces the earlier snooze.
  static String snoozeKey(
    String medicineId,
    String? scheduleId,
    int scheduledMs,
  ) => 'snooze|$medicineId|${scheduleId ?? ''}|$scheduledMs';

  /// Marks a reminder payload as a snooze, so a re-sync keeps it.
  static const snoozeMarker = 'snooze';

  /// Payload of a snoozed reminder: the usual `medicine|schedule|time` plus
  /// [snoozeMarker] (readers only use the first three parts).
  static String snoozePayload(
    String medicineId,
    String? scheduleId,
    int scheduledMs,
  ) => '$medicineId|${scheduleId ?? ''}|$scheduledMs|$snoozeMarker';

  /// Brings pending notifications in line with the database: re-schedules
  /// the next [horizonDays] of reminders (see [reminderOccurrences]), leaving
  /// out doses already [logged].
  ///
  /// Only notifications that haven't fired yet are replaced — ones showing
  /// in the notification shade stay. A pending snooze is kept while its
  /// medicine is still active and its dose isn't logged; otherwise it's
  /// cancelled.
  Future<void> rescheduleAll(
    List<Schedule> schedules,
    List<Medicine> medicines, {
    Set<String> logged = const {},
  }) async {
    final activeIds = {
      for (final m in medicines)
        if (m.isActive) m.id,
    };
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (keepSnooze(pending.payload, activeIds, logged)) continue;
      await _plugin.cancel(id: pending.id);
    }
    final occurrences = reminderOccurrences(
      schedules,
      medicines,
      DateTime.now(),
      logged: logged,
    );
    for (final o in occurrences) {
      final day = DateTime(o.time.year, o.time.month, o.time.day);
      await scheduleReminder(
        id: _occurrenceKey(o.medicine.id, o.schedule.id, day),
        medicineName: o.medicine.name,
        doseText: o.medicine.doseText(o.schedule.doseAmount),
        time: o.time,
        payload:
            '${o.medicine.id}|${o.schedule.id}|${o.time.millisecondsSinceEpoch}',
        isVariableDose: o.schedule.isVariableDose,
      );
    }
  }

  /// Single entry point to bring OS notifications in line with the database
  /// and user settings. Call after any change to medicines, schedules or
  /// notification settings, and on app start.
  Future<void> syncFromDatabase(DatabaseHelper db) async {
    final settings = SettingsRepository(db);
    snoozeMinutes = await settings.getInt(
      SettingsRepository.snoozeMinutesKey,
      defaultValue: defaultSnoozeMinutes,
    );
    final enabled = await settings.getBool(
      SettingsRepository.notificationsEnabledKey,
      defaultValue: true,
    );
    if (!enabled) {
      await cancelAll();
      return;
    }
    final pairs = await ScheduleRepository(db).getAllActiveWithMedicine();
    final meds = await MedicineRepository(db).getActive();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // From yesterday: a snooze can carry a late-evening dose past midnight.
    final logs = await DoseLogRepository(db).getByDateRange(
      DateTime(today.year, today.month, today.day - 1).millisecondsSinceEpoch,
      DateTime(
        today.year,
        today.month,
        today.day + horizonDays + 1,
      ).millisecondsSinceEpoch,
    );
    await rescheduleAll(
      pairs.map((p) => p.schedule).toList(),
      meds,
      logged: loggedDoseKeys(logs),
    );
    // rescheduleAll replaced the pending weekly summary too.
    await refreshWeeklySummary(db);
  }

  static String _occurrenceKey(
    String medicineId,
    String scheduleId,
    DateTime day,
  ) {
    final dateKey = '${day.year}-${day.month}-${day.day}';
    return '$medicineId|$scheduleId|$dateKey';
  }

  /// Deterministic 31-bit id from a string (stable across runs, unlike
  /// String.hashCode), so re-scheduling overwrites rather than duplicates.
  @visibleForTesting
  static int idFor(String key) => _idFor(key);

  static int _idFor(String key) {
    var hash = 2166136261; // FNV-1a 32-bit
    for (final codeUnit in key.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}

/// Key for "this schedule's dose on this local day", used to tell which
/// reminders are already dealt with. See [loggedDoseKeys].
String doseDayKey(String scheduleId, DateTime time) =>
    '$scheduleId|${time.year}-${time.month}-${time.day}';

/// [doseDayKey]s of every scheduled dose in [logs] that was taken or skipped.
Set<String> loggedDoseKeys(Iterable<DoseLog> logs) => {
  for (final l in logs)
    if (l.scheduleId != null && !l.isPending)
      doseDayKey(
        l.scheduleId!,
        DateTime.fromMillisecondsSinceEpoch(l.scheduledTime),
      ),
};

/// Whether a pending notification with [payload] is a snooze worth keeping:
/// its medicine is still active ([activeMedicineIds]) and its dose isn't in
/// [logged] (see [loggedDoseKeys]).
bool keepSnooze(
  String? payload,
  Set<String> activeMedicineIds,
  Set<String> logged,
) {
  final parts = payload?.split('|');
  if (parts == null ||
      parts.length < 4 ||
      parts[3] != NotificationService.snoozeMarker) {
    return false;
  }
  if (!activeMedicineIds.contains(parts[0])) return false;
  final scheduledMs = int.tryParse(parts[2]);
  if (parts[1].isEmpty || scheduledMs == null) return true;
  final due = DateTime.fromMillisecondsSinceEpoch(scheduledMs);
  return !logged.contains(doseDayKey(parts[1], due));
}

/// One reminder to schedule.
typedef ReminderOccurrence = ({
  Medicine medicine,
  Schedule schedule,
  DateTime time,
});

/// Every reminder due from [now] through the next
/// [NotificationService.horizonDays] days: active, non-PRN medicines only, on
/// each schedule's weekdays, never in the past, never after the last day
/// of a fixed course, and never for a dose already [logged] (see
/// [loggedDoseKeys]) — e.g. one taken early from the app.
///
/// Days are stepped by calendar date (not 24h durations) so daylight-saving
/// changes can't skip or duplicate a day.
List<ReminderOccurrence> reminderOccurrences(
  List<Schedule> schedules,
  List<Medicine> medicines,
  DateTime now, {
  Set<String> logged = const {},
}) {
  final byId = {for (final m in medicines) m.id: m};
  final result = <ReminderOccurrence>[];
  for (final schedule in schedules) {
    final medicine = byId[schedule.medicineId];
    if (medicine == null || !medicine.isActive || medicine.isPrn) continue;

    for (var d = 0; d <= NotificationService.horizonDays; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      if (!medicine.isOngoingOn(day)) break; // course over: later days too
      // ISO weekday 1..7; schedule.days uses the same convention.
      if (!schedule.days.contains(day.weekday)) continue;
      final time = DateTime(
        day.year,
        day.month,
        day.day,
        schedule.hour,
        schedule.minute,
      );
      if (time.isBefore(now)) continue; // don't schedule past times
      if (logged.contains(doseDayKey(schedule.id, time))) continue;
      result.add((medicine: medicine, schedule: schedule, time: time));
    }
  }
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}
