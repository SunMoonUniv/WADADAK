import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/wear_run_bridge.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/course_tracker.dart';
import 'package:wadadak/features/run/domain/ghost_live_comparison.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/route_guidance.dart';

import 'recording/run_controller_test.dart'
    show TestLocation, FailingStore, until;
import 'recording/course_run_start_test.dart' show CourseApi;
import 'run_device_controller_test.dart' show Device;
import 'ghost_recovery_support.dart';

class SlowStopDevice extends Device {
  Completer<void>? stopGate;
  bool stopWaiting = false;
  @override
  Future<void> stopSteps() async {
    if (stopGate != null) {
      stopWaiting = true;
      await stopGate!.future;
    }
    await super.stopSteps();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late RunController runs;
  late TestLocation location;
  late CourseApi api;
  late FailingStore store;
  late SlowStopDevice device;
  var lifecycle = AppLifecycleState.resumed;
  String? member;
  Future<double?> Function(String)? readWeight;
  setUp(() {
    member = 'alice';
    lifecycle = AppLifecycleState.resumed;
    readWeight = null;
    store = FailingStore();
    location = TestLocation();
    api = CourseApi();
    device = SlowStopDevice();
    runs = RunController(
      store,
      location,
      api,
      () async => member,
      device: device,
      automaticTicks: false,
      wait: (_) async {},
      nowMs: location.nowMs,
      utcNow: () => location.utc,
      lifecycleState: () => lifecycle,
      weightAtStart: (owner) async =>
          readWeight == null ? null : await readWeight!(owner),
    );
  });
  tearDown(() async {
    if (device.stopGate != null && !device.stopGate!.isCompleted) {
      device.stopGate!.complete();
    }
    await until(() => !runs.syncing && !runs.loadingHistory);
    await runs.shutdown();
    runs.dispose();
    for (final stream in location.streams) {
      await stream.close();
    }
  });
  Future<void> ready() async {
    await runs.bindOwner();
    await until(() => !runs.syncing && !runs.loadingHistory);
  }

  test(
    'QA start duplicate requests create one session and one GPS collector',
    () async {
      await ready();
      await Future.wait([for (var i = 0; i < 5; i++) runs.prepareStart()]);
      expect(runs.recorder.active, true);
      expect(await store.list('alice'), hasLength(1));
      expect(location.streams.where((s) => s.hasListener), hasLength(1));
    },
  );
  test(
    'QA cancel during weight lookup cannot start a delayed session',
    () async {
      await ready();
      final weight = Completer<double?>();
      var requested = false;
      readWeight = (_) {
        requested = true;
        return weight.future;
      };
      final preparing = runs.prepareStart();
      await until(() => requested);
      runs.cancelStart();
      weight.complete(65);
      await preparing;
      expect(runs.recorder.active, false);
      expect(await store.list('alice'), isEmpty);
    },
  );
  test(
    'QA account switch during weight lookup cannot save previous owner run',
    () async {
      await ready();
      final weight = Completer<double?>();
      var requested = false;
      readWeight = (_) {
        requested = true;
        return weight.future;
      };
      final preparing = runs.prepareStart();
      await until(() => requested);
      member = 'bob';
      await runs.accountChanged();
      weight.complete(65);
      await preparing;
      expect(runs.recorder.active, false);
      expect(await store.list('alice'), isEmpty);
      expect(runs.currentOwner, 'bob');
    },
  );
  test('QA missing weight does not prevent offline free run', () async {
    await ready();
    readWeight = (_) async =>
        throw const ApiException(ApiException.network, 'offline');
    await runs.prepareStart();
    expect(runs.recorder.active, true);
    expect(runs.run!.weightKg, isNull);
  });
  test('QA repeated pause and resume create one boundary each', () async {
    await runs.prepareStart();
    location.clock = 1000;
    await Future.wait([for (var i = 0; i < 5; i++) runs.pause()]);
    expect(
      runs.run!.inputs.where((i) => i.kind == RunKind.pause),
      hasLength(1),
    );
    location.clock = 3000;
    await Future.wait([for (var i = 0; i < 5; i++) runs.resume()]);
    expect(
      runs.run!.inputs.where((i) => i.kind == RunKind.resume),
      hasLength(1),
    );
    expect(runs.metrics.activeMs, 1000);
  });
  test(
    'watch start uses the prepared GPS stream after phone screen locks',
    () async {
      await ready();
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
      final bridge = WearRunBridge(() => runs);
      Future<Map<String, Object?>> request(String command, [String? readyId]) =>
          bridge.handle(
            MethodCall('request', {'command': command, 'readyId': readyId}),
          );

      final preparation = runs.prepareWearStart();
      await until(() => location.streams.isNotEmpty);
      expect(runs.wearReadyId, isNull);
      location.streams.single.add(location.point(36));
      await until(() => runs.wearReadyId != null);
      final status = await request('status');
      expect(status['phase'], 'ready');
      final readyId = status['readyId'] as String;
      expect(await store.list('alice'), isEmpty);

      lifecycle = AppLifecycleState.paused;
      binding.handleAppLifecycleStateChanged(lifecycle);
      expect((await request('start', 'stale'))['phase'], 'ready');
      expect((await request('start', readyId))['phase'], 'preparing');
      await preparation;
      expect((await request('status'))['phase'], 'running');
      expect(runs.wearReadyId, isNull);
      expect(location.streams.single.hasListener, isTrue);
      expect(await store.list('alice'), hasLength(1));
    },
  );

  test(
    'watch controls the same run and duplicate END stores one record',
    () async {
      await ready();
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
      final bridge = WearRunBridge(() => runs);
      Future<Map<String, Object?>> request(String command, [String? id]) =>
          bridge.handle(
            MethodCall('request', {'command': command, 'sessionId': id}),
          );

      expect((await request('start'))['phase'], 'preparing');
      await until(() => runs.recorder.active && !runs.preparing);
      final id = runs.run!.id;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      location.clock = 1000;
      location.streams.single.add(location.point(36.00005));
      await until(() => runs.run!.checkpointMs == 1000);
      location.clock = 3000;
      location.streams.single.add(location.point(36.00010));
      await until(() => runs.metrics.distanceM > 0);
      final live = await request('status');
      expect(live['sessionId'], id);
      expect(live['activeMs'], greaterThan(0));
      expect((await request('pause', 'stale-session'))['phase'], 'running');
      expect((await request('pause', id))['phase'], 'paused');
      expect((await request('resume', id))['phase'], 'running');
      expect((await request('pause', id))['phase'], 'paused');
      await Future.wait([request('end', id), request('end', id)]);
      final result = await request('end', id);
      expect(result['phase'], 'ended');
      expect(result['saved'], isTrue);
      final records = await store.list('alice');
      expect(records, hasLength(1));
      expect(records.single.id, id);
      expect(
        records.single.inputs.where((i) => i.kind == RunKind.end),
        hasLength(1),
      );
    },
  );

  test('watch recovers the same session after missing live updates', () async {
    await ready();
    final bridge = WearRunBridge(() => runs);
    Future<Map<String, Object?>> status([String? id]) => bridge.handle(
      MethodCall('request', {'command': 'status', 'sessionId': id}),
    );

    await runs.prepareStart();
    final initial = await status();
    final id = initial['sessionId'] as String;
    expect(initial['phase'], 'running');

    // The phone receives fixes while the watch sends no requests.
    location.clock = 1000;
    location.streams.single.add(location.point(36.00010));
    await until(() => runs.run!.checkpointMs == 1000);
    location.clock = 3000;
    location.streams.single.add(location.point(36.00025));
    await until(() => runs.metrics.distanceM > 0);
    final resumed = await status(id);
    expect(resumed['phase'], 'running');
    expect(resumed['sessionId'], id);
    expect(resumed['distanceM'] as num, greaterThan(0));
    expect(location.streams.single.hasListener, isTrue);

    await runs.pause();
    await runs.end();
    runs.clearResult();
    expect((await status())['phase'], 'ready');
    final result = await status(id);
    expect(result['phase'], 'ended');
    expect(result['sessionId'], id);
    expect(result['saved'], isTrue);
    expect(result['distanceM'] as num, greaterThan(0));
    expect(await store.list('alice'), hasLength(1));

    member = 'bob';
    expect((await status(id))['phase'], 'ready');
    expect(await store.list('alice'), hasLength(1));
    expect(await store.list('bob'), isEmpty);
  });

  test(
    'watch restores a dismissed course and ghost verdict from storage',
    () async {
      await ready();
      final bridge = WearRunBridge(() => runs);
      Future<Map<String, Object?>> status(String id) => bridge.handle(
        MethodCall('request', {
          'command': 'status',
          'sessionId': id,
          'mode': 'ghost',
        }),
      );

      await runs.prepareStart();
      final id = runs.run!.id;
      location.clock = 2000;
      await runs.pause();
      await runs.end();
      await until(() => !runs.syncing);

      // Seed a saved verdict directly so the watch must read it without relying
      // on an in-memory active session or a copy of the phone's result screen.
      final saved = (await store.list('alice', id: id)).single;
      runs.clearResult();
      final pending = await status(id);
      expect(pending['phase'], 'ended');
      expect(pending['mode'], 'ghost');
      expect(pending, isNot(contains('courseResult')));
      expect(pending, isNot(contains('ghostResult')));

      await store.synced(saved, {
        'id': id,
        'metrics': {
          'distanceM': 1234.0,
          'activeMs': 221000,
          'paceSecondsPerKm': 179.1,
        },
        'course': {
          'courseName': '테스트 코스',
          'completed': true,
          'recognizedDistanceMeters': 1234.0,
          'courseElapsedSeconds': 221,
        },
        'ghost': {
          'outcome': 'WIN',
          'courseElapsedSeconds': 221,
          'sourceElapsedSeconds': 234,
        },
      });
      await runs.sync();
      final verdict = await status(id);
      expect(verdict['mode'], 'ghost');
      expect(verdict['distanceM'], 1234.0);
      expect(verdict['courseResult'], containsPair('completed', true));
      expect(verdict['ghostResult'], containsPair('outcome', 'WIN'));
      expect(await store.list('alice'), hasLength(1));
    },
  );

  test('QA double end persists one END and retains sequence order', () async {
    await runs.prepareStart();
    location.clock = 3000;
    await runs.pause();
    location.clock = 5000;
    await Future.wait([runs.end(), runs.end()]);
    expect(runs.run!.inputs.where((i) => i.kind == RunKind.end), hasLength(1));
    expect(runs.metrics.elapsedMs, 5000);
    expect(runs.metrics.activeMs, 3000);
    expect(
      runs.run!.inputs.map((i) => i.seq),
      orderedEquals(List.generate(runs.run!.inputs.length, (i) => i)),
    );
  });
  test('QA starting next run before prior cleanup finishes keeps its GPS collector', () async {
    await runs.prepareStart();
    location.clock = 1000;
    await runs.pause();
    await until(() => !runs.syncing && !runs.loadingHistory);
    device.stopGate = Completer<void>();
    final oldEnd = runs.end();
    await until(() => device.stopWaiting);
    expect(runs.run!.phase, RunPhase.ended);
    final oldId = runs.run!.id;
    runs.clearResult();
    final nextStart = runs.prepareStart();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      runs.recorder.active,
      false,
      reason:
          'The previous cleanup must finish before the next recorder starts.',
    );
    device.stopGate!.complete();
    await Future.wait([oldEnd, nextStart]);
    expect(runs.recorder.active, true);
    expect(runs.run!.id, isNot(oldId));
    expect(
      location.streams.last.hasListener,
      true,
      reason: 'A user may confirm the visible result and start again while optional hardware is still stopping.',
    );
    expect(location.streams.where((s) => s.hasListener), hasLength(1));
  });
  test(
    'QA course-only end retains pause and one session when continuing',
    () async {
      await ready();
      runs.selectCourse(const CourseSelection('course-1', 'QA'));
      await runs.prepareStart();
      await runs.prepareStart();
      final id = runs.run!.id;
      location.clock = 2000;
      await runs.pause();
      await runs.endCourse('COURSE_ONLY');
      expect(runs.run!.phase, RunPhase.paused);
      expect(runs.onCourse, false);
      location.clock = 5000;
      await runs.resume();
      expect(runs.run!.id, id);
      expect(runs.metrics.activeMs, 2000);
      expect(
        runs.run!.inputs.where((i) => i.kind == RunKind.segmentEnd),
        hasLength(1),
      );
    },
  );
  test(
    'QA a queued restart can be cancelled while old hardware is stopping',
    () async {
      await runs.prepareStart();
      location.clock = 1000;
      await runs.pause();
      device.stopGate = Completer<void>();
      final ending = runs.end();
      await until(() => device.stopWaiting);
      runs.clearResult();
      final nextStart = runs.prepareStart();
      runs.cancelStart();
      device.stopGate!.complete();
      await Future.wait([ending, nextStart]);
      expect(runs.recorder.active, false);
      expect(await store.list('alice'), hasLength(1));
      expect(location.streams.where((s) => s.hasListener), isEmpty);
    },
  );
  test(
    'QA restart also waits for cleanup after required permission ends a run',
    () async {
      await runs.prepareStart();
      device.allowed = false;
      device.stopGate = Completer<void>();
      final ticking = () async {
        for (var i = 0; i < 5; i++) {
          location.clock += 1000;
          await runs.refreshMeasurement();
        }
      }();
      await until(
        () => device.stopWaiting && runs.run?.phase == RunPhase.ended,
      );
      expect(runs.run!.endReason, 'PERMISSION_REVOKED');
      runs.clearResult();
      device.allowed = true;
      final nextStart = runs.prepareStart();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(runs.recorder.active, false);
      device.stopGate!.complete();
      await Future.wait([ticking, nextStart]);
      expect(runs.recorder.active, true);
      expect(location.streams.last.hasListener, true);
      expect(location.streams.where((s) => s.hasListener), hasLength(1));
    },
  );
  test('QA course offline preparation never starts or records', () async {
    await ready();
    api.prepareError = const ApiException(ApiException.network, 'offline');
    runs.selectCourse(const CourseSelection('course-1', 'QA'));
    await runs.prepareStart();
    expect(runs.recorder.active, false);
    expect(await store.list('alice'), isEmpty);
    expect(runs.error, contains('인터넷'));
    expect(api.started, isEmpty);
  });

