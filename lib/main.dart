import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/utils/app_logger.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'services/ad_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Anything that slips past local handling is logged, not lost.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.error(
      'Flutter framework error',
      details.exception,
      details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Uncaught async error', error, stack);
    return true;
  };

  // Notifications must be ready before the first frame so a cold start from a
  // notification tap can be routed. Failures are logged, never fatal.
  try {
    await NotificationService.instance.init();
  } catch (e) {
    AppLogger.warn('Notification init failed', e);
  }

  // Ads are non-critical: initialize in the background.
  unawaited(
    AdService.instance.init().catchError(
      (Object e) => AppLogger.warn('Ads init failed', e),
    ),
  );

  var showOnboarding = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    showOnboarding = !(prefs.getBool(OnboardingScreen.completedKey) ?? false);
  } catch (e) {
    AppLogger.warn('Reading onboarding state failed', e);
  }

  runApp(ProviderScope(child: PillTrackApp(showOnboarding: showOnboarding)));
}
