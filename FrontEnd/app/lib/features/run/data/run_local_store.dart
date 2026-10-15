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
  Future<List<LocalRun>> list(
    String owner, {
    bool summaryOnly = false,
    bool pendingOnly = false,
    bool unfinishedOnly = false,
    String? id,
  });
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
        version: 3,
        onUpgrade: (db, old, _) async {
          if (old < 2) await _createExtras(db);
          if (old < 3) {
            await db.execute('ALTER TABLE sessions ADD COLUMN summary TEXT');
          }
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
            "CREATE UNIQUE INDEX one_active_run ON sessions(owner) WHERE phase <> 'ended'",
          );
          await db.execute(
            'CREATE TABLE inputs (session_id TEXT NOT NULL REFERENCES sessions(id), seq INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(session_id,seq))',
          );
          await _createExtras(db);
          await db.execute('ALTER TABLE sessions ADD COLUMN summary TEXT');
        },
      ),
    );
  }

  @override
  Future<void> create(LocalRun run, RunInput start) async {
    final db = await database;
    await db.transaction((tx) async {
      if ((await tx.query(
        'run_deletions',
        columns: ['id'],
        where: 'id=?',
        whereArgs: [run.id],
      )).isNotEmpty) {
        throw StateError('삭제한 기록 ID는 다시 사용할 수 없어요.');
      }
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
      if (phase == RunPhase.ended) {
        final row = (await tx.query(
          'sessions',
          where: 'id=? AND owner=?',
          whereArgs: [run.id, run.owner],
        )).single;
        final raw = await tx.query(
          'inputs',
          where: 'session_id=?',
          whereArgs: [run.id],
          orderBy: 'seq',
        );
        await tx.update(
          'sessions',
          {'summary': jsonEncode(_summary(row, _inputs(raw)))},
          where: 'id=? AND owner=?',
          whereArgs: [run.id, run.owner],
        );
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
  Future<List<LocalRun>> list(
    String owner, {
    bool summaryOnly = false,
    bool pendingOnly = false,
    bool unfinishedOnly = false,
    String? id,
  }) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      columns: summaryOnly
          ? [
              'id',
              'owner',
              'started_at',
              'phase',
              'checkpoint_ms',
              'pending',
              'end_reason',
              'sync_state',
              'sync_failure',
              'summary',
            ]
          : null,
      where:
          'owner=? AND id NOT IN (SELECT id FROM run_deletions WHERE owner=?)'
          '${summaryOnly ? " AND phase='ended'" : ""}'
          '${pendingOnly ? " AND pending=1 AND phase='ended'" : ""}'
          '${unfinishedOnly ? " AND phase<>'ended'" : ""}'
          '${id == null ? "" : " AND id=?"}',
      whereArgs: [owner, owner, ?id],
      orderBy: 'started_at DESC',
    );
    final result = <LocalRun>[];
    for (final row in rows) {
      final raw = summaryOnly && row['summary'] != null
          ? <Map<String, Object?>>[]
          : await db.query(
              'inputs',
              where: 'session_id=?',
              whereArgs: [row['id']],
              orderBy: 'seq',
            );
      Map<String, dynamic>? summary = row['summary'] == null
          ? null
          : (jsonDecode(row['summary'] as String) as Map)
                .cast<String, dynamic>();
      if (summaryOnly && summary == null) {
        // Backfill old rows once, preserving the original calculation version.
        final full = (await db.query(
          'sessions',
          where: 'id=? AND owner=?',
          whereArgs: [row['id'], owner],
        )).firstOrNull;
        if (full == null) continue;
        summary = _summary(full, _inputs(raw));
        await db.update(
          'sessions',
          {'summary': jsonEncode(summary)},
          where: 'id=? AND owner=? AND summary IS NULL',
          whereArgs: [row['id'], owner],
        );
      }
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
          summary: summary,
          inputsLoaded: !summaryOnly,
          result: row['result'] == null
              ? null
              : (jsonDecode(row['result'] as String) as Map)
                    .cast<String, dynamic>(),
          inputs: (summaryOnly ? <Map<String, Object?>>[] : raw)
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
    if (result['id'] != run.id) throw StateError('다른 러닝 기록의 결과는 저장할 수 없어요.');
    final summary = _resultSummary(result);
    final updated = await db.update(
      'sessions',
      {
        'pending': 0,
        'summary': jsonEncode(summary),
        'result': jsonEncode(result),
        'sync_state': 'synced',
        'sync_failure': null,
      },
      where: 'id=? AND owner=? AND phase=?',
      whereArgs: [run.id, run.owner, 'ended'],
    );
    if (updated != 1) return;
    run.summary = summary;
    run.pending = false;
    run.result = result;
    run.syncState = 'synced';
    run.syncFailure = null;
  }

  static List<RunInput> _inputs(List<Map<String, Object?>> raw) => raw
      .map(
        (r) => RunInput.fromJson(
          (jsonDecode(r['payload'] as String) as Map).cast<String, dynamic>(),
        ),
      )
      .toList();

  static Map<String, dynamic> _resultSummary(Map<String, dynamic> result) => {
    for (final key in [
      'id',
      'startedAt',
      'endedAt',
      'registeredAt',
      'endReason',
      'metrics',
      'policyVersion',
      'calculationVersion',
    ])
      if (result.containsKey(key)) key: result[key],
  };

  static Map<String, dynamic> _summary(
    Map<String, Object?> row,
    List<RunInput> inputs,
  ) {
    if (row['result'] != null) {
      return _resultSummary(
        (jsonDecode(row['result'] as String) as Map).cast<String, dynamic>(),
      );
    }
    final startedAt = DateTime.parse(row['started_at'] as String);
    final ms = row['checkpoint_ms'] as int;
    return {
      'id': row['id'],
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': startedAt
          .add(Duration(milliseconds: ms))
          .toUtc()
          .toIso8601String(),
      'endReason': row['end_reason'],
      'metrics': RunCalculator.replay(inputs).at(ms).toJson(),
      'calculationVersion': inputs.firstOrNull?.reason,
    };
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
