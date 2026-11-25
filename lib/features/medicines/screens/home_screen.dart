import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/guarded.dart';
import '../../../data/adherence.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/prescription.dart';
import '../../../data/models/schedule.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../services/notification_service.dart';
import '../../history/screens/history_screen.dart';
import '../../prescriptions/providers/prescription_providers.dart';
import '../../prescriptions/screens/prescriptions_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../providers/medicine_providers.dart';
import '../widgets/amount_entry_dialog.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/dose_card.dart';
import '../widgets/dose_feedback.dart';
import '../widgets/dose_options_sheet.dart';
import '../widgets/medicine_card.dart';
import 'edit_medicine_screen.dart';
import 'medicine_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  StreamSubscription<NotificationEvent>? _sub;

  /// True when the OS is blocking notifications, so no reminder can arrive.
  bool _remindersOff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = NotificationService.actionStream.listen(_onNotificationEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFrame());
  }

  @override
  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Background-isolate notification actions write straight to the DB, so
    // re-read when the user comes back to the app.
    if (state == AppLifecycleState.resumed) {
      ref.read(medicineActionsProvider).refreshAll();
      // The user may have just changed notification access in Settings.
      _checkReminderAccess();
    }
  }

  Future<void> _onFirstFrame() async {
    // Permissions are requested during onboarding; here we only reflect them.
    await _checkReminderAccess();
    await ref.read(medicineActionsProvider).resync();

    final launch = NotificationService.instance.takeLaunchEvent();
    if (launch != null) {
      await _onNotificationEvent(launch);
    } else {
      await _maybeAskForReview();
    }
  }

  Future<void> _checkReminderAccess() async {
    var allowed = true;
    try {
      allowed = await NotificationService.instance.notificationsAllowed();
    } catch (e) {
      AppLogger.warn('Notification permission check failed', e);
    }
    if (mounted && allowed == _remindersOff) {
      setState(() => _remindersOff = !allowed);
    }
  }

  Future<void> _turnOnReminders() async {
    try {
      await NotificationService.instance.requestNotificationPermission();
    } catch (e) {
      AppLogger.warn('Notification permission request failed', e);
    }
    await _checkReminderAccess();
  }

  /// One-time store-review request after a week of good adherence. Uses the
  /// platform's in-app review sheet directly (no "do you like us?" gate,
  /// which store policies discourage).
  Future<void> _maybeAskForReview() async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      if (await settings.getBool(SettingsRepository.reviewPromptedKey)) return;

      final now = DateTime.now();
      final firstUseMs = await settings.getInt(
        SettingsRepository.firstUseAtKey,
      );
      if (firstUseMs == 0) {
        await settings.setInt(
          SettingsRepository.firstUseAtKey,
          now.millisecondsSinceEpoch,
        );
        return;
      }

      final recent = await loadDailyAdherence(
        ref.read(databaseHelperProvider),
        days: reviewPromptMinDays,
        to: now,
        cutoff: now,
      );
      final eligible = qualifiesForReviewPrompt(
        firstUse: DateTime.fromMillisecondsSinceEpoch(firstUseMs),
        now: now,
        recentDays: recent,
      );
      if (!eligible) return;

      await settings.setBool(SettingsRepository.reviewPromptedKey, true);
      final review = InAppReview.instance;
      if (await review.isAvailable()) await review.requestReview();
    } catch (e) {
      AppLogger.warn('Review prompt check failed', e);
    }
  }

  Future<void> _onNotificationEvent(NotificationEvent event) async {
    final actions = ref.read(medicineActionsProvider);
    actions.refreshAll();
    if (event.actionId != NotificationService.actionLogDose) return;

    final medicine = await ref
        .read(medicineRepositoryProvider)
        .getById(event.medicineId);
    final schedules = await ref
        .read(scheduleRepositoryProvider)
        .getByMedicineId(event.medicineId);
    Schedule? schedule;
    for (final s in schedules) {
      if (s.id == event.scheduleId) schedule = s;
    }
    if (medicine == null || schedule == null || !mounted) return;

    await _logVariable(
      TodayDose(
        medicine: medicine,
        schedule: schedule,
        time: DateTime.fromMillisecondsSinceEpoch(event.scheduledTimeMs),
      ),
    );
  }

  Future<void> _logVariable(TodayDose dose) async {
    final messenger = ScaffoldMessenger.of(context);
    final amount = await showAmountEntryDialog(
      context,
      title: 'How much ${dose.medicine.name}?',
      unitLabel: dose.medicine.unitLabelPlural,
      initial: dose.schedule.doseAmount > 0 ? dose.schedule.doseAmount : null,
    );
    if (amount == null) return;
    await guarded(messenger, _logFailed, () async {
      final result = await ref
          .read(medicineActionsProvider)
          .logScheduledDose(dose, amount);
      showDoseFeedback(messenger, result, medicineName: dose.medicine.name);
    });
  }

  static const _logFailed = "Couldn't save that dose. Please try again.";

  Future<void> _onPrimary(TodayDose dose) async {
    if (dose.schedule.isVariableDose) return _logVariable(dose);
    final messenger = ScaffoldMessenger.of(context);
    await guarded(messenger, _logFailed, () async {
      final result = await ref.read(medicineActionsProvider).markTaken(dose);
      showDoseFeedback(messenger, result, medicineName: dose.medicine.name);
    });
  }

  Future<void> _onSkip(TodayDose dose) => guarded(
    ScaffoldMessenger.of(context),
    "Couldn't record the skip. Please try again.",
    () => ref.read(medicineActionsProvider).skip(dose),
  );

  Future<void> _logPrn(Medicine medicine) async {
    final messenger = ScaffoldMessenger.of(context);
    final amount = await showAmountEntryDialog(
      context,
      title: 'Log ${medicine.name}',
      unitLabel: medicine.unitLabelPlural,
      initial: 1,
    );
    if (amount == null) return;
    await guarded(messenger, _logFailed, () async {
      final result = await ref
          .read(medicineActionsProvider)
          .logPrn(medicine, amount);
      showDoseFeedback(messenger, result, medicineName: medicine.name);
    });
  }

  static String? _prescriptionLabel(Prescription? p) => p == null
      ? null
      : p.reason == null
      ? p.doctorName
      : '${p.reason} · ${p.doctorName}';

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayDosesProvider);
    final prn = ref.watch(prnMedicinesProvider);
    final medicines = ref.watch(activeMedicinesProvider);
    final prescriptions = {
      for (final p
          in ref.watch(allPrescriptionsProvider).asData?.value ??
              const <Prescription>[])
        p.id: p,
    };
    final schedulesByMedicine = ref
        .watch(allSchedulesWithMedicineProvider)
        .maybeWhen(
          data: (pairs) {
            final map = <String, List<Schedule>>{};
            for (final p in pairs) {
              map.putIfAbsent(p.medicine.id, () => []).add(p.schedule);
            }
            return map;
          },
          orElse: () => const <String, List<Schedule>>{},
        );

    final meds = medicines.asData?.value;
    final showTabs = meds != null && meds.isNotEmpty;
    final pending = today.asData?.value.where((d) => d.isPending).length ?? 0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.appName),
          actions: [
            IconButton(
              tooltip: 'Prescriptions',
              icon: const Icon(Icons.receipt_long),
              onPressed: () => _open(const PrescriptionsScreen()),
            ),
            IconButton(
              tooltip: AppStrings.history,
              icon: const Icon(Icons.history),
              onPressed: () => _open(const HistoryScreen()),
            ),
            IconButton(
              tooltip: AppStrings.settings,
              icon: const Icon(Icons.settings),
              onPressed: () => _open(const SettingsScreen()),
            ),
          ],
          bottom: showTabs
              ? TabBar(
                  labelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(fontSize: 16),
                  tabs: [
                    Tab(
                      text: AppStrings.todaysDoses,
                      icon: Badge.count(
                        count: pending,
                        isLabelVisible: pending > 0,
                        child: const Icon(Icons.today),
                      ),
                    ),
                    const Tab(
                      text: AppStrings.myMedicines,
                      icon: Icon(Icons.medication_outlined),
                    ),
                  ],
                )
              : null,
        ),
        body: !showTabs
            ? RefreshIndicator(
                onRefresh: _refresh,
                child: medicines.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorView(
                    message: 'Could not load your medicines.',
                    onRetry: () =>
                        ref.read(medicineActionsProvider).refreshAll(),
                  ),
                  data: (_) => _EmptyState(
                    onAdd: () => _open(const EditMedicineScreen()),
                  ),
                ),
              )
            : Column(
                children: [
                  // Above both tabs: no reminder can arrive while this is shown.
                  if (_remindersOff)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _RemindersOffBanner(onTurnOn: _turnOnReminders),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _tabList('today', _todayTab(meds, today, prn)),
                        _tabList('medicines', [
                          for (final m in meds)
                            MedicineCard(
                              medicine: m,
                              schedules: schedulesByMedicine[m.id] ?? const [],
                              prescriptionLabel: _prescriptionLabel(
                                prescriptions[m.prescriptionId],
                              ),
                              onTap: () =>
                                  _open(MedicineDetailScreen(medicineId: m.id)),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _open(const EditMedicineScreen()),
          icon: const Icon(Icons.add),
          label: const Text(AppStrings.addMedicine),
        ),
        bottomNavigationBar: const SafeArea(child: BannerAdWidget()),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.read(medicineActionsProvider).refreshAll();
    await ref.read(activeMedicinesProvider.future);
  }

  /// One tab's scrollable content, with pull-to-refresh. The storage key keeps
  /// each tab's scroll position when switching between them.
  Widget _tabList(String key, List<Widget> children) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      key: PageStorageKey(key),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: children,
    ),
  );

  /// Today: streak, the day's scheduled doses, then as-needed medicines.
  List<Widget> _todayTab(
    List<Medicine> meds,
    AsyncValue<List<TodayDose>> today,
    AsyncValue<List<Medicine>> prn,
  ) {
    final hasScheduled = meds.any((m) => !m.isPrn);
    return [
      if (hasScheduled) ...[
        ...ref
            .watch(streakProvider)
            .maybeWhen(
              data: (streak) => streak.current > 0
                  ? [_StreakCard(streak: streak)]
                  : const <Widget>[],
              orElse: () => const <Widget>[],
            ),
        ...today.when(
          loading: () => [const LinearProgressIndicator()],
          error: (e, _) => [
            _ErrorView(
              message: "Could not load today's doses.",
              onRetry: () => ref.invalidate(todayDosesProvider),
            ),
          ],
          data: (doses) => doses.isEmpty
              ? [const _MutedText('No doses scheduled today')]
              : [
                  for (final d in doses)
                    DoseCard(
                      dose: d,
                      onPrimary: () => _onPrimary(d),
                      onSkip: () => _onSkip(d),
                      onEdit: () => showDoseOptions(context, ref, d),
                    ),
                ],
        ),
      ],
      ...prn.maybeWhen(
        data: (list) => list.isEmpty
            ? const <Widget>[]
            : [
                const _SectionHeader(AppStrings.asNeeded),
                for (final m in list)
                  _PrnCard(medicine: m, onLog: () => _logPrn(m)),
              ],
        orElse: () => const <Widget>[],
      ),
    ];
  }
}

class _PrnCard extends StatelessWidget {
  const _PrnCard({required this.medicine, required this.onLog});
  final Medicine medicine;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicine.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (medicine.trackInventory)
                    Text(
                      medicine.remainingLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onLog,
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.logADose),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    // ListView so pull-to-refresh still works on the empty state.
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.medication_outlined,
          size: 96,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.noMedicines,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add your first medicine'),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _RemindersOffBanner extends StatelessWidget {
  const _RemindersOffBanner({required this.onTurnOn});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.notifications_off, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Reminders are off. PillTrack can't remind you until "
                'notifications are allowed.',
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 16),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: onTurnOn, child: const Text('Turn on')),
          ],
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});
  final Streak streak;

  static String _days(int n) => n == 1 ? '1 day' : '$n days';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.local_fire_department,
              size: 36,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "You've taken every dose for ${_days(streak.current)} "
                    'in a row',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (streak.longest > streak.current)
                    Text(
                      'Your best: ${_days(streak.longest)}',
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
