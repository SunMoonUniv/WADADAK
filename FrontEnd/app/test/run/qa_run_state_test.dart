import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
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
  String? member;
  Future<double?> Function(String)? readWeight;
  setUp(() {
    member = 'alice';
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
      lifecycleState: () => AppLifecycleState.resumed,
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
}
