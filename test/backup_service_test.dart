import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:receipt_generator/features/finance/backup_service.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup_test_');
    BackupService.directoryOverride = dir;
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    BackupService.directoryOverride = null;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('backup then restore brings the old data back', () async {
    final receipts = await Hive.openBox<dynamic>('receipts_box');
    await receipts.add('R1');
    await receipts.add('R2');
    final loans = await Hive.openBox<dynamic>('loans_box');
    await loans.add('L1');

    final backup = await BackupService.createBackup();
    expect(backup.counts['receipts_box'], 2);
    expect(backup.counts['loans_box'], 1);
    expect(backup.counts['assets_box'], 0);

    // Things change after the backup was made.
    await receipts.add('R3');
    final assets = await Hive.openBox<dynamic>('assets_box');
    await assets.add('A1');

    final preview = await BackupService.prepareRestore(backup.file);
    expect(preview.counts['receipts_box'], 2);
    await BackupService.commitRestore();

    await Hive.close();
    await BackupService.applyPendingRestore();

    final r = await Hive.openBox<dynamic>('receipts_box');
    expect(r.values.toList(), ['R1', 'R2']);
    final l = await Hive.openBox<dynamic>('loans_box');
    expect(l.values.toList(), ['L1']);
    // Not in the backup, so it comes back empty.
    final a = await Hive.openBox<dynamic>('assets_box');
    expect(a.isEmpty, isTrue);

    final info = BackupService.lastRestore();
    expect(info, isNotNull);
    expect(info!['ok'], isTrue);
  });

  test('a file that is not a backup is refused and nothing changes', () async {
    final receipts = await Hive.openBox<dynamic>('receipts_box');
    await receipts.add('R1');

    final junk = File('${dir.path}/junk.json')..writeAsStringSync('not json');
    await expectLater(
        BackupService.prepareRestore(junk), throwsA(isA<BackupException>()));
    expect(receipts.length, 1);
  });

  test('a backup from a newer app version is refused', () async {
    final newer = File('${dir.path}/newer.json')
      ..writeAsStringSync(jsonEncode(<String, dynamic>{
        'format': BackupService.formatId,
        'schemaVersion': BackupService.schemaVersion + 1,
        'boxes': <dynamic>[],
      }));
    await expectLater(
      BackupService.prepareRestore(newer),
      throwsA(predicate((e) => e is BackupException && '$e'.contains('newer'))),
    );
  });

  test('a changed backup file fails the integrity check', () async {
    final receipts = await Hive.openBox<dynamic>('receipts_box');
    await receipts.add('R1');
    final backup = await BackupService.createBackup();

    final root =
        jsonDecode(backup.file.readAsStringSync()) as Map<String, dynamic>;
    final boxes = root['boxes'] as List;
    (boxes.first as Map<String, dynamic>)['sha256'] = 'tampered';
    backup.file.writeAsStringSync(jsonEncode(root));

    await expectLater(BackupService.prepareRestore(backup.file),
        throwsA(isA<BackupException>()));
    expect(receipts.length, 1);
  });

  test('a restore that fails part-way puts the old data back', () async {
    final receipts = await Hive.openBox<dynamic>('receipts_box');
    await receipts.add('R1');
    final backup = await BackupService.createBackup();
    await receipts.add('R2'); // live data now differs from the backup

    await BackupService.prepareRestore(backup.file);
    await BackupService.commitRestore();

    // Damage the staged copy, as an interrupted or broken restore would.
    File('${dir.path}/restore_pending/receipts_box.hive')
        .writeAsBytesSync(<int>[1, 2, 3]);

    await Hive.close();
    await BackupService.applyPendingRestore();

    final info = BackupService.lastRestore();
    expect(info, isNotNull);
    expect(info!['ok'], isFalse);

    final r = await Hive.openBox<dynamic>('receipts_box');
    expect(r.values.toList(), ['R1', 'R2']);
  });

  test('a staged restore that was never confirmed is ignored', () async {
    final receipts = await Hive.openBox<dynamic>('receipts_box');
    await receipts.add('R1');
    final backup = await BackupService.createBackup();
    await receipts.add('R2');

    await BackupService.prepareRestore(backup.file); // no commit
    await Hive.close();
    await BackupService.applyPendingRestore();

    final r = await Hive.openBox<dynamic>('receipts_box');
    expect(r.values.toList(), ['R1', 'R2']);
  });

  group('backup reminders', () {
    Future<void> setLast(DateTime? d) async {
      await BackupService.openMeta();
      final meta = Hive.box<String>(BackupService.metaBoxName);
      if (d == null) {
        await meta.delete('last_backup_at');
      } else {
        await meta.put('last_backup_at', d.toIso8601String());
      }
    }

    test('asks for a backup when none was ever made', () async {
      await setLast(null);
      expect(BackupService.reminderMessage(now: DateTime(2026, 6, 15)),
          contains('No backup'));
    });

    test('quiet when the last backup is recent', () async {
      await setLast(DateTime(2026, 6, 14));
      expect(BackupService.reminderMessage(now: DateTime(2026, 6, 15)), isNull);
    });

    test('asks again after 7 days', () async {
      await setLast(DateTime(2026, 6, 1));
      expect(BackupService.reminderMessage(now: DateTime(2026, 6, 15)),
          contains('7 days'));
    });

    test('asks when a new financial year has started since the last backup',
        () async {
      await setLast(DateTime(2025, 12, 30));
      expect(
          BackupService.reminderMessage(
              startMonth: 1, now: DateTime(2026, 1, 3)),
          contains('financial year'));
      await setLast(DateTime(2026, 1, 2));
      expect(
          BackupService.reminderMessage(
              startMonth: 1, now: DateTime(2026, 1, 3)),
          isNull);
    });
  });
}
