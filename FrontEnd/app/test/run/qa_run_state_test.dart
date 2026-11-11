import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/features/course/detail/course_ranking_state.dart';
import 'package:wadadak/features/review/review_state.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/wear_run_bridge.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/course_tracker.dart';
import 'package:wadadak/features/run/domain/ghost_live_comparison.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/route_guidance.dart';
import 'package:wadadak/features/run/presentation/course_prep_view.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'recording/run_controller_test.dart'
    show TestLocation, FailingStore, until;
import 'recording/course_run_start_test.dart' show CourseApi;
import 'run_device_controller_test.dart' show Device;
import 'ghost_recovery_support.dart';

class TrackingLocation extends TestLocation {
  final settingsUsed = <LocationSettings>[];

  @override
  Stream<Position> positions({required LocationSettings settings}) {
    settingsUsed.add(settings);
    return super.positions(settings: settings);
  }
}

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
  late TrackingLocation location;
  late CourseApi api;
  late RecoveryApi ghostApi;
  late FailingStore store;
  late SlowStopDevice device;
  var lifecycle = AppLifecycleState.resumed;
  String? member;
  Future<String?> Function()? readOwner;
  Future<double?> Function(String)? readWeight;
  setUp(() {
    member = 'alice';
    readOwner = null;
    lifecycle = AppLifecycleState.resumed;
    readWeight = null;
    store = FailingStore();
    location = TrackingLocation();
    api = CourseApi();
    ghostApi = RecoveryApi();
    device = SlowStopDevice();
    runs = RunController(
      store,
      location,
      api,
      () async => readOwner == null ? member : await readOwner!(),
      device: device,
      ghostApi: ghostApi,
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

  void selectCourseForWatch(String mode) {
    if (mode == 'ghost') {
      runs.selectGhost(
        PreparedOwnGhost(
          'alice',
          const GhostCourseContext(courseId, 0),
          OwnGhostCandidate.fromJson({
            'id': sourceId,
            'courseId': courseId,
            'courseVersion': 0,
            'startedAt': ghostEpoch.toIso8601String(),
            'registeredAt': ghostEpoch.toIso8601String(),
            'courseElapsedSeconds': 230,
            'courseDistanceMeters': 1112,
          }),
          OwnGhostReplay.fromJson(
            (ghostApproval(ghostIntent())['playback'] as Map)
                .cast<String, dynamic>(),
          ),
        ),
      );
    } else {
      runs.selectCourse(const CourseSelection(courseId, 'QA'));
    }
  }

  testWidgets('phone offers watch preparation for a selected course and ghost', (
    tester,
  ) async {
    await tester.runAsync(ready);
    selectCourseForWatch('course');
    final screenController = FreeRunController.recording(runs);
    addTearDown(screenController.dispose);
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          freeRunControllerProvider.overrideWithValue(screenController),
          runCourseDetailProvider(courseId).overrideWith(
            (_) => throw StateError('Course metadata is outside this test'),
          ),
          reviewSummaryProvider(courseId).overrideWith(
            (_) => throw StateError('Reviews are outside this test'),
          ),
          courseRankingProvider((courseId: courseId, period: RankingPeriod.all))
              .overrideWith(
                (_) => throw StateError('Rankings are outside this test'),
              ),
        ],
        child: MaterialApp(theme: WdTheme.light(), home: const FreeRunScreen()),
      ),
    );
    final prepareButton = find.widgetWithText(WdButton, '워치로 시작 준비');
    expect(tester.widget<WdButton>(prepareButton).onPressed, isNotNull);

    selectCourseForWatch('ghost');
    await tester.pump();
    expect(find.text('고스트와 달리기'), findsOneWidget);
    expect(tester.widget<WdButton>(prepareButton).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in ['course', 'ghost']) {
    test('locked phone starts armed watch $mode with one GPS stream', () async {
      await ready();
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
      final bridge = WearRunBridge(() => runs);
      Future<Map<String, Object?>> request(String command, [String? id]) =>
          bridge.handle(MethodCall('request', {
            'command': command,
            'mode': mode,
            'sessionId': id,
          }));

      selectCourseForWatch(mode);
      final preparation = runs.prepareWearStart();
      await until(() => location.streams.isNotEmpty);
      final settings = location.settingsUsed.single as AndroidSettings;
      expect(settings.foregroundNotificationConfig, isNotNull);
      expect(runs.wearReadyId, isNull);

      location.streams.single.add(location.point(35.9995));
      await until(() => runs.wearReadyId != null);
      lifecycle = AppLifecycleState.paused;
      binding.handleAppLifecycleStateChanged(lifecycle);
      final approach = await request('status');
      final id = approach['sessionId'] as String;
      expect(approach['phase'], 'approach');
      expect(approach['mode'], mode);
      expect(approach['nearStart'], isFalse);
      expect(approach['startDistanceM'] as num, greaterThan(20));
      expect((await request('start', id))['phase'], 'approach');
      expect(await store.list('alice'), isEmpty);

      location.clock = 2000;
      location.streams.single.add(location.point(36));
      await until(() => runs.courseStart!.nearStart);
      expect((await request('status'))['nearStart'], isTrue);
      location.clock += 11000;
      final stale = await request('status');
      expect(stale['nearStart'], isFalse);
      expect(stale['message'], contains('GPS'));
      expect((await request('start', id))['phase'], 'approach');
      expect((await request('start', 'previous-selection'))['reselectCourse'], isTrue);
      expect(await store.list('alice'), isEmpty);

      location.streams.single.add(location.point(36));
      await until(() => runs.wearCourseHasFix);
      expect((await request('start', id))['phase'], 'preparing');
      await preparation;
      expect((await request('status'))['phase'], 'running');
      expect(runs.run!.id, id);
      expect(runs.onCourse, isTrue);
      expect(location.streams.single.hasListener, isTrue);
      expect(runs.run!.inputs.first.elapsedMs, 0);
      expect(await store.list('alice'), hasLength(1));
      if (mode == 'ghost') {
        expect(ghostApi.posts.single.id, id);
        expect(runs.run!.ghost, isNotNull);
        expect(api.started, isEmpty);
      } else {
        expect(api.started.single.$2, id);
        expect(ghostApi.posts, isEmpty);
      }
    });
  }

  test('cancelling a watch course approach releases GPS without a record', () async {
    await ready();
    final bridge = WearRunBridge(() => runs);
    selectCourseForWatch('course');
    final preparation = runs.prepareWearStart();
    await until(() => location.streams.isNotEmpty);
    location.streams.single.add(location.point(35.9995));
    await until(() => runs.wearReadyId != null);
    final id = runs.wearReadyId;
    await bridge.handle(MethodCall('request', {
      'command': 'cancelCourse',
      'mode': 'course',
      'sessionId': id,
    }));
    await preparation;
    expect(runs.courseStart, isNull);
    expect(runs.wearReadyId, isNull);
    expect(runs.selectedCourse?.courseId, courseId);
    expect(location.streams.single.hasListener, isFalse);
    expect(api.started, isEmpty);
    expect(await store.list('alice'), isEmpty);
  });

  for (final mode in ['course', 'ghost']) {
    test('cancelled watch $mode selection cannot start a free run', () async {
      await ready();
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final bridge = WearRunBridge(() => runs);

      await runs.prepareStart();
      final existingId = runs.run!.id;
      location.clock = 2000;
      await runs.pause();
      await runs.end();
      runs.clearResult();
      final original = (await store.list('alice')).single;

      selectCourseForWatch(mode);
      await runs.prepareStart();
      final staleId = runs.courseStart!.runId;
      expect(runs.courseStart!.nearStart, isTrue);

      Future<Map<String, Object?>> requestStaleStart() =>
          bridge.handle(MethodCall('request', {
            'command': 'start',
            'mode': mode,
            'sessionId': staleId,
          }));

      runs.cancelCourseStart();
      if (mode == 'ghost') {
        runs.clearGhost();
        expect(runs.selectedCourse, isNotNull);
        final ghostReply = await requestStaleStart();
        expect(ghostReply['reselectCourse'], isTrue);
        expect(ghostReply['message'], '코스와 고스트를 다시 선택해 주세요.');
      }
      runs.clearCourse();
      final reply = await requestStaleStart();

      expect(reply['phase'], 'ready');
      expect(reply['reselectCourse'], isTrue);
      expect(reply['message'], contains('다시 선택'));
      expect(runs.recorder.active, isFalse);
      expect(api.started, isEmpty);
      final remaining = (await store.list('alice')).single;
      expect(remaining.id, existingId);
      expect(remaining.inputs.map((input) => input.toJson()),
          original.inputs.map((input) => input.toJson()));
    });
  }

  test('watch course start rechecks selection after async preparation', () async {
    await ready();
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final bridge = WearRunBridge(() => runs);
    runs.selectCourse(const CourseSelection(courseId, 'QA'));
    await runs.prepareStart();
    final staleId = runs.courseStart!.runId;

    final checkingOwner = Completer<void>();
    final release = Completer<void>();
    var reads = 0;
    readOwner = () async {
      if (++reads == 3) {
        checkingOwner.complete();
        await release.future;
      }
      return member;
    };
    final start = await bridge.handle(MethodCall('request', {
      'command': 'start',
      'mode': 'course',
      'sessionId': staleId,
    }));
    expect(start['phase'], 'preparing');
    try {
      await checkingOwner.future.timeout(const Duration(seconds: 2));
      runs.cancelCourseStart();
      runs.clearCourse();
    } finally {
      release.complete();
    }

    Map<String, Object?> result = {};
    for (var attempt = 0; attempt < 40; attempt++) {
      result = await bridge.handle(const MethodCall('request', {'command': 'status'}));
      if (result['phase'] != 'preparing') break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(result['phase'], 'ready');
    expect(result['reselectCourse'], isTrue);
    expect(result['message'], contains('다시 선택'));
    expect(runs.recorder.active, isFalse);
    expect(api.started, isEmpty);
    expect(await store.list('alice'), isEmpty);

    readOwner = null;
    runs.selectCourse(const CourseSelection(courseId, 'QA'));
    await runs.prepareStart();
    final newId = runs.courseStart!.runId;
    expect(newId, isNot(staleId));
    await bridge.handle(MethodCall('request', {
      'command': 'start',
      'mode': 'course',
      'sessionId': newId,
    }));
    await until(() => runs.recorder.active && !runs.preparing);
    expect(runs.run!.id, newId);
    expect(runs.onCourse, isTrue);
    expect(api.started.single.$2, newId);
  });

  test('watch heart rate attaches replay to its original run exactly once', () async {
    await ready();
    final bridge = WearRunBridge(() => runs);
    await runs.prepareStart();
    final id = runs.run!.id;
    final startedAt = runs.run!.startedAt.millisecondsSinceEpoch;

    Future<Object?> send(String session, List<(int, int)> values) async {
      final response = await bridge.handle(
        MethodCall('request', {
          'command': 'heartRate',
          'sessionId': session,
          'samples': [
            for (final (elapsed, bpm) in values) [startedAt + elapsed, bpm],
          ],
        }),
      );
      return response['heartRateAck'];
    }

    location.clock = 2000;
    expect(await send(id, [(1000, 132)]), isTrue);
    final view = FreeRunController.recording(runs);
    addTearDown(view.dispose);
    expect(view.snapshot.currentHeartRateBpm, 132);
    expect(await send('unknown-run', [(1500, 150)]), isFalse);
    expect(await send(id, [(500, 128), (1000, 170)]), isTrue);
    expect(runs.currentHeartRateBpm, 132);
    // A slightly ahead watch clock can put a sample beyond a pause the phone
    // has not written yet. Final results use the authoritative run boundaries.
    expect(await send(id, [(3500, 250)]), isTrue);

    location.clock = 3000;
    await runs.pause();
    expect(runs.currentHeartRateBpm, isNull);
    location.clock = 6000;
    await runs.resume();
    expect(runs.currentHeartRateBpm, isNull);
    expect(await send(id, [(2000, 139)]), isTrue);
    expect(runs.currentHeartRateBpm, isNull);
    location.clock = 9500;
    await runs.pause();
    location.clock = 10000;
    await runs.end();
    expect(runs.run!.phase, RunPhase.ended);
    await until(() => !runs.syncing);
    final inputsBefore = (await store.list('alice', id: id))
        .single.inputs.map((input) => input.toJson()).toList();

    Future<Object?> watchSummary() async {
      final response = await bridge.handle(
        MethodCall('request', {'command': 'status', 'sessionId': id}),
      );
      return response['heartRateSummary'];
    }

    final summaries = StreamIterator(store.watchHeartRateSummary('alice', id));
    addTearDown(summaries.cancel);
    expect(await summaries.moveNext(), isTrue);
    expect(summaries.current, (averageBpm: 133, maxBpm: 139));
    expect(await watchSummary(), {'averageBpm': 133, 'maxBpm': 139});

    // The watch reconnects after a second run has already started.
    runs.clearResult();
    location.clock = 12000;
    await runs.prepareStart();
    expect(runs.run!.id, isNot(id));
    final replay = [(-100, 101), (4000, 155), (7000, 146), (11000, 190)];
    expect(await send(id, replay), isTrue);
    expect(await send(id, replay), isTrue);
    expect(await summaries.moveNext(), isTrue);
    expect(summaries.current, (averageBpm: 136, maxBpm: 146));
    expect(await watchSummary(), isNull);
    expect(runs.currentHeartRateBpm, isNull);
    expect(
      (await store.list('alice', id: id)).single.inputs.map((input) => input.toJson()),
      inputsBefore,
    );

    final database = await store.database;
    final rows = await database.query('run_heart_rates', orderBy: 'measured_at_ms');
    expect(rows.map((row) => row['session_id']), everyElement(id));
    expect(rows.map((row) => row['bpm']), [128, 132, 139, 250, 146]);
    member = 'bob';
    expect(await send(id, [(8000, 160)]), isFalse);
    expect(await database.query('run_heart_rates'), hasLength(5));
    expect(await store.heartRateSummary('bob', id), isNull);

    member = 'alice';
    await runs.bindOwner();
    runs.clearResult();
    expect(await watchSummary(), {'averageBpm': 136, 'maxBpm': 146});
    await store.deleteRecord('alice', id);
    expect(await send(id, [(8000, 160)]), isTrue);
    expect(await database.query('run_heart_rates'), isEmpty);
  });

  test('upgrading a version six run database preserves existing inputs', () async {
    await ready();
    await runs.prepareStart();
    final run = runs.run!;
    final input = run.inputs.first;
    final directory = await Directory.systemTemp.createTemp('wadadak_run_upgrade_');
    final file = '${directory.path}/runs.db';
    final old = RunLocalStore(factory: databaseFactoryFfi, databasePath: file);
    final upgraded = RunLocalStore(factory: databaseFactoryFfi, databasePath: file);
    addTearDown(() async {
      await old.close();
      await upgraded.close();
      await directory.delete(recursive: true);
    });
    await old.create(run, input);
    final db = await old.database;
    await db.execute('DROP TABLE run_heart_rates');
    await db.setVersion(6);
    await old.close();

    final restored = (await upgraded.list('alice', id: run.id)).single;
    expect(restored.inputs.single.toJson(), input.toJson());
    expect((await (await upgraded.database).query('run_heart_rates')), isEmpty);
    expect(await upgraded.heartRateSummary('alice', run.id), isNull);
  });

  test('watch live heart rate expires without a fresh measurement', () async {
    await ready();
    await runs.prepareStart();
    final session = runs.run!;
    location.clock = 1000;
    expect(
      await runs.receiveWearHeartRates('alice', session.id, [
        (measuredAtMs: location.utc.millisecondsSinceEpoch, bpm: 143),
      ]),
      isTrue,
    );
    expect(runs.currentHeartRateBpm, 143);
    location.clock = 16000;
    expect(runs.currentHeartRateBpm, isNull);
  });

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

  for (final mode in ['course', 'ghost']) {
    test('watch distinguishes waiting and failed $mode verdicts', () async {
      await ready();
      final bridge = WearRunBridge(() => runs);
      Future<Map<String, Object?>> status(String id) => bridge.handle(
        MethodCall('request', {
          'command': 'status',
          'sessionId': id,
          'mode': mode,
        }),
      );

      selectCourseForWatch(mode);
      await runs.prepareStart();
      await runs.prepareStart();
      final id = runs.run!.id;
      location.clock = 1000;
      location.streams.last.add(location.point(36.00008));
      await until(() => runs.run!.checkpointMs == 1000);
      location.clock = 3000;
      location.streams.last.add(location.point(36.00018));
      await until(() => runs.metrics.distanceM > 0);
      final live = await status(id);
      expect(live['phase'], 'running');
      expect(live['position'], [36.00018, 127.0]);
      expect(live['nearRoute'], isNotEmpty);
      final nearTrack = live['nearTrack'] as List<List<List<double>>>;
      expect(nearTrack.last.last, [36.00018, 127.0]);
      expect(nearTrack.last.length, greaterThan(1));

      await runs.pause();
      expect(await status(id), isNot(contains('nearTrack')));
      await runs.end();
      await until(() => !runs.syncing);

      final waiting = await status(id);
      expect(waiting['verdictStatus'], 'pending');
      expect(waiting['saved'], isTrue);
      final original = (await store.list('alice', id: id)).single;
      expect(original.syncState, 'processing');

      await store.syncStatus(original, 'blocked', failure: 'TEST_REJECTION');
      await runs.sync();
      final failed = await status(id);
      expect(failed['verdictStatus'], 'failed');
      expect(failed['saved'], isTrue);
      expect(failed, isNot(contains('courseResult')));
      expect(failed, isNot(contains('ghostResult')));

      runs.clearResult();
      final restored = await status(id);
      expect(restored['sessionId'], id);
      expect(restored['verdictStatus'], 'failed');
      expect(restored['saved'], isTrue);

      await store.syncStatus(original, 'processing');
      await runs.sync();
      expect((await status(id))['verdictStatus'], 'pending');

      await store.synced(original, {
        'id': id,
        'metrics': original.summary!['metrics'],
        'course': {
          'courseName': '테스트 코스',
          'completed': false,
          'recognizedDistanceMeters': 10,
          'courseElapsedSeconds': 0,
        },
        if (mode == 'ghost')
          'ghost': {
            'outcome': 'INVALID',
            'courseElapsedSeconds': 0,
            'sourceElapsedSeconds': 230,
          },
      });
      await runs.sync();
      final finalized = await status(id);
      expect(finalized, isNot(contains('verdictStatus')));
      expect(finalized['courseResult'], containsPair('completed', false));
      if (mode == 'ghost') {
        expect(finalized['ghostResult'], containsPair('outcome', 'INVALID'));
      }
      final after = (await store.list('alice')).single;
      expect(after.id, id);
      expect(after.inputs.map((input) => input.toJson()),
          original.inputs.map((input) => input.toJson()));
    });
  }

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
