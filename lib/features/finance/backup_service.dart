import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'finance_boxes.dart';

/// A problem the manager should be told about in plain words.
class BackupException implements Exception {
  final String message;
  BackupException(this.message);

  @override
  String toString() => message;
}

class BackupResult {
  final File file;
  final String fileName;
  final Map<String, int> counts;
  const BackupResult(this.file, this.fileName, this.counts);
}

class RestorePreview {
  final DateTime? createdAt;
  final String appVersion;
  final Map<String, int> counts;
  const RestorePreview({
    required this.createdAt,
    required this.appVersion,
    required this.counts,
  });
}

/// Full backup and restore of every Hive box, as one versioned file.
///
/// Backup copies each box's own file byte for byte, so a receipt comes back
/// exactly as it was saved. Restore never touches live data while the app is
/// running: the file is checked and staged, and the swap happens at the next
/// app start, before any box is opened, with a snapshot of the old data taken
/// first and a rollback if anything fails.
///
/// Never included: the licence box (`license_state`) and Google tokens.
/// The manager password is only ever stored as a hash, which is included.
///
/// Hive refuses to hand out an already-open box under a different type than
/// it was opened with. The app opens most boxes with their own types, so this
/// class never asks Hive for those boxes. It reads their files from disk and
/// counts records by opening a private copy as a temporary box.
class BackupService {
  BackupService._();

  static const String formatId = 'printiverse-backup';

  /// Bump when the file layout changes. A backup with a higher number than
  /// this is refused.
  static const int schemaVersion = 1;
  static const String appVersion = '1.0.0';
  static const int reminderDays = 7;

  /// Tests point this at a temporary folder. Leave null in the app.
  @visibleForTesting
  static Directory? directoryOverride;

  /// The three app boxes. Names match the ones AppStateController opens.
  static const List<String> appBoxNames = <String>[
    'settings_box',
    'products_box',
    'receipts_box',
  ];

  /// Every box that goes into a backup. A new box added to
  /// [FinanceBoxes.allBoxNames] is picked up here automatically.
  static List<String> get allBoxNames =>
      <String>[...appBoxNames, ...FinanceBoxes.allBoxNames];

  static const Map<String, String> _labels = <String, String>{
    'settings_box': 'Business settings',
    'products_box': 'Products',
    'receipts_box': 'Receipts',
    'finance_settings_box': 'Finance settings',
    'expense_categories_box': 'Expense categories',
    'asset_categories_box': 'Asset categories',
    'receipt_links_box': 'Balance links',
    'stock_counts_box': 'Stock counts',
    'assets_box': 'Assets',
    'loans_box': 'Loans',
    'loan_transactions_box': 'Loan repayments',
    'finance_expenses_box': 'Expenses',
  };

  static String labelFor(String name) => _labels[name] ?? name;

  static const String metaBoxName = 'backup_meta_box';
  static const String _pendingDir = 'restore_pending';
  static const String _checkDir = 'restore_check';
  static const String _countDir = 'backup_count_tmp';
  static const String _snapshotRoot = 'backup_snapshots';
  static const String _filePrefix = 'Printiverse_backup_';
  static const int _keepSnapshots = 3;

  // ---------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------

  static Future<Directory> _docs() async =>
      directoryOverride ?? await getApplicationDocumentsDirectory();

  static String _fileFor(Directory dir, String name) =>
      '${dir.path}/${name.toLowerCase()}.hive';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _stamp(DateTime d) =>
      '${d.year}${_two(d.month)}${_two(d.day)}_${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

  static Future<void> _deleteDir(Directory d) async {
    if (await d.exists()) {
      await d.delete(recursive: true);
    }
  }

  static String _checksumOf(List<Map<String, dynamic>> entries) {
    final text = entries
        .map((e) => '${e['name']}:${e['sha256']}:${e['records']}')
        .join('|');
    return sha256.convert(utf8.encode(text)).toString();
  }

  // ---------------------------------------------------------------------
  // Last backup date (its own small box, not BusinessSettings)
  // ---------------------------------------------------------------------

  /// Opens the small box that remembers the last backup and last restore.
  /// Never throws.
  static Future<void> openMeta() async {
    try {
      if (!Hive.isBoxOpen(metaBoxName)) {
        await Hive.openBox<String>(metaBoxName);
      }
    } catch (e) {
      debugPrint('Backup meta box could not be opened: $e');
    }
  }

  static Box<String>? get _meta =>
      Hive.isBoxOpen(metaBoxName) ? Hive.box<String>(metaBoxName) : null;

