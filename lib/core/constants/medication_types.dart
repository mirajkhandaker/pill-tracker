/// Canonical terminology for the app. Keys are the stable internal values
/// persisted in SQLite; values are the user-facing labels shown in the UI.
///
/// IMPORTANT: for the `liquid` form the medicine's `dose_unit` is always `ml`.
/// `tsp`/`tbsp` are input-time conveniences only (a schedule row may be entered
/// in teaspoons/tablespoons and converted to ml for storage) and never persist
/// as a medicine's `dose_unit`. See [doseUnitMlPerUnit] and the Medicine model.
library;

/// Medication form (the physical form of the medicine).
const Map<String, String> medicationForms = {
  'tablet': 'Tablet',
  'capsule': 'Capsule',
  'liquid': 'Liquid / Syrup',
  'injection': 'Injection',
  'inhaler': 'Inhaler',
  'drops': 'Drops',
  'patch': 'Patch',
  'cream': 'Cream / Ointment',
  'other': 'Other',
};

/// Package type (how the medicine is stored/sold).
const Map<String, String> packageTypes = {
  'strip': 'Strip',
  'bottle': 'Bottle',
  'vial': 'Vial',
  'pen': 'Pen',
  'canister': 'Canister',
  'box': 'Box',
  'tube': 'Tube',
};

/// Pluralized package labels (English). Kept explicit so irregular plurals
/// like "Boxes" are correct rather than naively suffixed.
const Map<String, String> packageTypesPlural = {
  'strip': 'Strips',
  'bottle': 'Bottles',
  'vial': 'Vials',
  'pen': 'Pens',
  'canister': 'Canisters',
  'box': 'Boxes',
  'tube': 'Tubes',
};

/// Dose units — singular labels.
const Map<String, String> doseUnitsSingular = {
  'pcs': 'Piece',
  'tsp': 'Teaspoon',
  'tbsp': 'Tablespoon',
  'ml': 'ml',
  'IU': 'IU',
  'mg': 'mg',
  'mcg': 'mcg',
  'puff': 'Puff',
  'drop': 'Drop',
};

/// Dose units — plural labels. Units of measure (ml, IU, mg, mcg) are invariant.
const Map<String, String> doseUnitsPlural = {
  'pcs': 'Pieces',
  'tsp': 'Teaspoons',
  'tbsp': 'Tablespoons',
  'ml': 'ml',
  'IU': 'IU',
  'mg': 'mg',
  'mcg': 'mcg',
  'puff': 'Puffs',
  'drop': 'Drops',
};

/// Forms whose `pcs` unit reads better as a specific noun ("1 Tablet",
/// "20 Capsules left") than the generic "Piece". (singular, plural).
const Map<String, (String, String)> pieceNounsByForm = {
  'tablet': ('Tablet', 'Tablets'),
  'capsule': ('Capsule', 'Capsules'),
  'patch': ('Patch', 'Patches'),
};

/// ml equivalent for the spoon-based input units. Used to show the ml value
/// alongside a teaspoon/tablespoon dose and to convert spoon input to ml.
const Map<String, double> doseUnitMlPerUnit = {'tsp': 5.0, 'tbsp': 15.0};

/// For a given form, the package types that make sense for it and the dose
/// unit(s) offered in the Add Medicine screen. The first entry in each list
/// is the default. Only these packages are offered, so impossible
/// combinations (e.g. tablets in a vial) can't be chosen. An empty `units`
/// list means the form is not count-tracked.
const Map<String, Map<String, List<String>>> formDefaults = {
  'tablet': {
    'packages': ['strip', 'bottle', 'box'],
    'units': ['pcs', 'mg'],
  },
  'capsule': {
    'packages': ['strip', 'bottle', 'box'],
    'units': ['pcs', 'mg'],
  },
  'liquid': {
    'packages': ['bottle'],
    'units': ['ml', 'tsp', 'tbsp'],
  },
  'injection': {
    'packages': ['vial', 'pen'],
    'units': ['IU', 'ml'],
  },
  'inhaler': {
    'packages': ['canister'],
    'units': ['puff'],
  },
  'drops': {
    'packages': ['bottle'],
    'units': ['drop', 'ml'],
  },
  'patch': {
    'packages': ['box'],
    'units': ['pcs'],
  },
  'cream': {
    'packages': ['tube'],
    'units': [], // no decrement
  },
  'other': {
    'packages': ['strip', 'bottle', 'box', 'vial', 'pen', 'canister', 'tube'],
    'units': ['pcs'],
  },
};

/// Package types offered for [form] (first = default).
List<String> packagesForForm(String form) =>
    formDefaults[form]?['packages'] ?? packageTypes.keys.toList();

/// Dose units offered for [form] (first = default; empty = not countable).
List<String> unitsForForm(String form) =>
    formDefaults[form]?['units'] ?? const [];
