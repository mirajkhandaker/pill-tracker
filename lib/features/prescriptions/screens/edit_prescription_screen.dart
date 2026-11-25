import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/guarded.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/prescription.dart';
import '../providers/prescription_providers.dart';
import '../widgets/prescription_photos.dart';
import 'prescription_detail_screen.dart';

const _uuid = Uuid();

/// Create a prescription (when [prescription] is null) or edit its details.
///
/// A new prescription can replace an existing one — the usual case after a
/// follow-up visit: the user ticks which medicines continue, the rest stop,
/// and the old prescription moves to "Past" with its history intact.
class EditPrescriptionScreen extends ConsumerStatefulWidget {
  const EditPrescriptionScreen({super.key, this.prescription, this.replacesId});

  final Prescription? prescription;

  /// Pre-selects the prescription being replaced (from its detail page).
  final String? replacesId;

  @override
  ConsumerState<EditPrescriptionScreen> createState() =>
      _EditPrescriptionScreenState();
}

class _EditPrescriptionScreenState
    extends ConsumerState<EditPrescriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _doctor;
  late final TextEditingController _reason;
  late final TextEditingController _notes;
  late DateTime _issued;

  String? _replaces;

  /// Medicines (of [_replaces]) the user is continuing.
  final Set<String> _keep = {};

  /// Which prescription [_keep] was initialised for (all ticked by default).
  String? _keepInitFor;

  /// Photos picked for a new prescription; copied into storage on save.
  final List<String> _photoPaths = [];
  bool _saving = false;

  bool get _isEdit => widget.prescription != null;

  @override
  void initState() {
    super.initState();
    final p = widget.prescription;
    _doctor = TextEditingController(text: p?.doctorName ?? '');
    _reason = TextEditingController(text: p?.reason ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    final now = DateTime.now();
    _issued = p?.issuedDate ?? DateTime(now.year, now.month, now.day);
    _replaces = widget.replacesId;
  }

  @override
  void dispose() {
    _doctor.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  static String? _orNull(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final actions = ref.read(prescriptionActionsProvider);
    final existing = widget.prescription;

    final prescription = Prescription(
      id: existing?.id ?? _uuid.v4(),
      doctorName: _doctor.text.trim(),
      reason: _orNull(_reason.text),
      notes: _orNull(_notes.text),
      issuedAt: _issued.millisecondsSinceEpoch,
      status: existing?.status ?? Prescription.statusActive,
      endedAt: existing?.endedAt,
      createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );

    final ok = await guarded(
      messenger,
      "Couldn't save the prescription. Please try again.",
      () => _isEdit
          ? actions.update(prescription)
          : actions.create(
              prescription,
              replaces: _replaces,
              continueMedicineIds: _replaces == null ? const {} : _keep,
              photoPaths: _photoPaths,
            ),
    );
    if (!ok) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    if (_isEdit) {
      navigator.pop();
    } else {
      // Straight to the new prescription so its medicines can be added.
      await navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              PrescriptionDetailScreen(prescriptionId: prescription.id),
        ),
      );
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _replaces != null && !_isEdit
              ? 'New prescription saved. The old one is in Past.'
              : 'Prescription saved',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit prescription' : 'New prescription'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _doctor,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: "Doctor's name *",
                hintText: 'e.g. Dr. Rahman',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? "Enter the doctor's name"
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What is it for? (optional)',
                hintText: 'e.g. Blood pressure',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('Date: ${DateFormat('d MMM yyyy').format(_issued)}'),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _issued,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(now.year, now.month, now.day),
                  helpText: 'Date on the prescription',
                );
                if (picked != null) setState(() => _issued = picked);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. Follow-up in 3 months',
              ),
            ),
            if (!_isEdit) ..._photoSection(),
            if (!_isEdit) ..._replaceSection(),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _photoSection() {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 20),
      Text(
        'Photo of the prescription (optional)',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      if (_photoPaths.isNotEmpty) ...[
        SizedBox(
          height: PhotoThumbnail.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photoPaths.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => PhotoThumbnail(
              file: File(_photoPaths[i]),
              label: 'Photo ${i + 1} of ${_photoPaths.length}',
              onRemove: () => setState(() => _photoPaths.removeAt(i)),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
      PhotoSourceButtons(
        onPicked: (paths) => setState(() => _photoPaths.addAll(paths)),
      ),
    ];
  }

  List<Widget> _replaceSection() {
    final active =
        ref.watch(activePrescriptionsProvider).asData?.value ??
        const <Prescription>[];
    if (active.isEmpty) return const [];
    final theme = Theme.of(context);
    final replacing = active.any((p) => p.id == _replaces) ? _replaces : null;

    return [
      const SizedBox(height: 24),
      Text(
        'Does this replace an earlier prescription?',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(
        key: ValueKey('replaces-${active.length}-$replacing'),
        initialValue: replacing,
        isExpanded: true,
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text("No — it's an additional prescription"),
          ),
          for (final p in active)
            DropdownMenuItem<String?>(
              value: p.id,
              child: Text(
                'Yes — replaces ${p.shortTitle} (${p.label})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) => setState(() => _replaces = v),
      ),
      if (replacing != null) ..._carryOver(replacing),
    ];
  }

  List<Widget> _carryOver(String replacesId) {
    final theme = Theme.of(context);
    final medicines = ref.watch(prescriptionMedicinesProvider(replacesId));
    return medicines.when(
      loading: () => [const LinearProgressIndicator()],
      error: (e, _) => [const Text('Could not load its medicines')],
      data: (all) {
        final current = all.where((m) => m.isActive).toList();
        if (_keepInitFor != replacesId) {
          // Default: keep everything; the user unticks what the doctor stopped.
          _keepInitFor = replacesId;
          _keep
            ..clear()
            ..addAll(current.map((m) => m.id));
        }
        return [
          const SizedBox(height: 12),
          Text(
            current.isEmpty
                ? 'That prescription has no current medicines.'
                : 'Which medicines are you still taking? Unticked ones will '
                      'stop. The old prescription is kept in your history.',
            style: theme.textTheme.bodyMedium,
          ),
          for (final Medicine m in current)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _keep.contains(m.id),
              title: Text(m.name),
              subtitle: Text(_keep.contains(m.id) ? 'Keep taking' : 'Stop'),
              onChanged: (on) => setState(
                () => on == true ? _keep.add(m.id) : _keep.remove(m.id),
              ),
            ),
          if (current.isNotEmpty)
            Text(
              'You can add new medicines on the next screen.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ];
      },
    );
  }
}
