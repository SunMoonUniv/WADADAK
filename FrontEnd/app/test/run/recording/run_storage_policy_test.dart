import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late RunLocalStore store;
  late LocalRun run;
  late List<RunInput> inputs;
  final start = DateTime.utc(2026, 10, 12);

  setUp(() async {
    store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final fixture = jsonDecode(
      File('../../run/fixtures/free_pause_v1.json').readAsStringSync(),
    ) as Map;
    inputs = (fixture['inputs'] as List)
        .map((j) => RunInput.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
    run = LocalRun(
      id: 'record',
      owner: 'alice',
      startedAt: start,
      phase: RunPhase.ended,
      pending: true,
    );
    await store.create(run, inputs.first);
    await store.append(
      run,
      inputs.sublist(1),
      RunPhase.ended,
      inputs.last.elapsedMs,
      pending: true,
    );
  });
  tearDown(() async => store.close());

  test('summary reads exclude original GPS and full result while keeping detail available', () async {
    final summary = (await store.list('alice', summaryOnly: true)).single;
    expect(summary.inputsLoaded, false);
    expect(summary.inputs, isEmpty);
    expect(summary.result, isNull);
    expect(
      summary.summary!['metrics']['distanceM'],
      closeTo(22.239016, .000001),
    );
    expect(summary.summary, isNot(contains('routeSegments')));
    expect(summary.summary, isNot(contains('laps')));
    final detail = (await store.list('alice', id: run.id)).single;
    expect(detail.inputs.map((p) => p.toJson()), inputs.map((p) => p.toJson()));

    // A list must not decode either large payload, even when they are unreadable.
    final db = await store.database;
    await db.update('inputs', {'payload': 'unreadable GPS'});
    await db.update('sessions', {'result': 'unreadable route'});
    expect(
      (await store.list('alice', summaryOnly: true)).single.summary,
      summary.summary,
    );
  });

  test(
    'confirmed result replaces summary without changing original inputs',
    () async {
      final server = {
        'id': run.id,
        'startedAt': start.toIso8601String(),
        'registeredAt': '2026-10-15T00:00:00Z',
        'metrics': {'distanceM': 999.0, 'elapsedMs': 120000},
        'routeSegments': <Object>[],
        'laps': <Object>[],
      };
      await store.synced(run, server);
      final summary = (await store.list('alice', summaryOnly: true)).single;
      expect(summary.summary!['metrics']['distanceM'], 999.0);
      expect(summary.syncState, 'synced');
      expect(await store.list('alice', pendingOnly: true), isEmpty);
      final detail = (await store.list('alice', id: run.id)).single;
      expect(
        detail.inputs.map((p) => p.toJson()),
        inputs.map((p) => p.toJson()),
      );
      expect(detail.result, server);
    },
  );

  test('deleted ID cannot recreate original coordinates and late result is ignored', () async {
    await store.deleteRecord('alice', run.id);
    await expectLater(store.create(run, inputs.first), throwsStateError);
    await expectLater(
      store.create(
        LocalRun(id: run.id, owner: 'bob', startedAt: start),
        inputs.first,
      ),
      throwsStateError,
    );
    await store.synced(run, {'id': run.id});
    expect(run.pending, true);
    expect(run.result, isNull);
    expect(await store.list('alice'), isEmpty);
    final db = await store.database;
    expect(
      (await db.rawQuery('SELECT count(*) FROM inputs')).single.values.single,
      0,
    );
    expect(await store.deletedIds('alice'), {run.id});
  });

  test(
    'a response for a different ID never confirms pending original data',
    () async {
      await expectLater(
        store.synced(run, {'id': 'different'}),
        throwsStateError,
      );
      expect((await store.list('alice')).single.pending, true);
    },
  );

  test('v2 upgrade backfills once and preserves raw source and confirmed registration', () async {
    final dir = await Directory.systemTemp.createTemp('run-storage-upgrade-');
    final path = '${dir.path}/runs.db';
    var disk = RunLocalStore(factory: databaseFactoryFfi, databasePath: path);
    try {
      await disk.create(run, inputs.first);
      await disk.append(
        run,
        inputs.sublist(1),
        RunPhase.ended,
        inputs.last.elapsedMs,
        pending: true,
      );
      final result = {
        'id': run.id,
        'startedAt': start.toIso8601String(),
        'registeredAt': '2026-10-13T00:00:00Z',
        'metrics': {'distanceM': 789.0},
        'routeSegments': <Object>[],
      };
      await disk.synced(run, result);
      final db = await disk.database;
      await db.execute('ALTER TABLE sessions DROP COLUMN summary');
      // Reconstruct the actual pre-ghost v2 schema before exercising both upgrades.
      await db.execute('DROP TABLE ghost_closures');
      await db.execute('DROP TABLE ghost_start_intents');
      await db.execute('ALTER TABLE sessions DROP COLUMN ghost_context');
      await db.execute('ALTER TABLE sessions DROP COLUMN recovery_anchor');
      await db.execute('DROP TABLE course_start_intents');
      await db.execute('PRAGMA user_version=2');
      await disk.close();
      disk = RunLocalStore(factory: databaseFactoryFfi, databasePath: path);
      final summary = (await disk.list('alice', summaryOnly: true)).single;
      expect(summary.summary!['metrics']['distanceM'], 789.0);
      expect(summary.summary!['registeredAt'], '2026-10-13T00:00:00Z');
      final detail = (await disk.list('alice', id: run.id)).single;
      expect(
        detail.inputs.map((p) => p.toJson()),
        inputs.map((p) => p.toJson()),
      );
      expect(detail.result, result);
      expect(await disk.list('bob', summaryOnly: true), isEmpty);
    } finally {
      await disk.close();
      await dir.delete(recursive: true);
    }
  });
}
