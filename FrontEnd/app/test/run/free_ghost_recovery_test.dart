import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/free_ghost.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

import 'free_ghost_flow_test.dart' show preparation, approval;
import 'ghost_controller_recovery_test.dart' show GhostLocation;
import 'ghost_recovery_support.dart';
import 'recording/course_run_start_test.dart' show CourseApi;
import 'recording/run_controller_test.dart' show until;

class ZeroApi extends CourseApi {
  bool zero = false;
  int verdictReads = 0;
  @override
  Future<Map<String, dynamic>> status(RunUpload run) async => zero
      ? {'processing': 'FAILED', 'failure': 'ZERO_DISTANCE'}
      : super.status(run);
  @override
  Future<Map<String, dynamic>> ghostResult(String owner, String id) async {
    verdictReads++;
    return {
      'version': 'GHOST_RESULT_FREE_V1',
      'outcome': 'LOSE',
      'courseElapsedSeconds': 250,
      'sourceElapsedSeconds': 230,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late RunController runs;
  late GhostLocation location;
  late ZeroApi api;
  late RecoveryApi starts;
  String boot = 'boot-a';
  void connect(int clock) {
    location = GhostLocation()..clock = clock;
    runs = RunController(
      RunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/runs.db',
      ),
      location,
      api,
      () async => 'alice',
      wait: (_) async {},
      utcNow: () => location.utc,
      nowMs: location.nowMs,
      recoveryClock: () async => RunClockSample(location.clock, boot),
      ghostApi: starts,
      lifecycleState: () => AppLifecycleState.resumed,
      automaticTicks: false,
    );
  }

  Future<void> close() async {
    await until(() => !runs.syncing && !runs.loadingHistory);
    await runs.shutdown();
    runs.dispose();
    for (final s in location.streams) {
      await s.close();
    }
  }

  Future<void> begin({bool v2 = false}) async {
    await runs.bindOwner();
    runs.selectFreeGhost(
      PreparedFreeGhost(
        'alice',
        preparation(
          version: v2 ? 'GHOST_PLAYBACK_FREE_V2' : 'GHOST_PLAYBACK_FREE_V1',
        ),
      ),
    );
    await runs.prepareStart();
    expect(runs.courseStart, isNotNull);
    await runs.prepareStart();
    expect(runs.error, isNull);
    expect(runs.recorder.active, true);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('free-ghost-device-');
    boot = 'boot-a';
    api = ZeroApi();
    starts = RecoveryApi()..onStart = (i) async => approval(i);
    connect(100000);
  });
  tearDown(() async {
    await close();
    await directory.delete(recursive: true);
  });
  test('a refused private source can be chosen again immediately without registering a course', () async {
    await runs.bindOwner();
    runs.selectFreeGhost(PreparedFreeGhost('alice', preparation()));
    await runs.prepareStart();
    starts.onStart = (_) async =>
        throw const ApiException('RUN-004', 'denied', status: 409);
    starts.onGet = (_, _) async =>
        throw const ApiException('RUN-002', 'missing', status: 404);
    await runs.prepareStart();
    expect(runs.canSelectGhost, true);
    expect(runs.selectedFreeGhost, isNull);
    expect(runs.courseStart, isNull);
    expect(runs.recorder.active, false);
    expect(await runs.store.pendingGhostStarts('alice'), isEmpty);
    runs.acknowledgeGhostStartRejection();
    starts.onStart = (i) async => approval(i);
    runs.selectFreeGhost(PreparedFreeGhost('alice', preparation()));
    await runs.prepareStart();
    await runs.prepareStart();
    expect(runs.recorder.active, true);
    expect(starts.posts[0].id, isNot(starts.posts[1].id));
    expect(api.prepared, isEmpty);
    expect(api.started, isEmpty);
  });
  test('private reference resumes offline within sixty seconds without course IDs or new approval', () async {
    await begin();
    location.clock += 1000;
    await runs.recorder.gps(36.00005, 127, 3);
    final id = runs.run!.id;
    await close();
    connect(131000);
    await runs.bindOwner();
    expect(runs.recorder.active, true);
    expect(runs.run!.id, id);
    expect(runs.run!.ghost!.intent.isFree, true);
    expect(runs.course, isNull);
    expect(runs.courseTracker, isNotNull);
    expect(runs.metrics.elapsedMs, 31000);
    expect(
      runs.run!.inputs.where(
        (i) => i.kind == RunKind.gap && i.reason == 'PROCESS_RECOVERY',
      ),
      isNotEmpty,
    );
    expect(starts.posts, hasLength(1));
    expect(api.prepared, isEmpty);
    expect(api.started, isEmpty);
  });
  test(
    'V2 start survives SQLite restart and offline recovery without becoming V1',
    () async {
      await begin(v2: true);
      expect(runs.run!.ghost!.intent.freeGhostV2, true);
      expect(starts.posts.single.playbackVersion, 'GHOST_PLAYBACK_FREE_V2');
      await close();
      connect(130000);
      await runs.bindOwner();
      expect(runs.recorder.active, true);
      expect(runs.run!.ghost!.intent.freeGhostV2, true);
      expect(
        runs.run!.ghost!.replay.playback.version,
        'GHOST_PLAYBACK_FREE_V2',
      );
      expect(starts.posts, hasLength(1));
      expect(runs.courseTracker, isNotNull);
    },
  );
  test('recovery beyond sixty seconds closes a private duel and keeps it pending for server verdict', () async {
    await begin();
    await close();
    connect(160001);
    await runs.bindOwner();
    expect(runs.recorder.active, false);
    final record = (await runs.store.list('alice')).single;
    expect(record.endReason, 'INTERRUPTED');
    expect(record.ghost!.intent.isFree, true);
    expect(record.pending, true);
    expect(starts.posts, hasLength(1));
  });
  test('zero-distance private duel uploads and retrieves its dedicated verdict without a course signal', () async {
    await begin();
    await runs.recorder.pause();
    location.clock += 250000;
    await runs.recorder.end();
    expect(runs.run!.pending, true);
    api.zero = true;
    await runs.sync(manual: true);
    expect(api.verdictReads, 1);
    expect(runs.run!.pending, false);
    expect(runs.run!.result!['ghost']['outcome'], 'LOSE');
    expect(api.segmentEnds, isEmpty);
    expect(runs.records, isEmpty);
    final ui = FreeRunController.recording(runs);
    addTearDown(ui.dispose);
    expect(ui.snapshot.ghost!['outcome'], 'LOSE');
    expect(ui.snapshot.storageStatus, contains('거리 기록 없음'));
  });
}
