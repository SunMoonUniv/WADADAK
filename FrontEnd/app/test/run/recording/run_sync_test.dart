import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/features/run/application/run_sync_worker.dart';
import 'package:wadadak/features/run/data/run_api_client.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

class FakeApi extends RunApiClient {
  FakeApi() : super(Dio());
  final uploaded = <String>{};
  final requests = <String>[];
  bool loseResponse = false, failRecord = false;
  String? Function()? currentOwner;
  @override
  Future<Map<String, dynamic>> prepare(LocalRun run) async {
    requests.add(run.id);
    return {
      'processing': failRecord && run.id == 'bad'
          ? 'FAILED'
          : uploaded.contains(run.id)
          ? 'DONE'
          : 'PREPARED',
      'failure': 'RUN-001',
    };
  }

  @override
  Future<Map<String, dynamic>> upload(
    LocalRun run,
    List<RunInput> inputs,
  ) async {
    uploaded.add(run.id);
    if (loseResponse) {
      loseResponse = false;
      throw const ApiException(ApiException.network, '응답 유실');
    }
    return {'processing': 'DONE'};
  }

  @override
  Future<Map<String, dynamic>> status(LocalRun run) async => {
    'processing': 'DONE',
  };
  @override
  Future<Map<String, dynamic>> result(String owner, String id) async {
    if (currentOwner != null && currentOwner!() != owner) {
      throw StateError('wrong owner');
    }
    return {'id': id, 'registeredAt': '2026-10-12T00:00:00Z'};
  }
}

void main() {
  late RunLocalStore store;
  late FakeApi api;
  late RunSyncWorker worker;
  String? owner = 'alice';
  final start = DateTime.utc(2026, 10, 12);
  Future<void> addRun(String id) async {
    final run = LocalRun(id: id, owner: 'alice', startedAt: start);
    final first = RunInput(
      seq: 0,
      kind: RunKind.start,
      elapsedMs: 0,
      measuredAt: start,
    );
    await store.create(run, first);
    await store.append(
      run,
      [
        RunInput(
          seq: 1,
          kind: RunKind.end,
          elapsedMs: 1000,
          measuredAt: start.add(const Duration(seconds: 1)),
          reason: 'INTERRUPTED',
        ),
      ],
      RunPhase.ended,
      1000,
      pending: true,
    );
  }

  setUp(() {
    sqfliteFfiInit();
    owner = 'alice';
    store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    api = FakeApi();
    worker = RunSyncWorker(api, store, () async => owner);
  });
  tearDown(() async => store.close());
  test(
    'lost response retries same record and keeps source until confirmed',
    () async {
      await addRun('one');
      api.loseResponse = true;
      await expectLater(worker.sync('alice'), throwsA(isA<ApiException>()));
      expect((await store.list('alice')).single.pending, true);
      expect((await store.list('alice')).single.inputs.length, 2);
      await worker.sync('alice');
      final saved = (await store.list('alice')).single;
      expect(saved.pending, false);
      expect(saved.syncState, 'synced');
      expect(api.uploaded, {'one'});
      expect(api.requests, ['one', 'one']);
    },
  );
  test('terminal error in one record does not block another record', () async {
    await addRun('bad');
    await addRun('good');
    api.failRecord = true;
    await worker.sync('alice');
    final rows = await store.list('alice');
    expect(rows.singleWhere((r) => r.id == 'bad').syncState, 'blocked');
    expect(rows.singleWhere((r) => r.id == 'good').pending, false);
    api.requests.clear();
    await worker.sync('alice');
    expect(api.requests, isEmpty);
  });
  test(
    'another signed-in account cannot upload pending original records',
    () async {
      await addRun('one');
      owner = 'bob';
      await worker.sync('alice');
      expect(api.requests, isEmpty);
      expect((await store.list('alice')).single.pending, true);
    },
  );
}
