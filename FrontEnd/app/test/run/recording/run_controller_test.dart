import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';
import 'package:wadadak/features/run/data/run_api_client.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/data/run_location.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

final epoch = DateTime.utc(2026, 10, 13);

class TestLocation extends RunLocation {
  int clock = 0;
  Object? setupError;
  Completer<Position>? pendingReady;
  LocationPermission allowed = LocationPermission.whileInUse;
  RunSetupAction? opened;
  final streams = <StreamController<Position>>[];
  DateTime get utc => epoch.add(Duration(milliseconds: clock));
  Position point(double lat, {DateTime? timestamp}) => Position(
    latitude: lat,
    longitude: 127,
    timestamp: timestamp ?? utc,
    accuracy: 3,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
  @override
  Future<int> nowMs() async => clock;
  @override
  Future<Position> ready() async {
    if (setupError != null) throw setupError!;
    if (pendingReady != null) return pendingReady!.future;
    return point(36);
  }

  @override
  Future<LocationPermission> permission() async => allowed;
  @override
  Future<void> openSettings(RunSetupAction action) async => opened = action;
  @override
  Stream<Position> positions() {
    final stream = StreamController<Position>();
    streams.add(stream);
    return stream.stream;
  }
}

class TestApi extends RunApiClient {
  TestApi() : super(Dio());
  final historyOwners = <String>[];
  @override
  Future<Map<String, dynamic>> history(String owner, {String? cursor}) async {
    historyOwners.add(owner);
    return {'items': <Object>[], 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>> prepare(LocalRun run) async => {
    'processing': 'PROCESSING',
  };
  @override
  Future<Map<String, dynamic>> status(LocalRun run) async => {
    'processing': 'PROCESSING',
  };
}

class FailingStore extends RunLocalStore {
  FailingStore()
    : super(factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
  bool failAppend = false;
  @override
  Future<void> append(
    LocalRun run,
    List<RunInput> inputs,
    RunPhase phase,
    int checkpointMs, {
    bool pending = false,
    String? endReason,
  }) async {
    if (failAppend) throw StateError('disk full');
    await super.append(
      run,
      inputs,
      phase,
      checkpointMs,
      pending: pending,
      endReason: endReason,
    );
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), true, reason: 'asynchronous operation did not finish');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RunController controller;
  late TestLocation location;
  late TestApi api;
  late FailingStore store;
  String? owner;
  var lifecycle = AppLifecycleState.resumed;

  RunController build({Future<void> Function(Duration)? wait}) => RunController(
    store,
    location,
    api,
    () async => owner,
    wait: wait ?? (_) async {},
    utcNow: () => location.utc,
    lifecycleState: () => lifecycle,
    automaticTicks: false,
  );

  setUp(() {
    sqfliteFfiInit();
    owner = 'alice';
    lifecycle = AppLifecycleState.resumed;
    location = TestLocation();
    api = TestApi();
    store = FailingStore();
    controller = build();
  });
  tearDown(() async {
    await until(() => !controller.syncing && !controller.loadingHistory);
    await controller.shutdown();
    controller.dispose();
    for (final stream in location.streams) {
      await stream.close();
    }
  });

  test(
    'cancelled countdown cannot stop the next start or create a record',
    () async {
      await controller.shutdown();
      controller.dispose();
      store = FailingStore();
      final waits = <Completer<void>>[];
      controller = build(
        wait: (_) {
          final done = Completer<void>();
          waits.add(done);
          return done.future;
        },
      );
      final first = controller.prepareStart();
      await until(() => waits.length == 1);
      expect(await store.list('alice'), isEmpty);
      controller.cancelStart();
      final second = controller.prepareStart();
      await until(() => waits.length == 2);
      waits[0].complete();
      await first;
      expect(location.streams.last.hasListener, true);
      expect(location.streams.first.hasListener, false);
      expect(await store.list('alice'), isEmpty);
      for (var i = 1; i <= 3; i++) {
        await until(() => waits.length > i);
        waits[i].complete();
      }
      await second;
      expect(controller.recorder.active, true);
      expect((await store.list('alice')).length, 1);
      expect(location.streams.last.hasListener, true);
    },
  );

  test('background GPS error keeps collection and resumes without bridging the gap', () async {
    await controller.prepareStart();
    location.clock = 1000;
    location.streams.single.add(location.point(36.00005));
    await until(() => controller.run!.checkpointMs == 1000);
    lifecycle = AppLifecycleState.paused;
    location.clock = 2000;
    location.streams.single.addError(StateError('temporary GPS failure'));
    await until(() => controller.run!.inputs.last.kind == RunKind.gap);
    expect(location.streams.single.hasListener, true);
    location.clock = 20000;
    location.streams.single.add(location.point(36.01));
    await until(() => controller.run!.checkpointMs == 20000);
    location.clock = 21000;
    location.streams.single.add(location.point(36.01005));
    await until(() => controller.run!.checkpointMs == 21000);
    location.clock = 22000;
    location.streams.single.add(location.point(36.0101));
    await until(() => controller.run!.checkpointMs == 22000);
    expect(controller.metrics.distanceM, closeTo(11.119508, 0.00001));
    expect(controller.metrics.elapsedMs, 22000);
    expect(controller.storageFault, false);
  });

  test(
    'cached old GPS fixes are excluded and checkpoint time continues',
    () async {
      await controller.prepareStart();
      location.clock = 20000;
      location.streams.single.add(location.point(36.001, timestamp: epoch));
      await until(() => controller.run!.inputs.last.kind == RunKind.gap);
      expect(
        controller.run!.inputs.where((p) => p.kind == RunKind.gps).length,
        1,
      );
      for (var i = 0; i < 5; i++) {
        await controller.refreshMeasurement();
      }
      expect(controller.metrics.elapsedMs, 20000);
      expect((await store.list('alice')).single.checkpointMs, 20000);
      expect(controller.metrics.distanceM, 0);
    },
  );

  test('permission revocation ends durably and offers app settings', () async {
    await controller.prepareStart();
    location.allowed = LocationPermission.deniedForever;
    location.clock = 1000;
    location.streams.single.addError(StateError('permission revoked'));
    await until(
      () =>
          controller.run?.phase == RunPhase.ended &&
          !location.streams.single.hasListener,
    );
    final saved = (await store.list('alice')).single;
    expect(saved.endReason, 'PERMISSION_REVOKED');
    expect(controller.setupAction, RunSetupAction.appSettings);
    await controller.openSettings();
    expect(location.opened, RunSetupAction.appSettings);
    expect(controller.records, isEmpty);
  });

  test(
    'failed storage freezes durable metrics and rejects queued samples',
    () async {
      await controller.prepareStart();
      location.clock = 1000;
      location.streams.single.add(location.point(36.00005));
      await until(() => controller.run!.checkpointMs == 1000);
      location.clock = 2000;
      location.streams.single.add(location.point(36.0001));
      await until(() => controller.run!.checkpointMs == 2000);
      store.failAppend = true;
      location.clock = 3000;
      location.streams.single.add(location.point(36.0001));
      location.streams.single.add(location.point(36.00015));
      await until(() => controller.storageFault);
      expect(location.streams.single.hasListener, false);
      location.clock = 30000;
      await controller.refreshMeasurement();
      expect(controller.metrics.elapsedMs, 2000);
      expect(controller.metrics.distanceM, closeTo(11.119508, 0.00001));
      await expectLater(
        controller.recorder.gps(36.01, 127, 3),
        throwsA(isA<RunStorageFailure>()),
      );
      final saved = (await store.list('alice')).single;
      expect(saved.checkpointMs, 2000);
      expect(saved.inputs.length, 4);
      store.failAppend = false;
      final restarted = RunRecorder(store, () async => location.clock);
      final recovered = (await restarted.recover('alice')).single;
      expect(recovered.endReason, 'INTERRUPTED');
      expect(recovered.inputs.last.elapsedMs, 2000);
      await restarted.close();
    },
  );

  test(
    'invalid end operation does not disable healthy storage or GPS',
    () async {
      await controller.prepareStart();
      await controller.end();
      expect(controller.storageFault, false);
      expect(controller.recorder.active, true);
      expect(location.streams.single.hasListener, true);
      await controller.pause();
      await controller.end();
      expect(controller.run!.phase, RunPhase.ended);
    },
  );

  test(
    'GPS setup failure has an actionable setting and creates no session',
    () async {
      location.setupError = const RunSetupException(
        '위치 서비스를 켜 주세요.',
        action: RunSetupAction.locationSettings,
      );
      await controller.prepareStart();
      expect(controller.preparing, false);
      expect(controller.setupAction, RunSetupAction.locationSettings);
      await controller.openSettings();
      expect(location.opened, RunSetupAction.locationSettings);
      expect(await store.list('alice'), isEmpty);
    },
  );

  test('account change finalizes old run and isolates records', () async {
    await controller.prepareStart();
    owner = 'bob';
    await controller.accountChanged();
    expect(controller.currentOwner, 'bob');
    expect(controller.run, null);
    expect(controller.records, isEmpty);
    expect((await store.list('alice')).single.endReason, 'ACCOUNT_CHANGED');
    expect(location.streams.single.hasListener, false);
    await controller.prepareStart();
    expect(controller.run!.owner, 'bob');
  });

  test('system permission dialog does not cancel preparation', () async {
    location.pendingReady = Completer<Position>();
    final beginning = controller.prepareStart();
    await until(() => controller.preparing);
    lifecycle = AppLifecycleState.paused;
    controller.didChangeAppLifecycleState(lifecycle);
    expect(controller.preparing, true);
    expect(controller.countdown, null);
    lifecycle = AppLifecycleState.resumed;
    controller.didChangeAppLifecycleState(lifecycle);
    location.pendingReady!.complete(location.point(36));
    await beginning;
    expect(controller.recorder.active, true);
  });
}
