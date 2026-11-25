import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/dose_formatter.dart';
import '../../../data/models/dose_log.dart';
import '../../../data/models/medicine.dart';
import '../../medicines/providers/medicine_providers.dart';
import '../../medicines/widgets/edit_dose_sheet.dart';
import '../../medicines/widgets/inline_ad_card.dart';
import '../widgets/dose_log_tile.dart';

enum HistoryFilter {
  all(AppStrings.filterAll),
  last7(AppStrings.filter7),
  last30(AppStrings.filter30),
  thisMonth(AppStrings.filterMonth);

  const HistoryFilter(this.label);
  final String label;

  /// [start, end) in unix ms.
  (int, int) range(DateTime now) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final end = tomorrow.millisecondsSinceEpoch;
    return switch (this) {
      HistoryFilter.all => (0, end),
      HistoryFilter.last7 => (
        DateTime(now.year, now.month, now.day + 1 - 7).millisecondsSinceEpoch,
        end,
      ),
      HistoryFilter.last30 => (
        DateTime(now.year, now.month, now.day + 1 - 30).millisecondsSinceEpoch,
        end,
      ),
      HistoryFilter.thisMonth => (
        DateTime(now.year, now.month).millisecondsSinceEpoch,
        end,
      ),
    };
  }
}

/// Logged (non-pending) doses for a filter, newest first. Auto-disposed so the
/// screen always shows fresh data when reopened.
final historyLogsProvider = FutureProvider.autoDispose
    .family<List<DoseLog>, HistoryFilter>((ref, filter) async {
      final (start, end) = filter.range(DateTime.now());
      final logs = await ref
          .watch(doseLogRepositoryProvider)
          .getByDateRange(start, end);
      return logs.where((l) => !l.isPending).toList();
    });

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryFilter _filter = HistoryFilter.last7;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(historyLogsProvider(_filter));
    final medicines = ref.watch(allMedicinesProvider).asData?.value ?? const [];
    final byId = {for (final m in medicines) m.id: m};

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.history)),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final f in HistoryFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: logs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: OutlinedButton(
                  onPressed: () => ref.invalidate(historyLogsProvider(_filter)),
                  child: const Text('Could not load — retry'),
                ),
              ),
              data: (list) => list.isEmpty
                  ? const _EmptyHistory()
                  : _HistoryList(logs: list, medicines: byId, onEdit: _editLog),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text(AppStrings.exportPdf),
                  onPressed: _exporting || (logs.asData?.value.isEmpty ?? true)
                      ? null
                      : () => _export(logs.asData!.value, byId),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editLog(DoseLog log, Medicine medicine) async {
    final changed = await showEditDoseSheet(
      context,
      log: log,
      medicine: medicine,
    );
    // This screen's list is its own (auto-disposed) provider.
    if (changed) ref.invalidate(historyLogsProvider);
  }

  Future<void> _export(List<DoseLog> logs, Map<String, Medicine> byId) async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildHistoryPdf(logs, byId, _filter.label);
      await Printing.sharePdf(bytes: bytes, filename: 'pilltrack-history.pdf');
    } catch (e, st) {
      AppLogger.error('PDF export failed', e, st);
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't create the PDF. Please try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// Adherence over a set of logs: taken vs. all logged outcomes.
({int taken, int total}) adherence(List<DoseLog> logs) {
  final taken = logs.where((l) => l.isTaken).length;
  return (taken: taken, total: logs.length);
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.logs,
    required this.medicines,
    required this.onEdit,
  });
  final List<DoseLog> logs;
  final Map<String, Medicine> medicines;
  final void Function(DoseLog log, Medicine medicine) onEdit;

  @override
  Widget build(BuildContext context) {
    final groups = <DateTime, List<DoseLog>>{};
    for (final l in logs) {
      final t = DateTime.fromMillisecondsSinceEpoch(l.scheduledTime);
      groups.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(l);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final stats = adherence(logs);
    final pct = stats.total == 0
        ? 0
        : (stats.taken * 100 / stats.total).round();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "You've taken ${stats.taken} of ${stats.total} doses in this "
              'period ($pct%)',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        const InlineAdCard(),
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(
              DateFormat('EEEE, d MMMM').format(day),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final l in groups[day]!)
            DoseLogTile(
              log: l,
              medicine: medicines[l.medicineId],
              showName: true,
              onTap: medicines[l.medicineId] == null
                  ? null
                  : () => onEdit(l, medicines[l.medicineId]!),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Renders the history table + adherence summary as a PDF document.
/// [details] are extra header lines (e.g. which prescription it covers).
Future<Uint8List> buildHistoryPdf(
  List<DoseLog> logs,
  Map<String, Medicine> medicines,
  String periodLabel, {
  String heading = 'PillTrack — dose history',
  List<String> details = const [],
}) async {
  final stats = adherence(logs);
  final pct = stats.total == 0 ? 0 : (stats.taken * 100 / stats.total).round();
  final dateFmt = DateFormat('yyyy-MM-dd');
  final timeFmt = DateFormat('HH:mm');

  final rows = [
    for (final l in logs)
      () {
        final m = medicines[l.medicineId];
        final t = DateTime.fromMillisecondsSinceEpoch(
          l.actionTime ?? l.scheduledTime,
        );
        final dose = l.isTaken
            ? (m?.form == 'cream'
                  ? 'Applied'
                  : (m?.doseText(l.doseAmount) ??
                        formatDose(l.doseAmount, 'pcs')))
            : '-';
        return [
          dateFmt.format(t),
          timeFmt.format(t),
          m?.name ?? 'Deleted medicine',
          dose,
          l.status[0].toUpperCase() + l.status.substring(1),
        ];
      }(),
  ];

  final doc = pw.Document(title: 'PillTrack history');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Header(level: 0, text: heading),
        for (final line in details) pw.Text(line),
        pw.Text('Period: $periodLabel'),
        pw.Text('Taken ${stats.taken} of ${stats.total} doses ($pct%)'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const ['Date', 'Time', 'Medicine', 'Dose', 'Status'],
          data: rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
        ),
      ],
    ),
  );
  return doc.save();
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, size: 80, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'No doses logged in this period',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Doses you take or skip will show up here. Try a longer period.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
