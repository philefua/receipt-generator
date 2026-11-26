import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../services/google_drive_service.dart';
import '../backup_service.dart';

/// Manager-only: make a full backup file (saved or shared, or sent to Google
/// Drive), and restore from one. Reached from the Finance card in the Manager
/// Backend, behind the password.
class ManagerBackupPage extends StatefulWidget {
  const ManagerBackupPage({super.key});

  @override
  State<ManagerBackupPage> createState() => _ManagerBackupPageState();
}

class _ManagerBackupPageState extends State<ManagerBackupPage> {
  bool _busy = false;

  static final DateFormat _fmt = DateFormat('d MMM yyyy, HH:mm');

  GoogleDriveService get _drive => GoogleDriveService.instance;

  @override
  void initState() {
    super.initState();
    _tryRestoreDriveConnection();
  }

  /// Picks up a previously connected Google account without any prompt.
  Future<void> _tryRestoreDriveConnection() async {
    if (_drive.isSignedIn) return;
    await _drive.trySilentSignIn();
    if (mounted) setState(() {});
  }

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

  // ---------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------

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

  Future<void> _connectDrive() async {
    setState(() => _busy = true);
    try {
      final r = await _drive.signIn();
      _snack(r.message, error: !r.success);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupToDrive() async {
    setState(() => _busy = true);
    try {
      final result = await BackupService.createBackup();
      final bytes = await result.file.readAsBytes();
      final up = await _drive.uploadBackupFile(
        bytes: bytes,
        fileName: result.fileName,
      );
      if (up.success) {
        await BackupService.recordBackupCreated();
        final receipts = result.counts['receipts_box'] ?? 0;
        _snack('Backup uploaded to Google Drive ($receipts receipts).');
      } else {
        _snack(up.message, error: true);
      }
    } catch (e) {
      _snack('Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------
  // Restore (from a file, or from Google Drive)
  // ---------------------------------------------------------------------

  Future<void> _restoreFromFile() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = picked?.files.single.path;
      if (picked == null || path == null) return;
      await _stageAndConfirm(File(path));
    } on BackupException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      await BackupService.cancelRestore();
      _snack('Restore could not start: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromDrive() async {
    setState(() => _busy = true);
    File? temp;
    try {
      final list = await _drive.listBackupFiles();
      if (!list.success) {
        _snack(list.message, error: true);
        return;
      }
      if (list.files.isEmpty) {
        _snack(
            'No Printiverse backups were found in this Google account for this app.',
            error: true);
        return;
      }
      if (!mounted) return;
      final choice = await showDialog<DriveBackupFile>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Choose a backup'),
          children: [
            for (final f in list.files)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(f),
                child: Text(_driveFileLabel(f)),
              ),
          ],
        ),
      );
      if (choice == null) return;

      final dl = await _drive.downloadFile(choice.id);
      final bytes = dl.bytes;
      if (!dl.success || bytes == null) {
        _snack(dl.message, error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      temp = File('${dir.path}/printiverse_drive_restore.json');
      await temp.writeAsBytes(bytes, flush: true);
      await _stageAndConfirm(temp);
    } on BackupException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      await BackupService.cancelRestore();
      _snack('Restore could not start: $e', error: true);
    } finally {
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  String _driveFileLabel(DriveBackupFile f) {
    final when = f.createdTime == null
        ? f.name
        : _fmt.format(f.createdTime!.toLocal());
    final size = f.sizeBytes;
    final kb = size == null ? '' : '  (${(size / 1024).round()} KB)';
    return '$when$kb';
  }

  /// Checks and stages the file, asks for confirmation, then asks the
  /// manager to restart the app. Live data is not touched here.
  Future<void> _stageAndConfirm(File file) async {
    final preview = await BackupService.prepareRestore(file);
    if (!mounted) {
      await BackupService.cancelRestore();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmRestoreDialog(
        preview: preview,
        current: BackupService.currentCounts(),
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
  }

  // ---------------------------------------------------------------------
  // Screen
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = BackupService.lastBackupAt();
    final reason = BackupService.reminderMessage(
        startMonth: BackupService.currentStartMonth());
    final restore = BackupService.lastRestore();
    final signedIn = _drive.isSignedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: reason != null ? theme.colorScheme.tertiaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last backup', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(last == null
                      ? 'No backup has been made on this device yet.'
                      : _fmt.format(last)),
                  if (reason != null) ...[
                    const SizedBox(height: 6),
                    Text(reason),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Back up', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Google Drive', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    signedIn
                        ? 'Signed in as ${_drive.signedInEmail ?? 'your Google account'}'
                        : 'Not connected.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (!signedIn)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _connectDrive,
                      icon: const Icon(Icons.login),
                      label: const Text('Connect Google account'),
                    ),
                  if (signedIn)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _backupToDrive,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Back up to Google Drive'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Restore', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restoreFromFile,
            icon: const Icon(Icons.restore_outlined),
            label: const Text('Restore from backup file'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (_busy || !signedIn) ? null : _restoreFromDrive,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Restore from Google Drive'),
          ),
          const SizedBox(height: 8),
          Text(
            'Replaces all data on this device with the backup. Your current '
            'data is saved as a safety copy first. Drive restore only shows '
            'backups this app uploaded to the signed-in Google account.',
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
            'Install the app, restore your backup (file or Drive), check the '
            'counts, request a new licence for the new device, pair the '
            'Bluetooth printer again, link Google Drive again, then print a '
            'test receipt.',
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
