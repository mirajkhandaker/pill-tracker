import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../../../core/utils/app_logger.dart';
import '../../../core/utils/dose_formatter.dart';
import '../../../core/utils/dose_frequency.dart';
import '../../../core/utils/guarded.dart';
import '../../../data/models/dose_log.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/prescription.dart';
import '../../../data/models/schedule.dart';
import '../../history/screens/history_screen.dart';
import '../../medicines/providers/medicine_providers.dart';
import '../../medicines/screens/edit_medicine_screen.dart';
import '../../medicines/screens/medicine_detail_screen.dart';
import '../providers/prescription_providers.dart';
import '../widgets/prescription_photos.dart';
import 'edit_prescription_screen.dart';
import 'photo_viewer_screen.dart';
import 'scan_prescription_screen.dart';

/// One prescription: its details, medicines (current, finished, stopped),
/// adherence, and the actions that matter after a doctor visit.
class PrescriptionDetailScreen extends ConsumerWidget {
  const PrescriptionDetailScreen({super.key, required this.prescriptionId});

  final String prescriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rx = ref.watch(prescriptionByIdProvider(prescriptionId));
    return rx.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: OutlinedButton(
            onPressed: () =>
                ref.invalidate(prescriptionByIdProvider(prescriptionId)),
            child: const Text('Could not load — retry'),
          ),
        ),
      ),
      data: (p) => p == null
          ? Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('Prescription not found')),
            )
          : _Body(prescription: p),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.prescription});
  final Prescription prescription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = prescription;
    final theme = Theme.of(context);
    final medicines = ref.watch(prescriptionMedicinesProvider(p.id));
    final logs = ref.watch(prescriptionLogsProvider(p.id));
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(p.shortTitle),
        actions: [
          IconButton(
            tooltip: 'Edit details',
            icon: const Icon(Icons.edit),
            onPressed: () =>
                _push(context, EditPrescriptionScreen(prescription: p)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            p.shortTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            p.label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!p.isActive && p.endedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Chip(
                avatar: const Icon(Icons.history, size: 18),
                label: Text(
                  'Ended ${DateFormat('d MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(p.endedAt!))}',
                ),
              ),
            ),
          if (p.notes != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.notes),
                title: const Text('Notes'),
                subtitle: Text(p.notes!),
              ),
            ),
          _PhotosSection(prescriptionId: p.id),
          ...logs.maybeWhen(
            data: (l) => [_AdherenceCard(logs: l)],
            orElse: () => const <Widget>[],
          ),
          if (p.isActive) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan prescription for medicines'),
              onPressed: () =>
                  _push(context, ScanPrescriptionScreen(prescriptionId: p.id)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add a medicine yourself'),
              onPressed: () =>
                  _push(context, EditMedicineScreen(prescriptionId: p.id)),
            ),
          ],
          ...medicines.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [const Text('Could not load medicines')],
            data: (list) => _medicineSections(context, list, now),
          ),
          const SizedBox(height: 16),
          if (p.isActive) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.autorenew),
              label: const Text('Got a new prescription?'),
              onPressed: () =>
                  _push(context, EditPrescriptionScreen(replacesId: p.id)),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Dose history PDF for your doctor'),
            onPressed: () => _exportPdf(context, ref, p),
          ),
          if (p.isActive) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End this prescription'),
              onPressed: () => _confirmEnd(context, ref, p),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _medicineSections(
    BuildContext context,
    List<Medicine> list,
    DateTime now,
  ) {
    if (list.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('No medicines on this prescription yet.'),
        ),
      ];
    }
    final current = list
        .where((m) => m.isActive && !m.isCourseFinished(now))
        .toList();
    final finished = list
        .where((m) => m.isActive && m.isCourseFinished(now))
        .toList();
    final stopped = list.where((m) => !m.isActive).toList();
    return [
      if (current.isNotEmpty) ...[
        const _SectionHeader('Taking now'),
        for (final m in current) _MedicineTile(medicine: m),
      ],
      if (finished.isNotEmpty) ...[
        const _SectionHeader('Course finished'),
        for (final m in finished) _MedicineTile(medicine: m),
      ],
      if (stopped.isNotEmpty) ...[
        const _SectionHeader('Stopped'),
        for (final m in stopped) _MedicineTile(medicine: m),
      ],
    ];
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _confirmEnd(
    BuildContext context,
    WidgetRef ref,
    Prescription p,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End this prescription?'),
        content: const Text(
          'Reminders stop for all its medicines. The prescription and its '
          'dose history stay in Past.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End prescription'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await guarded(
      ScaffoldMessenger.of(context),
      "Couldn't end the prescription. Please try again.",
      () => ref.read(prescriptionActionsProvider).end(p.id),
    );
  }

  Future<void> _exportPdf(
    BuildContext context,
    WidgetRef ref,
    Prescription p,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final medicines = await ref.read(
        prescriptionMedicinesProvider(p.id).future,
      );
      final logs = (await ref.read(prescriptionLogsProvider(p.id).future))
          .where((l) => !l.isPending)
          .toList();
      if (logs.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No doses logged for it yet.')),
        );
        return;
      }
      final fmt = DateFormat('d MMM yyyy');
      final end = p.endedAt == null
          ? 'present'
          : fmt.format(DateTime.fromMillisecondsSinceEpoch(p.endedAt!));
      final bytes = await buildHistoryPdf(
        logs,
        {for (final m in medicines) m.id: m},
        '${fmt.format(p.issuedDate)} – $end',
        heading: 'PillTrack — prescription history',
        details: [
          'Prescribed by: ${p.doctorName}',
          if (p.reason != null) 'For: ${p.reason}',
        ],
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'pilltrack-prescription.pdf',
      );
    } catch (e, st) {
      AppLogger.error('Prescription PDF export failed', e, st);
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't create the PDF. Please try again."),
        ),
      );
    }
  }
}

