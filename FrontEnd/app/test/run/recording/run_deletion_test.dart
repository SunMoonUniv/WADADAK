import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/features/run/application/run_sync_worker.dart';
import 'package:wadadak/features/run/data/run_api_client.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/run_voice.dart';

class DeletionApi extends RunApiClient {
  DeletionApi() : super(Dio());
  final calls = <String>[];
  bool offline = false;
  Completer<void>? uploadGate;
  @override
  Future<void> delete(String owner, String id) async {
    calls.add('delete:$owner:$id');
    if (offline) throw const ApiException(ApiException.network, 'offline');
  }

  @override
  Future<Map<String, dynamic>> prepare(LocalRun r) async {
    calls.add('prepare:${r.id}');
    return {'processing': 'PREPARED'};
  }

  @override
  Future<Map<String, dynamic>> upload(LocalRun r, List<RunInput> inputs) async {
    calls.add('upload:${r.id}');
    await uploadGate?.future;
    return {'processing': 'DONE'};
  }

  @override
  Future<Map<String, dynamic>> status(LocalRun r) async {
    calls.add('status:${r.id}');
    return {'processing': 'DONE'};
  }

  @override
  Future<Map<String, dynamic>> result(String owner, String id) async {
    calls.add('result:$id');
    return {'id': id};
  }
}

Future<LocalRun> save(RunLocalStore store, String owner, String id) async {
  final run = LocalRun(
    id: id,
    owner: owner,
    startedAt: DateTime.utc(2026, 10, 14),
  );
  final first = RunInput(
    seq: 0,
    kind: RunKind.start,
    elapsedMs: 0,
    measuredAt: run.startedAt,
  );
  final last = RunInput(
    seq: 1,
    kind: RunKind.end,
    elapsedMs: 1000,
    measuredAt: run.startedAt.add(const Duration(seconds: 1)),
    reason: 'INTERRUPTED',
  );
  await store.create(run, first);
  await store.append(run, [last], RunPhase.ended, 1000, pending: true);
  return run;
}

void main() {
  setUpAll(sqfliteFfiInit);
  test('offline deletion survives reopening and another owner cannot transmit it; retries delete before upload', () async {
    final dir = await Directory.systemTemp.createTemp('run-deletion-');
    final path = '${dir.path}/runs.db';
    var store = RunLocalStore(factory: databaseFactoryFfi, databasePath: path);
    final api = DeletionApi()..offline = true;
    try {
      await save(store, 'alice', 'deleted');
      await save(store, 'alice', 'kept');
      await store.deleteRecord('alice', 'deleted');
      await expectLater(
        RunSyncWorker(api, store, () async => 'alice').sync('alice'),
        throwsA(isA<ApiException>()),
      );
      expect((await store.list('alice')).map((r) => r.id), ['kept']);
      await store.close();
      store = RunLocalStore(factory: databaseFactoryFfi, databasePath: path);
      expect(await store.pendingDeletions('alice'), ['deleted']);
      expect(await store.pendingDeletions('bob'), isEmpty);
      api.offline = false;
      api.calls.clear();
      await RunSyncWorker(api, store, () async => 'bob').sync('alice');
      expect(api.calls, isEmpty);
      await RunSyncWorker(api, store, () async => 'alice').sync('alice');
      expect(api.calls.first, 'delete:alice:deleted');
      expect(api.calls, isNot(contains('prepare:deleted')));
      expect(await store.pendingDeletions('alice'), isEmpty);
      expect(await store.deletedIds('alice'), {'deleted'});
      expect((await store.list('alice')).single.syncState, 'synced');
      expect(await store.deletedIds('bob'), isEmpty);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
  test('deleting while upload response is delayed cannot resurrect source or cached result', () async {
    final store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final api = DeletionApi()..uploadGate = Completer<void>();
    try {
      await save(store, 'alice', 'race');
      final syncing = RunSyncWorker(
        api,
        store,
        () async => 'alice',
      ).sync('alice');
      for (var i = 0; i < 100 && !api.calls.contains('upload:race'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(api.calls, contains('upload:race'));
      await store.deleteRecord('alice', 'race');
      api.uploadGate!.complete();
      await syncing;
      expect(await store.list('alice'), isEmpty);
      expect(api.calls, isNot(contains('result:race')));
      expect(api.calls.last, 'delete:alice:race');
      expect(await store.deletedIds('alice'), {'race'});
      expect(await store.pendingDeletions('alice'), isEmpty);
    } finally {
      await store.close();
    }
  });
  test('v1 upgrade preserves raw records and adds owner-scoped voice settings and deletion queue', () async {
    final dir = await Directory.systemTemp.createTemp('run-upgrade-');
    final path = '${dir.path}/runs.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            "CREATE TABLE sessions (id TEXT PRIMARY KEY, owner TEXT NOT NULL, started_at TEXT NOT NULL, phase TEXT NOT NULL, checkpoint_ms INTEGER NOT NULL, pending INTEGER NOT NULL DEFAULT 0, end_reason TEXT, result TEXT, sync_state TEXT NOT NULL DEFAULT 'pending', sync_failure TEXT)",
          );
          await db.execute(
            'CREATE TABLE inputs (session_id TEXT, seq INTEGER, payload TEXT, PRIMARY KEY(session_id,seq))',
          );
        },
      ),
    );
    final utc = DateTime.utc(2026, 10, 14);
    await old.insert('sessions', {
      'id': 'old',
      'owner': 'alice',
      'started_at': utc.toIso8601String(),
      'phase': 'ended',
      'checkpoint_ms': 1000,
      'pending': 1,
    });
    await old.insert('inputs', {
      'session_id': 'old',
      'seq': 0,
      'payload': jsonEncode(
        RunInput(
          seq: 0,
          kind: RunKind.start,
          elapsedMs: 0,
          measuredAt: utc,
        ).toJson(),
      ),
    });
    await old.insert('inputs', {
      'session_id': 'old',
      'seq': 1,
      'payload': jsonEncode(
        RunInput(
          seq: 1,
          kind: RunKind.end,
          elapsedMs: 1000,
          measuredAt: utc.add(const Duration(seconds: 1)),
          reason: 'INTERRUPTED',
        ).toJson(),
      ),
    });
    await old.close();
    final store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    try {
      expect((await store.list('alice')).single.inputs.length, 2);
      await store.saveVoiceSettings(
        'alice',
        const RunVoiceSettings(
          enabled: false,
          unit: VoiceUnit.time,
          timeMinutes: 10,
        ),
      );
      expect((await store.voiceSettings('alice')).timeMinutes, 10);
      expect((await store.voiceSettings('bob')).enabled, true);
      expect((await store.voiceSettings('bob')).distanceKm, 1);
      final active = LocalRun(
        id: 'active',
        owner: 'bob',
        startedAt: DateTime.utc(2026),
      );
      await store.create(
        active,
        RunInput(
          seq: 0,
          kind: RunKind.start,
          elapsedMs: 0,
          measuredAt: active.startedAt,
        ),
      );
      await expectLater(store.deleteRecord('bob', 'active'), throwsStateError);
      await expectLater(store.deleteRecord('bob', 'old'), throwsStateError);
      expect(await store.deletedIds('bob'), isEmpty);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
