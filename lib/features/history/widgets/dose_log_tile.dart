import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/dose_formatter.dart';
import '../../../data/models/dose_log.dart';
import '../../../data/models/medicine.dart';

/// One history row: date/time, amount, and a colored status dot. Tappable
/// (with an edit icon) when [onTap] is given, to correct the entry.
class DoseLogTile extends StatelessWidget {
  const DoseLogTile({
    super.key,
    required this.log,
    required this.medicine,
    this.showName = false,
    this.onTap,
  });

  final DoseLog log;
  final Medicine? medicine;
  final bool showName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final when = DateTime.fromMillisecondsSinceEpoch(
      log.actionTime ?? log.scheduledTime,
    );
    final unit = medicine?.doseUnit ?? 'pcs';
    final dose = log.status == DoseLog.statusTaken
        ? (medicine?.form == 'cream'
              ? 'Applied'
              : medicine?.doseText(log.doseAmount) ??
                    formatDose(log.doseAmount, unit))
        : '—';
    final (color, label) = statusStyle(context, log.status);
    final title = showName
        ? (medicine?.name ?? 'Deleted medicine')
        : DateFormat('EEE d MMM').format(when);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(radius: 7, backgroundColor: color),
      title: Text(title),
      subtitle: Text('${DateFormat('h:mm a').format(when)} · $dose'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.edit_outlined,
              size: 20,
              semanticLabel: 'Edit',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  static (Color, String) statusStyle(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      DoseLog.statusTaken => (Colors.green.shade700, 'Taken'),
      DoseLog.statusSkipped => (scheme.outline, 'Skipped'),
      DoseLog.statusMissed => (scheme.error, 'Missed'),
      _ => (scheme.secondary, 'Pending'),
    };
  }
}
