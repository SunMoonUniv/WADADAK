import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../domain/recording_models.dart';
import '../domain/run_voice.dart';

abstract interface class RunStore {
  Future<void> create(LocalRun run, RunInput start);
  Future<void> append(
    LocalRun run,
    List<RunInput> inputs,
    RunPhase phase,
    int checkpointMs, {
    bool pending = false,
    String? endReason,
  });
  Future<void> checkpoint(LocalRun run, int elapsedMs);
  Future<List<LocalRun>> list(String owner);
  Future<void> synced(LocalRun run, Map<String, dynamic> result);
  Future<void> syncStatus(LocalRun run, String state, {String? failure});
}

abstract interface class RunHistoryStore {
  Future<Set<String>> deletedIds(String owner);
  Future<List<String>> pendingDeletions(String owner);
  Future<void> deleteRecord(String owner, String id);
  Future<void> deletionSynced(String owner, String id);
}

class RunLocalStore implements RunStore, RunHistoryStore {
  RunLocalStore({this.factory, this.databasePath});
  final DatabaseFactory? factory;
  final String? databasePath;
  Future<Database>? _database;
  Future<Database> get database => _database ??= _open();
  Future<Database> _open() async {
    final dbFactory = factory ?? databaseFactory;
    return dbFactory.openDatabase(
      databasePath ??
          path.join(await dbFactory.getDatabasesPath(), 'runs_v1.db'),
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (db, old, _) async {
          if (old < 2) await _createExtras(db);
        },
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE sessions (id TEXT PRIMARY KEY, owner TEXT NOT NULL, started_at TEXT NOT NULL, phase TEXT NOT NULL, checkpoint_ms INTEGER NOT NULL, pending INTEGER NOT NULL DEFAULT 0, end_reason TEXT, result TEXT, sync_state TEXT NOT NULL DEFAULT \'pending\', sync_failure TEXT)',
          );
          await db.execute(
            'CREATE INDEX sessions_owner ON sessions(owner, started_at)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX one_active_run ON sessions(owner) WHERE phase <> \'ended\'',
          );
          await db.execute(
            'CREATE TABLE inputs (session_id TEXT NOT NULL REFERENCES sessions(id), seq INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(session_id,seq))',
          );
          await _createExtras(db);
        },
      ),
    );
  }

  @override
  Future<void> create(LocalRun run, RunInput start) async {
    final db = await database;
    await db.transaction((tx) async {
      await tx.insert('sessions', {
        'id': run.id,
        'owner': run.owner,
        'started_at': run.startedAt.toUtc().toIso8601String(),
        'phase': 'running',
        'checkpoint_ms': 0,
        'pending': 0,
      });
      await tx.insert('inputs', {
        'session_id': run.id,
        'seq': start.seq,
        'payload': jsonEncode(start.toJson()),
      });
    });
  }

  @override
  Future<void> append(
    LocalRun run,
    List<RunInput> inputs,
    RunPhase phase,
    int checkpointMs, {
    bool pending = false,
    String? endReason,
  }) async {
    final db = await database;
    await db.transaction((tx) async {
      for (final input in inputs) {
        await tx.insert('inputs', {
          'session_id': run.id,
          'seq': input.seq,
          'payload': jsonEncode(input.toJson()),
        });
      }
      final updated = await tx.update(
        'sessions',
        {
          'phase': phase.name,
          'checkpoint_ms': checkpointMs,
          'pending': pending ? 1 : 0,
          'end_reason': endReason,
        },
        where: 'id=? AND owner=? AND phase <> ?',
        whereArgs: [run.id, run.owner, 'ended'],
      );
      if (updated != 1) {
        throw StateError('종료된 기록에는 입력을 추가할 수 없어요.');
      }
    });
  }

  @override
  Future<void> checkpoint(LocalRun run, int elapsedMs) async {
    final db = await database;
    await db.update(
      'sessions',
      {'checkpoint_ms': elapsedMs},
      where: 'id=? AND owner=? AND phase <> ?',
      whereArgs: [run.id, run.owner, 'ended'],
    );
  }

  @override
  Future<List<LocalRun>> list(String owner) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where:
          'owner=? AND id NOT IN (SELECT id FROM run_deletions WHERE owner=?)',
      whereArgs: [owner, owner],
      orderBy: 'started_at DESC',
    );
    final result = <LocalRun>[];
    for (final row in rows) {
      final raw = await db.query(
        'inputs',
        where: 'session_id=?',
        whereArgs: [row['id']],
        orderBy: 'seq',
      );
      result.add(
        LocalRun(
          id: row['id'] as String,
          owner: owner,
          startedAt: DateTime.parse(row['started_at'] as String),
          phase: RunPhase.values.byName(row['phase'] as String),
          checkpointMs: row['checkpoint_ms'] as int,
          pending: row['pending'] == 1,
          endReason: row['end_reason'] as String?,
          syncState: row['sync_state'] as String,
          syncFailure: row['sync_failure'] as String?,
          result: row['result'] == null
              ? null
              : (jsonDecode(row['result'] as String) as Map)
                    .cast<String, dynamic>(),
          inputs: raw
              .map(
                (r) => RunInput.fromJson(
                  (jsonDecode(r['payload'] as String) as Map)
                      .cast<String, dynamic>(),
                ),
              )
              .toList(),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> synced(LocalRun run, Map<String, dynamic> result) async {
    final db = await database;
    await db.update(
      'sessions',
      {
        'pending': 0,
        'result': jsonEncode(result),
        'sync_state': 'synced',
        'sync_failure': null,
      },
      where: 'id=? AND owner=? AND phase=?',
      whereArgs: [run.id, run.owner, 'ended'],
    );
    run.pending = false;
    run.result = result;
    run.syncState = 'synced';
    run.syncFailure = null;
  }

  @override
  Future<void> syncStatus(LocalRun run, String state, {String? failure}) async {
    final db = await database;
    await db.update(
      'sessions',
      {'sync_state': state, 'sync_failure': failure},
      where: 'id=? AND owner=?',
      whereArgs: [run.id, run.owner],
    );
    run.syncState = state;
    run.syncFailure = failure;
  }

  static Future<void> _createExtras(Database db) async {
    await db.execute(
      'CREATE TABLE run_deletions (owner TEXT NOT NULL, id TEXT NOT NULL, pending INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(owner,id))',
    );
    await db.execute(
      'CREATE TABLE run_settings (owner TEXT PRIMARY KEY, payload TEXT NOT NULL)',
    );
  }

  @override
  Future<Set<String>> deletedIds(String owner) async =>
      (await (await database).query(
        'run_deletions',
        columns: ['id'],
        where: 'owner=?',
        whereArgs: [owner],
      )).map((r) => r['id'] as String).toSet();
  @override
  Future<List<String>> pendingDeletions(String owner) async =>
      (await (await database).query(
        'run_deletions',
        columns: ['id'],
        where: 'owner=? AND pending=1',
        whereArgs: [owner],
      )).map((r) => r['id'] as String).toList();
  @override
  Future<void> deleteRecord(String owner, String id) async {
    await (await database).transaction((tx) async {
      final local = await tx.query('sessions', where: 'id=?', whereArgs: [id]);
      if (local.isNotEmpty &&
          (local.single['owner'] != owner ||
              local.single['phase'] != 'ended')) {
        throw StateError('이 기록은 삭제할 수 없어요.');
      }
      await tx.insert('run_deletions', {
        'owner': owner,
        'id': id,
        'pending': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await tx.delete(
        'inputs',
        where: 'session_id IN (SELECT id FROM sessions WHERE id=? AND owner=?)',
        whereArgs: [id, owner],
      );
      await tx.delete(
        'sessions',
        where: 'id=? AND owner=? AND phase=?',
        whereArgs: [id, owner, 'ended'],
      );
    });
  }

  @override
  Future<void> deletionSynced(String owner, String id) async {
    await (await database).update(
      'run_deletions',
      {'pending': 0},
      where: 'owner=? AND id=?',
      whereArgs: [owner, id],
    );
  }

  Future<RunVoiceSettings> voiceSettings(String owner) async {
    final rows = await (await database).query(
      'run_settings',
      where: 'owner=?',
      whereArgs: [owner],
    );
    return rows.isEmpty
        ? const RunVoiceSettings()
        : RunVoiceSettings.fromJson(
            (jsonDecode(rows.single['payload'] as String) as Map)
                .cast<String, dynamic>(),
          );
  }

  Future<void> saveVoiceSettings(
    String owner,
    RunVoiceSettings settings,
  ) async {
    await (await database).insert('run_settings', {
      'owner': owner,
      'payload': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async {
    if (_database != null) {
      await (await _database!).close();
    }
  }
}
