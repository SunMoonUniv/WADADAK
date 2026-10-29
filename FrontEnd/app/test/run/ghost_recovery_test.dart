import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/features/run/application/run_sync_worker.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';
import 'package:wadadak/features/run/application/ghost_start_flow.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';

import 'ghost_recovery_support.dart';

class ClosureApi extends RunApiClient {
  ClosureApi() : super(Dio());
  bool fail = true;
  final closed = <String>[];
  final prepared = <RunUpload>[];
  final batches = <List<Map<String, dynamic>>>[];
  @override
  Future<void> segmentEnd(String owner, String id) async {
    closed.add('$owner/$id');
    if (fail) throw const ApiException('NETWORK', 'offline');
  }

  @override
  Future<Map<String, dynamic>> prepare(RunUpload run) async {
    prepared.add(run);
    return {'processing': 'PREPARED'};
  }

  @override
  Future<Map<String, dynamic>> upload(
    RunUpload run,
    List<Map<String, dynamic>> inputs,
  ) async {
    batches.add(inputs);
    return {'processing': 'PROCESSING'};
  }

  @override
  Future<Map<String, dynamic>> status(RunUpload run) async => {
    'processing': 'PROCESSING',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late RunLocalStore store;
  late RunRecorder recorder;
  late GhostStartFlow flow;
  late RecoveryClock clock;
  late RecoveryApi api;
  String? member;
  void connect() {
    store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/runs.db',
    );
    recorder = RunRecorder(
      store,
      clock.now,
      recoveryClock: clock.sample,
      motionFiltering: false,
    );
    flow = GhostStartFlow(
      store,
      api,
      recorder,
      clock.sample,
      () async => member,
    );
  }

  Future<void> restart() async {
    await recorder.close();
    await store.close();
    connect();
  }

  Future<void> begin() async {
    expect(await flow.begin(ghostIntent()), true);
  }

