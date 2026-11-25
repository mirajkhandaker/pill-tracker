import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/models/prescription.dart';
import 'package:pilltrack/data/models/schedule.dart';
import 'package:pilltrack/features/medicines/providers/medicine_providers.dart';
import 'package:pilltrack/features/medicines/screens/edit_medicine_screen.dart';
import 'package:pilltrack/features/prescriptions/providers/prescription_providers.dart';

Widget _app(Widget screen, {List<Prescription> prescriptions = const []}) =>
    ProviderScope(
      overrides: [
        activePrescriptionsProvider.overrideWith((ref) async => prescriptions),
        prescriptionByIdProvider.overrideWith(
          (ref, id) async => prescriptions.where((p) => p.id == id).firstOrNull,
        ),
      ],
      child: MaterialApp(home: screen),
    );

/// Scrolls [f] fully into view: scrollUntilVisible stops as soon as it's
/// barely on screen, where its centre (the tap point) may still be off-screen.
Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(f);
  await tester.pump();
}

/// Captures what the edit screen saves instead of writing to a database.
class _RecordingActions extends MedicineActions {
  _RecordingActions(super.ref);
  List<Schedule>? saved;

  @override
  Future<void> saveMedicine(Medicine medicine, List<Schedule> schedules) async {
    saved = schedules;
  }
}

void main() {
  packageTests();
  frequencyTests();

  testWidgets('saving an edit keeps the schedule ids doses are logged on', (
    tester,
  ) async {
    _tallScreen(tester);
    const med = Medicine(
      id: 'm',
      name: 'Amlodipine',
      form: 'tablet',
      packageType: 'strip',
      doseUnit: 'pcs',
      unitsPerPackage: 0,
      trackInventory: false,
      createdAt: 0,
    );
    const schedules = [
      Schedule(id: 's-am', medicineId: 'm', timeOfDay: '08:00'),
      Schedule(id: 's-pm', medicineId: 'm', timeOfDay: '20:00'),
    ];
    late _RecordingActions actions;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activePrescriptionsProvider.overrideWith((ref) async => const []),
          medicineActionsProvider.overrideWith(
            (ref) => actions = _RecordingActions(ref),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => const EditMedicineScreen(
                    medicine: med,
                    schedules: schedules,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Notes'), 'x');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(actions.saved!.map((s) => s.id), ['s-am', 's-pm']);
  });

  testWidgets('supply tracking is off by default for a new medicine', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const EditMedicineScreen()));
    await tester.pump();

    await _scrollTo(tester, find.text('Track my supply'));
    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Track my supply'),
    );
    expect(toggle.value, isFalse);
    expect(find.text('How many Tablets do you have now? *'), findsNothing);

    await tester.tap(find.text('Track my supply'));
    await tester.pump();
    await _scrollTo(tester, find.text('How many Tablets do you have now? *'));
    // Just one question; packs are optional and start collapsed.
    expect(find.text('Pack size (optional)'), findsOneWidget);
    expect(find.text('Tablets per Strip'), findsNothing);
  });

  testWidgets('editing keeps an existing medicine\'s tracking choice', (
    tester,
  ) async {
    const tracked = Medicine(
      id: 'm',
      name: 'Paracetamol',
      form: 'tablet',
      packageType: 'strip',
      doseUnit: 'pcs',
      unitsPerPackage: 10,
      trackInventory: true,
      createdAt: 0,
    );
    await tester.pumpWidget(_app(const EditMedicineScreen(medicine: tracked)));
    await tester.pump();
    await _scrollTo(tester, find.text('Track my supply'));
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Track my supply'),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('offers active prescriptions and pre-selects one', (
    tester,
  ) async {
    final rx = Prescription(
      id: 'rx',
      doctorName: 'Dr. Rahman',
      reason: 'Blood pressure',
      issuedAt: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      createdAt: 0,
    );
    await tester.pumpWidget(
      _app(const EditMedicineScreen(prescriptionId: 'rx'), prescriptions: [rx]),
    );
    await tester.pump();
    await tester.pump();
    await _scrollTo(tester, find.textContaining('Blood pressure'));
    expect(find.textContaining('Blood pressure · Dr. Rahman'), findsOneWidget);
  });

  testWidgets('a fixed course defaults to 7 days', (tester) async {
    await tester.pumpWidget(_app(const EditMedicineScreen()));
    await tester.pump();
    await _scrollTo(tester, find.text('Fixed course'));
    await tester.tap(find.text('Fixed course'));
    await tester.pump();
    await _scrollTo(tester, find.text('7 days'));
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '7 days'),
    );
    expect(chip.selected, isTrue);
  });
}

