/// Turns text read from a prescription photo into medicine suggestions.
///
/// This is deliberately conservative: it only suggests rows that look like a
/// medicine (a form prefix such as "Tab." or a strength such as "500mg"), and
/// every suggestion is shown to the user to check before anything is saved.
/// Common prescription shorthand is understood: dose patterns ("1+0+1"),
/// frequency abbreviations (OD, BD, TDS, QID, q8h, SOS), course lengths
/// ("x 7 days", "1 month", "continue") and meal instructions.
library;

/// One line of recognised text with its position on the photo.
class OcrLine {
  const OcrLine(
    this.text, {
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
}

/// Joins recognised lines that sit side by side into one row of text, top to
/// bottom. Prescriptions often put the dose and duration in a separate column
/// from the medicine name, and the recogniser returns those as separate lines.
List<String> groupIntoRows(List<OcrLine> lines) {
  final sorted = [...lines.where((l) => l.text.trim().isNotEmpty)]
    ..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <List<OcrLine>>[];
  for (final line in sorted) {
    final row = rows.isEmpty ? null : rows.last;
    if (row != null) {
      final rowCenter =
          row.map((l) => l.centerY).reduce((a, b) => a + b) / row.length;
      final rowHeight =
          row.map((l) => l.height).reduce((a, b) => a + b) / row.length;
      final tolerance =
          0.5 * (line.height < rowHeight ? line.height : rowHeight);
      if ((line.centerY - rowCenter).abs() <= tolerance) {
        row.add(line);
        continue;
      }
    }
    rows.add([line]);
  }
  return [
    for (final row in rows)
      (row..sort((a, b) => a.left.compareTo(b.left)))
          .map((l) => l.text.trim())
          .join('  '),
  ];
}

/// A daily reminder time suggested by a scan, with the dose for that time
/// (null when the amount couldn't be read safely, e.g. a syrup without a unit).
typedef ScanSlot = ({int hour, int minute, double? amount});

/// A medicine read from a prescription. Everything except [name] is optional.
class ScannedMedicine {
  const ScannedMedicine({
    required this.name,
    this.form,
    this.strength,
    this.doseParts,
    this.timesPerDay,
    this.everyHours,
    this.amount,
    this.amountUnit,
    this.courseDays,
    this.ongoing = false,
    this.asNeeded = false,
    this.instructions,
    required this.sourceText,
  });

  final String name;

  /// Key from `medicationForms`; null when the row didn't say.
  final String? form;

  /// Display strength, e.g. "500mg" or "120mg/5ml".
  final String? strength;

  /// Dose per time of day from a "1+0+1" pattern (morning, noon, night —
  /// four parts add evening). Zeros are kept: they mean "not at that time".
  final List<double>? doseParts;

  /// From OD/BD/TDS/QID when there's no dose pattern.
  final int? timesPerDay;

  /// From "q8h" / "every 8 hours" / "8 hourly".
  final int? everyHours;

  /// Amount per dose from text like "2 tabs" or "5 ml".
  final double? amount;

  /// Key from `doseUnitsSingular` for [amount] (pcs, ml, tsp, tbsp, puff,
  /// drop, IU).
  final String? amountUnit;

  /// Length of a fixed course in days.
  final int? courseDays;

  /// "Continue" — no end date.
  final bool ongoing;

  /// SOS / PRN / as needed.
  final bool asNeeded;

  /// "Before meals", "After meals", "With food" or "At bedtime".
  final String? instructions;

  /// The row of text this came from, shown so the user can compare.
  final String sourceText;

  /// Forms whose dose patterns count whole pieces (tablets, puffs, drops), so
  /// "1+0+1" can be read as an amount without a written unit.
  static const _countedForms = {
    'tablet',
    'capsule',
    'patch',
    'inhaler',
    'drops',
    'other',
  };

  /// The dose at a time of day whose pattern part is [part]. A written
  /// amount wins over a plain yes/no pattern ("1+0+1, 2 tsp each"); bare
  /// pattern numbers are only trusted for counted forms.
  double? _amountFor(double part) {
    if (amount != null && part <= 1) return amount;
    if (amountUnit != null || _countedForms.contains(form ?? 'tablet')) {
      return part;
    }
    return null;
  }

  /// The unit to enter amounts in: the written one, or the form's piece unit.
  String? get effectiveUnit =>
      amountUnit ??
      switch (form ?? 'tablet') {
        'inhaler' => 'puff',
        'drops' => 'drop',
        'liquid' || 'injection' || 'cream' => null,
        _ => 'pcs',
      };

  /// Suggested daily times. Empty for as-needed medicines and when the
  /// prescription didn't say how often (the editor's default applies).
  List<ScanSlot> dailySlots() {
    if (asNeeded) return const [];
    final parts = doseParts;
    if (parts != null) {
      final hours = switch (parts.length) {
        1 => const [8],
        2 => const [8, 20],
        3 => const [8, 14, 20],
        _ => const [8, 13, 18, 22],
      };
      return [
        for (var i = 0; i < parts.length && i < hours.length; i++)
          if (parts[i] > 0)
            (hour: hours[i], minute: 0, amount: _amountFor(parts[i])),
      ];
    }
    final every = everyHours;
    if (every != null) {
      return [
        for (var h = 8; h < 8 + 24; h += every)
          (hour: h % 24, minute: 0, amount: amount),
      ];
    }
    final hours = switch (timesPerDay) {
      1 => [instructions == 'At bedtime' ? 21 : 8],
      2 => const [8, 20],
      3 => const [8, 14, 20],
      4 => const [8, 13, 18, 22],
      _ => const <int>[],
    };
    return [for (final h in hours) (hour: h, minute: 0, amount: amount)];
  }
}

// --- Patterns ---------------------------------------------------------------

const _formWords = <String, String>{
  'tab': 'tablet',
  'tabs': 'tablet',
  'tablet': 'tablet',
  'tablets': 'tablet',
  'cap': 'capsule',
  'caps': 'capsule',
  'capsule': 'capsule',
  'capsules': 'capsule',
  'syp': 'liquid',
  'syr': 'liquid',
  'syrup': 'liquid',
  'susp': 'liquid',
  'suspension': 'liquid',
  'sol': 'liquid',
  'solution': 'liquid',
  'inj': 'injection',
  'injection': 'injection',
  'drop': 'drops',
  'drops': 'drops',
  'oint': 'cream',
  'ointment': 'cream',
  'cream': 'cream',
  'crm': 'cream',
  'gel': 'cream',
  'lotion': 'cream',
  'inh': 'inhaler',
  'inhaler': 'inhaler',
  'patch': 'patch',
};

/// Leading numbering / bullets: "1.", "2)", "•", "-", "Rx".
final _leader = RegExp(
  r'^\s*(?:(?:\d{1,2}\s*[.):]|\d{1,2}\s+(?=[a-z])|[•*·\-–]|rx\b\.?)\s*)+',
  caseSensitive: false,
);

final _formPrefix = RegExp(
  r'^(?:(?:(eye|ear|nasal)\s*)?('
  '${_formWords.keys.join('|')}'
  r')|(e/d))\b\.?\s*',
  caseSensitive: false,
);

final _strength = RegExp(
  r'(?<![A-Za-z\d.])(\d+(?:[.,]\d+)?)\s?(mg|mcg|µg|ug|gm|g|iu|%)'
  r'(?:\s?/\s?(\d+(?:[.,]\d+)?)?\s?(ml))?(?![A-Za-z])',
  caseSensitive: false,
);

/// One part of a dose pattern: 0–4, halves, or an "O" misread for zero.
const _part = r'(?:[0-4](?:\.5)?|½|¼|1/2|[oO])';
final _dosePattern = RegExp(
  '(?<![\\d./])($_part)\\s*[+\\-–—]\\s*($_part)'
  '(?:\\s*[+\\-–—]\\s*($_part))?(?:\\s*[+\\-–—]\\s*($_part))?(?![\\d/])',
);

final _amount = RegExp(
  r'(?<![\d./])(\d+(?:\.\d+)?|½|1/2)\s*'
  r'(tabs?|tablets?|caps?|capsules?|puffs?|drops?|tsf|tsp|teaspoons?|'
  r'spoons?|tbsp|tablespoons?|ml|iu|units?)\b',
  caseSensitive: false,
);

final _everyHours = RegExp(
  r'\bq\s?(\d{1,2})\s?h(?:rs?)?\b|\bevery\s+(\d{1,2})\s*(?:hours?|hrs?|h)\b'
  r'|\b(\d{1,2})\s*(?:-\s*)?(?:hourly|hrly)\b',
  caseSensitive: false,
);

final _qid = RegExp(
  r'\b(?:q\.?i\.?d\.?|qds|4\s*times?(?:\s*a)?\s*(?:day|daily))',
  caseSensitive: false,
);
final _tds = RegExp(
  r'\b(?:t\.?d\.?s\.?|t\.?i\.?d\.?|thrice|3\s*times?(?:\s*a)?\s*(?:day|daily))',
  caseSensitive: false,
);
final _bd = RegExp(
  r'\b(?:b\.?d\.?|b\.?i\.?d\.?|twice|2\s*times?(?:\s*a)?\s*(?:day|daily))(?![a-z])',
  caseSensitive: false,
);
final _od = RegExp(
  r'\b(?:o\.?d\.?|q\.?d\.?|once(?:\s*a\s*day|\s*daily)?|daily|h\.?s\.?|nocte|'
  r'at\s*(?:night|bedtime))(?![a-z])',
  caseSensitive: false,
);
final _prn = RegExp(
  r'\b(?:prn|sos|as\s+needed|when\s+needed|if\s+(?:needed|required))\b',
  caseSensitive: false,
);

final _days = RegExp(r'\b(\d{1,3})\s*(?:d|days?|dys?)\b', caseSensitive: false);
final _weeks = RegExp(r'\b(\d{1,2})\s*(?:wks?|weeks?)\b', caseSensitive: false);
final _months = RegExp(
  r'\b(\d{1,2})\s*(?:mo|mon|months?)\b',
  caseSensitive: false,
);
final _continue = RegExp(
  r'\b(?:cont\.?|continue[sd]?|ongoing|long\s*term|lifelong|regular)\b',
  caseSensitive: false,
);

final _beforeMeal = RegExp(
  r'\b(?:before\s+(?:meals?|food|breakfast|eating)|empty\s+stomach)\b|\ba/c\b|\ba\.c\.',
  caseSensitive: false,
);
final _afterMeal = RegExp(
  r'\bafter\s+(?:meals?|food|breakfast|eating)\b|\bp/c\b|\bp\.c\.',
  caseSensitive: false,
);
final _withFood = RegExp(r'\bwith\s+(?:meals?|food)\b', caseSensitive: false);
final _bedtime = RegExp(
  r'\b(?:h\.?s\.?|at\s+bedtime|nocte)(?![a-z])',
  caseSensitive: false,
);

/// Rows that are about the patient or doctor, not a medicine.
final _noise = RegExp(
  r'\b(?:patient|name|age|sex|date|dr|doctor|mbbs|fcps|frcp|bmdc|reg(?:d|n)?|'
  r'phone|mobile|tel|cell|email|address|hospital|clinic|chamber|diagnosis|'
  r'dx|c/c|o/e|bp|pulse|weight|wt|temp|hb|rbs|fbs|investigations?|advice|'
  r'follow(?:\s*-?\s*up)?|signature|visit|test)\b',
  caseSensitive: false,
);

// --- Parsing ----------------------------------------------------------------

/// Medicine suggestions from recognised [rows] of prescription text, in the
/// order they appear. A row with only dosing details (written under the
/// medicine) fills in the medicine above it.
List<ScannedMedicine> parsePrescriptionText(List<String> rows) {
  final found = <_Draft>[];
  _Draft? last;
  for (final raw in rows) {
    final row = _normalise(raw);
    if (row.isEmpty) continue;
    final draft = _parseMedicineRow(row);
    if (draft != null) {
      found.add(draft);
      last = draft;
      continue;
    }
    // A short dosing-only row continues the medicine above it.
    if (last != null && !_noise.hasMatch(row) && _looksLikeDosing(row)) {
      last
        ..sourceText = '${last.sourceText}\n${raw.trim()}'
        ..fillFrom(_details(row));
      continue;
    }
    last = null;
  }
  return [for (final d in found) d.build()];
}

String _normalise(String s) => s
    .replaceAll('½', '0.5')
    .replaceAll('¼', '0.25')
    .replaceAll(RegExp(r'[|]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _looksLikeDosing(String row) {
  final d = _details(row);
  final hasDosing =
      d.doseParts != null ||
      d.timesPerDay != null ||
      d.everyHours != null ||
      d.asNeeded;
  final hasCourse = d.courseDays != null || d.ongoing;
  final wordCount = row.split(' ').length;
  return (hasDosing && wordCount <= 10) || (hasCourse && wordCount <= 5);
}

_Draft? _parseMedicineRow(String row) {
  var rest = row.replaceFirst(_leader, '');
  final formMatch = _formPrefix.firstMatch(rest);
  String? form;
  if (formMatch != null) {
    final word = formMatch.group(2);
    form = formMatch.group(1) != null || word == null
        ? 'drops'
        : _formWords[word.toLowerCase()];
    rest = rest.substring(formMatch.end);
  }
  final strengthMatch = _strength.firstMatch(rest);

  // Without a form prefix, only a row with a strength and no patient/doctor
  // words is taken as a medicine.
  if (form == null && (strengthMatch == null || _noise.hasMatch(rest))) {
    return null;
  }

  final named = _extractName(rest);
  if (named == null) return null;

  return _Draft(name: named.name, form: form, sourceText: row)
    // "Seclo 20" with no unit: the trailing number is still the strength.
    ..strength = strengthMatch == null
        ? named.trailingNumber
        : _formatStrength(strengthMatch)
    ..fillFrom(_details(rest));
}

/// The medicine name: the words before the strength or dosing details, and
/// a bare number left after it (often a strength written without a unit).
({String name, String? trailingNumber})? _extractName(String text) {
  var end = text.length;
  for (final re in [
    _strength,
    _dosePattern,
    _amount,
    _everyHours,
    _qid,
    _tds,
    _bd,
    _od,
    _prn,
    _days,
    _beforeMeal,
    _afterMeal,
    RegExp(r'[(\[:;,]|\s[x×]\s?\d|\s-\s'),
  ]) {
    final m = re.firstMatch(text);
    if (m != null && m.start < end) end = m.start;
  }
  final words = text
      .substring(0, end)
      .replaceAll(RegExp(r'[^A-Za-z0-9\s\-+&]'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(4)
      .toList();
  // Drop a trailing dash or stray digits left behind by the cut.
  String? trailingNumber;
  while (words.isNotEmpty && !RegExp('[A-Za-z]').hasMatch(words.last)) {
    final w = words.removeLast();
    if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(w)) trailingNumber ??= w;
  }
  if (words.isEmpty) return null;
  final name = words.join(' ');
  if (RegExp('[A-Za-z]').allMatches(name).length < 3) return null;
  return (name: _tidyCase(name), trailingNumber: trailingNumber);
}

/// "NAPA EXTEND" → "Napa Extend"; mixed-case names are kept as written.
String _tidyCase(String name) {
  if (name != name.toUpperCase()) return name;
  return name
      .split(' ')
      .map(
        (w) => w.length <= 1 || RegExp(r'\d').hasMatch(w)
            ? w
            : '${w[0]}${w.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _formatStrength(RegExpMatch m) {
  String num(String s) => s.replaceAll(',', '.');
  var unit = m.group(2)!.toLowerCase();
  unit = switch (unit) {
    'iu' => 'IU',
    'gm' => 'g',
    'ug' || 'µg' => 'mcg',
    _ => unit,
  };
  final base = '${num(m.group(1)!)}$unit';
  if (m.group(4) == null) return base;
  return '$base/${num(m.group(3) ?? '')}ml';
}

double? _partValue(String? s) {
  if (s == null) return null;
  if (s == 'o' || s == 'O') return 0;
  if (s == '1/2') return 0.5;
  return double.tryParse(s);
}

/// Dosing details found anywhere in [text].
_Details _details(String text) {
  final d = _Details();
  final pattern = _dosePattern.firstMatch(text);
  if (pattern != null) {
    final parts = [for (var g = 1; g <= 4; g++) _partValue(pattern.group(g))]
        .whereType<double>()
        .toList();
    if (parts.any((p) => p > 0)) d.doseParts = parts;
  }
  // The pattern's digits mustn't be read again as amounts or durations.
  final rest = pattern == null
      ? text
      : text.replaceRange(pattern.start, pattern.end, ' ');

  // A large ml figure is the bottle size ("Syp. Tusca 100ml"), not a dose.
  final amount = _amount.allMatches(rest).where((m) {
    final value = _partValue(m.group(1)) ?? 0;
    return m.group(2)!.toLowerCase() != 'ml' || value <= 30;
  }).firstOrNull;
  if (amount != null) {
    d.amount = _partValue(amount.group(1));
    d.amountUnit = switch (amount.group(2)!.toLowerCase()) {
      'ml' => 'ml',
      'tsp' ||
      'tsf' ||
      'teaspoon' ||
      'teaspoons' ||
      'spoon' ||
      'spoons' => 'tsp',
      'tbsp' || 'tablespoon' || 'tablespoons' => 'tbsp',
      'puff' || 'puffs' => 'puff',
      'drop' || 'drops' => 'drop',
      'iu' || 'unit' || 'units' => 'IU',
      _ => 'pcs',
    };
  }

  final every = _everyHours.firstMatch(rest);
  final hours = every == null
      ? null
      : int.tryParse(every.group(1) ?? every.group(2) ?? every.group(3)!);
  if (hours != null && const [4, 6, 8, 12].contains(hours)) {
    d.everyHours = hours;
  } else if (_qid.hasMatch(rest)) {
    d.timesPerDay = 4;
  } else if (_tds.hasMatch(rest)) {
    d.timesPerDay = 3;
  } else if (_bd.hasMatch(rest)) {
    d.timesPerDay = 2;
  } else if (_od.hasMatch(rest)) {
    d.timesPerDay = 1;
  }
  d.asNeeded = _prn.hasMatch(rest);

  final days = _days.firstMatch(rest);
  final weeks = _weeks.firstMatch(rest);
  final months = _months.firstMatch(rest);
  final courseDays = days != null
      ? int.parse(days.group(1)!)
      : weeks != null
      ? int.parse(weeks.group(1)!) * 7
      : months != null
      ? int.parse(months.group(1)!) * 30
      : null;
  if (courseDays != null && courseDays > 0 && courseDays <= 365) {
    d.courseDays = courseDays;
  }
  d.ongoing = d.courseDays == null && _continue.hasMatch(rest);

  if (_beforeMeal.hasMatch(rest)) {
    d.instructions = 'Before meals';
  } else if (_afterMeal.hasMatch(rest)) {
    d.instructions = 'After meals';
  } else if (_withFood.hasMatch(rest)) {
    d.instructions = 'With food';
  } else if (_bedtime.hasMatch(rest)) {
    d.instructions = 'At bedtime';
  }
  return d;
}

class _Details {
  List<double>? doseParts;
  int? timesPerDay;
  int? everyHours;
  double? amount;
  String? amountUnit;
  int? courseDays;
  bool ongoing = false;
  bool asNeeded = false;
  String? instructions;
}

class _Draft extends _Details {
  _Draft({required this.name, this.form, required this.sourceText});

  final String name;
  final String? form;
  String sourceText;
  String? strength;

  /// Takes any details this medicine doesn't have yet.
  void fillFrom(_Details d) {
    if (doseParts == null && timesPerDay == null && everyHours == null) {
      doseParts = d.doseParts;
      timesPerDay = d.timesPerDay;
      everyHours = d.everyHours;
    }
    if (amount == null) {
      amount = d.amount;
      amountUnit = d.amountUnit;
    }
    if (courseDays == null && !ongoing) {
      courseDays = d.courseDays;
      ongoing = d.ongoing;
    }
    asNeeded = asNeeded || d.asNeeded;
    instructions ??= d.instructions;
  }

  ScannedMedicine build() => ScannedMedicine(
    name: name,
    form: form,
    strength: strength,
    doseParts: doseParts,
    timesPerDay: timesPerDay,
    everyHours: everyHours,
    amount: amount,
    amountUnit: amountUnit,
    courseDays: courseDays,
    ongoing: ongoing,
    asNeeded: asNeeded,
    instructions: instructions,
    sourceText: sourceText,
  );
}
