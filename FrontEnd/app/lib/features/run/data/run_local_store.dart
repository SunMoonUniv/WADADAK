import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../domain/recording_models.dart';
import '../domain/run_calories.dart';
import '../domain/run_result_stats.dart';
import '../domain/run_voice.dart';
import '../domain/ghost_run.dart';
import '../domain/course_run.dart';
import '../../../core/time/monotonic_clock.dart';

typedef RunHeartRateSample = ({int measuredAtMs, int bpm});
const wearHeartRateClockSkewMs = 5000;

abstract interface class RunGhostStore {
  Future<void> saveGhostIntent(GhostStartIntent intent);
  Future<void> saveGhostApproval(
    GhostRunContext context, {
    RunClockSample? checkpointClock,
  });
  Future<List<PendingGhostStart>> pendingGhostStarts(String owner);
  Future<List<String>> pendingGhostClosures(String owner);
  Future<void> ghostClosureSynced(String owner, String id);
}

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

class RunLocalStore implements RunStore, RunHistoryStore, RunGhostStore {
  RunLocalStore({this.factory, this.databasePath});
  final DatabaseFactory? factory;
  final String? databasePath;
  Future<Database>? _database;
  final _heartRateChanges =
      StreamController<({String owner, String sessionId})>.broadcast();
  Future<Database> get database => _database ??= _open();
  Future<Database> _open() async {
    final dbFactory = factory ?? databaseFactory;
    return dbFactory.openDatabase(
      databasePath ??
          path.join(await dbFactory.getDatabasesPath(), 'runs_v1.db'),
      options: OpenDatabaseOptions(
        version: 7,
        onUpgrade: (db, old, _) async {
          if (old < 2) await _createExtras(db);
          if (old < 3) {
            await db.execute('ALTER TABLE sessions ADD COLUMN summary TEXT');
          }
          if (old < 4) await _createGhostStorage(db);
          if (old < 5) await _createCourseStarts(db);
          if (old < 6) await _createAccountAndGuidanceStorage(db);
          if (old < 7) await _createHeartRateStorage(db);
        },
        onOpen: _retryWithdrawnOwners,
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
          await _createGhostStorage(db);
          await _createCourseStarts(db);
          await _createAccountAndGuidanceStorage(db);
          await _createHeartRateStorage(db);
        },
      ),
    );
  }

  static Future<void> _createHeartRateStorage(Database db) => db.execute(
    'CREATE TABLE run_heart_rates ('
    'session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, '
    'measured_at_ms INTEGER NOT NULL, bpm INTEGER NOT NULL, '
    'PRIMARY KEY(session_id, measured_at_ms))',
  );

  static Future<void> _createAccountAndGuidanceStorage(Database db) async {
    await db.execute('ALTER TABLE sessions ADD COLUMN guidance_state TEXT');
    await db.execute(
      'CREATE TABLE withdrawn_run_owners (owner TEXT PRIMARY KEY)',
    );
    for (final table in [
      'sessions',
      'run_settings',
      'run_deletions',
      'course_start_intents',
      'ghost_start_intents',
      'ghost_closures',
    ]) {
      for (final action in ['INSERT', 'UPDATE']) {
        await db.execute(
          "CREATE TRIGGER ${table}_withdrawn_${action.toLowerCase()} "
          "BEFORE $action ON $table WHEN EXISTS "
          "(SELECT 1 FROM withdrawn_run_owners WHERE owner=NEW.owner) "
          "BEGIN SELECT RAISE(ABORT, 'WITHDRAWN_ACCOUNT'); END",
        );
      }
    }
  }

  /// Adds the watch samples without changing the recorder or server input log.
  /// Returns an acknowledgement only after the transaction has committed.
  Future<({bool acknowledged, RunHeartRateSample? latest})> saveHeartRates(
    String owner,
    String sessionId,
    List<RunHeartRateSample> samples, {
    required int receivedAtMs,
  }) async {
    final db = await database;
    var hasAcceptedSample = false;
    final receipt = await db.transaction((tx) async {
      final row = await _heartRateSession(tx, owner, sessionId);
      if (row == null) {
        final deleted = await tx.query(
          'run_deletions',
          columns: ['id'],
          where: 'id=? AND owner=?',
          whereArgs: [sessionId, owner],
          limit: 1,
        );
        return (acknowledged: deleted.isNotEmpty, latest: null);
      }

      final start = DateTime.parse(row['started_at'] as String);
      final startMs = start.millisecondsSinceEpoch;
      final endMs = row['phase'] == RunPhase.ended.name
          ? startMs + (row['checkpoint_ms'] as int)
          : null;
      final transitions = await _heartRateTransitions(tx, sessionId);
      final ordered = [...samples]
        ..sort((a, b) => a.measuredAtMs.compareTo(b.measuredAtMs));
      final batch = tx.batch();
      final windows = _heartRateWindows(startMs, endMs, transitions).iterator;
      var hasWindow = windows.moveNext();
      for (final sample in ordered) {
        final at = sample.measuredAtMs;
        if (at > receivedAtMs + wearHeartRateClockSkewMs) break;
        while (hasWindow && windows.current.endMs != null && at >= windows.current.endMs!) {
          hasWindow = windows.moveNext();
        }
        if (!hasWindow) break;
        if (at < windows.current.startMs) continue;
        hasAcceptedSample = true;
        batch.insert(
          'run_heart_rates',
          {'session_id': sessionId, 'measured_at_ms': at, 'bpm': sample.bpm},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
      final saved = await tx.query(
        'run_heart_rates',
        columns: ['measured_at_ms', 'bpm'],
        where: 'session_id=?',
        whereArgs: [sessionId],
        orderBy: 'measured_at_ms DESC',
        limit: 1,
      );
      final latest = saved.firstOrNull;
      final measuredAtMs = latest?['measured_at_ms'] as int?;
      final lastResume = transitions.lastOrNull;
      return (
        acknowledged: true,
        latest: measuredAtMs == null ||
                (lastResume != null &&
                    lastResume.kind == RunKind.resume &&
                    measuredAtMs < startMs + lastResume.elapsedMs)
            ? null
            : (measuredAtMs: measuredAtMs, bpm: latest!['bpm'] as int),
      );
    });
    if (hasAcceptedSample && !_heartRateChanges.isClosed) {
      _heartRateChanges.add((owner: owner, sessionId: sessionId));
    }
    return receipt;
  }

  Future<RunHeartRateSummary?> heartRateSummary(
    String owner,
    String sessionId,
  ) async {
    final db = await database;
    return db.transaction((tx) async {
      final session = await _heartRateSession(tx, owner, sessionId);
      if (session == null || session['phase'] != RunPhase.ended.name) return null;
      final startMs = DateTime.parse(session['started_at'] as String).millisecondsSinceEpoch;
      final endMs = startMs + (session['checkpoint_ms'] as int);
      final transitions = await _heartRateTransitions(tx, sessionId);
      final windows = _heartRateWindows(startMs, endMs, transitions).toList();
      var count = 0;
      var total = 0;
      var peak = 0;
      // Keep below SQLite's bind parameter limit even after many pauses.
      for (var offset = 0; offset < windows.length; offset += 200) {
        final ranges = windows.skip(offset).take(200).toList();
        final values = List.filled(ranges.length, '(?, ?)').join(', ');
        final rows = await tx.rawQuery(
          'WITH active_ranges(start_ms, end_ms) AS (VALUES $values) '
          'SELECT COUNT(*) AS sample_count, SUM(h.bpm) AS total_bpm, MAX(h.bpm) AS peak_bpm '
          'FROM active_ranges r JOIN run_heart_rates h '
          'ON h.session_id = ? AND h.measured_at_ms >= r.start_ms '
          'AND h.measured_at_ms < r.end_ms',
          [
            for (final range in ranges) ...[range.startMs, range.endMs],
            sessionId,
          ],
        );
        final stats = rows.single;
        count += stats['sample_count'] as int;
        total += (stats['total_bpm'] as int?) ?? 0;
        final windowPeak = (stats['peak_bpm'] as int?) ?? 0;
        if (windowPeak > peak) peak = windowPeak;
      }
      return count == 0 ? null : (averageBpm: (total / count).round(), maxBpm: peak);
    });
  }

  Stream<RunHeartRateSummary?> watchHeartRateSummary(String owner, String sessionId) =>
      Stream<void>.multi((events) {
        final subscription = _heartRateChanges.stream
            .where((key) => key.owner == owner && key.sessionId == sessionId)
            .listen((_) => events.add(null), onDone: events.close);
        events.onCancel = subscription.cancel;
        events.add(null);
      }).asyncMap((_) => heartRateSummary(owner, sessionId)).distinct();

  Future<Map<String, Object?>?> _heartRateSession(
    DatabaseExecutor tx,
    String owner,
    String sessionId,
  ) async => (await tx.query(
    'sessions',
    columns: ['started_at', 'phase', 'checkpoint_ms'],
    where: 'id=? AND owner=? AND NOT EXISTS '
        '(SELECT 1 FROM withdrawn_run_owners WHERE owner=sessions.owner)',
    whereArgs: [sessionId, owner],
    limit: 1,
  )).firstOrNull;

  Future<List<RunInput>> _heartRateTransitions(DatabaseExecutor tx, String sessionId) async {
    final boundaries = await tx.query(
      'inputs',
      columns: ['payload'],
      where: 'session_id=? AND (payload LIKE ? OR payload LIKE ?)',
      whereArgs: [sessionId, '%"kind":"PAUSE"%', '%"kind":"RESUME"%'],
      orderBy: 'seq',
    );
    return boundaries.map((row) => RunInput.fromJson(
      jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    )).toList();
  }

  static Iterable<({int startMs, int? endMs})> _heartRateWindows(
    int startMs,
    int? endMs,
    List<RunInput> transitions,
  ) sync* {
    int? activeFrom = startMs;
    for (final transition in transitions) {
      final at = startMs + transition.elapsedMs;
      if (endMs != null && at >= endMs) break;
      if (transition.kind == RunKind.pause) {
        if (activeFrom != null && activeFrom < at) {
          yield (startMs: activeFrom, endMs: at);
        }
        activeFrom = null;
      } else {
        activeFrom ??= at;
      }
    }
    if (activeFrom != null && (endMs == null || activeFrom < endMs)) {
      yield (startMs: activeFrom, endMs: endMs);
    }
  }

  Future<void> saveGuidanceState(
    LocalRun run,
    Map<String, dynamic> state,
  ) async {
    final updated = await (await database).update(
      'sessions',
      {'guidance_state': jsonEncode(state)},
      where: 'id=? AND owner=? AND phase<>?',
      whereArgs: [run.id, run.owner, 'ended'],
    );
    if (updated != 1) throw StateError('러닝 안내 설정을 저장하지 못했어요.');
    run.guidanceState = Map.of(state);
  }

  /// The committed marker also retries failed cleanup when the store reopens.
  Future<void> purgeWithdrawnOwner(String owner) async {
    final db = await database;
    await db.insert('withdrawn_run_owners', {
      'owner': owner,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.transaction((tx) => _deleteOwnerRows(tx, owner));
  }

  static Future<void> _deleteOwnerRows(
    DatabaseExecutor tx,
    String owner,
  ) async {
    await tx.delete(
      'inputs',
      where: 'session_id IN (SELECT id FROM sessions WHERE owner=?)',
      whereArgs: [owner],
    );
    for (final table in [
      'ghost_closures',
      'sessions',
      'ghost_start_intents',
      'course_start_intents',
      'run_deletions',
      'run_settings',
    ]) {
      await tx.delete(table, where: 'owner=?', whereArgs: [owner]);
    }
  }

  static Future<void> _retryWithdrawnOwners(Database db) async {
    for (final row in await db.query(
      'withdrawn_run_owners',
      columns: ['owner'],
    )) {
      try {
        await db.transaction(
          (tx) => _deleteOwnerRows(tx, row['owner'] as String),
        );
      } on Object {
        // Preserve the durable marker and other accounts; retry on the next open.
      }
    }
  }

  @override
  Future<void> create(LocalRun run, RunInput start) async {
    final db = await database;
    await db.transaction((tx) async {
      final courseDrafts = await tx.query(
        'course_start_intents',
        where: 'owner=?',
        whereArgs: [run.owner],
      );
      if (courseDrafts.isNotEmpty) {
        final intent = CourseStartIntent.fromJson(
          (jsonDecode(courseDrafts.single['intent'] as String) as Map)
              .cast<String, dynamic>(),
        );
        if (run.ghost != null ||
            intent.id != run.id ||
            intent.owner != run.owner ||
            intent.startedAt != run.startedAt) {
          throw StateError('확인 중인 코스 시작을 먼저 복구해 주세요.');
        }
      }
      final drafts = await tx.query(
        'ghost_start_intents',
        where: 'owner=?',
        whereArgs: [run.owner],
      );
      if (drafts.isNotEmpty) {
        if (run.ghost == null ||
            drafts.length != 1 ||
            drafts.single['id'] != run.id ||
            drafts.single['intent'] != jsonEncode(run.ghost!.intent.toJson()) ||
            run.ghost!.intent.owner != run.owner ||
            run.ghost!.intent.startedAt != run.startedAt ||
            drafts.single['approval'] == null ||
            drafts.single['approval'] != run.ghost!.approvalJson) {
          throw StateError('확인 중인 고스트 시작을 먼저 복구해 주세요.');
        }
      } else if (run.ghost != null) {
        throw StateError('기기에 저장한 고스트 시작 정보가 없어요.');
      }
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
        'ghost_context': run.ghost == null
            ? null
            : jsonEncode(run.ghost!.toJson()),
        'recovery_anchor': run.recoveryAnchor == null
            ? null
            : jsonEncode(run.recoveryAnchor!.toJson()),
      });
      await tx.insert('inputs', {
        'session_id': run.id,
        'seq': start.seq,
        'payload': jsonEncode(start.toJson()),
      });
      await tx.delete(
        'course_start_intents',
        where: 'id=? AND owner=?',
        whereArgs: [run.id, run.owner],
      );
      if (run.ghost != null) {
        await tx.delete(
          'ghost_start_intents',
          where: 'id=? AND owner=?',
          whereArgs: [run.id, run.owner],
        );
      }
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
          'recovery_anchor': run.recoveryAnchor == null
              ? null
              : jsonEncode(run.recoveryAnchor!.toJson()),
        },
        where: 'id=? AND owner=? AND phase <> ?',
        whereArgs: [run.id, run.owner, 'ended'],
      );
      if (updated != 1) {
        throw StateError('종료된 기록에는 입력을 추가할 수 없어요.');
      }
      if (run.ghost != null &&
          !run.ghost!.intent.isFree &&
          (phase == RunPhase.ended ||
              inputs.any((i) => i.kind == RunKind.segmentEnd))) {
        await tx.insert('ghost_closures', {
          'id': run.id,
          'owner': run.owner,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
    final updated = await db.update(
      'sessions',
      {
        'checkpoint_ms': elapsedMs,
        'recovery_anchor': run.recoveryAnchor == null
            ? null
            : jsonEncode(run.recoveryAnchor!.toJson()),
      },
      where: 'id=? AND owner=? AND phase <> ?',
      whereArgs: [run.id, run.owner, 'ended'],
    );
    if (updated != 1) throw StateError('기록 저장 지점을 갱신할 수 없어요.');
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
          ghost: row['ghost_context'] == null
              ? null
              : GhostRunContext.fromJson(
                  (jsonDecode(row['ghost_context'] as String) as Map)
                      .cast<String, dynamic>(),
                ),
          guidanceState: row['guidance_state'] == null
              ? null
              : (jsonDecode(row['guidance_state'] as String) as Map)
                    .cast<String, dynamic>(),
          recoveryAnchor: row['recovery_anchor'] == null
              ? null
              : RunRecoveryAnchor.fromJson(
                  (jsonDecode(row['recovery_anchor'] as String) as Map)
                      .cast<String, dynamic>(),
                ),
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
      'stats',
      'course',
      'gpsGap',
      'ghost',
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
    final calculator = RunCalculator.replay(inputs);
    return {
      'id': row['id'],
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': startedAt
          .add(Duration(milliseconds: ms))
          .toUtc()
          .toIso8601String(),
      'endReason': row['end_reason'],
      'metrics': {
        ...calculator.at(ms).toJson(),
        'weightKg': inputs.firstOrNull?.weightKg,
        'estimatedCaloriesKcal': estimateRunCalories(
          inputs.firstOrNull?.weightKg,
          calculator.at(ms).distanceM,
        ),
      },
      'stats': calculator.resultStats(inputs).toJson(),
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

  /// Permanently removes this owner's local runs, GPS, start receipts and settings.
  ///
  /// After server withdrawal succeeds, stop recording and other writes before
  /// calling this method. Unlike [deleteRecord], this creates no server deletion
  /// requests. Errors propagate and the entire transaction is rolled back.
  Future<void> deleteOwner(String owner) async {
    await (await database).transaction((tx) => _deleteOwnerRows(tx, owner));
  }

  @override
  Future<void> deleteRecord(String owner, String id) async {
    await (await database).transaction((tx) async {
      final courseDraft = await tx.query(
        'course_start_intents',
        where: 'id=?',
        whereArgs: [id],
      );
      if (courseDraft.isNotEmpty && courseDraft.single['owner'] != owner) {
        throw StateError('다른 계정의 시작 정보예요.');
      }
      await tx.delete(
        'course_start_intents',
        where: 'id=? AND owner=?',
        whereArgs: [id, owner],
      );
      final draft = await tx.query(
        'ghost_start_intents',
        where: 'id=?',
        whereArgs: [id],
      );
      if (draft.isNotEmpty && draft.single['owner'] != owner) {
        throw StateError('다른 계정의 시작 정보예요.');
      }
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
      await tx.delete(
        'ghost_start_intents',
        where: 'id=? AND owner=?',
        whereArgs: [id, owner],
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
    unawaited(_heartRateChanges.close());
    if (_database != null) {
      await (await _database!).close();
    }
  }

  static Future<void> _createCourseStarts(Database db) async {
    await db.execute(
      'CREATE TABLE course_start_intents (id TEXT PRIMARY KEY, owner TEXT NOT NULL UNIQUE, intent TEXT NOT NULL)',
    );
  }

  Future<void> saveCourseIntent(CourseStartIntent intent) async {
    await (await database).transaction((tx) async {
      if ((await tx.query(
            'run_deletions',
            where: 'id=?',
            whereArgs: [intent.id],
          )).isNotEmpty ||
          (await tx.query(
            'sessions',
            where: 'owner=? AND phase<>?',
            whereArgs: [intent.owner, 'ended'],
          )).isNotEmpty ||
          (await tx.query(
            'ghost_start_intents',
            where: 'owner=?',
            whereArgs: [intent.owner],
          )).isNotEmpty) {
        throw StateError('코스 시작 정보를 저장할 수 없어요.');
      }
      final old = await tx.query(
        'course_start_intents',
        where: 'id=? OR owner=?',
        whereArgs: [intent.id, intent.owner],
      );
      final payload = jsonEncode(intent.toJson());
      if (old.isNotEmpty) {
        if (old.length != 1 ||
            old.single['owner'] != intent.owner ||
            old.single['intent'] != payload) {
          throw StateError('이미 확인 중인 코스 시작이 있어요.');
        }
        return;
      }
      await tx.insert('course_start_intents', {
        'id': intent.id,
        'owner': intent.owner,
        'intent': payload,
      });
    });
  }

  Future<List<CourseStartIntent>> pendingCourseStarts(String owner) async => [
    for (final row in await (await database).query(
      'course_start_intents',
      where: 'owner=?',
      whereArgs: [owner],
    ))
      _courseIntent(row),
  ];
  static CourseStartIntent _courseIntent(Map<String, Object?> row) {
    final intent = CourseStartIntent.fromJson(
      (jsonDecode(row['intent'] as String) as Map).cast<String, dynamic>(),
    );
    if (intent.owner != row['owner'] || intent.id != row['id']) {
      throw const FormatException('Invalid course owner');
    }
    return intent;
  }

  static Future<void> _createGhostStorage(Database db) async {
    await db.execute('ALTER TABLE sessions ADD COLUMN ghost_context TEXT');
    await db.execute('ALTER TABLE sessions ADD COLUMN recovery_anchor TEXT');
    await db.execute(
      'CREATE TABLE ghost_start_intents (id TEXT PRIMARY KEY, owner TEXT NOT NULL UNIQUE, intent TEXT NOT NULL, approval TEXT, checkpoint_clock TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE ghost_closures (id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE, owner TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX ghost_closures_owner ON ghost_closures(owner)',
    );
  }

  @override
  Future<void> saveGhostIntent(GhostStartIntent intent) async {
    await (await database).transaction((tx) async {
      if ((await tx.query(
            'course_start_intents',
            where: 'owner=?',
            whereArgs: [intent.owner],
          )).isNotEmpty ||
          (await tx.query(
            'run_deletions',
            where: 'id=?',
            whereArgs: [intent.id],
          )).isNotEmpty ||
          (await tx.query(
            'sessions',
            where: 'owner=? AND phase<>?',
            whereArgs: [intent.owner, 'ended'],
          )).isNotEmpty) {
        throw StateError('고스트 시작 정보를 저장할 수 없어요.');
      }
      final old = await tx.query(
        'ghost_start_intents',
        where: 'id=? OR owner=?',
        whereArgs: [intent.id, intent.owner],
      );
      final payload = jsonEncode(intent.toJson());
      if (old.isNotEmpty) {
        if (old.length != 1 ||
            old.single['owner'] != intent.owner ||
            old.single['intent'] != payload) {
          throw StateError('이미 확인 중인 고스트 시작이 있어요.');
        }
        return;
      }
      await tx.insert('ghost_start_intents', {
        'id': intent.id,
        'owner': intent.owner,
        'intent': payload,
        'checkpoint_clock': jsonEncode(intent.clock.toJson()),
      });
    });
  }

  @override
  Future<void> saveGhostApproval(
    GhostRunContext context, {
    RunClockSample? checkpointClock,
  }) async {
    await (await database).transaction((tx) async {
      final intent = context.intent;
      final old = await tx.query(
        'ghost_start_intents',
        where: 'id=? AND owner=?',
        whereArgs: [intent.id, intent.owner],
      );
      if (old.length != 1 ||
          old.single['intent'] != jsonEncode(intent.toJson()) ||
          old.single['approval'] != null &&
              old.single['approval'] != context.approvalJson ||
          (await tx.query(
            'run_deletions',
            where: 'id=?',
            whereArgs: [intent.id],
          )).isNotEmpty) {
        throw StateError('고스트 시작 정보를 다시 확인해 주세요.');
      }
      if (old.single['approval'] != null) {
        return; // A receipt read alone cannot extend the restart window.
      }
      await tx.update(
        'ghost_start_intents',
        {
          'approval': context.approvalJson,
          'checkpoint_clock': jsonEncode(
            (checkpointClock ?? intent.clock).toJson(),
          ),
        },
        where: 'id=? AND owner=?',
        whereArgs: [intent.id, intent.owner],
      );
    });
  }

  @override
  Future<List<PendingGhostStart>> pendingGhostStarts(String owner) async => [
    for (final row in await (await database).query(
      'ghost_start_intents',
      where: 'owner=?',
      whereArgs: [owner],
    ))
      _pendingGhost(row),
  ];
  static PendingGhostStart _pendingGhost(Map<String, Object?> row) {
    final intent = GhostStartIntent.fromJson(
      (jsonDecode(row['intent'] as String) as Map).cast<String, dynamic>(),
    );
    if (intent.owner != row['owner'] || intent.id != row['id']) {
      throw const FormatException('Invalid ghost owner');
    }
    return PendingGhostStart(
      intent,
      row['approval'] == null
          ? null
          : GhostRunContext(
              intent,
              (jsonDecode(row['approval'] as String) as Map)
                  .cast<String, dynamic>(),
            ),
      RunClockSample.fromJson(
        (jsonDecode(row['checkpoint_clock'] as String) as Map)
            .cast<String, dynamic>(),
      ),
    );
  }

  @override
  Future<List<String>> pendingGhostClosures(String owner) async => [
    for (final row in await (await database).query(
      'ghost_closures',
      where: 'owner=?',
      whereArgs: [owner],
    ))
      row['id'] as String,
  ];
  @override
  Future<void> ghostClosureSynced(String owner, String id) async {
    await (await database).delete(
      'ghost_closures',
      where: 'owner=? AND id=?',
      whereArgs: [owner, id],
    );
  }
}
