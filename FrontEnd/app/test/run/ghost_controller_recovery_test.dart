import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:io';

import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

import 'ghost_recovery_support.dart';
import 'recording/run_controller_test.dart' show TestLocation, until;
import 'recording/course_run_start_test.dart' show CourseApi;

class GhostLocation extends TestLocation {
  @override
  DateTime get utc => ghostEpoch.add(Duration(milliseconds: clock - 100000));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late RunController controller;
  late GhostLocation location;
  late CourseApi courseApi;
  late RecoveryApi ghostApi;
  var member = 'alice';
  final receipts = <String, Map<String, dynamic>>{};
  void connect([int clock = 100000]) {
    location = GhostLocation()..clock = clock;
    controller = RunController(
      RunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/runs.db',
      ),
      location,
      courseApi,
      () async => member,
      wait: (_) async {},
      utcNow: () => location.utc,
      nowMs: location.nowMs,
      recoveryClock: () async => RunClockSample(location.clock, 'boot-a'),
      ghostApi: ghostApi,
      lifecycleState: () => AppLifecycleState.resumed,
      automaticTicks: false,
    );
  }

  Future<void> close() async {
    await until(() => !controller.syncing && !controller.loadingHistory);
    await controller.shutdown();
    controller.dispose();
    for (final stream in location.streams) {
      await stream.close();
    }
  }

  PreparedOwnGhost selection([String record = sourceId]) {
    final candidate = OwnGhostCandidate.fromJson({
      'id': record,
      'courseId': courseId,
      'courseVersion': 0,
      'startedAt': ghostEpoch
          .subtract(const Duration(days: 1))
          .toIso8601String(),
      'registeredAt': ghostEpoch
          .subtract(const Duration(days: 1))
          .toIso8601String(),
      'courseElapsedSeconds': 230,
      'courseDistanceMeters': 1112,
    });
    final replay = OwnGhostReplay.fromJson({
      ...(ghostApproval(ghostIntent())['playback'] as Map)
          .cast<String, dynamic>(),
      'sourceRecordId': record,
    });
    return PreparedOwnGhost(
      'alice',
      const GhostCourseContext(courseId, 0),
      candidate,
      replay,
    );
  }

  Future<void> begin() async {
    await controller.bindOwner();
    controller.selectGhost(selection());
    await controller.prepareStart();
    expect(controller.courseStart, isNotNull);
    await controller.prepareStart();
    expect(controller.error, isNull);
    expect(controller.recorder.active, true);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ghost-controller-');
    member = 'alice';
    receipts.clear();
    courseApi = CourseApi();
    ghostApi = RecoveryApi();
    ghostApi.onStart = (intent) async {
      final receipt = ghostApproval(intent);
      receipts[intent.id] = receipt;
      return receipt;
    };
    ghostApi.onGet = (_, id) async => receipts[id]!;
    connect();
  });
  tearDown(() async {
    await close();
    await directory.delete(recursive: true);
  });

  for (final refusal in [('RUN-002', 404), ('RUN-004', 409)]) {
    test(
      'controller clears definitive ${refusal.$1} and can choose a different source immediately',
      () async {
        await controller.bindOwner();
        controller.selectGhost(selection());
        await controller.prepareStart();
        ghostApi.onStart = (_) async {
          throw ApiException(refusal.$1, 'denied', status: refusal.$2);
        };
        ghostApi.onGet = (_, _) async =>
            throw const ApiException('RUN-002', 'no approval', status: 404);
        await controller.prepareStart();
        final rejectedId = ghostApi.posts.single.id;
        expect(controller.hasPendingGhostStart, false);
        expect(controller.canSelectGhost, true);
        expect(controller.courseStart, isNull);
        expect(controller.selectedGhost, isNull);
        expect(controller.recorder.active, false);
        expect(controller.ghostStartRejection, contains('사용할 수 없는 고스트입니다.'));
        expect(await controller.store.pendingGhostStarts('alice'), isEmpty);
        const nextSource = '019e0000-0000-7000-8000-000000000099';
        controller.acknowledgeGhostStartRejection();
        controller.selectGhost(selection(nextSource));
        ghostApi.onStart = (intent) async => ghostApproval(intent);
        await controller.prepareStart();
        expect(controller.courseStart!.runId, isNot(rejectedId));
        await controller.prepareStart();
        expect(controller.recorder.active, true);
        expect(controller.run!.ghost!.intent.sourceId, nextSource);
        expect(ghostApi.posts, hasLength(2));
        expect(courseApi.started, isEmpty);
      },
    );
  }

  test('a refused saved start is cleared during account binding and allows a fresh selection', () async {
    await controller.store.saveGhostIntent(ghostIntent());
      ghostApi.onGet = (_, _) async =>
        throw const ApiException('RUN-002', 'missing', status: 404);
    ghostApi.onStart = (_) async =>
        throw const ApiException('RUN-004', 'denied', status: 409);
    await controller.bindOwner();
    expect(controller.hasPendingGhostStart, false);
    expect(controller.canSelectGhost, true);
    expect(controller.ghostStartRejection, isNotNull);
    expect(controller.recorder.active, false);
    controller.acknowledgeGhostStartRejection();
    controller.selectGhost(selection());
    expect(controller.selectedGhost, isNotNull);
  });

  test('existing F6 preparation starts a ghost with its own approval API and persists the full course identity', () async {
    await begin();
    expect(courseApi.started, isEmpty);
    expect(ghostApi.posts, hasLength(1));
    expect(controller.onCourse, true);
    final saved = (await controller.store.list('alice')).single;
    expect(saved.ghost!.intent.id, courseApi.prepared.single.$2);
    expect(saved.ghost!.intent.course.courseId, courseId);
    expect(saved.ghost!.intent.course.version, 0);
    expect(saved.inputs.where((i) => i.kind == RunKind.start), hasLength(1));
  });

  test('controller restart restores tracking and collection offline without a new start or route bridge', () async {
    await begin();
    location.clock += 1000;
    await controller.recorder.gps(36.00005, 127, 3);
    final id = controller.run!.id, distance = controller.metrics.distanceM;
    final clock = location.clock + 30000;
    await close();
    connect(clock);
    await controller.bindOwner();
    expect(controller.run!.id, id);
    expect(controller.recorder.elapsedMs, 31000);
    expect(controller.onCourse, true);
    expect(controller.courseTracker, isNotNull);
    expect(controller.course!.courseId, courseId);
    expect(location.streams, hasLength(1));
    expect(ghostApi.posts, hasLength(1));
    expect(ghostApi.gets, isEmpty);
    await controller.recorder.gps(36.005, 127, 3);
    expect(controller.metrics.distanceM, closeTo(distance, .000001));
  });

  test('a finished course segment stays closed while the paused session is resumed', () async {
    await begin();
    await controller.pause();
    await controller.endCourse('COURSE_ONLY');
    final clock = location.clock + 10000;
    await close();
    connect(clock);
    await controller.bindOwner();
    expect(controller.recorder.active, true);
    expect(controller.run!.phase, RunPhase.paused);
    expect(controller.onCourse, false);
    expect(controller.courseEndReason, 'COURSE_ONLY');
    expect(
      controller.run!.inputs.where((i) => i.kind == RunKind.segmentEnd),
      hasLength(1),
    );
  });

  test('retrying a lost response attaches the same start and closes the approach watcher', () async {
    await controller.bindOwner();
    controller.selectGhost(selection());
    await controller.prepareStart();
    ghostApi.onStart = (intent) async {
      receipts[intent.id] = ghostApproval(intent);
      throw const ApiException('NETWORK', 'lost response');
    };
    await controller.prepareStart();
    expect(controller.hasPendingGhostStart, true);
    expect(controller.recorder.active, false);
    await controller.retryGhostStart();
    expect(controller.hasPendingGhostStart, false);
    expect(controller.onCourse, true);
    expect(controller.courseStart, isNull);
    expect(ghostApi.posts, hasLength(1));
    expect(ghostApi.gets, hasLength(1));
    expect(location.streams.where((s) => s.hasListener), hasLength(1));
  });

  test(
    'binding another account neither loads nor resumes the saved opponent',
    () async {
      await begin();
      final id = controller.run!.id;
      await close();
      member = 'bob';
      connect(110000);
      await controller.bindOwner();
      expect(controller.run, isNull);
      expect(controller.records, isEmpty);
      expect(controller.onCourse, false);
      expect(
        (await controller.store.list('alice', id: id)).single.phase,
        RunPhase.running,
      );
      member = 'alice';
      await controller.bindOwner();
      expect(controller.run!.id, id);
      expect(controller.recorder.active, true);
    },
  );

  test('sign-out cancels an unresolved start by durable ID and cannot expose its preparation to the next account', () async {
    await controller.bindOwner();
    controller.selectGhost(selection());
    await controller.prepareStart();
    ghostApi.onStart = (_) async =>
        throw const ApiException('NETWORK', 'offline');
    await controller.prepareStart();
    final id = (await controller.store.pendingGhostStarts('alice'))
        .single
        .intent
        .id;
    member = 'bob';
    await controller.bindOwner();
    expect(controller.courseStart, isNull);
    expect(controller.selectedGhost, isNull);
    expect(controller.hasPendingGhostStart, false);
    expect(await controller.store.pendingGhostStarts('alice'), isEmpty);
    expect(await controller.store.pendingDeletions('alice'), [id]);
  });
}
