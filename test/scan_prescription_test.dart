import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/core/providers.dart';
import 'package:pilltrack/core/utils/prescription_parser.dart';
import 'package:pilltrack/data/models/prescription_photo.dart';
import 'package:pilltrack/features/prescriptions/providers/prescription_providers.dart';
import 'package:pilltrack/features/prescriptions/screens/scan_prescription_screen.dart';
import 'package:pilltrack/services/text_scan_service.dart';

class _FakeScanner implements TextScanService {
  _FakeScanner(this.rows);
  final List<String> rows;
  final scanned = <String>[];

  @override
  Future<List<String>> readRows(String imagePath) async {
    scanned.add(imagePath);
    return rows;
  }
}

Widget _app(_FakeScanner scanner) => ProviderScope(
  overrides: [
    textScanServiceProvider.overrideWithValue(scanner),
    prescriptionPhotosProvider.overrideWith(
      (ref, id) async => [
        PrescriptionPhoto(
          id: 'ph1',
          prescriptionId: id,
          fileName: 'page1.jpg',
          createdAt: 0,
        ),
      ],
    ),
    photoDirectoryProvider.overrideWith((ref) async => Directory('/photos')),
    activePrescriptionsProvider.overrideWith((ref) async => const []),
    prescriptionByIdProvider.overrideWith((ref, id) async => null),
  ],
  child: const MaterialApp(home: ScanPrescriptionScreen(prescriptionId: 'rx')),
);

String _fieldText(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  testWidgets('scanning a saved photo suggests medicines to add', (
    tester,
  ) async {
    final scanner = _FakeScanner([
      'Dr. Rahman MBBS',
      'Tab. Napa 500mg 1+0+1 x 7 days after meal',
      'Cap. Seclo 20mg 0+0+1 continue',
    ]);
    await tester.pumpWidget(_app(scanner));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Scan prescription photo 1 of 1'));
    await tester.pumpAndSettle();

    expect(scanner.scanned, ['/photos/page1.jpg']);
    expect(find.text('Found 2 medicines'), findsOneWidget);
    expect(
      find.text('Tablet · 500mg · 1+0+1 · 7 days · After meals'),
      findsOneWidget,
    );
    expect(find.text('Seclo'), findsOneWidget);

    // Add opens the normal form, filled in, with a reminder to check it.
    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pumpAndSettle();
    expect(find.text('Filled in from your prescription photo'), findsOneWidget);
    expect(_fieldText(tester, 'Name *'), 'Napa');
    expect(_fieldText(tester, 'Dosage (e.g. 500 mg)'), '500mg');
  });

  testWidgets('nothing recognised offers adding by hand', (tester) async {
    await tester.pumpWidget(_app(_FakeScanner(['Dr. Rahman', 'Age 45'])));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Scan prescription photo 1 of 1'));
    await tester.pumpAndSettle();

    expect(find.text('No medicines found'), findsOneWidget);
    expect(find.text('Add a medicine yourself'), findsOneWidget);
    expect(find.text('Text read from the photo'), findsOneWidget);
  });

  test('scanSummary describes frequency words and as-needed', () {
    expect(
      scanSummary(
        const ScannedMedicine(
          name: 'Salbutamol',
          form: 'inhaler',
          amount: 2,
          amountUnit: 'puff',
          asNeeded: true,
          sourceText: '',
        ),
      ),
      'Inhaler · 2 Puffs · As needed',
    );
    expect(
      scanSummary(
        const ScannedMedicine(
          name: 'Metformin',
          strength: '500mg',
          timesPerDay: 2,
          ongoing: true,
          sourceText: '',
        ),
      ),
      '500mg · Twice a day · Continue',
    );
  });
}
