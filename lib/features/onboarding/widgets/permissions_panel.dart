import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/app_logger.dart';
import '../../../services/notification_service.dart';

/// Shows each permission PillTrack needs, why, and its live status, with a
/// Grant button. Re-checks when the app resumes, because granting exact alarms
/// (and re-enabling notifications after denials) happens in system settings.
class PermissionsPanel extends StatefulWidget {
  const PermissionsPanel({super.key});

  @override
  State<PermissionsPanel> createState() => _PermissionsPanelState();
}

class _PermissionsPanelState extends State<PermissionsPanel>
    with WidgetsBindingObserver {
  final _service = NotificationService.instance;
  bool? _notifications;
  bool? _exactAlarms;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    bool? notifications;
    bool? exact;
    try {
      notifications = await _service.notificationsAllowed();
      exact = await _service.exactAlarmsAllowed();
    } catch (e) {
      AppLogger.warn('Permission status check failed', e);
    }
    if (mounted) {
      setState(() {
        _notifications = notifications;
        _exactAlarms = exact;
      });
    }
  }

  Future<void> _run(Future<void> Function() request) async {
    try {
      await request();
    } catch (e) {
      AppLogger.warn('Permission request failed', e);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PermissionTile(
          icon: Icons.notifications_active_outlined,
          title: 'Notifications',
          why:
              'So PillTrack can remind you when each dose is due. '
              "Without this, you won't get any reminders.",
          granted: _notifications,
          onGrant: () => _run(_service.requestNotificationPermission),
        ),
        if (_isAndroid)
          _PermissionTile(
            icon: Icons.alarm_on_outlined,
            title: 'Alarms & reminders',
            why:
                'Lets reminders arrive at the exact minute, even when your '
                'phone is idle. Without it they may arrive a few minutes late.',
            granted: _exactAlarms,
            onGrant: () => _run(_service.requestExactAlarmPermission),
          ),
      ],
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.why,
    required this.granted,
    required this.onGrant,
  });

  final IconData icon;
  final String title;
  final String why;

  /// Null while the status is still being read.
  final bool? granted;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(why, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  switch (granted) {
                    true => Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Allowed',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    false => FilledButton(
                      onPressed: onGrant,
                      child: const Text('Grant'),
                    ),
                    null => const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
