import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

const tables = [
  'sessions',
  'inputs',
  'ghost_closures',
  'ghost_start_intents',
  'course_start_intents',
  'run_deletions',
  'run_settings',
];

Future<Map<String, Object>> snapshot(RunLocalStore store) async {
  final db = await store.database;
  return {
    for (final table in tables) table: await db.query(table, orderBy: 'rowid'),
  };
}

// Include stale receipts without a session and unreadable payloads: account
// deletion must not depend on decoding or recovering any individual record.
Future<void> seed(RunLocalStore store, String owner) async {
  final db = await store.database;
  for (final state in ['pending', 'synced', 'interrupted', 'paused']) {
    final id = '$owner-$state';
    await db.insert('sessions', {
      'id': id,
      'owner': owner,
      'started_at': '2026-11-03T00:00:00Z',
      'phase': state == 'paused' ? 'paused' : 'ended',
      'checkpoint_ms': 1000,
      'pending': state == 'pending' ? 1 : 0,
      'sync_state': state == 'synced' ? 'synced' : 'pending',
      'end_reason': state == 'interrupted' ? 'INTERRUPTED' : null,
      'result': jsonEncode({
        'id': id,
        'routeSegments': [
          [
            {'lat': 37.5, 'lng': 127.0},
          ],
        ],
      }),
      'summary': 'unreadable summary',
      'ghost_context': 'unreadable approval with route',
      'recovery_anchor': 'unreadable recovery anchor',
    });
    await db.insert('inputs', {
      'session_id': id,
      'seq': 0,
      'payload': 'GPS $owner 37.5 127.0',
    });
    await db.insert('ghost_closures', {'owner': owner, 'id': id});
  }
  await db.insert('ghost_start_intents', {
    'id': '$owner-ghost-draft',
    'owner': owner,
    'intent': 'unreadable ghost route',
    'approval': 'unreadable server approval',
    'checkpoint_clock': 'unreadable clock',
  });
  await db.insert('course_start_intents', {
    'id': '$owner-course-draft',
    'owner': owner,
    'intent': 'unreadable course route',
  });
  for (final pending in [0, 1]) {
    await db.insert('run_deletions', {
      'owner': owner,
      'id': '$owner-deleted-$pending',
      'pending': pending,
    });
  }
  await db.insert('run_settings', {
    'owner': owner,
    'payload': 'unreadable settings',
  });
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory dir;
  late RunLocalStore store;
  late String dbPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('run-owner-deletion-');
    dbPath = '${dir.path}/runs_v1.db';
    store = RunLocalStore(factory: databaseFactoryFfi, databasePath: dbPath);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'purges all owner data durably, preserving every row of other owners',
    () async {
      await seed(store, 'bob');
      final bob = await snapshot(store);
      await seed(store, 'alice');
      final db = await store.database;
      expect(
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );

      await store.deleteOwner('alice');
      expect(await snapshot(store), bob);
      expect(await store.list('alice'), isEmpty);
      expect(await store.deletedIds('alice'), isEmpty);
      expect(await store.pendingGhostStarts('alice'), isEmpty);
      expect(await store.pendingCourseStarts('alice'), isEmpty);
      expect(await store.pendingGhostClosures('alice'), isEmpty);

      await store.close();
      store = RunLocalStore(factory: databaseFactoryFfi, databasePath: dbPath);
      expect(await snapshot(store), bob);
      await store.deleteOwner('alice');
      await store.deleteOwner('missing');
      expect(await snapshot(store), bob);
    },
  );

  test(
    'an error rolls back GPS, sessions, receipts, queues and settings together',
    () async {
      await seed(store, 'alice');
      await seed(store, 'bob');
      final before = await snapshot(store);
      final db = await store.database;
      await db.execute('''
      CREATE TRIGGER fail_owner_cleanup BEFORE DELETE ON run_settings
      WHEN OLD.owner='alice'
      BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END
    ''');

      await expectLater(
        store.deleteOwner('alice'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await snapshot(store), before);
      await db.execute('DROP TRIGGER fail_owner_cleanup');
      await store.deleteOwner('alice');
      expect(
        (await db.query('sessions')).every((row) => row['owner'] == 'bob'),
        true,
      );
    },
  );

  test('owner matching is exact, including SQL punctuation', () async {
    await seed(store, "alice' OR 1=1 --");
    final kept = await snapshot(store);
    await seed(store, 'alice');
    await store.deleteOwner('alice');
    expect(await snapshot(store), kept);
    await store.deleteOwner("alice' OR 1=1 --");
    expect((await snapshot(store)).values, everyElement(isEmpty));
  });

  test('late sync updates cannot recreate a purged session or GPS', () async {
    final run = LocalRun(
      id: 'pending',
      owner: 'alice',
      startedAt: DateTime.utc(2026, 11, 3),
    );
    await store.create(
      run,
      RunInput(
        seq: 0,
        kind: RunKind.start,
        elapsedMs: 0,
        measuredAt: run.startedAt,
      ),
    );
    await store.append(
      run,
      [
        RunInput(
          seq: 1,
          kind: RunKind.end,
          elapsedMs: 1000,
          measuredAt: run.startedAt.add(const Duration(seconds: 1)),
          reason: 'INTERRUPTED',
        ),
      ],
      RunPhase.ended,
      1000,
      pending: true,
    );

    await store.deleteOwner('alice');
    await store.synced(run, {
      'id': run.id,
      'routeSegments': [
        [37.5, 127.0],
      ],
    });
    await store.syncStatus(run, 'pending');
    await store.deletionSynced('alice', run.id);
    await store.ghostClosureSynced('alice', run.id);
    expect((await snapshot(store)).values, everyElement(isEmpty));
  });
}