class _AdherenceCard extends StatelessWidget {
  const _AdherenceCard({required this.logs});
  final List<DoseLog> logs;

  @override
  Widget build(BuildContext context) {
    final logged = logs.where((l) => !l.isPending && l.scheduleId != null);
    final total = logged.length;
    if (total == 0) return const SizedBox.shrink();
    final taken = logged.where((l) => l.isTaken).length;
    final pct = (taken * 100 / total).round();
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Taken $taken of $total scheduled doses you logged ($pct%)',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// One medicine on the prescription. Tapping a current (or finished-course)
/// medicine opens it straight in the editor; a stopped one is a historical
/// record, so it opens read-only.
class _MedicineTile extends ConsumerWidget {
  const _MedicineTile({required this.medicine});
  final Medicine medicine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = medicine;
    final editable = m.isActive;
    final schedules = ref.watch(schedulesForMedicineProvider(m.id));
    final end = m.endDay;
    final details = [
      formLabel(m.form),
      if (m.dosageText != null) m.dosageText!,
      if (end != null) 'until ${DateFormat('d MMM').format(end)}',
    ].join(' · ');
    final plan = scheduleSummary(m, schedules.asData?.value ?? const []);

    return Card(
      child: ListTile(
        leading: const Icon(Icons.medication_outlined),
        title: Text(m.name),
        subtitle: Text(plan.isEmpty ? details : '$plan\n$details'),
        isThreeLine: plan.isNotEmpty,
        trailing: Icon(
          editable ? Icons.edit_outlined : Icons.history,
          semanticLabel: editable ? 'Edit' : 'View history',
        ),
        onTap: () async {
          final navigator = Navigator.of(context);
          if (!editable) {
            await navigator.push(
              MaterialPageRoute(
                builder: (_) => MedicineDetailScreen(medicineId: m.id),
              ),
            );
            return;
          }
          final current = await ref.read(
            schedulesForMedicineProvider(m.id).future,
          );
          await navigator.push(
            MaterialPageRoute(
              builder: (_) =>
                  EditMedicineScreen(medicine: m, schedules: current),
            ),
          );
        },
      ),
    );
  }
}

/// "1 Tablet · Twice a day", "As needed", "Variable dose · Every 8 hours".
String scheduleSummary(Medicine m, List<Schedule> schedules) {
  if (m.isPrn) return 'As needed';
  if (schedules.isEmpty) return '';
  final f = inferFrequency([
    for (final s in schedules) TimeOfDay(hour: s.hour, minute: s.minute),
  ]);
  final often = switch (f.frequency) {
    DoseFrequency.once => 'Once a day',
    DoseFrequency.twice => 'Twice a day',
    DoseFrequency.thrice => '3 times a day',
    DoseFrequency.interval => 'Every ${f.intervalHours} hours',
    DoseFrequency.custom => '${schedules.length} times a day',
  };
  final amounts = {for (final s in schedules) s.doseAmount};
  final dose = schedules.any((s) => s.isVariableDose)
      ? 'Variable dose'
      : amounts.length == 1
      ? m.doseText(amounts.single)
      : 'Varying amounts';
  final everyDay = schedules.every((s) => s.dayCount == 7);
  return '$dose · $often${everyDay ? '' : ', some days'}';
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

/// The prescription's photos (pages): thumbnails that open full-screen, and
/// buttons to add more.
class _PhotosSection extends ConsumerWidget {
  const _PhotosSection({required this.prescriptionId});
  final String prescriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos =
        ref.watch(prescriptionPhotosProvider(prescriptionId)).asData?.value ??
        const [];
    final dir = ref.watch(photoDirectoryProvider).asData?.value;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prescription photos',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (photos.isNotEmpty && dir != null) ...[
            SizedBox(
              height: PhotoThumbnail.height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => PhotoThumbnail(
                  file: File(p.join(dir.path, photos[i].fileName)),
                  label: 'Prescription photo ${i + 1} of ${photos.length}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PhotoViewerScreen(
                        prescriptionId: prescriptionId,
                        initialIndex: i,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Keep a photo of the paper prescription so you always have '
                'it with you.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          PhotoSourceButtons(
            onPicked: (paths) => guarded(
              ScaffoldMessenger.of(context),
              "Couldn't save the photo. Please try again.",
              () => ref
                  .read(prescriptionActionsProvider)
                  .addPhotos(prescriptionId, paths),
            ),
          ),
        ],
      ),
    );
  }
}
