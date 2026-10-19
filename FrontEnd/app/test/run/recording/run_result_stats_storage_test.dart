import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/run_sync_worker.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

import 'run_controller_test.dart' as fake;
import 'run_altitude_test.dart' as transport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  for (final filename in ['free_result_stats_v2', 'free_barometer_v3']) {
    test(
      'SQLite reopen, summaries, sync and old-server fallback keep $filename stats',
      () async {
        final fixture = jsonDecode(
          File('../../run/fixtures/$filename.json').readAsStringSync(),
        ) as Map;
        final inputs = ((fixture['cases'] as List).first['inputs'] as List)
            .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
            .toList();
        final expected = RunCalculator.replay(inputs)
            .resultStats(inputs)
            .toJson();
        final dir = await Directory.systemTemp.createTemp('run-result-stats-');
        final path = '${dir.path}/runs.db';
        var store = RunLocalStore(
          factory: databaseFactoryFfi,
          databasePath: path,
        );
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
          store = RunLocalStore(
            factory: databaseFactoryFfi,
            databasePath: path,
          );
          final detail = (await store.list('alice', id: 'saved')).single;
          expect(
            detail.inputs.map((p) => p.toJson()),
            inputs.map((p) => p.toJson()),
          );
          final summary = (await store.list('alice', summaryOnly: true)).single;
          expect(summary.summary!['stats'], expected);
          expect(jsonEncode(summary.summary), isNot(contains('pressureHpa')));
          if (filename == 'free_barometer_v3') {
            final api = transport.AltitudeApi()..loseResponse = true;
            final worker = RunSyncWorker(api, store, () async => 'alice');
            await expectLater(worker.sync('alice'), throwsException);
            expect(
              (await store.list('alice', id: 'saved')).single.pending,
              true,
            );
            await worker.sync('alice');
            expect(api.batches.single, inputs.map((p) => p.toJson()).toList());
            final synced = (await store.list('alice', id: 'saved')).single;
            expect(synced.pending, false);
            expect(
              synced.inputs.map((p) => p.toJson()),
              inputs.map((p) => p.toJson()),
            );
          }
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
            'stats': {
              ...expected,
              'version': 'RESULT_V1',
              'elevationGainM': 0.0,
            },
          };
          await store.synced(detail, v1Result);
          final v1Detail = (await store.list('alice', id: 'saved')).single;
          final refreshed = ui.savedSnapshot(v1Detail);
          expect(refreshed.resultStats!.toJson(), expected);
          final v2Result = {
            ...v1Result,
            'stats': {
              ...expected,
              'version': 'RESULT_V2',
              'elevationGainM': 0.0,
            },
          };
          await store.synced(detail, v2Result);
          final v2Detail = (await store.list('alice', id: 'saved')).single;
          expect(ui.savedSnapshot(v2Detail).resultStats!.toJson(), expected);
          expect(v2Detail.result, v2Result);
          expect(refreshed.distanceMeters, oldResult['metrics']!['distanceM']);
          expect(
            v1Detail.result,
            v1Result,
          ); // Enrich the view; preserve stored history.
          final result = {...oldResult, 'stats': expected};
          await store.synced(detail, result);
          expect(
            (await store.list(
              'alice',
              summaryOnly: true,
            )).single.summary!['stats'],
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
      },
    );
  }
}
