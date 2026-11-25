import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/dose_formatter.dart';
import '../../../core/utils/guarded.dart';
import '../../../core/utils/prescription_parser.dart';
import '../../medicines/screens/edit_medicine_screen.dart';
import '../providers/prescription_providers.dart';
import '../widgets/prescription_photos.dart';

/// Reads a prescription photo on the device and suggests its medicines.
/// Nothing is saved from the scan itself: each suggestion opens the normal
/// Add medicine form, filled in, for the user to check and save.
class ScanPrescriptionScreen extends ConsumerStatefulWidget {
  const ScanPrescriptionScreen({super.key, required this.prescriptionId});

  final String prescriptionId;

  @override
  ConsumerState<ScanPrescriptionScreen> createState() =>
      _ScanPrescriptionScreenState();
}

class _ScanPrescriptionScreenState
    extends ConsumerState<ScanPrescriptionScreen> {
  bool _scanning = false;

  /// Text rows read from the photo; null until a photo has been scanned.
  List<String>? _rows;
  List<ScannedMedicine> _found = const [];

  /// Suggestions the user has saved as medicines.
  final Set<int> _added = {};

  Future<void> _scan(List<String> paths) async {
    final messenger = ScaffoldMessenger.of(context);
    final scanner = ref.read(textScanServiceProvider);
    setState(() => _scanning = true);
    try {
      final rows = <String>[];
      for (final path in paths) {
        rows.addAll(await scanner.readRows(path));
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _found = parsePrescriptionText(rows);
        _added.clear();
      });
    } catch (e, st) {
      AppLogger.error('Prescription scan failed', e, st);
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't read the photo. Try a clearer photo."),
        ),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// A new photo is kept with the prescription as well as scanned.
  Future<void> _scanNew(List<String> paths) async {
    await guarded(
      ScaffoldMessenger.of(context),
      "Couldn't save the photo to the prescription.",
      () => ref
          .read(prescriptionActionsProvider)
          .addPhotos(widget.prescriptionId, paths),
    );
    await _scan(paths);
  }

  Future<void> _add(int index) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditMedicineScreen(
          prescriptionId: widget.prescriptionId,
          scanned: _found[index],
        ),
      ),
    );
    if (saved == true && mounted) setState(() => _added.add(index));
  }

  Future<void> _addManually() => Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => EditMedicineScreen(prescriptionId: widget.prescriptionId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan for medicines')),
      body: _scanning
          ? const _Reading()
          : _rows == null
          ? _PhotoChoice(
              prescriptionId: widget.prescriptionId,
              onExisting: (path) => _scan([path]),
              onNew: _scanNew,
            )
          : _results(context),
    );
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    final again = TextButton.icon(
      icon: const Icon(Icons.refresh),
      label: const Text('Scan another photo'),
      onPressed: () => setState(() => _rows = null),
    );
    final manual = OutlinedButton.icon(
      icon: const Icon(Icons.add),
      label: Text(
        _found.isEmpty
            ? 'Add a medicine yourself'
            : 'Missing one? Add it yourself',
      ),
      onPressed: _addManually,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (_found.isEmpty) ...[
          const SizedBox(height: 24),
          Icon(Icons.search_off, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'No medicines found',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Handwriting and blurry photos are hard to read. Try a sharper '
            'photo in good light, or add the medicines yourself.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
        ] else ...[
          Text(
            _found.length == 1
                ? 'Found 1 medicine'
                : 'Found ${_found.length} medicines',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap Add to check the details and save each one. Only add '
            'medicines that match your prescription.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _found.length; i++)
            _SuggestionCard(
              medicine: _found[i],
              added: _added.contains(i),
              onAdd: () => _add(i),
            ),
          const SizedBox(height: 16),
        ],
        manual,
        const SizedBox(height: 8),
        again,
        if (_rows!.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Text read from the photo'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(_rows!.join('\n')),
              ),
            ],
          ),
      ],
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Reading the prescription…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

/// Pick which photo to read: one already saved with the prescription, or a
/// new one from the camera or gallery.
class _PhotoChoice extends ConsumerWidget {
  const _PhotoChoice({
    required this.prescriptionId,
    required this.onExisting,
    required this.onNew,
  });

  final String prescriptionId;
  final ValueChanged<String> onExisting;
  final ValueChanged<List<String>> onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final photos =
        ref.watch(prescriptionPhotosProvider(prescriptionId)).asData?.value ??
        const [];
    final dir = ref.watch(photoDirectoryProvider).asData?.value;
    final heading = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'PillTrack reads the photo on your phone and suggests the medicines '
          'it finds. You check each one before it is added.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('For the best result'),
            subtitle: const Text(
              'Lay the paper flat in good light and fill the photo with it. '
              'Printed prescriptions read best; handwriting often can’t be '
              'read.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (photos.isNotEmpty && dir != null) ...[
          Text('Scan a saved photo', style: heading),
          const SizedBox(height: 8),
          SizedBox(
            height: PhotoThumbnail.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final path = p.join(dir.path, photos[i].fileName);
                return PhotoThumbnail(
                  file: File(path),
                  label: 'Scan prescription photo ${i + 1} of ${photos.length}',
                  onTap: () => onExisting(path),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text('Or a new photo', style: heading),
        ] else
          Text('Take or choose a photo', style: heading),
        const SizedBox(height: 8),
        PhotoSourceButtons(onPicked: onNew),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.medicine,
    required this.added,
    required this.onAdd,
  });

  final ScannedMedicine medicine;
  final bool added;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = scanSummary(medicine);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicine.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (summary.isNotEmpty)
                    Text(summary, style: theme.textTheme.bodyMedium),
                  Text(
                    '“${medicine.sourceText.replaceAll('\n', ' ')}”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (added)
              Chip(
                avatar: Icon(Icons.check, color: theme.colorScheme.primary),
                label: const Text('Added'),
              )
            else
              FilledButton.tonal(onPressed: onAdd, child: const Text('Add')),
          ],
        ),
      ),
    );
  }
}

/// "Tablet · 500mg · 1+0+1 · 7 days · After meals".
String scanSummary(ScannedMedicine m) {
  final parts = m.doseParts;
  final amount = m.amount;
  final unit = m.amountUnit;
  final hours = m.everyHours;
  return [
    if (m.form != null) formLabel(m.form!),
    if (m.strength != null) m.strength!,
    if (parts != null) parts.map(formatAmount).join('+'),
    if (parts == null && amount != null && unit != null)
      formatDose(amount, unit, form: m.form),
    if (m.asNeeded)
      'As needed'
    else if (parts == null && hours != null)
      'Every $hours hours'
    else if (parts == null && m.timesPerDay != null)
      switch (m.timesPerDay!) {
        1 => 'Once a day',
        2 => 'Twice a day',
        final n => '$n times a day',
      },
    if (m.courseDays != null)
      m.courseDays == 1 ? '1 day' : '${m.courseDays} days'
    else if (m.ongoing)
      'Continue',
    if (m.instructions != null) m.instructions!,
  ].join(' · ');
}
