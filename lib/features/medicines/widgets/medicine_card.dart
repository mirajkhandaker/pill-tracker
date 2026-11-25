import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/dose_formatter.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/schedule.dart';

/// Summary card for one medicine: name, form, remaining stock, and days of
/// supply left (color-coded against the refill threshold).
class MedicineCard extends StatelessWidget {
  const MedicineCard({
    super.key,
    required this.medicine,
    required this.schedules,
    required this.onTap,
    this.prescriptionLabel,
  });

  final Medicine medicine;
  final List<Schedule> schedules;
  final VoidCallback onTap;

  /// Which prescription this medicine is on, e.g. "Blood pressure · Dr. Rahman".
  final String? prescriptionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final end = medicine.endDay;
    final subtitle = <Widget>[
      Text(
        [
          formLabel(medicine.form),
          if (end != null) 'until ${DateFormat('d MMM').format(end)}',
        ].join(' · '),
        style: muted,
      ),
      if (prescriptionLabel != null)
        Row(
          children: [
            Icon(Icons.receipt_long, size: 16, color: muted?.color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                prescriptionLabel!,
                style: muted,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
    ];

    if (medicine.trackInventory) {
      subtitle.add(
        Text(medicine.remainingLabel, style: theme.textTheme.bodyMedium),
      );
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicine.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ...subtitle,
                  ],
                ),
              ),
              if (medicine.trackInventory && !medicine.isPrn)
                DaysLeftChip(medicine: medicine, schedules: schedules),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// "N days" pill: red at/under the refill threshold, amber under 2x the
/// threshold, green otherwise. Hidden when supply is effectively unlimited.
class DaysLeftChip extends StatelessWidget {
  const DaysLeftChip({
    super.key,
    required this.medicine,
    required this.schedules,
  });

  final Medicine medicine;
  final List<Schedule> schedules;

  @override
  Widget build(BuildContext context) {
    final days = medicine.daysUntilEmpty(schedules);
    if (days >= 999) return const SizedBox.shrink();

    final threshold = medicine.refillThresholdDays;
    final Color color;
    if (days <= threshold) {
      color = Theme.of(context).colorScheme.error;
    } else if (days <= threshold * 2) {
      color = Colors.amber.shade800;
    } else {
      color = Colors.green.shade700;
    }

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        days == 1 ? '1 day' : '$days days',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }
}
