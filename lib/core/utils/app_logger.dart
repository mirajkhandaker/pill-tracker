import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error }

/// Minimal on-device logger. No analytics or crash reporting leaves the device
/// (see the privacy policy); entries go to the debug console and a small
/// in-memory ring buffer that a future "copy diagnostics" option can read.
abstract final class AppLogger {
  static const int _capacity = 200;
  static final ListQueue<String> _recent = ListQueue<String>();

  /// Most recent entries, oldest first.
  static List<String> get recent => List.unmodifiable(_recent);

  static void info(String message) => _log(LogLevel.info, message);

  static void warn(String message, [Object? error]) =>
      _log(LogLevel.warning, message, error);

  static void error(String message, Object error, [StackTrace? stack]) =>
      _log(LogLevel.error, message, error, stack);

  static void _log(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    final line =
        '${DateTime.now().toIso8601String()} '
        '[${level.name.toUpperCase()}] $message'
        '${error == null ? '' : ': $error'}';

    _recent.addLast(line);
    while (_recent.length > _capacity) {
      _recent.removeFirst();
    }

    developer.log(
      message,
      name: 'PillTrack',
      level: switch (level) {
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      },
      error: error,
      stackTrace: stack,
    );
    if (kDebugMode) debugPrint(line);
  }
}