  static DateTime? lastBackupAt() {
    final v = _meta?.get('last_backup_at');
    return v == null ? null : DateTime.tryParse(v);
  }

  /// True when no backup file was ever made, or the last one is 7+ days old.
  static bool reminderDue() {
    final t = lastBackupAt();
    return t == null || DateTime.now().difference(t).inDays >= reminderDays;
  }

  static Future<void> recordBackupCreated() async {
    await openMeta();
    await _meta?.put('last_backup_at', DateTime.now().toIso8601String());
  }

  /// What the last restore attempt did, or null if none has happened.
  static Map<String, dynamic>? lastRestore() {
    final v = _meta?.get('last_restore');
    if (v == null) return null;
    try {
      final decoded = jsonDecode(v);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _recordRestore(Map<String, dynamic> info) async {
    await openMeta();
    await _meta?.put('last_restore', jsonEncode(info));
  }

  // ---------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------

  /// Counts the records in a copy of a box file. The copy is opened as its
  /// own temporary box, so this works whatever type the live box was opened
  /// with, and the live box is never touched.
  static Future<int> _countRecords(
      String name, List<int> bytes, Directory dir) async {
    final tmp = Directory('${dir.path}/$_countDir');
    final lower = name.toLowerCase();
    try {
      await _deleteDir(tmp);
      await tmp.create(recursive: true);
      await File('${tmp.path}/cnt_$lower.hive')
          .writeAsBytes(bytes, flush: true);
      final box = await Hive.openBox<dynamic>('cnt_$lower', path: tmp.path);
      final n = box.length;
      await box.close();
      return n;
    } finally {
      try {
        await _deleteDir(tmp);
      } catch (_) {}
    }
  }

  /// Record counts for the data on this device right now. Reads each box's
  /// file, so it does not matter how the app opened the box.
  static Future<Map<String, int>> currentCounts() async {
    final dir = await _docs();
    final counts = <String, int>{};
    for (final n in allBoxNames) {
      final f = File(_fileFor(dir, n));
      counts[n] = await f.exists()
          ? await _countRecords(n, await f.readAsBytes(), dir)
          : 0;
    }
    return counts;
  }

  /// The box's file as it is on disk. Hive writes each change straight to
  /// the file, so this is current. Null means the box was never created.
  static Future<List<int>?> _readBoxBytes(String name, Directory dir) async {
    final f = File(_fileFor(dir, name));
    if (await f.exists()) return f.readAsBytes();
    if (Hive.isBoxOpen(name)) {
      throw BackupException(
          'The ${labelFor(name)} data file could not be found, so no backup was made.');
    }
    return null;
  }

  /// Builds the backup file in the app's documents folder.
  static Future<BackupResult> createBackup() async {
    final dir = await _docs();
    final entries = <Map<String, dynamic>>[];
    final counts = <String, int>{};

    for (final name in allBoxNames) {
      final bytes = await _readBoxBytes(name, dir);
      if (bytes == null) {
        // A box that was never created has nothing to back up.
        counts[name] = 0;
        continue;
      }
      final records = await _countRecords(name, bytes, dir);
      counts[name] = records;
      entries.add(<String, dynamic>{
        'name': name,
        'records': records,
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'data': base64Encode(bytes),
      });
    }

    final createdAt = DateTime.now();
    final envelope = <String, dynamic>{
      'format': formatId,
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'createdAt': createdAt.toIso8601String(),
      'boxes': entries,
      'checksum': _checksumOf(entries),
    };

    // Keep only the newest backup file in the app folder.
    await for (final e in dir.list()) {
      if (e is File) {
        final base = e.uri.pathSegments.last;
        if (base.startsWith(_filePrefix) && base.endsWith('.json')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    }

    final fileName = '$_filePrefix${_stamp(createdAt)}.json';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonEncode(envelope), flush: true);
    return BackupResult(file, fileName, counts);
  }

  // ---------------------------------------------------------------------
  // Restore, part 1: check the file and stage it (live data untouched)
  // ---------------------------------------------------------------------

  static BackupException _damaged() => BackupException(
      'This backup file is damaged or incomplete. Nothing was changed.');

  /// Checks a backup file completely and stages it. Throws
  /// [BackupException] with a plain message if anything is wrong. Live data
  /// is not touched. Follow with [commitRestore] or [cancelRestore].
  static Future<RestorePreview> prepareRestore(File file) async {
    final dir = await _docs();

    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      root = decoded;
    } catch (_) {
      throw BackupException(
          'This file is not a Printiverse backup. Nothing was changed.');
    }
    if (root['format'] != formatId) {
      throw BackupException(
          'This file is not a Printiverse backup. Nothing was changed.');
    }
    final version = root['schemaVersion'];
    if (version is! int) throw _damaged();
    if (version > schemaVersion) {
      throw BackupException(
          'This backup was made by a newer version of the app (backup format $version). Update the app on this device first. Nothing was changed.');
    }
    final rawBoxes = root['boxes'];
    if (rawBoxes is! List) throw _damaged();

    final known = allBoxNames;
    final entries = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final raw in rawBoxes) {
      if (raw is! Map<String, dynamic>) throw _damaged();
      final name = raw['name'];
      if (name is! String || !known.contains(name) || !seen.add(name)) {
        throw BackupException(
            'This backup holds data this version of the app does not recognise. Nothing was changed.');
      }
      entries.add(raw);
    }

    final decodedBytes = <String, List<int>>{};
    for (final e in entries) {
      final data = e['data'];
      final records = e['records'];
      if (data is! String || records is! int) throw _damaged();
      List<int> bytes;
      try {
        bytes = base64Decode(data);
      } catch (_) {
        throw _damaged();
      }
      if (bytes.length != e['bytes'] ||
          sha256.convert(bytes).toString() != e['sha256']) {
        throw _damaged();
      }
      decodedBytes[e['name'] as String] = bytes;
    }
    if (_checksumOf(entries) != root['checksum']) throw _damaged();

    // Stage, then open each part as a temporary box to prove it reads and
    // that the record counts match what the backup says.
    final pending = Directory('${dir.path}/$_pendingDir');
    final check = Directory('${dir.path}/$_checkDir');
    await _deleteDir(pending);
    await _deleteDir(check);
    await pending.create(recursive: true);
    await check.create(recursive: true);

    final counts = <String, int>{};
    try {
      for (final e in entries) {
        final name = e['name'] as String;
        final bytes = decodedBytes[name]!;
        final lower = name.toLowerCase();
        await File('${pending.path}/$lower.hive')
            .writeAsBytes(bytes, flush: true);
        await File('${check.path}/rv_$lower.hive')
            .writeAsBytes(bytes, flush: true);
        final box =
            await Hive.openBox<dynamic>('rv_$lower', path: check.path);
        final n = box.length;
        await box.close();
        if (n != e['records']) throw _damaged();
        counts[name] = n;
      }
      await File('${pending.path}/manifest.json').writeAsString(
        jsonEncode(<String, dynamic>{
          'createdAt': root['createdAt'],
          'appVersion': root['appVersion'],
          'boxes': <Map<String, dynamic>>[
            for (final entry in counts.entries)
              <String, dynamic>{'name': entry.key, 'records': entry.value},
          ],
        }),
        flush: true,
      );
    } catch (e) {
      await _deleteDir(pending);
      await _deleteDir(check);
      if (e is BackupException) rethrow;
      throw BackupException(
          'The backup could not be read ($e). Nothing was changed.');
    }
    await _deleteDir(check);

    final created = root['createdAt'];
    final version2 = root['appVersion'];
    return RestorePreview(
      createdAt: created is String ? DateTime.tryParse(created) : null,
      appVersion: version2 is String ? version2 : '',
      counts: counts,
    );
  }

  /// Marks the staged restore ready. It is applied at the next app start.
  static Future<void> commitRestore() async {
    final dir = await _docs();
    final pending = Directory('${dir.path}/$_pendingDir');
    if (!await File('${pending.path}/manifest.json').exists()) {
      throw BackupException('There is no restore waiting. Start again.');
    }
    await File('${pending.path}/READY')
        .writeAsString(DateTime.now().toIso8601String(), flush: true);
  }

  /// Throws away a staged restore that was not committed.
  static Future<void> cancelRestore() async {
    final dir = await _docs();
    await _deleteDir(Directory('${dir.path}/$_pendingDir'));
    await _deleteDir(Directory('${dir.path}/$_checkDir'));
  }

  // ---------------------------------------------------------------------
  // Restore, part 2: runs once at app start, before any box is opened
  // ---------------------------------------------------------------------

  /// Finishes a restore that was staged and committed. Call after the
  /// adapters are registered and before the app opens its own boxes.
  /// Never throws.
  static Future<void> applyPendingRestore() async {
    try {
      final dir = await _docs();
      final pending = Directory('${dir.path}/$_pendingDir');
      if (!await pending.exists()) return;
      if (!await File('${pending.path}/READY').exists()) {
        // Staged but never confirmed: forget it.
        await _deleteDir(pending);
        return;
      }
      await _apply(dir, pending);
    } catch (e) {
      debugPrint('Restore step failed: $e');
    }
  }

  static Future<void> _apply(Directory dir, Directory pending) async {
    final counts = <String, int>{};
    String? backupCreatedAt;
    try {
      final manifest = jsonDecode(
          await File('${pending.path}/manifest.json').readAsString());
      backupCreatedAt = manifest['createdAt'] as String?;
      for (final b in (manifest['boxes'] as List)) {
        counts[b['name'] as String] = b['records'] as int;
      }
    } catch (e) {
      await _recordRestore(<String, dynamic>{
        'ok': false,
        'at': DateTime.now().toIso8601String(),
        'message':
            'The restore could not start, so nothing was changed ($e).',
      });
      await _deleteDir(pending);
      return;
    }

    final now = DateTime.now();
    final snapName = 'pre_restore_${_stamp(now)}';
    final snapDir = Directory('${dir.path}/$_snapshotRoot/$snapName');

    // 1. Snapshot the current data.
    try {
      await snapDir.create(recursive: true);
      for (final name in allBoxNames) {
        final live = File(_fileFor(dir, name));
        if (await live.exists()) {
          await live.copy('${snapDir.path}/${name.toLowerCase()}.hive');
        }
      }
    } catch (e) {
      await _recordRestore(<String, dynamic>{
        'ok': false,
        'at': now.toIso8601String(),
        'message':
            'A safety copy of the current data could not be made, so nothing was changed ($e).',
      });
      await _deleteDir(pending);
      return;
    }

    // 2. Swap the files in, then check the record counts.
    try {
      for (final name in allBoxNames) {
        final lower = name.toLowerCase();
        final live = File(_fileFor(dir, name));
        final staged = File('${pending.path}/$lower.hive');
        if (await staged.exists()) {
          final tmp = File('${live.path}.restore_tmp');
          await staged.copy(tmp.path);
          await tmp.rename(live.path);
        } else if (await live.exists()) {
          // Not in the backup (an older backup): the box comes back empty.
          await live.delete();
        }
        final compaction = File('${live.path}c');
        if (await compaction.exists()) await compaction.delete();
      }
      for (final entry in counts.entries) {
        final box = await Hive.openBox<dynamic>(entry.key);
        final n = box.length;
        await box.close();
        if (n != entry.value) {
          throw BackupException(
              '${labelFor(entry.key)}: expected ${entry.value}, found $n');
        }
      }
    } catch (e) {
      final rolledBack = await _rollback(dir, snapDir);
      await _recordRestore(<String, dynamic>{
        'ok': false,
        'at': now.toIso8601String(),
        'message': rolledBack
            ? 'The restore failed and your previous data was put back ($e).'
            : 'The restore failed and putting the previous data back also hit a problem ($e). A safety copy is in $snapName.',
      });
      await _deleteDir(pending);
      return;
    }

    await _recordRestore(<String, dynamic>{
      'ok': true,
      'at': now.toIso8601String(),
      'backupCreatedAt': backupCreatedAt,
      'counts': counts,
      'snapshot': snapName,
    });
    await _deleteDir(pending);
    await _pruneSnapshots(dir);
  }

  static Future<bool> _rollback(Directory dir, Directory snapDir) async {
    var allGood = true;
    for (final name in allBoxNames) {
      try {
        if (Hive.isBoxOpen(name)) await Hive.box(name).close();
        final live = File(_fileFor(dir, name));
        final snap = File('${snapDir.path}/${name.toLowerCase()}.hive');
        if (await snap.exists()) {
          final tmp = File('${live.path}.restore_tmp');
          await snap.copy(tmp.path);
          await tmp.rename(live.path);
        } else if (await live.exists()) {
          await live.delete();
        }
      } catch (e) {
        allGood = false;
        debugPrint('Rollback of $name failed: $e');
      }
    }
    return allGood;
  }

  static Future<void> _pruneSnapshots(Directory dir) async {
    try {
      final root = Directory('${dir.path}/$_snapshotRoot');
      if (!await root.exists()) return;
      final dirs = <Directory>[
        await for (final e in root.list())
          if (e is Directory) e,
      ];
      dirs.sort((a, b) => a.path.compareTo(b.path));
      while (dirs.length > _keepSnapshots) {
        await _deleteDir(dirs.removeAt(0));
      }
    } catch (_) {}
  }
}
