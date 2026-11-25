import 'package:flutter/foundation.dart';

import '../../core/constants/medication_types.dart';
import '../../core/utils/dose_formatter.dart';
import 'schedule.dart';

/// A medicine the user tracks, including its physical form, how it is packaged,
/// current inventory, and refill policy.
///
/// Unit handling: `doseUnit` is the base unit everything is stored in
/// (`loose_units`, schedule `dose_amount`, dose logs). For the `liquid` form
/// `doseUnit` is always `ml`; teaspoon/tablespoon are input-time conveniences
/// converted to ml before persistence — see [doseAmountInBaseUnit]. So the DB
/// never stores `tsp`/`tbsp` as a `doseUnit`.
@immutable
class Medicine {
  const Medicine({
    required this.id,
    required this.name,
    this.dosageText,
    this.notes,
    required this.form,
    required this.packageType,
    required this.doseUnit,
    required this.unitsPerPackage,
    this.packagesInHand = 0,
    this.looseUnits = 0,
    this.trackInventory = true,
    this.isPrn = false,
    this.refillThresholdDays = 3,
    this.isActive = true,
    required this.createdAt,
    this.prescriptionId,
    this.endDate,
  });

  final String id;
  final String name;

  /// Free-text display dosage like "500mg" — never used for calculations.
  final String? dosageText;
  final String? notes;

  /// Key from [medicationForms].
  final String form;

  /// Key from [packageTypes].
  final String packageType;

  /// Key from [doseUnitsSingular] (the base storage unit).
  final String doseUnit;

  /// Units contained in one unopened package (e.g. 10 tablets, 100 ml, 300 IU).
  /// 0 when the user hasn't given a pack size (it's optional).
  final double unitsPerPackage;

  /// Whether a pack size is known, so refills can add whole packages.
  bool get hasPackSize => unitsPerPackage > 0;

  /// Count of unopened packages on hand.
  final int packagesInHand;

  /// Loose units from an opened package, in [doseUnit].
  final double looseUnits;

  /// Whether the user chose to track their supply of this medicine. When false
  /// there is no stock count, decrement, or refill warning. Always false for
  /// creams/ointments (no countable dose).
  final bool trackInventory;

  /// True = as-needed, no schedule.
  final bool isPrn;

  final int refillThresholdDays;
  final bool isActive;

  /// Unix ms.
  final int createdAt;

  /// The prescription this medicine was prescribed on; null for medicines
  /// not linked to one (e.g. over-the-counter).
  final String? prescriptionId;

  /// Unix ms of local midnight on the *last* day of a fixed course ("take for
  /// 7 days"); null for ongoing medicines. No reminders after this day.
  final int? endDate;

  DateTime? get endDay =>
      endDate == null ? null : DateTime.fromMillisecondsSinceEpoch(endDate!);

  /// Whether the medicine is scheduled to be taken on [day] (any time that
  /// day), i.e. its course hasn't finished.
  bool isOngoingOn(DateTime day) =>
      endDate == null ||
      DateTime(day.year, day.month, day.day).millisecondsSinceEpoch <= endDate!;

  /// A fixed course whose last day is before [now]'s date.
  bool isCourseFinished(DateTime now) => !isOngoingOn(now);

  // --- Inventory math -------------------------------------------------------

  /// Total units on hand across unopened packages plus loose units.
  double get totalUnitsRemaining =>
      (packagesInHand * unitsPerPackage) + looseUnits;

  /// e.g. "45 ml left", "10 IU left", "20 Pieces left".
  String get remainingLabel =>
      formatRemaining(totalUnitsRemaining, doseUnit, form: form);

  /// Human breakdown of where the inventory sits, e.g.
  /// "2 Strips + 3 loose Pieces" or "1 Bottle + 45 ml". Count-style units
  /// ("pcs") describe loose stock as "N loose Pieces"; measures ("ml", "IU")
  /// just state the amount.
  String get inventoryBreakdown {
    final parts = <String>[];
    if (packagesInHand > 0) {
      final label = packagesInHand == 1
          ? packageLabel(packageType)
          : packageLabelPlural(packageType);
      parts.add('$packagesInHand $label');
    }
    if (looseUnits > 0) {
      final unit = unitLabel(looseUnits, doseUnit, form: form);
      // "loose" only means something next to unopened packages.
      parts.add(
        doseUnit == 'pcs' && packagesInHand > 0
            ? '${formatAmount(looseUnits)} loose $unit'
            : '${formatAmount(looseUnits)} $unit',
      );
    }
    if (parts.isEmpty) return 'Empty';
    return parts.join(' + ');
  }

  /// Plural label for this medicine's dose unit, e.g. "Tablets", "ml", "IU".
  String get unitLabelPlural => unitLabel(2, doseUnit, form: form);

  /// User-facing text for one dose of [amount] (e.g. "1 Tablet",
  /// "1 Teaspoon (5 ml)"). Creams/ointments have no countable dose, so they
  /// read "Apply as directed".
  String doseText(double amount) => form == 'cream'
      ? 'Apply as directed'
      : formatDose(amount, doseUnit, form: form);