  test('QA uncertain nearby branches must not display a definite ghost gap', () {
    // Three parallel stretches, with long connectors outside this local crossing.
    const routePoints = [
      GeoPoint(36, 127),
      GeoPoint(36.004, 127),
      GeoPoint(36.004, 127.0005),
      GeoPoint(36, 127.0005),
      GeoPoint(36, 127.00065),
      GeoPoint(36.004, 127.00065),
    ];
    final route = RouteGeometry(routePoints);
    final intent = GhostStartIntent(
      owner: 'alice',
      id: ghostId,
      startedAt: ghostEpoch,
      course: CourseSnapshot(
        sessionId: ghostId,
        courseId: courseId,
        version: 0,
        route: routePoints,
        totalDistanceMeters: route.length.round(),
      ),
      sourceId: sourceId,
      sourceSeconds: 230,
      clock: const RunClockSample(100000, 'boot-a'),
    );
    final context = GhostRunContext(intent, ghostApproval(intent));
    final run = LocalRun(
      id: ghostId,
      owner: 'alice',
      startedAt: ghostEpoch,
      ghost: context,
    );
    run.inputs.add(
      RunInput(
        seq: 0,
        kind: RunKind.start,
        elapsedMs: 0,
        measuredAt: ghostEpoch,
        reason: 'PACE_V4',
      ),
    );
    for (var n = 0; n <= 12; n++) {
      run.inputs.add(
        RunInput(
          seq: run.inputs.length,
          kind: RunKind.gps,
          elapsedMs: n * 3000,
          measuredAt: ghostEpoch.add(Duration(milliseconds: n * 3000)),
          lat: 36 + n * .001 / 12,
          lng: 127,
          accuracyM: 3,
        ),
      );
    }
    for (var n = 1; n <= 3; n++) {
      run.inputs.add(
        RunInput(
          seq: run.inputs.length,
          kind: RunKind.gps,
          elapsedMs: 36000 + n * 1000,
          measuredAt: ghostEpoch.add(Duration(milliseconds: 36000 + n * 1000)),
          lat: 36.001,
          lng: 127 + n * .0001,
          accuracyM: 3,
        ),
      );
    }
    final tracker = CourseTracker(route)..feed(run.inputs);
    final guidance = RouteGuidance(route)..feed(run.inputs);
    final comparison = compareGhostLive(
      current: run,
      tracker: tracker,
      elapsedMs: 39000,
    );
    debugPrint(
      'QA branches uncertain=${guidance.uncertain}, connected=${tracker.points.last.connected}, s=${tracker.points.last.s}, displayedGap=${comparison.distanceM}',
    );
    expect(
      guidance.uncertain,
      true,
      reason: 'Test route must first establish correspondence uncertainty.',
    );
    expect(
      comparison.distanceM,
      isNull,
      reason: 'An unconfirmed branch cannot establish ahead/behind distance.',
    );
    expect(comparison.timeDeltaMs, isNull);
    run.inputs.add(
      RunInput(
        seq: run.inputs.length,
        kind: RunKind.gps,
        elapsedMs: 40000,
        measuredAt: ghostEpoch.add(const Duration(seconds: 40)),
        lat: 36.001,
        lng: 127.0004,
        accuracyM: 3,
      ),
    );
    tracker.feed(run.inputs);
    guidance.feed(run.inputs);
    expect(guidance.uncertain, false);
    expect(
      compareGhostLive(
        current: run,
        tracker: tracker,
        elapsedMs: 40000,
      ).distanceM,
      isNotNull,
    );
  });

