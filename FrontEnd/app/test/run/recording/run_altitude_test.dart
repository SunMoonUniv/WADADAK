import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';
import 'package:wadadak/features/run/application/run_sync_worker.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

import 'run_controller_test.dart' as controller_fake;
import 'run_sync_test.dart' as sync_fake;

Map<String, dynamic> fixture(String name) => (jsonDecode(
  File('../../run/fixtures/$name.json').readAsStringSync(),
) as Map).cast<String, dynamic>();

class AltitudeApi extends sync_fake.FakeApi {
  final batches = <List<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> upload(
    RunUpload run,
    List<Map<String, dynamic>> inputs,
  ) {
    batches.add(inputs);
    return super.upload(run, inputs);
  }

  @override
  Future<Map<String, dynamic>> result(String owner, String id) async => {
    'id': id,
    'startedAt': '2026-10-12T00:00:00Z',
    'registeredAt': '2026-10-15T00:00:00Z',
    'metrics': {
      'distanceM': 22.239016,
      'elapsedMs': 120000,
      'activeMs': 100000,
    },
    'routeSegments': <Object>[],
    'laps': <Object>[],
  };
}

class AltitudeLocation extends controller_fake.TestLocation {
  Position vertical(
    double latitude, {
    double altitude = 0,
    double accuracy = 0,
    bool hasAltitude = false,
    bool hasAccuracy = false,
  }) => Position(
    latitude: latitude,
    longitude: 127,
    timestamp: utc,
    accuracy: 3,
    altitude: altitude,
    altitudeAccuracy: accuracy,
    hasAltitude: hasAltitude,
    hasAltitudeAccuracy: hasAccuracy,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<Position> currentPosition({LocationSettings? settings}) async =>
      vertical(36, hasAltitude: true, hasAccuracy: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('shared altitude fixture round-trips without changing distance, time, pace or laps', () {
    List<RunInput> decode(String name) => (fixture(name)['inputs'] as List)
        .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
        .toList();
    final oldInputs = decode('free_pause_v1');
    final newInputs = decode('free_altitude_v1');
    final old = RunCalculator.replay(oldInputs);
    final updated = RunCalculator.replay(newInputs);
    expect(updated.at(120000).toJson(), old.at(120000).toJson());
    expect(
      updated.lapsAt(120000).map((p) => p.toJson()),
      old.lapsAt(120000).map((p) => p.toJson()),
    );
    expect(newInputs[1].altitudeM, 0);
    expect(newInputs[1].altitudeAccuracyM, 0);
    expect(newInputs[2].altitudeM, -3.25);
    expect(newInputs[6].altitudeAccuracyM, isNull);
    expect(newInputs[7].toJson(), isNot(contains('altitudeM')));
    expect(
      newInputs.map((p) => RunInput.fromJson(p.toJson()).toJson()),
      newInputs.map((p) => p.toJson()),
    );
    expect(oldInputs.every((p) => p.altitudeM == null), true);
  });

  test('disk restart and response-loss retry preserve original vertical samples and summary isolation', () async {
    final dir = await Directory.systemTemp.createTemp('run-altitude-');
    final path = '${dir.path}/runs.db';
    var store = RunLocalStore(factory: databaseFactoryFfi, databasePath: path);
    final j = fixture('free_altitude_v1');
    final inputs = (j['inputs'] as List)
        .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
        .toList();
    final run = LocalRun(
      id: 'altitude',
      owner: 'alice',
      startedAt: DateTime.parse(j['startedAt']),
    );
    try {
      await store.create(run, inputs.first);
      await store.append(
        run,
        inputs.sublist(1),
        RunPhase.ended,
        120000,
        pending: true,
      );
      await store.close();
      store = RunLocalStore(factory: databaseFactoryFfi, databasePath: path);
      final recovered = (await store.list('alice', id: run.id)).single;
      expect(
        recovered.inputs.map((p) => p.toJson()),
        inputs.map((p) => p.toJson()),
      );
      final summary = (await store.list('alice', summaryOnly: true)).single;
      expect(summary.inputsLoaded, false);
      expect(jsonEncode(summary.summary), isNot(contains('altitudeM')));
      final api = AltitudeApi()..loseResponse = true;
      final worker = RunSyncWorker(api, store, () async => 'alice');
      await expectLater(worker.sync('alice'), throwsException);
      expect((await store.list('alice', pendingOnly: true)).single.id, run.id);
      await worker.sync('alice');
      expect(api.uploaded, {run.id});
      expect(api.batches.single, inputs.map((p) => p.toJson()).toList());
      final confirmed = (await store.list('alice', id: run.id)).single;
      expect(confirmed.pending, false);
      expect(
        confirmed.inputs.map((p) => p.toJson()),
        inputs.map((p) => p.toJson()),
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('recorder keeps altitude on automatic resume and treats invalid vertical data as absent', () async {
    final store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    var ms = 0;
    final recorder = RunRecorder(store, () async => ms);
    try {
      await recorder.start('resume', 'alice', DateTime.utc(2026, 10, 15));
      await recorder.pause();
      for (var i = 0; i < 3; i++) {
        ms = 1000 + i * 1000;
        await recorder.gps(
          36 + i * .00005,
          127,
          3,
          altitudeM: -3.25,
          altitudeAccuracyM: 1.5,
        );
      }
      expect(recorder.current!.phase, RunPhase.running);
      expect(recorder.current!.inputs.last.altitudeM, -3.25);
      expect(recorder.current!.inputs.last.altitudeAccuracyM, 1.5);
      ms += 1000;
      await recorder.gps(
        36.00015,
        127,
        3,
        altitudeM: double.nan,
        altitudeAccuracyM: 1,
      );
      expect(recorder.current!.inputs.last.kind, RunKind.gps);
      expect(recorder.current!.inputs.last.altitudeM, isNull);
      expect(recorder.current!.inputs.last.altitudeAccuracyM, isNull);
      ms += 1000;
      await recorder.gps(36.0002, 127, 3, altitudeM: 0, altitudeAccuracyM: -1);
      expect(recorder.current!.inputs.last.altitudeM, 0);
      expect(recorder.current!.inputs.last.altitudeAccuracyM, isNull);
    } finally {
      await store.close();
      await recorder.changes.close();
    }
  });

  test('initial fix and live fixes distinguish reported zero height from missing height', () async {
    final store = controller_fake.FailingStore();
    final location = AltitudeLocation();
    final c = RunController(
      store,
      location,
      controller_fake.TestApi(),
      () async => 'alice',
      wait: (_) async {},
      utcNow: () => location.utc,
      nowMs: location.nowMs,
      lifecycleState: () => AppLifecycleState.resumed,
      automaticTicks: false,
    );
    try {
      await c.prepareStart();
      expect(c.run!.inputs.last.altitudeM, 0);
      expect(c.run!.inputs.last.altitudeAccuracyM, 0);
      location.clock = 1000;
      location.streams.single.add(location.vertical(36.00005));
      await controller_fake.until(() => c.run!.inputs.last.elapsedMs == 1000);
      expect(c.run!.inputs.last.toJson(), isNot(contains('altitudeM')));
      location.clock = 2000;
      location.streams.single.add(
        location.vertical(
          36.0001,
          altitude: -3.25,
          accuracy: 2,
          hasAltitude: true,
          hasAccuracy: true,
        ),
      );
      await controller_fake.until(() => c.run!.inputs.last.elapsedMs == 2000);
      expect(c.run!.inputs.last.altitudeM, -3.25);
      expect(c.metrics.distanceM, closeTo(11.119508, .00001));
    } finally {
      await c.shutdown();
      c.dispose();
      for (final stream in location.streams) {
        await stream.close();
      }
      await store.close();
    }
  });
}
