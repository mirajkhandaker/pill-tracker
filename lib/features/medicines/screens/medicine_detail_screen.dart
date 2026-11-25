import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/utils/dose_formatter.dart';
import '../../../core/utils/guarded.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/schedule.dart';
import '../../history/widgets/dose_log_tile.dart';
import '../../prescriptions/providers/prescription_providers.dart';
import '../../prescriptions/screens/prescription_detail_screen.dart';
import '../providers/medicine_providers.dart';
import '../widgets/amount_entry_dialog.dart';
import '../widgets/edit_dose_sheet.dart';
import '../widgets/inline_ad_card.dart';
import 'edit_medicine_screen.dart';

const _weekdayShort = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

class MedicineDetailScreen extends ConsumerWidget {
  const MedicineDetailScreen({super.key, required this.medicineId});

  final String medicineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicine = ref.watch(medicineByIdProvider(medicineId));
    final schedules = ref.watch(schedulesForMedicineProvider(medicineId));

    return medicine.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: OutlinedButton(
            onPressed: () => ref.invalidate(medicineByIdProvider(medicineId)),
            child: const Text('Could not load — retry'),
          ),
        ),
      ),
      data: (m) {
        if (m == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Medicine not found')),
          );
        }
        final scheduleList = schedules.asData?.value ?? const <Schedule>[];
        return Scaffold(
          appBar: AppBar(
            title: Text(m.name),
            // A stopped medicine is a historical record: view only.
            actions: [
              if (m.isActive) ...[
                IconButton(
                  tooltip: AppStrings.edit,
                  icon: const Icon(Icons.edit),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditMedicineScreen(
                        medicine: m,
                        schedules: scheduleList,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.delete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, m),
                ),
              ],
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                m.name,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                formLabel(m.form),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (m.dosageText != null) ...[
                const SizedBox(height: 4),
                Text(
                  m.dosageText!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              const SizedBox(height: 16),
              _StatusBanner(medicine: m),
              if (m.prescriptionId != null)
                _PrescriptionLink(prescriptionId: m.prescriptionId!),
              if (m.endDay != null && !m.isCourseFinished(DateTime.now()))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_available),
                    title: const Text('Fixed course'),
                    subtitle: Text(
                      'Last day: ${DateFormat('EEE d MMM yyyy').format(m.endDay!)}',
                    ),
                  ),
                ),
              if (m.trackInventory && m.isActive)
                _InventoryCard(medicine: m, schedules: scheduleList),
              _ScheduleCard(medicine: m, schedules: scheduleList),
              if (m.notes != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notes),
                    title: const Text(AppStrings.notes),
                    subtitle: Text(m.notes!),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                AppStrings.recentHistory,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              _RecentHistory(medicine: m),
              // Last, so it never sits between pieces of medicine info.
              const InlineAdCard(),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Medicine m,
  ) async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${m.name}?'),
        content: const Text(
          'Reminders for this medicine will stop. Your dose history is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final deleted = await guarded(
      ScaffoldMessenger.of(context),
      "Couldn't delete ${m.name}. Please try again.",
      () => ref.read(medicineActionsProvider).deleteMedicine(m.id),
    );
    if (deleted) navigator.pop();
  }
}

