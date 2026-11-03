import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/run_result_mapper.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/run_calories.dart';
import 'package:wadadak/features/my/run_history_rows.dart';

import 'recording/run_controller_test.dart' show TestLocation, TestApi, until;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  test(
    'approved formula, fractional metres, missing weight and invalid values',
    () {
      expect(estimateRunCalories(65, 5000), 325);
      expect(estimateRunCalories(65, 1234.5), closeTo(80.2425, 1e-10));
      expect(estimateRunCalories(65, 0), 0);
      expect(estimateRunCalories(null, 5000), isNull);
      expect(estimateRunCalories(0, 5000), isNull);
      expect(estimateRunCalories(65, double.nan), isNull);
      expect(formatRunCalories(325), '325 kcal');
    },
  );
  test('START weight survives storage and server correction without using a later profile', () async {
    final store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    var clock = 0;
    final recorder = RunRecorder(
      store,
      () async => clock,
      motionFiltering: false,
    );
    addTearDown(recorder.close);
    await recorder.start('calories', 'alice', DateTime.utc(2026), weightKg: 65);
    await recorder.gps(36, 127, 3);
    clock = 1000;
    await recorder.gps(36.00005, 127, 3);
    await recorder.pause();
    clock = 2000;
    await recorder.end();
    final saved = (await store.list('alice')).single;
    expect(saved.weightKg, 65);
    final row = (await store.list('alice', summaryOnly: true)).single;
    expect(
      row.summary!['metrics']['estimatedCaloriesKcal'],
      closeTo(65 * recorder.metrics.distanceM / 1000, 1e-10),
    );
    final response = {
      'id': saved.id,
      'startedAt': saved.startedAt.toIso8601String(),
      'metrics': {
        'distanceM': 5000,
        'elapsedMs': 2000,
        'weightKg': 65,
        'estimatedCaloriesKcal': 325.0,
      },
      'routeSegments': <Object>[],
    };
    await store.synced(saved, response);
    final result = remoteRunSnapshot(
      (await store.list('alice')).single.result!,
    );
    expect(result.estimatedCaloriesKcal, 325);
    expect(
      remoteRunSnapshot({
        ...response,
        'metrics': {'distanceM': 5000},
      }).estimatedCaloriesKcal,
      isNull,
    );
  });
  test('actual start snapshots the available weight once and keeps offline start available', () async {
    final store = RunLocalStore(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final gps = TestLocation();
    var weight = 65.0, reads = 0;
    final runs = RunController(
      store,
      gps,
      TestApi(),
      () async => 'alice',
      nowMs: gps.nowMs,
      utcNow: () => gps.utc,
      automaticTicks: false,
      lifecycleState: () => AppLifecycleState.resumed,
      wait: (_) async {},
      weightAtStart: (_) async {
        reads++;
        return weight;
      },
    );
    await runs.bindOwner();
    await runs.prepareStart();
    expect(runs.run!.weightKg, 65);
    weight = 80;
    gps.clock = 1000;
    await runs.recorder.gps(36, 127, 3);
    gps.clock = 2000;
    await runs.recorder.gps(36.00005, 127, 3);
    final ui = FreeRunController.recording(runs);
    expect(
      ui.snapshot.estimatedCaloriesKcal,
      closeTo(65 * runs.metrics.distanceM / 1000, 1e-9),
    );
    expect(reads, 1);
    ui.dispose();
    await until(() => !runs.syncing && !runs.loadingHistory);
    await runs.shutdown();
    runs.dispose();
    for (final stream in gps.streams) {
      await stream.close();
    }
  });
  test('totals do not treat unknown historical calories as zero', () {
    RunHistoryRow row(String id, double? kcal) => RunHistoryRow(
      id: id,
      startedAt: DateTime.utc(2026),
      distanceMeters: 5000,
      elapsed: const Duration(minutes: 30),
      moving: const Duration(minutes: 30),
      paceSecondsPerKm: 360,
      syncState: 'synced',
      estimatedCaloriesKcal: kcal,
    );
    expect(
      RunTotals.of([row('a', 325), row('b', 100)]).estimatedCaloriesKcal,
      425,
    );
    expect(
      RunTotals.of([row('a', 325), row('old', null)]).estimatedCaloriesKcal,
      isNull,
    );
  });
}
