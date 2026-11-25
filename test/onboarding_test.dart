import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilltrack/features/onboarding/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Permission checks may leave a spinner running, so pump fixed frames instead
/// of pumpAndSettle: one to start the page animation, one to finish it.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Next walks through all three pages', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    expect(find.text('Never miss a dose'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);

    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Track your supply — if you want'), findsOneWidget);
    // The example is the real MedicineCard: 45 ml at 15 ml/day = 3 days.
    expect(find.text('45 ml left'), findsOneWidget);
    expect(find.text('3 days'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Turn on reminders'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('Skip jumps straight to the permissions page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.tap(find.text('Skip'));
    await _settle(tester);
    expect(find.text('Turn on reminders'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
  });
}
