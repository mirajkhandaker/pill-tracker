import 'package:flutter/material.dart';

import 'app_logger.dart';

/// Runs a user-initiated [action]. If it throws, the error is logged and
/// [failureMessage] is shown in a snackbar, so a failed save is never silent
/// (an uncaught async error would otherwise vanish with no feedback).
///
/// Returns true when [action] completed.
Future<bool> guarded(
  ScaffoldMessengerState messenger,
  String failureMessage,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (e, st) {
    AppLogger.error(failureMessage, e, st);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failureMessage)));
    return false;
  }
}