  /// Converts [amount] expressed in [inputUnit] (default: this medicine's
  /// [doseUnit]) into the medicine's base storage unit. Teaspoons and
  /// tablespoons convert to ml (5 / 15 ml); everything else is identity.
  double doseAmountInBaseUnit(double amount, [String? inputUnit]) {
    final unit = inputUnit ?? doseUnit;
    final mlPer = doseUnitMlPerUnit[unit];
    return mlPer == null ? amount : amount * mlPer;
  }

  /// Average units consumed per day across [schedules], each weighted by how
  /// many days a week it fires. Variable-dose schedules contribute their stored
  /// amount as an estimate.
  double dailyConsumption(List<Schedule> schedules) {
    var total = 0.0;
    for (final s in schedules) {
      total += s.doseAmount * (s.dayCount / 7.0);
    }
    return total;
  }

  /// Whole days until inventory is exhausted. Returns 999 (effectively
  /// "never"/"n/a") when inventory isn't tracked, the medicine is PRN, or there
  /// is no consumption.
  int daysUntilEmpty(List<Schedule> schedules) {
    if (!trackInventory || isPrn) return 999;
    final daily = dailyConsumption(schedules);
    if (daily <= 0) return 999;
    return (totalUnitsRemaining / daily).floor();
  }

  /// Whether remaining stock is at/under the refill warning threshold.
  bool needsRefill(List<Schedule> schedules) =>
      trackInventory && daysUntilEmpty(schedules) <= refillThresholdDays;

  // --- Serialization --------------------------------------------------------

  factory Medicine.fromMap(Map<String, Object?> map) => Medicine(
    id: map['id'] as String,
    name: map['name'] as String,
    dosageText: map['dosage_text'] as String?,
    notes: map['notes'] as String?,
    form: map['form'] as String,
    packageType: map['package_type'] as String,
    doseUnit: map['dose_unit'] as String,
    unitsPerPackage: (map['units_per_package'] as num).toDouble(),
    packagesInHand: map['packages_in_hand'] as int? ?? 0,
    looseUnits: (map['loose_units'] as num? ?? 0).toDouble(),
    trackInventory: (map['track_inventory'] as int? ?? 1) == 1,
    isPrn: (map['is_prn'] as int? ?? 0) == 1,
    refillThresholdDays: map['refill_threshold_days'] as int? ?? 3,
    isActive: (map['is_active'] as int? ?? 1) == 1,
    createdAt: map['created_at'] as int,
    prescriptionId: map['prescription_id'] as String?,
    endDate: map['end_date'] as int?,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'dosage_text': dosageText,
    'notes': notes,
    'form': form,
    'package_type': packageType,
    'dose_unit': doseUnit,
    'units_per_package': unitsPerPackage,
    'packages_in_hand': packagesInHand,
    'loose_units': looseUnits,
    'track_inventory': trackInventory ? 1 : 0,
    'is_prn': isPrn ? 1 : 0,
    'refill_threshold_days': refillThresholdDays,
    'is_active': isActive ? 1 : 0,
    'created_at': createdAt,
    'prescription_id': prescriptionId,
    'end_date': endDate,
  };

  Medicine copyWith({
    String? id,
    String? name,
    String? dosageText,
    String? notes,
    String? form,
    String? packageType,
    String? doseUnit,
    double? unitsPerPackage,
    int? packagesInHand,
    double? looseUnits,
    bool? trackInventory,
    bool? isPrn,
    int? refillThresholdDays,
    bool? isActive,
    int? createdAt,
    String? prescriptionId,
    int? endDate,
    // Nullable fields can't be cleared via `??`, so clearing is explicit.
    bool clearPrescription = false,
    bool clearEndDate = false,
  }) => Medicine(
    id: id ?? this.id,
    name: name ?? this.name,
    dosageText: dosageText ?? this.dosageText,
    notes: notes ?? this.notes,
    form: form ?? this.form,
    packageType: packageType ?? this.packageType,
    doseUnit: doseUnit ?? this.doseUnit,
    unitsPerPackage: unitsPerPackage ?? this.unitsPerPackage,
    packagesInHand: packagesInHand ?? this.packagesInHand,
    looseUnits: looseUnits ?? this.looseUnits,
    trackInventory: trackInventory ?? this.trackInventory,
    isPrn: isPrn ?? this.isPrn,
    refillThresholdDays: refillThresholdDays ?? this.refillThresholdDays,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    prescriptionId: clearPrescription
        ? null
        : prescriptionId ?? this.prescriptionId,
    endDate: clearEndDate ? null : endDate ?? this.endDate,
  );

  @override
  bool operator ==(Object other) =>
      other is Medicine &&
      other.id == id &&
      other.name == name &&
      other.dosageText == dosageText &&
      other.notes == notes &&
      other.form == form &&
      other.packageType == packageType &&
      other.doseUnit == doseUnit &&
      other.unitsPerPackage == unitsPerPackage &&
      other.packagesInHand == packagesInHand &&
      other.looseUnits == looseUnits &&
      other.trackInventory == trackInventory &&
      other.isPrn == isPrn &&
      other.refillThresholdDays == refillThresholdDays &&
      other.isActive == isActive &&
      other.createdAt == createdAt &&
      other.prescriptionId == prescriptionId &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    dosageText,
    notes,
    form,
    packageType,
    doseUnit,
    unitsPerPackage,
    packagesInHand,
    looseUnits,
    trackInventory,
    isPrn,
    refillThresholdDays,
    isActive,
    createdAt,
    prescriptionId,
    endDate,
  ]);
}
