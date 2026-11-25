import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/providers.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/guarded.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../services/backup_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/photo_store.dart';
import '../../history/screens/history_screen.dart';
import '../../medicines/providers/medicine_providers.dart';

// TODO(launch): replace with the hosted privacy policy URL and support email
// (Phase 9.1 in the build plan), and read the version from package info.
const _appVersion = '1.0.0';
const _privacyPolicyUrl = 'https://example.com/pilltrack/privacy';
const _contactEmail = 'support@example.com';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool? _enabled;
  int _snooze = NotificationService.defaultSnoozeMinutes;

  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var enabled = true;
    var snooze = NotificationService.defaultSnoozeMinutes;
    try {
      enabled = await _settings.getBool(
        SettingsRepository.notificationsEnabledKey,
        defaultValue: true,
      );
      snooze = await _settings.getInt(
        SettingsRepository.snoozeMinutesKey,
        defaultValue: NotificationService.defaultSnoozeMinutes,
      );
    } catch (e, st) {
      // Show defaults rather than leaving the controls stuck disabled.
      AppLogger.error('Loading settings failed', e, st);
    }
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _snooze = snooze;
      });
    }
  }

  ScaffoldMessengerState get _messenger => ScaffoldMessenger.of(context);

  Future<void> _setEnabled(bool v) async {
    final previous = _enabled;
    setState(() => _enabled = v);
    final ok = await guarded(
      _messenger,
      "Couldn't change reminders.",
      () async {
        await _settings.setBool(SettingsRepository.notificationsEnabledKey, v);
        await ref.read(medicineActionsProvider).resync();
      },
    );
    if (!ok && mounted) setState(() => _enabled = previous);
  }

  Future<void> _setSnooze(int minutes) async {
    final previous = _snooze;
    setState(() => _snooze = minutes);
    final ok = await guarded(_messenger, "Couldn't change snooze.", () async {
      await _settings.setInt(SettingsRepository.snoozeMinutesKey, minutes);
      // Re-schedule so the "Snooze N min" button label updates.
      await ref.read(medicineActionsProvider).resync();
    });
    if (!ok && mounted) setState(() => _snooze = previous);
  }

  void _snack(String text) => _messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  // --- Data -----------------------------------------------------------------

  Future<void> _export() async {
    await guarded(_messenger, "Couldn't create a backup.", () async {
      final json = await BackupService.exportJson(
        ref.read(databaseHelperProvider),
      );
      await Clipboard.setData(ClipboardData(text: json));
      _snack(
        'Backup copied to clipboard — paste it somewhere safe '
        '(e.g. an email to yourself). Prescription photos are not '
        'included.',
      );
    });
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste a PillTrack backup below. This replaces ALL '
              'current medicines and history.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: '{ "app": "pilltrack", ... }',
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    controller.text = data?.text ?? '';
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;

    try {
      await BackupService.importJson(ref.read(databaseHelperProvider), text);
    } on FormatException catch (e) {
      // A bad file: the message explains what's wrong; nothing was changed.
      _snack(e.message);
      return;
    } catch (e, st) {
      AppLogger.error('Import failed', e, st);
      _snack("Couldn't import that backup. Your existing data is unchanged.");
      return;
    }
    // The imported data has no photos; remove the old ones' files.
    await _deletePhotoFiles();
    await _afterDataReplaced();
    _snack('Data imported');
  }

  Future<void> _deleteAll() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Delete all data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This permanently deletes every medicine, schedule '
                'and dose record. Type DELETE to confirm.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setLocal(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: controller.text.trim() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete everything'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true) return;

    final ok = await guarded(
      _messenger,
      "Couldn't delete your data.",
      () => BackupService.deleteAll(ref.read(databaseHelperProvider)),
    );
    if (!ok) return;
    await _deletePhotoFiles();
    await _afterDataReplaced();
    _snack('All data deleted');
  }

  Future<void> _deletePhotoFiles() async {
    try {
      await PhotoStore.instance.deleteAll();
    } catch (e) {
      AppLogger.warn('Deleting photo files failed', e);
    }
  }

  Future<void> _afterDataReplaced() async {
    final actions = ref.read(medicineActionsProvider);
    actions.refreshAll();
    await actions.resync();
    await _load();
  }

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settings)),
      body: ListView(
        children: [
          const _Header(AppStrings.notifications),
          SwitchListTile(
            title: const Text('Medication reminders'),
            subtitle: const Text('Notify me when a dose is due'),
            value: enabled ?? true,
            onChanged: enabled == null ? null : _setEnabled,
          ),
          ListTile(
            title: const Text('Snooze duration'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('5 min')),
                  ButtonSegment(value: 10, label: Text('10 min')),
                  ButtonSegment(value: 15, label: Text('15 min')),
                ],
                selected: {_snooze},
                onSelectionChanged: (s) => _setSnooze(s.first),
              ),
            ),
          ),
          const ListTile(
            title: Text('Sound'),
            subtitle: Text('Default notification sound'),
            trailing: Icon(Icons.volume_up_outlined),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text(AppStrings.history),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          const Divider(),
          const _Header(AppStrings.data),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Export all data as JSON'),
            subtitle: const Text('Copies a backup to the clipboard'),
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Import data'),
            subtitle: const Text('Restore from a pasted backup'),
            onTap: _import,
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete all data',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: _deleteAll,
          ),
          const Divider(),
          const _Header(AppStrings.about),
          const ListTile(title: Text('Version'), trailing: Text(_appVersion)),
          const ListTile(
            title: Text('Privacy policy'),
            subtitle: SelectableText(_privacyPolicyUrl),
          ),
          const ListTile(
            title: Text('Contact'),
            subtitle: SelectableText(_contactEmail),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text(AppStrings.removeAds),
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text(AppStrings.comingSoon),
                content: const Text(
                  'An option to remove ads is on the way. Thanks for your '
                  'patience!',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
