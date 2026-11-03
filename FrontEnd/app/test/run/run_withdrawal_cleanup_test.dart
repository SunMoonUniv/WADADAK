import 'dart:io';

import 'package:flutter/widgets.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/run_voice.dart';

import 'recording/run_controller_test.dart' show TestLocation, TestApi, until;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  test('erases only withdrawn owner, blocks late writes and retains other accounts', () async {
    final store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final date = DateTime.utc(2026);
    final input = RunInput(
      seq: 0,
      kind: RunKind.start,
      elapsedMs: 0,
      measuredAt: date,
    );
    for (final owner in ['alice', 'bob']) {
      await store.create(
        LocalRun(id: owner, owner: owner, startedAt: date),
        input,
      );
      await store.saveVoiceSettings(owner, const RunVoiceSettings());
    }
    await store.purgeWithdrawnOwner('alice');
    expect(await store.list('alice'), isEmpty);
    expect(await store.list('bob'), hasLength(1));
    expect(
      await (await store.database).query(
        'inputs',
        where: 'session_id=?',
        whereArgs: ['alice'],
      ),
      isEmpty,
    );
    await expectLater(
      store.create(
        LocalRun(id: 'late', owner: 'alice', startedAt: date),
        input,
      ),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      store.saveVoiceSettings('alice', const RunVoiceSettings()),
      throwsA(isA<DatabaseException>()),
    );
    await store.purgeWithdrawnOwner('alice');
    expect(await store.list('bob'), hasLength(1));
    expect(
      jsonEncode(await (await store.database).query('withdrawn_run_owners')),
      isNot(contains('GPS')),
    );
  });
  test('stops active producers and cannot rebind a withdrawn owner from old tokens', () async {
    final store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final gps = TestLocation();
    final runs = RunController(
      store,
      gps,
      TestApi(),
      () async => 'alice',
      nowMs: gps.nowMs,
      utcNow: () => gps.utc,
      automaticTicks: false,
      lifecycleState: () => AppLifecycleState.resumed,
      wait: (_) async {},
    );
    await runs.bindOwner();
    await runs.prepareStart();
    expect(runs.recorder.active, true);
    await runs.purgeWithdrawnOwner('alice');
    await runs.bindOwner();
    expect(runs.currentOwner, isNull);
    expect(runs.run, isNull);
    await runs.recorder.gps(36, 127, 3);
    expect(await store.list('alice'), isEmpty);
    await until(() => !runs.syncing && !runs.loadingHistory);
    await runs.shutdown();
    runs.dispose();
    for (final stream in gps.streams) {
      await stream.close();
    }
  });

  test(
    'failed erasure keeps a durable retry marker and completes on reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'withdrawal-retry-',
      );
      final file = '${directory.path}/runs.db';
      var store = RunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: file,
      );
      final date = DateTime.utc(2026);
      final start = RunInput(
        seq: 0,
        kind: RunKind.start,
        elapsedMs: 0,
        measuredAt: date,
      );
      for (final owner in ['alice', 'bob']) {
        await store.create(
          LocalRun(id: owner, owner: owner, startedAt: date),
          start,
        );
        await store.saveVoiceSettings(owner, const RunVoiceSettings());
      }
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER fail_purge BEFORE DELETE ON run_settings "
        "WHEN OLD.owner='alice' BEGIN SELECT RAISE(ABORT,'disk error'); END",
      );
      await expectLater(
        store.purgeWithdrawnOwner('alice'),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await db.query('sessions', where: 'owner=?', whereArgs: ['alice']),
        hasLength(1),
      );
      expect(await db.query('withdrawn_run_owners'), hasLength(1));
      await db.execute('DROP TRIGGER fail_purge');
      await store.close();
      store = RunLocalStore(factory: databaseFactoryFfi, databasePath: file);
      expect(await store.list('alice'), isEmpty);
      expect(await store.list('bob'), hasLength(1));
      await store.close();
      await directory.delete(recursive: true);
    },
  );
}
