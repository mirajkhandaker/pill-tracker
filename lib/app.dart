import 'package:flutter/material.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/medicines/screens/home_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';

class PillTrackApp extends StatelessWidget {
  const PillTrackApp({super.key, this.showOnboarding = false});

  /// True on first run, until the onboarding flow is completed.
  final bool showOnboarding;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: showOnboarding ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