Medicine _tracked(String form, String package, String unit) => Medicine(
  id: 'm',
  name: 'Med',
  form: form,
  packageType: package,
  doseUnit: unit,
  unitsPerPackage: 10,
  trackInventory: true,
  createdAt: 0,
);

/// Expands "Pack size (optional)" if needed, then opens the Package type menu
/// so its options are on screen.
Future<void> _openPackages(WidgetTester tester) async {
  // Build the whole form so "is the pack section already open?" is reliable.
  _tallScreen(tester);
  await tester.pump();
  if (find.text('Package type').evaluate().isEmpty) {
    await _scrollTo(tester, find.text('Pack size (optional)'));
    await tester.tap(find.text('Pack size (optional)'));
    await tester.pumpAndSettle();
  }
  await _scrollTo(tester, find.text('Package type'));
  await tester.tap(
    find.widgetWithText(DropdownButtonFormField<String>, 'Package type'),
  );
  await tester.pumpAndSettle();
}

void packageTests() {
  testWidgets('tablets are only offered packages tablets come in', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const EditMedicineScreen()));
    await tester.pump();
    await _scrollTo(tester, find.text('Track my supply'));
    await tester.tap(find.text('Track my supply'));
    await tester.pump();
    await _openPackages(tester);

    for (final ok in ['Strip', 'Bottle', 'Box']) {
      expect(find.text(ok), findsWidgets, reason: '$ok should be offered');
    }
    for (final no in ['Vial', 'Pen', 'Canister', 'Tube']) {
      expect(find.text(no), findsNothing, reason: '$no makes no sense');
    }
  });

  testWidgets('a syrup has only one package, so no package question', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(EditMedicineScreen(medicine: _tracked('liquid', 'bottle', 'ml'))),
    );
    await tester.pump();
    await _scrollTo(tester, find.text('ml per Bottle'));
    expect(find.text('Package type'), findsNothing);
    expect(find.text('How much do you have now? *'), findsOneWidget);
  });

  testWidgets('a never-tracked medicine starts with empty supply fields', (
    tester,
  ) async {
    // Saved with tracking off: placeholder 1-per-pack / 0 packs, not real.
    const untracked = Medicine(
      id: 'm',
      name: 'Amlodipine',
      form: 'tablet',
      packageType: 'strip',
      doseUnit: 'pcs',
      unitsPerPackage: 1,
      trackInventory: false,
      createdAt: 0,
    );
    await tester.pumpWidget(
      _app(const EditMedicineScreen(medicine: untracked)),
    );
    await tester.pump();
    await _scrollTo(tester, find.text('Track my supply'));
    await tester.tap(find.text('Track my supply'));
    await tester.pump();
    String text(String label) => tester
        .widget<TextFormField>(find.widgetWithText(TextFormField, label))
        .controller!
        .text;
    await _scrollTo(tester, find.text('How many Tablets do you have now? *'));
    expect(text('How many Tablets do you have now? *'), isEmpty);
    await tester.tap(find.text('Pack size (optional)'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Tablets per Strip'));
    expect(text('Tablets per Strip'), isEmpty);
  });

  testWidgets('a tracked medicine shows its total stock as one number', (
    tester,
  ) async {
    final tracked = _tracked(
      'tablet',
      'strip',
      'pcs',
    ).copyWith(packagesInHand: 2, looseUnits: 3);
    await tester.pumpWidget(_app(EditMedicineScreen(medicine: tracked)));
    await tester.pump();
    await _scrollTo(tester, find.text('How many Tablets do you have now? *'));
    final stock = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'How many Tablets do you have now? *'),
    );
    expect(stock.controller!.text, '23');
  });

  testWidgets('injections choose between vial and pen', (tester) async {
    await tester.pumpWidget(
      _app(EditMedicineScreen(medicine: _tracked('injection', 'vial', 'IU'))),
    );
    await tester.pump();
    await _openPackages(tester);
    expect(find.text('Pen'), findsWidgets);
    expect(find.text('Strip'), findsNothing);
  });

  testWidgets('an existing odd combination stays visible to be fixed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(EditMedicineScreen(medicine: _tracked('tablet', 'vial', 'pcs'))),
    );
    await tester.pump();
    await _openPackages(tester);
    expect(find.text('Vial'), findsWidgets);
    expect(find.text('Strip'), findsWidgets);
  });
}

