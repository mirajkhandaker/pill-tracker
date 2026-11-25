import 'package:flutter/material.dart';

import '../providers/medicine_providers.dart';

/// Snackbar after logging a dose: warns on insufficient or low stock,
/// otherwise confirms.
void showDoseFeedback(
  ScaffoldMessengerState messenger,
  DoseResult result, {
  required String medicineName,
}) {
  final String message;
  if (result.alreadyLogged) {
    message = 'That dose was already logged';
  } else if (!result.covered) {
    message =
        'Not enough $medicineName left to cover that dose — '
        'stock is now empty. Add a refill.';
  } else if (result.lowStock != null) {
    message =
        "You're running low on $medicineName — "
        '${result.lowStock!.remainingLabel}';
  } else {
    message = 'Dose logged';
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
