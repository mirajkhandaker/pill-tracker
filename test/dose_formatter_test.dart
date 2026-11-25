import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/core/utils/dose_formatter.dart';

void main() {
  group('formatDose', () {
    test('whole tablet uses singular Piece', () {
      expect(formatDose(1, 'pcs'), '1 Piece');
    });

    test('half tablet uses plural and keeps decimal', () {
      expect(formatDose(0.5, 'pcs'), '0.5 Pieces');
    });

    test('two tablets use plural', () {
      expect(formatDose(2, 'pcs'), '2 Pieces');
    });

    test('teaspoon appends ml equivalent (singular)', () {
      expect(formatDose(1, 'tsp'), '1 Teaspoon (5 ml)');
    });

    test('teaspoon appends ml equivalent (plural)', () {
      expect(formatDose(2, 'tsp'), '2 Teaspoons (10 ml)');
    });

    test('tablespoon appends ml equivalent', () {
      expect(formatDose(1, 'tbsp'), '1 Tablespoon (15 ml)');
      expect(formatDose(2, 'tbsp'), '2 Tablespoons (30 ml)');
    });

    test('IU is invariant and drops trailing zero', () {
      expect(formatDose(10, 'IU'), '10 IU');
    });

    test('ml is invariant', () {
      expect(formatDose(5, 'ml'), '5 ml');
      expect(formatDose(2.5, 'ml'), '2.5 ml');
    });

    test('milligrams', () {
      expect(formatDose(500, 'mg'), '500 mg');
    });

    test('puffs pluralize', () {
      expect(formatDose(1, 'puff'), '1 Puff');
      expect(formatDose(2, 'puff'), '2 Puffs');
    });
  });

  group('formatRemaining', () {
    test('IU left', () => expect(formatRemaining(10, 'IU'), '10 IU left'));
    test('ml left', () => expect(formatRemaining(45, 'ml'), '45 ml left'));
    test(
      'pieces left',
      () => expect(formatRemaining(20, 'pcs'), '20 Pieces left'),
    );
    test(
      'single piece left',
      () => expect(formatRemaining(1, 'pcs'), '1 Piece left'),
    );
    test(
      'no ml conversion for spoons',
      () => expect(formatRemaining(3, 'tsp'), '3 Teaspoons left'),
    );
  });

  group('form-aware nouns', () {
    test('tablet', () {
      expect(formatDose(1, 'pcs', form: 'tablet'), '1 Tablet');
      expect(formatRemaining(20, 'pcs', form: 'tablet'), '20 Tablets left');
    });
    test('capsule and patch', () {
      expect(formatDose(2, 'pcs', form: 'capsule'), '2 Capsules');
      expect(formatDose(1, 'pcs', form: 'patch'), '1 Patch');
    });
    test(
      'other form keeps Piece',
      () => expect(formatDose(1, 'pcs', form: 'other'), '1 Piece'),
    );
    test(
      'non-pcs units ignore form',
      () => expect(formatDose(10, 'IU', form: 'tablet'), '10 IU'),
    );
  });

  group('labels', () {
    test('form label', () => expect(formLabel('injection'), 'Injection'));
    test('package label', () => expect(packageLabel('vial'), 'Vial'));
    test(
      'package plural regular',
      () => expect(packageLabelPlural('strip'), 'Strips'),
    );
    test(
      'package plural irregular',
      () => expect(packageLabelPlural('box'), 'Boxes'),
    );
    test('unknown key falls through', () => expect(formLabel('xyz'), 'xyz'));
  });

  group('formatAmount', () {
    test('drops .0', () => expect(formatAmount(10.0), '10'));
    test('keeps .5', () => expect(formatAmount(2.5), '2.5'));
    test('trims trailing zeros', () => expect(formatAmount(2.50), '2.5'));
  });
}
