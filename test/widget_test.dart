import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/data/models/dose_log.dart';
import 'package:pilltrack/data/models/medicine.dart';
import 'package:pilltrack/data/models/schedule.dart';
import 'package:pilltrack/features/medicines/providers/medicine_providers.dart';
import 'package:pilltrack/features/medicines/widgets/dose_card.dart';
import 'package:pilltrack/features/medicines/widgets/edit_dose_sheet.dart';
import 'package:pilltrack/features/medicines/widgets/medicine_card.dart';

Medicine _med({String form = 'tablet', String unit = 'pcs'}) => Medicine(
  id: 'm1',
  name: 'Paracetamol',
  form: form,
  packageType: 'strip',
  doseUnit: unit,
  unitsPerPackage: 10,
  packagesInHand: 2,
  createdAt: 0,
);

const _sched = Schedule(id: 's1', medicineId: 'm1', timeOfDay: '08:00');

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  editTests();
  takenAmountTests();

  testWidgets('pending DoseCard shows dose text and fires Mark Taken', (
    tester,
  ) async {
    var taken = 0;
    final dose = TodayDose(
      medicine: _med(),
      schedule: _sched,
      time: DateTime(2026, 1, 1, 8),
    );
    await tester.pumpWidget(
      _wrap(DoseCard(dose: dose, onPrimary: () => taken++, onSkip: () {})),
    );

    expect(find.text('Paracetamol'), findsOneWidget);
    expect(find.textContaining('1 Tablet'), findsOneWidget);
    await tester.tap(find.text('Mark Taken'));
    expect(taken, 1);
  });

  testWidgets('variable-dose DoseCard offers Log dose', (tester) async {
    final dose = TodayDose(
      medicine: _med(form: 'injection', unit: 'IU'),
      schedule: _sched.copyWith(isVariableDose: true),
      time: DateTime(2026, 1, 1, 8),
    );
    await tester.pumpWidget(
      _wrap(DoseCard(dose: dose, onPrimary: () {}, onSkip: () {})),
    );
    expect(find.text('Log dose'), findsOneWidget);
    expect(find.text('Mark Taken'), findsNothing);
  });

  testWidgets('taken DoseCard shows status instead of buttons', (tester) async {
    final dose = TodayDose(
      medicine: _med(),
      schedule: _sched,
      time: DateTime(2026, 1, 1, 8),
      log: const DoseLog(
        id: 'l1',
        medicineId: 'm1',
        scheduleId: 's1',
        scheduledTime: 0,
        actionTime: 0,
        doseAmount: 1,
        status: DoseLog.statusTaken,
      ),
    );
    await tester.pumpWidget(
      _wrap(DoseCard(dose: dose, onPrimary: () {}, onSkip: () {})),
    );
    expect(find.text('Taken'), findsOneWidget);
    expect(find.text('Mark Taken'), findsNothing);
  });

  testWidgets('MedicineCard shows remaining stock and days left', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MedicineCard(
          medicine: _med(),
          schedules: const [_sched], // 1/day, 20 pcs => 20 days
          onTap: () {},
        ),
      ),
    );
    expect(find.text('20 Tablets left'), findsOneWidget);
    expect(find.text('20 days'), findsOneWidget);
  });
}

// --- Editing logged doses -----------------------------------------------------

DoseLog _logged({
  String? scheduleId = 's1',
  String status = DoseLog.statusTaken,
}) => DoseLog(
  id: 'l1',
  medicineId: 'm1',
  scheduleId: scheduleId,
  scheduledTime: DateTime(2026, 1, 1, 8).millisecondsSinceEpoch,
  actionTime: DateTime(2026, 1, 1, 8, 5).millisecondsSinceEpoch,
  doseAmount: 1,
  status: status,
);

Future<void> _openSheet(WidgetTester tester, DoseLog log) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showEditDoseSheet(context, log: log, medicine: _med()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void editTests() {
  testWidgets('every DoseCard offers Edit, pending or logged', (tester) async {
    var edits = 0;
    for (final log in [null, _logged()]) {
      await tester.pumpWidget(
        _wrap(
          DoseCard(
            dose: TodayDose(
              medicine: _med(),
              schedule: _sched,
              time: DateTime(2026, 1, 1, 8),
              log: log,
            ),
            onPrimary: () {},
            onSkip: () {},
            onEdit: () => edits++,
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
    }
    expect(edits, 2);
    // A pending card keeps its main actions alongside Edit.
    await tester.pumpWidget(
      _wrap(
        DoseCard(
          dose: TodayDose(
            medicine: _med(),
            schedule: _sched,
            time: DateTime(2026, 1, 1, 8),
          ),
          onPrimary: () {},
          onSkip: () {},
          onEdit: () {},
        ),
      ),
    );
    expect(find.text('Mark Taken'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('log sheet for a pending dose: no Remove, defaults to now', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLogDoseSheet(
                  context,
                  dose: TodayDose(
                    medicine: _med(),
                    schedule: _sched,
                    time: DateTime(2026, 1, 1, 8),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Log dose'), findsOneWidget);
    expect(find.text('Remove this entry'), findsNothing);
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Amount taken'), findsOneWidget);
  });

  testWidgets('edit sheet: scheduled dose can switch Taken/Skipped', (
    tester,
  ) async {
    await _openSheet(tester, _logged());
    expect(find.text('Edit dose'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Amount taken'), findsOneWidget);
    expect(find.text('Taken at 8:05 AM'), findsOneWidget);

    await tester.tap(find.text('Skipped'));
    await tester.pumpAndSettle();
    // Nothing to enter for a skipped dose.
    expect(find.text('Amount taken'), findsNothing);
  });

  testWidgets('edit sheet: as-needed dose has no Skipped option', (
    tester,
  ) async {
    await _openSheet(tester, _logged(scheduleId: null));
    expect(find.textContaining('As-needed dose'), findsOneWidget);
    expect(find.text('Skipped'), findsNothing);
  });

  testWidgets('edit sheet rejects a zero amount without saving', (
    tester,
  ) async {
    await _openSheet(tester, _logged());
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than 0'), findsOneWidget);
    expect(find.text('Edit dose'), findsOneWidget, reason: 'sheet stays open');
  });
}

void takenAmountTests() {
  testWidgets('a taken dose shows the amount actually taken', (tester) async {
    final dose = TodayDose(
      medicine: _med(),
      schedule: _sched, // scheduled: 1 tablet
      time: DateTime(2026, 1, 1, 8),
      log: _logged().copyWith(doseAmount: 2),
    );
    await tester.pumpWidget(
      _wrap(DoseCard(dose: dose, onPrimary: () {}, onSkip: () {})),
    );
    expect(find.textContaining('2 Tablets'), findsOneWidget);
    expect(find.textContaining('1 Tablet'), findsNothing);
  });
}
