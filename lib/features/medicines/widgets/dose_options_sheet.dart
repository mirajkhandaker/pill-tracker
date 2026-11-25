import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../providers/medicine_providers.dart';
import '../screens/edit_medicine_screen.dart';
import 'edit_dose_sheet.dart';

enum _DoseEditChoice { dose, medicine }

/// "Edit" on a dose card: choose between this dose (log it differently, or
/// correct it once logged) and the medicine itself.
Future<void> showDoseOptions(
  BuildContext context,
  WidgetRef ref,
  TodayDose dose,
) async {
  final logged = dose.log != null;
  final choice = await showModalBottomSheet<_DoseEditChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                '${dose.medicine.name} · '
                '${DateFormat('h:mm a').format(dose.time)}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: Icon(logged ? Icons.edit_note : Icons.more_time),
              title: Text(
                logged
                    ? 'Edit this dose'
                    : 'Taken at a different time or amount',
              ),
              subtitle: Text(
                logged
                    ? 'Taken or skipped, amount, or time'
                    : 'Or mark it as skipped',
              ),
              onTap: () => Navigator.pop(ctx, _DoseEditChoice.dose),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.medication_outlined),
              title: const Text('Edit medicine'),
              subtitle: const Text('Name, dose, times, how long, prescription'),
              onTap: () => Navigator.pop(ctx, _DoseEditChoice.medicine),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case _DoseEditChoice.dose:
      final log = dose.log;
      await (log == null
          ? showLogDoseSheet(context, dose: dose)
          : showEditDoseSheet(context, log: log, medicine: dose.medicine));
    case _DoseEditChoice.medicine:
      final navigator = Navigator.of(context);
      final schedules = await ref
          .read(scheduleRepositoryProvider)
          .getByMedicineId(dose.medicine.id);
      await navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              EditMedicineScreen(medicine: dose.medicine, schedules: schedules),
        ),
      );
  }
}