  Future<void> movement() async {
    await recorder.gps(36, 127, 3);
    clock.ms += 1000;
    await recorder.gps(36.00005, 127, 3);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ghost-recovery-');
    clock = RecoveryClock();
    api = RecoveryApi();
    member = 'alice';
    connect();
  });
  tearDown(() async {
    await recorder.close();
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final refusal in [
    ('RUN-002', 404),
    ('RUN-004', 409),
    ('RUN-003', 409),
    ('COURSE-002', 409),
  ]) {
    test(
      'definitive ${refusal.$1} with no receipt durably cancels the attempt immediately',
      () async {
        api.onStart = (_) async {
          throw ApiException(refusal.$1, 'denied', status: refusal.$2);
        };
        api.onGet = (_, _) async =>
            throw const ApiException('RUN-002', 'no approval', status: 404);
        await expectLater(
          flow.begin(ghostIntent()),
          throwsA(isA<GhostStartRejected>()),
        );
        expect(await store.pendingGhostStarts('alice'), isEmpty);
        expect(await store.pendingDeletions('alice'), [ghostId]);
        expect(await store.list('alice'), isEmpty);
        expect(recorder.active, false);
        await expectLater(
          store.saveGhostIntent(ghostIntent()),
          throwsStateError,
        );
        expect(api.posts, hasLength(1));
      },
    );
  }

  test('receipt survives a conflicting POST response and starts exactly the saved duel', () async {
    api.onStart = (_) async =>
        throw const ApiException('RUN-003', 'conflict', status: 409);
    api.onGet = (_, _) async => ghostApproval(ghostIntent());
    expect(await flow.begin(ghostIntent()), true);
    expect(recorder.current!.id, ghostId);
    expect(await store.pendingDeletions('alice'), isEmpty);
    expect(api.posts, hasLength(1));
    expect(api.gets, hasLength(1));
  });

  test(
    'an uncertain receipt after refusal retains the same pending request',
    () async {
      api.onStart = (_) async =>
          throw const ApiException('RUN-004', 'denied', status: 409);
      api.onGet = (_, _) async =>
          throw const ApiException('NETWORK', 'lost receipt');
      await expectLater(
        flow.begin(ghostIntent()),
        throwsA(isA<ApiException>()),
      );
      expect(await store.pendingGhostStarts('alice'), hasLength(1));
      expect(await store.pendingDeletions('alice'), isEmpty);
      expect(recorder.active, false);
    },
  );

  test('a recovered pending POST that is definitively refused becomes selectable without waiting 60 seconds', () async {
    await store.saveGhostIntent(ghostIntent());
      api.onGet = (_, _) async =>
        throw const ApiException('RUN-002', 'no approval', status: 404);
    api.onStart = (_) async =>
        throw const ApiException('RUN-004', 'denied', status: 409);
    await expectLater(
      flow.recover('alice'),
      throwsA(isA<GhostStartRejected>()),
    );
    expect(await store.pendingGhostStarts('alice'), isEmpty);
    expect(await store.pendingDeletions('alice'), [ghostId]);
    expect(recorder.active, false);
  });

  test('a mismatching saved receipt never cancels the pending start', () async {
    api.onStart = (_) async =>
        throw const ApiException('RUN-004', 'denied', status: 409);
      api.onGet = (_, _) async => {
      ...ghostApproval(ghostIntent()),
      'sourceRecordId': 'wrong-source',
    };
    await expectLater(flow.begin(ghostIntent()), throwsFormatException);
    expect(await store.pendingGhostStarts('alice'), hasLength(1));
    expect(await store.pendingDeletions('alice'), isEmpty);
    expect(recorder.active, false);
  });

  test('an account switch during refusal confirmation preserves the original owner request', () async {
    api.onStart = (_) async =>
        throw const ApiException('RUN-004', 'denied', status: 409);
      api.onGet = (_, _) async {
      member = 'bob';
      throw const ApiException('RUN-002', 'missing', status: 404);
    };
    await expectLater(flow.begin(ghostIntent()), throwsA(isA<ApiException>()));
    expect(await store.pendingGhostStarts('alice'), hasLength(1));
    expect(await store.pendingDeletions('alice'), isEmpty);
    expect(await store.pendingGhostStarts('bob'), isEmpty);
    expect(recorder.active, false);
  });

  test('intent precedes HTTP and receipt/START move together into the durable session', () async {
    api.onStart = (intent) async {
      expect(
        (await store.pendingGhostStarts('alice')).single.intent.request,
        intent.request,
      );
      expect(await store.list('alice'), isEmpty);
      return ghostApproval(intent);
    };
    await begin();
    expect(await store.pendingGhostStarts('alice'), isEmpty);
    final saved = (await store.list('alice')).single;
    expect(saved.ghost!.intent.id, ghostId);
    expect(saved.inputs.where((i) => i.kind == RunKind.start), hasLength(1));
    expect(saved.recoveryAnchor!.checkpointClockMs, clock.ms);
    expect(saved.ghost!.approval, ghostApproval(ghostIntent()));
  });

  for (final age in [0, 59999, 60000]) {
    test(
      'same boot resumes at inclusive saved-checkpoint age $age ms without another start',
      () async {
        await begin();
        await movement();
        final before = recorder.metrics.distanceM;
        final checkpoint = recorder.current!.checkpointMs;
        await restart();
        clock.ms += age;
        await recorder.recover('alice', summaryOnly: true);
        expect(recorder.active, true);
        expect(recorder.elapsedMs, checkpoint + age);
        expect(recorder.current!.id, ghostId);
        expect(
          recorder.current!.inputs.where((i) => i.kind == RunKind.start),
          hasLength(1),
        );
        expect(
          recorder.current!.inputs.where((i) => i.kind == RunKind.gps),
          hasLength(2),
        );
        expect(recorder.metrics.distanceM, closeTo(before, 0.000001));
        expect(api.posts, hasLength(1));
        expect(api.gets, isEmpty);
        // Even a short process gap must not connect the old and new GPS points.
        await recorder.gps(36.005, 127, 3);
        expect(recorder.metrics.distanceM, closeTo(before, 0.000001));
        expect(
          recorder.current!.inputs.map((i) => i.seq),
          List.generate(recorder.current!.inputs.length, (i) => i),
        );
      },
    );
  }

  for (final failure in [
    'expired',
    'reboot',
    'unknown',
    'backwards',
    'unavailable',
  ]) {
    test(
      '$failure clock finalizes at the saved checkpoint and preserves original inputs',
      () async {
        await begin();
        await movement();
        final checkpoint = recorder.current!.checkpointMs;
        final raw = recorder.current!.inputs.map((i) => i.toJson()).toList();
        await restart();
        switch (failure) {
          case 'expired':
            clock.ms += 60001;
          case 'reboot':
            clock.boot = 'boot-b';
          case 'unknown':
            clock.boot = null;
          case 'backwards':
            clock.ms = 10;
          case 'unavailable':
            clock.fail = true;
        }
        final run = (await recorder.recover('alice')).single;
        expect(run.phase, RunPhase.ended);
        expect(run.endReason, 'INTERRUPTED');
        expect(run.checkpointMs, checkpoint);
        expect(run.inputs.take(raw.length).map((i) => i.toJson()), raw);
        expect(run.inputs.last.kind, RunKind.end);
        expect(await store.pendingGhostClosures('alice'), [ghostId]);
      },
    );
  }

  test(
    'paused phase, finished course segment and opponent time survive restart',
    () async {
      await begin();
      await movement();
      await recorder.pause();
      await recorder.segmentEnd('COURSE_ONLY');
      final ms = recorder.elapsedMs;
      await restart();
      clock.ms += 30000;
      await recorder.recover('alice');
      expect(recorder.current!.phase, RunPhase.paused);
      expect(
        recorder.current!.inputs.where((i) => i.kind == RunKind.segmentEnd),
        hasLength(1),
      );
      expect(
        recorder.current!.inputs.where((i) => i.kind == RunKind.resume),
        isEmpty,
      );
      expect(recorder.metrics.activeMs, ms);
      final opponent = recorder.current!.ghost!.replay.playback.at(
        recorder.elapsedMs,
      );
      expect(opponent.coursePositionM, greaterThan(100));
      expect(recorder.current!.ghost!.intent.startedAt, ghostEpoch);
    },
  );

  test('repeated recovery never repeats START or grants a new 60 seconds without a saved checkpoint', () async {
    await begin();
    await movement();
    for (var i = 1; i <= 3; i++) {
      await restart();
      clock.ms += 20000;
      await recorder.recover('alice');
      expect(recorder.elapsedMs, 1000 + i * 20000);
      final count = recorder.current!.inputs.length;
      await recorder.recover('alice');
      expect(recorder.current!.inputs.length, count);
    }
    expect(
      recorder.current!.inputs.where((i) => i.kind == RunKind.start),
      hasLength(1),
    );
  });

  test('lost POST response is recovered by GET with the original ID and clock, without another POST', () async {
    api.onStart = (_) async =>
        throw const ApiException('NETWORK', 'lost response');
    await expectLater(flow.begin(ghostIntent()), throwsA(isA<ApiException>()));
    await restart();
    clock.ms += 10000;
    expect(await flow.recover('alice'), true);
    expect(api.posts, hasLength(1));
    expect(api.gets, ['alice/$ghostId']);
    expect(recorder.elapsedMs, 10000);
    expect(recorder.current!.ghost!.intent.request, ghostIntent().request);
  });

  test(
    'GET 404 retries only the exact durable request within 60 seconds',
    () async {
      await store.saveGhostIntent(ghostIntent());
      api.onGet = (_, _) async =>
          throw const ApiException('RUN-002', 'pending', status: 404);
      clock.ms += 60000;
      expect(await flow.recover('alice'), true);
      expect(api.posts.single.request, ghostIntent().request);
      expect(recorder.elapsedMs, 60000);
    },
  );

  test('expired unknown start is tombstoned on GET 404; late approval cannot resurrect it', () async {
    await store.saveGhostIntent(ghostIntent());
    api.onGet = (_, _) async =>
        throw const ApiException('RUN-002', 'pending', status: 404);
    clock.ms += 60001;
    expect(await flow.recover('alice'), false);
    expect(api.posts, isEmpty);
    expect(await store.pendingDeletions('alice'), [ghostId]);
    await expectLater(
      store.saveGhostApproval(
        GhostRunContext(ghostIntent(), ghostApproval(ghostIntent())),
      ),
      throwsStateError,
    );
    expect(await store.list('alice'), isEmpty);
  });

  test(
    'approved but unattached receipt recovers offline without HTTP',
    () async {
      final context = GhostRunContext(
        ghostIntent(),
        ghostApproval(ghostIntent()),
      );
      await store.saveGhostIntent(context.intent);
      await store.saveGhostApproval(context);
      await restart();
      clock.ms += 5000;
      expect(await flow.recover('alice'), true);
      expect(api.gets, isEmpty);
      expect(api.posts, isEmpty);
      expect(recorder.elapsedMs, 5000);
    },
  );

  test('expired known approval preserves receipt in an interrupted zero-distance record', () async {
    final context = GhostRunContext(
      ghostIntent(),
      ghostApproval(ghostIntent()),
    );
    await store.saveGhostIntent(context.intent);
    await store.saveGhostApproval(context);
    clock.ms += 60001;
    expect(await flow.recover('alice'), false);
    final run = (await store.list('alice')).single;
    expect(run.endReason, 'INTERRUPTED');
    expect(run.checkpointMs, 0);
    expect(run.ghost!.approval, context.approval);
    expect(await store.pendingGhostClosures('alice'), [ghostId]);
  });

  test('a recently saved approval is the checkpoint even if the first START write failed', () async {
    final db = await store.database;
    await db.execute(
      "CREATE TRIGGER fail_start BEFORE INSERT ON inputs BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
    );
    api.onStart = (intent) async {
      clock.ms += 5000;
      return ghostApproval(intent);
    };
    await expectLater(
      flow.begin(ghostIntent()),
      throwsA(isA<RunStorageFailure>()),
    );
    expect(
      (await store.pendingGhostStarts('alice'))
          .single
          .checkpointClock
          .elapsedMs,
      105000,
    );
    await db.execute('DROP TRIGGER fail_start');
    await restart();
    clock.ms += 60000;
    expect(await flow.recover('alice'), true);
    expect(recorder.elapsedMs, 65000);
    expect(api.posts, hasLength(1));
    expect(api.gets, isEmpty);
  });

  test(
    'a late GET receipt cannot reset an expired unresolved request window',
    () async {
      await store.saveGhostIntent(ghostIntent());
      clock.ms += 60001;
      expect(await flow.recover('alice'), false);
      final run = (await store.list('alice')).single;
      expect(run.endReason, 'INTERRUPTED');
      expect(run.checkpointMs, 0);
      expect(api.posts, isEmpty);
    },
  );

  test(
    'offline unknown approval remains pending and blocks a new free start',
    () async {
      await store.saveGhostIntent(ghostIntent());
      api.onGet = (_, _) async =>
          throw const ApiException('NETWORK', 'offline');
      await expectLater(flow.recover('alice'), throwsA(isA<ApiException>()));
      expect(await store.pendingGhostStarts('alice'), hasLength(1));
      await expectLater(
        recorder.start('another', 'alice', ghostEpoch),
        throwsA(isA<RunStorageFailure>()),
      );
      expect(await store.list('alice'), isEmpty);
    },
  );

  test('account changes cannot attach a late receipt or expose another owner pending start', () async {
    api.onStart = (intent) async {
      member = 'bob';
      return ghostApproval(intent);
    };
    expect(await flow.begin(ghostIntent()), false);
    expect(recorder.active, false);
    expect(await store.pendingGhostStarts('bob'), isEmpty);
    expect(await flow.recover('bob'), false);
    expect(await store.pendingGhostStarts('alice'), hasLength(1));
    await expectLater(store.deleteRecord('bob', ghostId), throwsStateError);
  });

  test(
    'mismatched approval cannot be persisted or start the recorder',
    () async {
      api.onStart = (intent) async => {
        ...ghostApproval(intent),
        'sourceRecordId': 'other',
      };
      await expectLater(flow.begin(ghostIntent()), throwsFormatException);
      expect((await store.pendingGhostStarts('alice')).single.context, isNull);
      expect(await store.list('alice'), isEmpty);
    },
  );

  test(
    'a local START transaction failure retains the approved ledger for retry',
    () async {
      final context = GhostRunContext(
        ghostIntent(),
        ghostApproval(ghostIntent()),
      );
      await store.saveGhostIntent(context.intent);
      await store.saveGhostApproval(context);
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER fail_start BEFORE INSERT ON inputs BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
      );
      await expectLater(
        recorder.startGhost(context),
        throwsA(isA<RunStorageFailure>()),
      );
      expect(await store.list('alice'), isEmpty);
      expect(
        (await store.pendingGhostStarts('alice')).single.context!.approval,
        context.approval,
      );
      await db.execute('DROP TRIGGER fail_start');
      await restart();
      expect(await flow.recover('alice'), true);
      expect(api.posts, isEmpty);
      expect(api.gets, isEmpty);
    },
  );

  test(
    'failed checkpoint does not advance the persisted recovery window',
    () async {
      await begin();
      await movement();
      final db = await store.database;
      final before = (await store.list('alice')).single;
      await db.execute(
        "CREATE TRIGGER fail_save BEFORE UPDATE ON sessions BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
      );
      clock.ms += 50000;
      await expectLater(
        recorder.tick(persist: true),
        throwsA(isA<RunStorageFailure>()),
      );
      expect(
        recorder.current!.recoveryAnchor!.checkpointClockMs,
        before.recoveryAnchor!.checkpointClockMs,
      );
      await db.execute('DROP TRIGGER fail_save');
      await restart();
      clock.ms += 10001;
      expect((await recorder.recover('alice')).single.phase, RunPhase.ended);
    },
  );

  test('v3 migration preserves raw input, confirmed results, deletion reservations and legacy recovery', () async {
    final run = LocalRun(id: 'legacy', owner: 'alice', startedAt: ghostEpoch);
    await store.create(
      run,
      RunInput(
        seq: 0,
        kind: RunKind.start,
        elapsedMs: 0,
        measuredAt: ghostEpoch,
      ),
    );
    await store.checkpoint(run, 1234);
    await store.deleteRecord('bob', 'deleted-remote');
    final db = await store.database;
    await db.execute('DROP TABLE ghost_closures');
    await db.execute('DROP TABLE ghost_start_intents');
    await db.execute('ALTER TABLE sessions DROP COLUMN ghost_context');
    await db.execute('ALTER TABLE sessions DROP COLUMN recovery_anchor');
    await db.execute('DROP TABLE course_start_intents');
      await db.execute('PRAGMA user_version=3');
    await restart();
    final recovered = (await recorder.recover('alice')).single;
    expect(recovered.endReason, 'INTERRUPTED');
    expect(recovered.checkpointMs, 1234);
    expect(
      recovered.inputs.first.toJson(),
      run.inputs.isEmpty
          ? RunInput(
              seq: 0,
              kind: RunKind.start,
              elapsedMs: 0,
              measuredAt: ghostEpoch,
            ).toJson()
          : run.inputs.first.toJson(),
    );
    expect(await store.deletedIds('bob'), {'deleted-remote'});
    expect((await store.database).getVersion(), completion(5));
    expect(jsonEncode(recovered.inputs.last.toJson()), contains('INTERRUPTED'));
  });

  test('interrupted closure is retried durably before uploading the original session identity and stream', () async {
    await begin();
    await movement();
    await restart();
    clock.ms += 60001;
    await recorder.recover('alice');
    final transport = ClosureApi();
    final worker = RunSyncWorker(transport, store, () async => member);
    await expectLater(worker.sync('alice'), throwsA(isA<ApiException>()));
    expect(await store.pendingGhostClosures('alice'), [ghostId]);
    expect(transport.prepared, isEmpty);
    transport.fail = false;
    await worker.sync('alice');
    expect(await store.pendingGhostClosures('alice'), isEmpty);
    expect(transport.closed, ['alice/$ghostId', 'alice/$ghostId']);
    expect(transport.prepared.single.id, ghostId);
    expect(transport.prepared.single.startedAt, ghostEpoch);
    expect(
      transport.batches.single.where((i) => i['kind'] == 'START'),
      hasLength(1),
    );
    expect(transport.batches.single.last['reason'], 'INTERRUPTED');
    expect(api.posts, hasLength(1));
  });
}
