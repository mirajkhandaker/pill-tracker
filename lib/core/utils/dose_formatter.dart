import '../constants/medication_types.dart';

/// Formatting helpers that turn stored numeric amounts + unit keys into the
/// user-facing strings shown on cards, notifications, and history rows.

/// Formats a number for display: whole numbers drop the trailing `.0`
/// ("10" not "10.0"); fractional values keep their significant decimals
/// ("0.5", "2.5") without trailing-zero noise ("0.50").
String formatAmount(double amount) {
  if (amount == amount.truncateToDouble()) {
    return amount.toInt().toString();
  }
  // Trim any trailing zeros while keeping at least one decimal digit.
  var s = amount.toString();
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Label for [unit] at [amount] (singular only for exactly 1). When [form] is
/// given, `pcs` uses the form's noun ("Tablet", "Capsules") instead of "Piece".
String unitLabel(double amount, String unit, {String? form}) {
  final isSingular = amount == 1;
  final noun = unit == 'pcs' ? pieceNounsByForm[form] : null;
  if (noun != null) return isSingular ? noun.$1 : noun.$2;
  final map = isSingular ? doseUnitsSingular : doseUnitsPlural;
  return map[unit] ?? unit;
}

/// A single dose, e.g. "1 Teaspoon (5 ml)", "10 IU", "500 mg", "2 Puffs",
/// "0.5 Pieces" ("1 Tablet" when [form] is given). For `tsp`/`tbsp` the ml
/// equivalent is appended in parentheses.
String formatDose(double amount, String unit, {String? form}) {
  final label = unitLabel(amount, unit, form: form);
  final base = '${formatAmount(amount)} $label';
  final mlPer = doseUnitMlPerUnit[unit];
  if (mlPer != null) {
    return '$base (${formatAmount(amount * mlPer)} ml)';
  }
  return base;
}

/// Remaining inventory framed as "10 IU left", "45 ml left", "20 Pieces left".
/// No ml conversion: loose units are always stored in the form's base unit.
String formatRemaining(double amount, String unit, {String? form}) {
  return '${formatAmount(amount)} ${unitLabel(amount, unit, form: form)} left';
}

/// UI label for a medication form key (e.g. 'tablet' -> 'Tablet').
String formLabel(String formKey) => medicationForms[formKey] ?? formKey;

/// UI label for a package type key (e.g. 'strip' -> 'Strip').
String packageLabel(String packageKey) =>
    packageTypes[packageKey] ?? packageKey;

/// Pluralized package label (e.g. 'strip' -> 'Strips', 'box' -> 'Boxes').
String packageLabelPlural(String packageKey) =>
    packageTypesPlural[packageKey] ?? packageLabel(packageKey);