  test('course ghost hides its pin and both gaps during either detour', () {
    final routePoints = [const GeoPoint(36, 127), const GeoPoint(36.01, 127)];
    final route = RouteGeometry(routePoints);
    final intent = ghostIntent();
    final courseIntent = GhostStartIntent(
      owner: intent.owner,
      id: intent.id,
      startedAt: intent.startedAt,
      course: CourseSnapshot(
        sessionId: intent.id,
        courseId: intent.course.courseId,
        version: intent.course.version,
        route: routePoints,
        totalDistanceMeters: route.length.round(),
      ),
      sourceId: intent.sourceId,
      sourceSeconds: 120,
      clock: intent.clock,
    );
    final approval = ghostApproval(courseIntent);
    final playback = approval['playback'] as Map<String, dynamic>;
    playback['spans'] = [
      {
        'fromMs': 0,
        'toMs': 20000,
        'fromPositionM': 0,
        'toPositionM': 80,
        'state': 'TRACKED',
      },
      {'fromMs': 20000, 'toMs': 30000, 'state': 'UNKNOWN'},
      {
        'fromMs': 30000,
        'toMs': 120000,
        'fromPositionM': 90,
        'toPositionM': 1112,
        'state': 'TRACKED',
      },
    ];
    final run = LocalRun(
      id: courseIntent.id,
      owner: courseIntent.owner,
      startedAt: courseIntent.startedAt,
      ghost: GhostRunContext(courseIntent, approval),
    );
    final tracker = CourseTracker(route);
    void fix(int ms, double north, [double east = 0]) {
      run.inputs.add(
        RunInput(
          seq: run.inputs.length,
          kind: RunKind.gps,
          elapsedMs: ms,
          measuredAt: run.startedAt.add(Duration(milliseconds: ms)),
          lat: 36 + north,
          lng: 127 + east,
          accuracyM: 4,
        ),
      );
    }

    GhostLiveComparison at(int ms) =>
        compareGhostLive(current: run, tracker: tracker, elapsedMs: ms);

    fix(0, 0);
    fix(5000, .00015);
    expect(at(5000).position, isNotNull);
    expect(at(5000).distanceM, isNotNull);
    expect(at(5000).timeDeltaMs, isNotNull);

    fix(10000, .0002, .0004);
    expect(at(10000).position, isNull);
    expect(at(10000).distanceM, isNull);
    expect(at(10000).timeDeltaMs, isNull);

    fix(15000, .0002);
    expect(at(15000).position, isNotNull);
    expect(at(15000).distanceM, isNotNull);
    expect(at(15000).timeDeltaMs, isNotNull);

    fix(20000, .0003);
    fix(25000, .00035);
    expect(at(25000).position, isNull);
    expect(at(25000).distanceM, isNull);
    expect(at(25000).timeDeltaMs, isNull);
    fix(30000, .0004);
    expect(at(30000).position, isNotNull);
    expect(at(30000).distanceM, isNotNull);
    expect(at(30000).timeDeltaMs, isNotNull);
  });
}
