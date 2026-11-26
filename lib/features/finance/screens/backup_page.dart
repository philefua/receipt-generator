import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../backup_service.dart';

/// Manager-only: make a full backup file, and restore from one. Reached from
/// the Finance card in the Manager Backend, behind the password.
class ManagerBackupPage extends StatefulWidget {
  const ManagerBackupPage({super.key});

  @override
  State<ManagerBackupPage> createState() => _ManagerBackupPageState();
}

class _ManagerBackupPageState extends State<ManagerBackupPage> {
  bool _busy = false;

  static final DateFormat _fmt = DateFormat('d MMM yyyy, HH:mm');

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : Colors.green.shade700,
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    try {
      final result = await BackupService.createBackup();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.file.path, name: result.fileName)],
          text: 'Printiverse backup (${result.fileName})',
        ),
      );
      await BackupService.recordBackupCreated();
      final receipts = result.counts['receipts_box'] ?? 0;
      _snack(
          'Backup file created ($receipts receipts). Save it somewhere safe, such as Google Drive.');
    } catch (e) {
      _snack('Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = picked?.files.single.path;
      if (picked == null || path == null) return;

      final preview = await BackupService.prepareRestore(File(path));
      if (!mounted) {
        await BackupService.cancelRestore();
        return;
      }

      final current = await BackupService.currentCounts();
      if (!mounted) {
        await BackupService.cancelRestore();
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ConfirmRestoreDialog(
          preview: preview,
          current: current,
        ),
      );
      if (confirmed != true) {
        await BackupService.cancelRestore();
        return;
      }

      await BackupService.commitRestore();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore is ready'),
          content: const Text(
            'Close the app now, swipe it away from recent apps, then open it '
            'again. The restore finishes while the app starts. Please do not '
            'make any sales or entries until then.',
          ),
          actions: [
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Close app'),
            ),
          ],
        ),
      );
    } on BackupException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      await BackupService.cancelRestore();
      _snack('Restore could not start: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = BackupService.lastBackupAt();
    final due = BackupService.reminderDue();
    final restore = BackupService.lastRestore();

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: due ? theme.colorScheme.tertiaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last backup', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(last == null
                      ? 'No backup file has been made on this device yet.'
                      : _fmt.format(last)),
                  if (due) ...[
                    const SizedBox(height: 6),
                    Text(last == null
                        ? 'Make a backup now.'
                        : 'This backup is more than ${BackupService.reminderDays} days old. Make a new one.'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _createBackup,
            icon: const Icon(Icons.backup_outlined),
            label: Text(_busy ? 'Please wait...' : 'Create backup file'),
          ),
          const SizedBox(height: 8),
          Text(
            'Includes receipts, products, settings, expenses, assets, loans '
            'and everything else in the app. It does not include the licence.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore_outlined),
            label: const Text('Restore from backup file'),
          ),
          const SizedBox(height: 8),
          Text(
            'Replaces all data on this device with the backup. Your current '
            'data is saved as a safety copy first.',
            style: theme.textTheme.bodySmall,
          ),
          if (restore != null) ...[
            const SizedBox(height: 16),
            _lastRestoreCard(theme, restore),
          ],
          const SizedBox(height: 24),
          Text('Moving to a new device', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Install the app, restore your backup file, check the counts, '
            'request a new licence for the new device, pair the Bluetooth '
            'printer again, link Google Drive again, then print a test receipt.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _lastRestoreCard(ThemeData theme, Map<String, dynamic> info) {
    final ok = info['ok'] == true;
    final at = DateTime.tryParse('${info['at']}');
    final counts = info['counts'];
    final lines = <String>[];
    if (ok && counts is Map) {
      for (final name in BackupService.allBoxNames) {
        final n = counts[name];
        if (n is int && n > 0) {
          lines.add('${BackupService.labelFor(name)}: $n');
        }
      }
    }
    return Card(
      color: ok ? null : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ok ? 'Last restore: done' : 'Last restore: failed',
                style: theme.textTheme.titleMedium),
            if (at != null) Text(_fmt.format(at)),
            const SizedBox(height: 6),
            if (!ok) Text('${info['message'] ?? ''}'),
            if (ok && lines.isNotEmpty) Text(lines.join('\n')),
          ],
        ),
      ),
    );
  }
}

class _ConfirmRestoreDialog extends StatefulWidget {
  final RestorePreview preview;
  final Map<String, int> current;

  const _ConfirmRestoreDialog({required this.preview, required this.current});

  @override
  State<_ConfirmRestoreDialog> createState() => _ConfirmRestoreDialogState();
}

class _ConfirmRestoreDialogState extends State<_ConfirmRestoreDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final created = p.createdAt == null
        ? 'unknown date'
        : DateFormat('d MMM yyyy, HH:mm').format(p.createdAt!);
    final rows = <Widget>[];
    for (final name in BackupService.allBoxNames) {
      final b = p.counts[name] ?? 0;
      final c = widget.current[name] ?? 0;
      if (b == 0 && c == 0) continue;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(BackupService.labelFor(name))),
            SizedBox(width: 70, child: Text('$b', textAlign: TextAlign.end)),
            SizedBox(width: 70, child: Text('$c', textAlign: TextAlign.end)),
          ],
        ),
      ));
    }

    return AlertDialog(
      title: const Text('Replace all data?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backup made on $created.'),
            const SizedBox(height: 8),
            const Text(
              'Everything on this device will be replaced by the backup. '
              'Nothing is merged. A safety copy of the current data is kept.',
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: Text('')),
                SizedBox(
                    width: 70,
                    child: Text('Backup',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 70,
                    child: Text('Now',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ...rows,
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration:
                  const InputDecoration(labelText: 'Type RESTORE to confirm'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().toUpperCase() == 'RESTORE'
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