class _InventoryCard extends ConsumerWidget {
  const _InventoryCard({required this.medicine, required this.schedules});
  final Medicine medicine;
  final List<Schedule> schedules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final days = medicine.daysUntilEmpty(schedules);
    final low = medicine.needsRefill(schedules);
    final pluralPkg = packageLabelPlural(medicine.packageType);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              medicine.remainingLabel,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: low ? theme.colorScheme.error : null,
              ),
            ),
            const SizedBox(height: 4),
            // Pack breakdown only when there are whole packs to describe.
            if (medicine.packagesInHand > 0)
              Text(
                medicine.inventoryBreakdown,
                style: theme.textTheme.bodyLarge,
              ),
            if (days < 999) ...[
              const SizedBox(height: 4),
              Text(
                '$days ${AppStrings.daysUntilEmpty}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: low ? theme.colorScheme.error : null,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (medicine.hasPackSize)
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text('Add $pluralPkg'),
                    onPressed: () => _addPackages(context, ref),
                  ),
                medicine.hasPackSize
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text('Add ${medicine.unitLabelPlural}'),
                        onPressed: () => _addUnits(context, ref),
                      )
                    : FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text('Add ${medicine.unitLabelPlural}'),
                        onPressed: () => _addUnits(context, ref),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPackages(BuildContext context, WidgetRef ref) async {
    final pluralPkg = packageLabelPlural(medicine.packageType);
    final messenger = ScaffoldMessenger.of(context);
    final n = await showAmountEntryDialog(
      context,
      title: 'Add $pluralPkg',
      unitLabel: pluralPkg,
      initial: 1,
    );
    if (n == null) return;
    final count = n.round();
    if (count < 1) return;
    final added = await guarded(
      messenger,
      "Couldn't update your stock. Please try again.",
      () => ref.read(medicineActionsProvider).addPackages(medicine.id, count),
    );
    if (!added) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Added $count '
          '${count == 1 ? packageLabel(medicine.packageType) : pluralPkg}',
        ),
      ),
    );
  }

  /// Refill by a number of units — the simple path when no pack size is set.
  Future<void> _addUnits(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final amount = await showAmountEntryDialog(
      context,
      title: 'Add ${medicine.unitLabelPlural}',
      unitLabel: medicine.unitLabelPlural,
    );
    if (amount == null) return;
    final added = await guarded(
      messenger,
      "Couldn't update your stock. Please try again.",
      () => ref.read(medicineActionsProvider).addUnits(medicine.id, amount),
    );
    if (!added) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Added ${formatAmount(amount)} '
          '${unitLabel(amount, medicine.doseUnit, form: medicine.form)}',
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.medicine, required this.schedules});
  final Medicine medicine;
  final List<Schedule> schedules;

  static String _days(Schedule s) {
    if (s.dayCount == 7) return 'Every day';
    final sorted = s.days.toList()..sort();
    return sorted.map((d) => _weekdayShort[d]).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (medicine.isPrn) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.back_hand_outlined),
          title: Text('As-needed'),
          subtitle: Text('No fixed schedule — log doses when you take them'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final s in schedules)
            ListTile(
              leading: const Icon(Icons.alarm),
              title: Text(
                DateFormat('h:mm a')
                    .format(DateTime(2000, 1, 1, s.hour, s.minute)),
              ),
              subtitle: Text(
                '${_days(s)} · ${s.isVariableDose ? 'Variable dose' : medicine.doseText(s.doseAmount)}',
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentHistory extends ConsumerWidget {
  const _RecentHistory({required this.medicine});
  final Medicine medicine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(
      medicineLogsProvider((medicineId: medicine.id, days: 14)),
    );
    return logs.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => const Text('Could not load history'),
      data: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No doses logged in the last 14 days'),
          );
        }
        return Column(
          children: [
            for (final l in list)
              DoseLogTile(
                log: l,
                medicine: medicine,
                onTap: () =>
                    showEditDoseSheet(context, log: l, medicine: medicine),
              ),
          ],
        );
      },
    );
  }
}

/// Explains why a medicine has no reminders: stopped, or its course is over.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.medicine});
  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final m = medicine;
    final String? text;
    if (!m.isActive) {
      text = 'Stopped — you no longer take this. Its history is kept.';
    } else if (m.isCourseFinished(DateTime.now())) {
      text =
          'Course finished on ${DateFormat('d MMM yyyy').format(m.endDay!)}. '
          'No more reminders.';
    } else {
      text = null;
    }
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(text),
      ),
    );
  }
}

/// Tappable link to the prescription a medicine belongs to.
class _PrescriptionLink extends ConsumerWidget {
  const _PrescriptionLink({required this.prescriptionId});
  final String prescriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(prescriptionByIdProvider(prescriptionId)).asData?.value;
    if (p == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long),
        title: Text(p.reason == null ? 'Prescription' : p.reason!),
        subtitle: Text(p.isActive ? p.label : '${p.label} · ended'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                PrescriptionDetailScreen(prescriptionId: prescriptionId),
          ),
        ),
      ),
    );
  }
}
