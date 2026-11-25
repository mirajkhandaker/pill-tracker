import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/medication_types.dart';
import '../../../core/utils/dose_formatter.dart';
import '../../../core/utils/dose_frequency.dart';
import '../../../core/utils/prescription_parser.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/prescription.dart';
import '../../../data/models/schedule.dart';
import '../../prescriptions/providers/prescription_providers.dart';
import '../providers/medicine_providers.dart';

const _uuid = Uuid();

/// Display order of the weekday chips (Sun first) mapped to ISO weekday numbers.
const _weekdayOrder = [7, 1, 2, 3, 4, 5, 6];
const _weekdayLetters = {
  1: 'M',
  2: 'T',
  3: 'W',
  4: 'T',
  5: 'F',
  6: 'S',
  7: 'S',
};
const _weekdayNames = {
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

const _maxSlots = 6;

/// One weekday toggle. Letters alone are ambiguous (two T's, two S's), so the
/// full day name is exposed to screen readers.
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.letter,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        label: name,
        selected: selected,
        button: true,
        excludeSemantics: true,
        child: Material(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Editable state for one schedule row before it's saved.
class _SlotDraft {
  _SlotDraft({
    required this.time,
    required String amount,
    required this.inputUnit,
    Set<int>? days,
    this.isVariable = false,
    this.scheduleId,
  }) : amount = TextEditingController(text: amount),
       days = days ?? {1, 2, 3, 4, 5, 6, 7};

  TimeOfDay time;
  final TextEditingController amount;

  /// Id of the saved schedule this slot edits; null for a new time. Kept on
  /// save so doses already logged against it (matched by schedule id) stay
  /// logged — a fresh id would make today's taken doses look untaken.
  final String? scheduleId;

  /// Unit the amount is entered in. For liquids this may be tsp/tbsp; it's
  /// converted to ml on save.
  String inputUnit;
  Set<int> days;
  bool isVariable;

  /// Same dose settings as this slot, at [at]. A new time, so no schedule id.
  _SlotDraft copyAt(TimeOfDay at) => _SlotDraft(
    time: at,
    amount: amount.text,
    inputUnit: inputUnit,
    days: {...days},
    isVariable: isVariable,
  );

  /// Takes [other]'s dose settings (not its time).
  void copySettingsFrom(_SlotDraft other) {
    amount.text = other.amount.text;
    inputUnit = other.inputUnit;
    days = {...other.days};
    isVariable = other.isVariable;
  }

  bool sameSettingsAs(_SlotDraft o) =>
      amount.text.trim() == o.amount.text.trim() &&
      inputUnit == o.inputUnit &&
      isVariable == o.isVariable &&
      days.length == o.days.length &&
      days.containsAll(o.days);

  void dispose() => amount.dispose();
}

/// Add (when [medicine] is null) or edit a medicine and its schedule.
class EditMedicineScreen extends ConsumerStatefulWidget {
  const EditMedicineScreen({
    super.key,
    this.medicine,
    this.schedules,
    this.prescriptionId,
    this.scanned,
  });

  final Medicine? medicine;
  final List<Schedule>? schedules;

  /// Prescription to pre-select when adding from a prescription's page.
  final String? prescriptionId;

  /// A medicine read from a prescription photo, used to fill in a new
  /// medicine (ignored when editing).
  final ScannedMedicine? scanned;

  @override
  ConsumerState<EditMedicineScreen> createState() => _EditMedicineScreenState();
}

class _EditMedicineScreenState extends ConsumerState<EditMedicineScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _dosageText;
  late final TextEditingController _notes;

  /// "How many do you have now?" — the one required supply question.
  late final TextEditingController _stockNow;

  /// Optional pack size (units per strip/bottle/…), used for whole-pack refills.
  late final TextEditingController _packSize;

  late String _form;
  late String _packageType;

  /// For non-liquids: the stored dose unit. For liquids: the default *input*
  /// unit for new rows (storage is always ml).
  late String _doseUnit;
  late double _refillDays;
  late bool _isPrn;

  /// User's choice to count down their supply. Off by default for new
  /// medicines — tracking is opt-in.
  late bool _trackSupply;

  String? _prescriptionId;

  /// Last day of a fixed course; null = continue (no end date).
  DateTime? _endDay;

  /// How the daily times are chosen (see [DoseFrequency]).
  late DoseFrequency _frequency;
  int _intervalHours = 8;

  final List<_SlotDraft> _slots = [];

  bool _saving = false;

  bool get _isEdit => widget.medicine != null;
  ScannedMedicine? get _scan => _isEdit ? null : widget.scanned;
  bool get _isLiquid => _form == 'liquid';

  /// Whether doses of this form can be counted. Creams/ointments can't, so
  /// they have no dose amount, unit, or supply tracking.
  bool get _countable => _form != 'cream';
  bool get _tracksSupply => _countable && _trackSupply;
  String get _storageUnit => _isLiquid ? 'ml' : _doseUnit;

  List<String> get _unitOptions {
    final units = unitsForForm(_form);
    if (!_isLiquid && !units.contains(_doseUnit) && _countable) {
      return [...units, _doseUnit];
    }
    return units;
  }

  /// Packages that make sense for the current form. A medicine saved earlier
  /// with an unusual package keeps it as an option, so it stays visible (and
  /// fixable) instead of breaking the dropdown.
  List<String> get _packageOptions {
    final options = packagesForForm(_form);
    return options.contains(_packageType)
        ? options
        : [...options, _packageType];
  }

  @override
  void initState() {
    super.initState();
    final m = widget.medicine;
    _name = TextEditingController(text: m?.name ?? '');
    _dosageText = TextEditingController(text: m?.dosageText ?? '');
    _notes = TextEditingController(text: m?.notes ?? '');
    _form = m?.form ?? 'tablet';
    _packageType = m?.packageType ?? _defaultPackage(_form);
    _doseUnit = m?.doseUnit ?? _defaultUnit(_form);
    // Only show real numbers: a medicine whose supply was never tracked has
    // nothing meaningful stored, so its fields start empty.
    final tracked = m != null && m.trackInventory;
    _stockNow = TextEditingController(
      text: tracked ? formatAmount(m.totalUnitsRemaining) : '',
    );
    _packSize = TextEditingController(
      text: tracked && m.hasPackSize ? formatAmount(m.unitsPerPackage) : '',
    );
    _refillDays = (m?.refillThresholdDays ?? 3).toDouble().clamp(1, 14);
    _isPrn = m?.isPrn ?? false;
    _trackSupply = m?.trackInventory ?? false;
    _prescriptionId = m?.prescriptionId ?? widget.prescriptionId;
    _endDay = m?.endDay;

    final scan = _scan;
    if (scan != null) _applyScan(scan);

    final existing = widget.schedules ?? const <Schedule>[];
    if (scan != null) {
      for (final s in scan.dailySlots()) {
        _slots.add(
          _SlotDraft(
            time: TimeOfDay(hour: s.hour, minute: s.minute),
            amount: s.amount == null ? '' : formatAmount(s.amount!),
            inputUnit: _doseUnit,
          ),
        );
      }
      if (_slots.isEmpty) {
        // How often wasn't readable: the usual default, with any amount read.
        final amount = scan.amount;
        _slots.add(
          _newSlot()
            ..amount.text = amount != null
                ? formatAmount(amount)
                : scan.effectiveUnit == null
                ? ''
                : '1',
        );
      }
    } else if (existing.isNotEmpty) {
      for (final s in existing) {
        _slots.add(
          _SlotDraft(
            time: TimeOfDay(hour: s.hour, minute: s.minute),
            amount: formatAmount(s.doseAmount),
            // Stored amounts are in the base unit (ml for liquids).
            inputUnit: _storageUnit,
            days: s.days.toSet(),
            isVariable: s.isVariableDose,
            scheduleId: s.id,
          ),
        );
      }
    } else {
      _slots.add(_newSlot());
    }

    // Show the same "how often" the user picked. Slots with different
    // amounts/days only fit Custom, so their differences are never flattened.
    final inferred = inferFrequency([for (final s in _slots) s.time]);
    final uniform = _slots.every((s) => s.sameSettingsAs(_slots.first));
    _frequency = uniform ? inferred.frequency : DoseFrequency.custom;
    _intervalHours = inferred.intervalHours;
  }

  /// Fills the basic fields of a new medicine from a prescription scan.
  void _applyScan(ScannedMedicine scan) {
    _name.text = scan.name;
    _dosageText.text = scan.strength ?? '';
    _notes.text = scan.instructions ?? '';
    final form = scan.form;
    if (form != null && medicationForms.containsKey(form)) {
      _form = form;
      _packageType = _defaultPackage(form);
      _doseUnit = _defaultUnit(form);
    }
    final unit = scan.effectiveUnit;
    if (unit != null && unitsForForm(_form).contains(unit)) _doseUnit = unit;
    _isPrn = scan.asNeeded;
    final days = scan.courseDays;
    if (days != null) {
      final now = DateTime.now();
      _endDay = DateTime(now.year, now.month, now.day + days - 1);
    }
  }

  /// Rebuilds the slots for [times], keeping the first slot's dose settings.
  void _applyTimes(List<TimeOfDay> times) {
    final template = _slots.first;
    final next = <_SlotDraft>[
      for (var i = 0; i < times.length; i++)
        i < _slots.length
            ? (_slots[i]
                ..time = times[i]
                ..copySettingsFrom(template))
            : template.copyAt(times[i]),
    ];
    for (final extra in _slots.skip(times.length)) {
      extra.dispose();
    }
    _slots
      ..clear()
      ..addAll(next);
  }

  void _setFrequency(DoseFrequency f) {
    setState(() {
      _frequency = f;
      switch (f) {
        case DoseFrequency.once:
        case DoseFrequency.twice:
        case DoseFrequency.thrice:
          _applyTimes(presetTimes(f));
        case DoseFrequency.interval:
          _applyTimes(intervalTimes(_slots.first.time, _intervalHours));
        case DoseFrequency.custom:
          // Start from the shared settings; each time can now differ.
          for (final s in _slots.skip(1)) {
            s.copySettingsFrom(_slots.first);
          }
      }
    });
  }

  void _setInterval({int? hours, TimeOfDay? first}) {
    setState(() {
      _intervalHours = hours ?? _intervalHours;
      _applyTimes(intervalTimes(first ?? _slots.first.time, _intervalHours));
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _dosageText, _notes, _stockNow, _packSize]) {
      c.dispose();
    }
    for (final s in _slots) {
      s.dispose();
    }
    super.dispose();
  }

  static String _defaultPackage(String form) => packagesForForm(form).first;

  static String _defaultUnit(String form) {
    final units = unitsForForm(form);
    return units.isEmpty ? 'pcs' : units.first;
  }

  _SlotDraft _newSlot() => _SlotDraft(
    time: const TimeOfDay(hour: 8, minute: 0),
    amount: '1',
    inputUnit: _doseUnit,
  );

  void _onFormChanged(String form) {
    setState(() {
      _form = form;
      _packageType = _defaultPackage(form);
      _doseUnit = _defaultUnit(form);
      for (final s in _slots) {
        s.inputUnit = _doseUnit;
      }
    });
  }

  /// "Tablets", "Capsules", "Pieces", "ml", "IU", "Puffs"...
  String get _unitNounPlural => unitLabel(2, _storageUnit, form: _form);

  String get _packSizeLabel =>
      '$_unitNounPlural per ${packageLabel(_packageType)}';

  /// Counted units read "How many…"; measures (ml, IU, mg) read "How much…".
  String get _stockQuestion =>
      const {'pcs', 'puff', 'drop'}.contains(_storageUnit)
      ? 'How many $_unitNounPlural do you have now?'
      : 'How much do you have now?';

  // --- Save -----------------------------------------------------------------

  String? _validateSlots() {
    if (_isPrn) return null;
    if (_slots.isEmpty) return 'Add at least one time';
    for (final s in _slots) {
      if (s.days.isEmpty) return 'Each time needs at least one day selected';
      if (!_countable) continue;
      final amount = double.tryParse(s.amount.text.trim());
      if (!s.isVariable && (amount == null || amount <= 0)) {
        return 'Enter a dose amount for every time';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final slotError = _validateSlots();
    if (slotError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(slotError)));
      return;
    }

    if (_frequency != DoseFrequency.custom) {
      for (final s in _slots.skip(1)) {
        s.copySettingsFrom(_slots.first);
      }
    }

    setState(() => _saving = true);
    final existing = widget.medicine;
    final id = existing?.id ?? _uuid.v4();

    final medicine = Medicine(
      id: id,
      name: _name.text.trim(),
      dosageText: _emptyToNull(_dosageText.text),
      notes: _emptyToNull(_notes.text),
      form: _form,
      packageType: _packageType,
      doseUnit: _countable ? _storageUnit : 'pcs',
      // Tracked: the stock is the single number the user gave (kept as loose
      // units), and the pack size is optional (0 = not given). Untracked:
      // whatever was stored before is left untouched.
      unitsPerPackage: _tracksSupply
          ? _positiveOr(_packSize.text, 0)
          : existing?.unitsPerPackage ?? 0,
      packagesInHand: _tracksSupply ? 0 : existing?.packagesInHand ?? 0,
      looseUnits: _tracksSupply
          ? double.tryParse(_stockNow.text.trim()) ?? 0
          : existing?.looseUnits ?? 0,
      trackInventory: _tracksSupply,
      isPrn: _isPrn,
      refillThresholdDays: _refillDays.round(),
      // Never reactivate a stopped medicine just by editing it.
      isActive: existing?.isActive ?? true,
      createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      prescriptionId: _prescriptionId,
      endDate: _endDay?.millisecondsSinceEpoch,
    );

    final schedules = _isPrn
        ? const <Schedule>[]
        : [
            for (final s in _slots)
              Schedule(
                id: s.scheduleId ?? _uuid.v4(),
                medicineId: id,
                timeOfDay: _hhmm(s.time),
                doseAmount: _countable
                    ? medicine.doseAmountInBaseUnit(
                        double.tryParse(s.amount.text.trim()) ?? 0,
                        s.inputUnit,
                      )
                    : 1,
                isVariableDose: _countable && s.isVariable,
                daysOfWeek: (s.days.toList()..sort()).join(','),
              ),
          ];

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(medicineActionsProvider).saveMedicine(medicine, schedules);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
      return;
    }

    navigator.pop(true);
    messenger.showSnackBar(const SnackBar(content: Text(AppStrings.saved)));
  }

  static String? _emptyToNull(String s) => s.trim().isEmpty ? null : s.trim();

  static double _positiveOr(String text, double fallback) {
    final n = double.tryParse(text.trim());
    return (n == null || n <= 0) ? fallback : n;
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit medicine' : AppStrings.addMedicine),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_scan != null) const _ScanNotice(),
            _section(AppStrings.basicInfo),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: '${AppStrings.name} *',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            _gap,
            TextFormField(
              controller: _dosageText,
              decoration: const InputDecoration(
                labelText: AppStrings.dosageText,
              ),
            ),
            _gap,
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: AppStrings.notes),
            ),
            _gap,
            DropdownButtonFormField<String>(
              initialValue: _form,
              decoration: const InputDecoration(
                labelText: '${AppStrings.form} *',
              ),
              items: [
                for (final e in medicationForms.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => v == null ? null : _onFormChanged(v),
            ),
            if (_countable) ..._doseUnitField(),
            ..._prescriptionSection(),
            ..._scheduleSection(),
            if (_countable) ..._supplySection(),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(AppStrings.save),
            ),
          ],
        ),
      ),
    );
  }

  /// Unit doses are entered in — needed for reminders whether or not the
  /// supply is tracked.
  List<Widget> _doseUnitField() => [
    _gap,
    DropdownButtonFormField<String>(
      key: ValueKey('unit-$_form'),
      initialValue: _doseUnit,
      decoration: const InputDecoration(labelText: AppStrings.doseUnit),
      items: [
        for (final u in _unitOptions)
          DropdownMenuItem(
            value: u,
            child: Text(unitLabel(2, u, form: _form)),
          ),
      ],
      onChanged: (v) => setState(() {
        _doseUnit = v ?? _doseUnit;
        for (final s in _slots) {
          s.inputUnit = _isLiquid ? _doseUnit : _storageUnit;
        }
      }),
    ),
    if (_isLiquid && _doseUnit != 'ml')
      const Padding(
        padding: EdgeInsets.only(top: 6, left: 4),
        child: Text(AppStrings.storedAsMl),
      ),
  ];

  List<Widget> _supplySection() => [
    _section('Supply tracking'),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Track my supply'),
      subtitle: const Text(
        'Count down what you have and warn me before I run out',
      ),
      value: _trackSupply,
      onChanged: (v) => setState(() => _trackSupply = v),
    ),
    if (_trackSupply) ..._supplyFields(),
  ];

  List<Widget> _supplyFields() => [
    _gap,
    TextFormField(
      controller: _stockNow,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_decimalOnly],
      decoration: InputDecoration(
        labelText: '$_stockQuestion *',
        suffixText: _unitNounPlural,
        hintText: 'e.g. 30',
      ),
      validator: (v) {
        final n = double.tryParse(v?.trim() ?? '');
        return (n == null || n < 0)
            ? 'Enter how many you have (0 if none)'
            : null;
      },
    ),
    _gap,
    Text(
      'Warn me when I have less than ${_refillDays.round()} '
      '${_refillDays.round() == 1 ? 'day' : 'days'} left',
      style: Theme.of(context).textTheme.bodyLarge,
    ),
    Slider(
      value: _refillDays,
      min: 1,
      max: 14,
      divisions: 13,
      label: '${_refillDays.round()}',
      onChanged: (v) => setState(() => _refillDays = v),
    ),
    // Packs are optional detail: they only make refilling quicker.
    Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        initiallyExpanded: _packSize.text.isNotEmpty,
        title: const Text('Pack size (optional)'),
        subtitle: Text(
          'Refill a whole ${packageLabel(_packageType).toLowerCase()} '
          'at a time',
        ),
        children: [
          // Only ask when there's a real choice; otherwise the label names it.
          if (_packageOptions.length > 1) ...[
            DropdownButtonFormField<String>(
              // Key on form so the field resets when the form changes.
              key: ValueKey('pkg-$_form'),
              initialValue: _packageType,
              decoration: const InputDecoration(
                labelText: AppStrings.packageType,
              ),
              items: [
                for (final p in _packageOptions)
                  DropdownMenuItem(value: p, child: Text(packageLabel(p))),
              ],
              onChanged: (v) =>
                  setState(() => _packageType = v ?? _packageType),
            ),
            _gap,
          ],
          TextFormField(
            controller: _packSize,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_decimalOnly],
            decoration: InputDecoration(
              labelText: _packSizeLabel,
              hintText: 'e.g. 10',
            ),
            validator: (v) {
              final text = v?.trim() ?? '';
              if (text.isEmpty) return null; // optional
              final n = double.tryParse(text);
              return (n == null || n <= 0)
                  ? 'Enter a number greater than 0'
                  : null;
            },
          ),
        ],
      ),
    ),
  ];

  /// Last day of a course of [days] days that starts today (day 1 = today).
  static DateTime _courseEnd(int days) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day + days - 1);
  }

  static const _courseLengths = [3, 5, 7, 10, 14, 30];

  List<Widget> _prescriptionSection() {
    final active =
        ref.watch(activePrescriptionsProvider).asData?.value ??
        const <Prescription>[];
    // Keep the current link selectable even if that prescription has ended.
    final linkedId = _prescriptionId;
    final linked = linkedId == null
        ? null
        : ref.watch(prescriptionByIdProvider(linkedId)).asData?.value;
    final options = [
      ...active,
      if (linked != null && !active.any((p) => p.id == linked.id)) linked,
    ];
    final selected = options.any((p) => p.id == linkedId) ? linkedId : null;
    final theme = Theme.of(context);

    return [
      _section('Prescription & duration'),
      if (options.isNotEmpty)
        DropdownButtonFormField<String?>(
          // Rebuild once prescriptions finish loading.
          key: ValueKey('rx-${options.length}-$selected'),
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Prescription'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Not on a prescription'),
            ),
            for (final p in options)
              DropdownMenuItem<String?>(
                value: p.id,
                child: Text(
                  p.reason == null ? p.label : '${p.reason} · ${p.label}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _prescriptionId = v),
        )
      else
        Text(
          'Not linked to a prescription. Add prescriptions from the '
          'Prescriptions page to group medicines by doctor visit.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      _gap,
      Text('How long?', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            label: Text('Continue'),
            icon: Icon(Icons.all_inclusive),
          ),
          ButtonSegment(
            value: true,
            label: Text('Fixed course'),
            icon: Icon(Icons.event_available),
          ),
        ],
        selected: {_endDay != null},
        onSelectionChanged: (s) =>
            setState(() => _endDay = s.first ? _courseEnd(7) : null),
      ),
      const SizedBox(height: 6),
      Text(
        _endDay == null
            ? 'Keep taking it until you or your doctor stop it.'
            : 'For a set number of days — reminders stop after the last day.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      if (_endDay != null) ...[
        _gap,
        Text('Starting today, for:', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in _courseLengths)
              ChoiceChip(
                label: Text('$n days'),
                selected: _endDay == _courseEnd(n),
                onSelected: (_) => setState(() => _endDay = _courseEnd(n)),
              ),
          ],
        ),
        _gap,
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(
            'Last day: ${DateFormat('EEE d MMM yyyy').format(_endDay!)}',
          ),
          onPressed: () async {
            final today = _courseEnd(1);
            final current = _endDay!;
            final picked = await showDatePicker(
              context: context,
              initialDate: current,
              firstDate: current.isBefore(today) ? current : today,
              lastDate: DateTime(today.year + 2, today.month, today.day),
              helpText: 'Last day of the course',
            );
            if (picked != null) setState(() => _endDay = picked);
          },
        ),
      ],
    ];
  }

  List<Widget> _scheduleSection() {
    final theme = Theme.of(context);
    final custom = _frequency == DoseFrequency.custom;
    return [
      _section(AppStrings.schedule),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(AppStrings.takeAsNeeded),
        value: _isPrn,
        onChanged: (v) => setState(() => _isPrn = v),
      ),
      if (!_isPrn) ...[
        Text('How often?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in DoseFrequency.values)
              ChoiceChip(
                label: Text(f.label),
                selected: _frequency == f,
                onSelected: (_) => _setFrequency(f),
              ),
          ],
        ),
        if (_frequency == DoseFrequency.interval) ..._intervalControls(),
        _gap,
        if (custom) ...[
          for (var i = 0; i < _slots.length; i++) _customSlotCard(i),
          if (_slots.length < _maxSlots)
            OutlinedButton.icon(
              onPressed: () => setState(
                () => _slots.add(_slots.last.copyAt(_slots.last.time)),
              ),
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.addAnotherTime),
            ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _slots.length == 1 ? 'Time' : 'Times',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < _slots.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _timeButton(
                        _slots[i],
                        // Interval times follow from the first dose.
                        editable: _frequency != DoseFrequency.interval,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Each dose', style: theme.textTheme.labelLarge),
                  ..._doseSettings(_slots.first),
                ],
              ),
            ),
          ),
        ],
      ],
    ];
  }

  List<Widget> _intervalControls() => [
    _gap,
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final h in intervalChoices)
          ChoiceChip(
            label: Text('Every $h hours'),
            selected: _intervalHours == h,
            onSelected: (_) => _setInterval(hours: h),
          ),
      ],
    ),
    _gap,
    OutlinedButton.icon(
      icon: const Icon(Icons.wb_twilight),
      label: Text('First dose at ${_slots.first.time.format(context)}'),
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: _slots.first.time,
          helpText: 'Time of the first dose of the day',
        );
        if (picked != null) _setInterval(first: picked);
      },
    ),
  ];

  Widget _timeButton(_SlotDraft slot, {bool editable = true}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.access_time),
        label: Text(
          slot.time.format(context),
          style: const TextStyle(fontSize: 18),
        ),
        onPressed: editable
            ? () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: slot.time,
                );
                if (picked != null) setState(() => slot.time = picked);
              }
            : null,
      ),
    );
  }

  /// One time with its own dose settings (Custom mode).
  Widget _customSlotCard(int index) {
    final slot = _slots[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _timeButton(slot)),
                if (_slots.length > 1)
                  IconButton(
                    tooltip: 'Remove time',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      _slots.removeAt(index).dispose();
                    }),
                  ),
              ],
            ),
            ..._doseSettings(slot),
          ],
        ),
      ),
    );
  }

  /// Amount, liquid unit, days and variable-dose controls for [slot].
  List<Widget> _doseSettings(_SlotDraft slot) {
    final theme = Theme.of(context);
    return [
      if (_countable) ...[
        const SizedBox(height: 12),
        TextField(
          controller: slot.amount,
          enabled: !slot.isVariable,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_decimalOnly],
          decoration: InputDecoration(
            labelText: slot.isVariable
                ? 'Usual amount (estimate)'
                : 'Dose amount',
            suffixText: _isLiquid ? null : _unitNounPlural,
          ),
        ),
        if (_isLiquid) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final u in const ['ml', 'tsp', 'tbsp'])
                ChoiceChip(
                  label: Text(doseUnitsPlural[u]!),
                  selected: slot.inputUnit == u,
                  onSelected: (_) => setState(() => slot.inputUnit = u),
                ),
            ],
          ),
        ],
      ],
      const SizedBox(height: 12),
      Text('Days', style: theme.textTheme.labelLarge),
      const SizedBox(height: 4),
      Row(
        children: [
          for (final d in _weekdayOrder)
            Expanded(
              child: _DayToggle(
                letter: _weekdayLetters[d]!,
                name: _weekdayNames[d]!,
                selected: slot.days.contains(d),
                onTap: () => setState(() {
                  slot.days.contains(d)
                      ? slot.days.remove(d)
                      : slot.days.add(d);
                }),
              ),
            ),
        ],
      ),
      if (_countable)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(AppStrings.variableDose),
          value: slot.isVariable,
          onChanged: (v) => setState(() => slot.isVariable = v),
        ),
    ];
  }

  static final _decimalOnly = FilteringTextInputFormatter.allow(
    RegExp(r'[0-9.]'),
  );
  static const _gap = SizedBox(height: 12);

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

/// Reminds the user that scanned details must be checked before saving.
class _ScanNotice extends StatelessWidget {
  const _ScanNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.document_scanner_outlined,
          color: scheme.onTertiaryContainer,
        ),
        title: Text(
          'Filled in from your prescription photo',
          style: TextStyle(color: scheme.onTertiaryContainer),
        ),
        subtitle: Text(
          'The scan can misread. Check the name, dose and times against '
          'the paper before saving.',
          style: TextStyle(color: scheme.onTertiaryContainer),
        ),
      ),
    );
  }
}