/// A viewport tall enough that the whole form is built at once (lists only
/// build what's near the screen), so assertions can see every card.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void frequencyTests() {
  testWidgets('duration defaults to Continue', (tester) async {
    await tester.pumpWidget(_app(const EditMedicineScreen()));
    await tester.pump();
    await _scrollTo(tester, find.text('Continue'));
    final seg = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(seg.selected, {false});
    expect(find.text('7 days'), findsNothing);
  });

  testWidgets('3 times a day fills in 8 AM, 2 PM, 8 PM', (tester) async {
    await tester.pumpWidget(_app(const EditMedicineScreen()));
    await tester.pump();
    await _scrollTo(tester, find.text('3 times a day'));
    await tester.tap(find.text('3 times a day'));
    await tester.pump();
    await _scrollTo(tester, find.text('8:00 PM'));
    for (final time in ['8:00 AM', '2:00 PM', '8:00 PM']) {
      expect(find.text(time), findsOneWidget);
    }
    // One shared set of dose settings, not one per time.
    expect(find.text('Each dose'), findsOneWidget);
    expect(find.text('Dose amount'), findsOneWidget);
  });

  testWidgets('every 8 hours works out the times from the first dose', (
    tester,
  ) async {
    _tallScreen(tester);
    await tester.pumpWidget(_app(const EditMedicineScreen()));
    await tester.pump();
    await _scrollTo(tester, find.text('Every few hours'));
    await tester.tap(find.text('Every few hours'));
    await tester.pump();
    await _scrollTo(tester, find.text('Every 8 hours'));
    await tester.tap(find.text('Every 8 hours'));
    await tester.pump();
    await _scrollTo(tester, find.text('Each dose'));
    // Default first dose 8 AM -> 8 AM, 4 PM, midnight.
    expect(find.text('First dose at 8:00 AM'), findsOneWidget);
    expect(find.text('4:00 PM'), findsOneWidget);
    expect(find.text('12:00 AM'), findsOneWidget);
  });

  testWidgets('custom keeps a full card per time', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(_app(const EditMedicineScreen()));
    await tester.pump();
    await _scrollTo(tester, find.text('Twice a day'));
    await tester.tap(find.text('Twice a day'));
    await tester.pump();
    await tester.tap(find.text('Custom'));
    await tester.pump();
    await _scrollTo(tester, find.text('Add another time'));
    expect(find.text('Each dose'), findsNothing);
    expect(find.text('Dose amount'), findsNWidgets(2));
  });

  testWidgets('different amounts per time open in Custom', (tester) async {
    const insulin = Medicine(
      id: 'm',
      name: 'Insulin',
      form: 'injection',
      packageType: 'pen',
      doseUnit: 'IU',
      unitsPerPackage: 300,
      createdAt: 0,
    );
    await tester.pumpWidget(
      _app(
        const EditMedicineScreen(
          medicine: insulin,
          schedules: [
            Schedule(
              id: 'a',
              medicineId: 'm',
              timeOfDay: '08:00',
              doseAmount: 10,
            ),
            Schedule(
              id: 'b',
              medicineId: 'm',
              timeOfDay: '20:00',
              doseAmount: 6,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await _scrollTo(tester, find.text('Custom'));
    final custom = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Custom'),
    );
    expect(custom.selected, isTrue);
  });
}
