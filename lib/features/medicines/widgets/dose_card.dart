import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/dose_log.dart';
import '../providers/medicine_providers.dart';

/// A single scheduled dose for today with its status and quick actions.
class DoseCard extends StatelessWidget {
  const DoseCard({
    super.key,
    required this.dose,
    required this.onPrimary,
    required this.onSkip,
    this.onEdit,
  });

  final TodayDose dose;

  /// "Mark Taken" (fixed) or "Log dose" (variable) pressed.
  final VoidCallback onPrimary;
  final VoidCallback onSkip;

  /// Opens the edit options for this dose (log it differently, correct a
  /// logged dose, or edit the medicine).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLabel = DateFormat('h:mm a').format(dose.time);
    final isVariable = dose.schedule.isVariableDose;
    // Once taken, show what was actually taken (it may have been corrected,
    // or entered for a variable dose) rather than the scheduled amount.
    final doseText = dose.isTaken
        ? dose.medicine.doseText(dose.log!.doseAmount)
        : isVariable
        ? 'Variable dose'
        : dose.medicine.doseText(dose.schedule.doseAmount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _StatusBadge(dose: dose),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dose.medicine.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$timeLabel · $doseText',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (dose.isPending)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: onPrimary,
                    child: Text(isVariable ? 'Log dose' : 'Mark Taken'),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onEdit != null)
                        TextButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit'),
                        ),
                      TextButton(onPressed: onSkip, child: const Text('Skip')),
                    ],
                  ),
                ],
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusText(status: dose.status),
                  if (onEdit != null)
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.dose});
  final TodayDose dose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final IconData icon;
    late final Color color;

    if (dose.isTaken) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (dose.status == DoseLog.statusSkipped) {
      icon = Icons.remove_circle;
      color = scheme.outline;
    } else if (dose.isPast) {
      icon = Icons.error;
      color = scheme.error;
    } else {
      icon = Icons.schedule;
      color = scheme.secondary;
    }
    return Icon(icon, color: color, size: 32);
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      DoseLog.statusTaken => 'Taken',
      DoseLog.statusSkipped => 'Skipped',
      DoseLog.statusMissed => 'Missed',
      _ => 'Pending',
    };
    return Text(label, style: Theme.of(context).textTheme.bodyMedium);
  }
}
