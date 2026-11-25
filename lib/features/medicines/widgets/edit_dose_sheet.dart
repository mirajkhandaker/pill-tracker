import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/dose_formatter.dart';
import '../../../core/utils/guarded.dart';
import '../../../data/models/dose_log.dart';
import '../../../data/models/medicine.dart';
import '../providers/medicine_providers.dart';
import 'dose_feedback.dart';

/// Opens the sheet for correcting a logged dose: Taken/Skipped, the amount
/// taken, the time taken, or removing the entry. Resolves to true when the
/// log was changed or removed.
Future<bool> showEditDoseSheet(
  BuildContext context, {
  required DoseLog log,
  required Medicine medicine,
}) => _open(context, log: log, medicine: medicine, isNew: false);

/// Opens the same sheet to log a scheduled dose that hasn't been logged yet,
/// with details the user chooses — e.g. taken at a different time or amount
/// than scheduled, or skipped. Resolves to true when a dose was logged.
Future<bool> showLogDoseSheet(BuildContext context, {required TodayDose dose}) {
  final now = DateTime.now();
  final scheduled = dose.schedule.doseAmount;
  return _open(
    context,
    medicine: dose.medicine,
    isNew: true,
    log: DoseLog(
      id: const Uuid().v4(),
      medicineId: dose.medicine.id,
      scheduleId: dose.schedule.id,
      scheduledTime: dose.time.millisecondsSinceEpoch,
      actionTime: now.millisecondsSinceEpoch,
      doseAmount: scheduled > 0 ? scheduled : 1,
      status: DoseLog.statusTaken,
    ),
  );
}

Future<bool> _open(
  BuildContext context, {
  required DoseLog log,
  required Medicine medicine,
  required bool isNew,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EditDoseSheet(log: log, medicine: medicine, isNew: isNew),
  );
  return changed ?? false;
}

class _EditDoseSheet extends ConsumerStatefulWidget {
  const _EditDoseSheet({
    required this.log,
    required this.medicine,
    required this.isNew,
  });
  final DoseLog log;
  final Medicine medicine;

  /// True when logging a dose for the first time rather than correcting one.
  final bool isNew;

  @override
  ConsumerState<_EditDoseSheet> createState() => _EditDoseSheetState();
}

class _EditDoseSheetState extends ConsumerState<_EditDoseSheet> {
  late String _status;
  late final TextEditingController _amount;
  late DateTime _time;
  String? _error;
  bool _busy = false;

  DoseLog get _log => widget.log;
  Medicine get _medicine => widget.medicine;

  /// As-needed logs have no "skipped" — they only exist because one was taken.
  bool get _isPrn => _log.scheduleId == null;
  bool get _countable => _medicine.form != 'cream';
  bool get _taken => _status == DoseLog.statusTaken;
  bool get _isNew => widget.isNew;

  @override
  void initState() {
    super.initState();
    _status = _log.isTaken ? DoseLog.statusTaken : DoseLog.statusSkipped;
    // A skipped log stores 0; offer a sensible amount if they switch to taken.
    _amount = TextEditingController(
      text: formatAmount(_log.doseAmount > 0 ? _log.doseAmount : 1),
    );
    _time = DateTime.fromMillisecondsSinceEpoch(
      _log.actionTime ?? _log.scheduledTime,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
      helpText: 'When did you take it?',
    );
    if (picked == null) return;
    setState(() {
      _time = DateTime(
        _time.year,
        _time.month,
        _time.day,
        picked.hour,
        picked.minute,
      );
      _error = null;
    });
  }

  Future<void> _save() async {
    double amount = 0;
    if (_taken) {
      if (_countable) {
        final parsed = double.tryParse(_amount.text.trim());
        if (parsed == null || parsed <= 0) {
          setState(() => _error = 'Enter an amount greater than 0');
          return;
        }
        amount = parsed;
      } else {
        amount = _log.doseAmount > 0 ? _log.doseAmount : 1;
      }
      if (_time.isAfter(DateTime.now())) {
        setState(() => _error = "The time taken can't be in the future");
        return;
      }
    }

    final updated = _log.copyWith(
      status: _status,
      doseAmount: amount,
      actionTime: _taken ? _time.millisecondsSinceEpoch : _log.actionTime,
      // An as-needed dose is filed under when it was taken.
      scheduledTime: _isPrn ? _time.millisecondsSinceEpoch : _log.scheduledTime,
    );
    if (_isNew) return _record(updated);
    if (updated == _log) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await guarded(
      messenger,
      "Couldn't update that dose. Please try again.",
      () => ref.read(medicineActionsProvider).editDoseLog(_log, updated),
    );
    if (!ok) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    navigator.pop(true);
    messenger.showSnackBar(const SnackBar(content: Text('Dose updated')));
  }

  Future<void> _record(DoseLog log) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    DoseResult? result;
    final ok = await guarded(
      messenger,
      "Couldn't save that dose. Please try again.",
      () async =>
          result = await ref.read(medicineActionsProvider).recordDose(log),
    );
    if (!ok) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    navigator.pop(true);
    if (log.isTaken) {
      showDoseFeedback(messenger, result!, medicineName: _medicine.name);
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Marked as skipped')),
      );
    }
  }

  Future<void> _remove() async {
    final returnsStock = _medicine.trackInventory && _log.isTaken;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this entry?'),
        content: Text(
          [
            _isPrn
                ? 'This as-needed dose will be removed from your history.'
                : 'This dose will show as not yet taken or skipped.',
            if (returnsStock) 'The amount it used goes back to your supply.',
          ].join(' '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await guarded(
      messenger,
      "Couldn't remove that entry. Please try again.",
      () => ref.read(medicineActionsProvider).removeDoseLog(_log),
    );
    if (!ok) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    navigator.pop(true);
    messenger.showSnackBar(const SnackBar(content: Text('Entry removed')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = DateTime.fromMillisecondsSinceEpoch(_log.scheduledTime);
    final subtitle = _isPrn
        ? 'As-needed dose'
        : 'Due ${DateFormat('h:mm a · EEE d MMM').format(due)}';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isNew ? 'Log dose' : 'Edit dose',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_medicine.name} · $subtitle',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (!_isPrn) ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: DoseLog.statusTaken,
                    label: Text('Taken'),
                    icon: Icon(Icons.check_circle_outline),
                  ),
                  ButtonSegment(
                    value: DoseLog.statusSkipped,
                    label: Text('Skipped'),
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() {
                  _status = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
            ],
            if (_taken && _countable) ...[
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount taken',
                  suffixText: _medicine.unitLabelPlural,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
            ],
            if (_taken)
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(
                  'Taken at ${DateFormat('h:mm a').format(_time)}',
                  style: const TextStyle(fontSize: 18),
                ),
                onPressed: _pickTime,
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
            // Nothing to remove yet when logging for the first time.
            if (!_isNew) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove this entry'),
                onPressed: _busy ? null : _remove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
