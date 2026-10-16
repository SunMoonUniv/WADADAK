import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

import 'run_controller_test.dart' as fake;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  test('SQLite reopen, summaries, sync and old-server fallback keep calculated stats', () async {
    final fixture = jsonDecode(
      File('../../run/fixtures/free_result_stats_v2.json').readAsStringSync(),
    ) as Map;
    final inputs = ((fixture['cases'] as List).first['inputs'] as List)
        .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
        .toList();
    final expected = RunCalculator.replay(inputs).resultStats(inputs).toJson();
    final dir = await Directory.systemTemp.createTemp('run-result-stats-');
    final path = '${dir.path}/runs.db';
    var store = RunLocalStore(factory: databaseFactoryFfi, databasePath: path);
    RunController? engine;
    FreeRunController? ui;
    try {
      final run = LocalRun(
        id: 'saved',
        owner: 'alice',
        startedAt: inputs.first.measuredAt,
      );
      await store.create(run, inputs.first);
      await store.append(
        run,
        inputs.sublist(1),
        RunPhase.ended,
        inputs.last.elapsedMs,
        pending: true,
      );
      await store.close();
      store = RunLocalStore(factory: databaseFactoryFfi, databasePath: path);
      final detail = (await store.list('alice', id: 'saved')).single;
      final summary = (await store.list('alice', summaryOnly: true)).single;
      expect(summary.summary!['stats'], expected);
      final gps = fake.TestLocation();
      engine = RunController(
        store,
        gps,
        fake.TestApi(),
        () async => 'alice',
        automaticTicks: false,
        nowMs: gps.nowMs,
      );
      ui = FreeRunController.recording(engine);
      expect(ui.savedSnapshot(detail).resultStats!.toJson(), expected);
      expect(ui.savedSnapshot(summary).resultStats!.toJson(), expected);
      final oldResult = <String, dynamic>{
        'id': 'saved',
        'startedAt': inputs.first.measuredAt.toIso8601String(),
        'metrics': {
          'distanceM': 3200,
          'elapsedMs': inputs.last.elapsedMs,
          'activeMs': inputs.last.elapsedMs,
        },
      };
      await store.synced(detail, oldResult);
      final oldDetail = (await store.list('alice', id: 'saved')).single;
      expect(ui.savedSnapshot(oldDetail).resultStats!.toJson(), expected);
      final v1Result = {
        ...oldResult,
        'stats': {...expected, 'version': 'RESULT_V1', 'elevationGainM': 0.0},
      };
      await store.synced(detail, v1Result);
      final v1Detail = (await store.list('alice', id: 'saved')).single;
      final refreshed = ui.savedSnapshot(v1Detail);
      expect(refreshed.resultStats!.toJson(), expected);
      expect(refreshed.distanceMeters, oldResult['metrics']!['distanceM']);
      expect(
        v1Detail.result,
        v1Result,
      ); // Enrich the view; preserve stored history.
      final result = {...oldResult, 'stats': expected};
      await store.synced(detail, result);
      expect(
        (await store.list('alice', summaryOnly: true)).single.summary!['stats'],
        expected,
      );
      expect(
        (await store.list('alice', id: 'saved')).single.result!['stats'],
        expected,
      );
    } finally {
      ui?.dispose();
      engine?.dispose();
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
