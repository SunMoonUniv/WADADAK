import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/data/ghost_comparison_api.dart';
import 'package:wadadak/features/run/domain/ghost_comparison.dart';
import 'package:wadadak/features/run/presentation/ghost_result_entry_screen.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'ghost_comparison_test.dart'
    show comparisonJson, snapshot, ComparisonServer;
import 'free_ghost_flow_test.dart' show preparation;
import 'ghost_recovery_support.dart';
import 'recording/run_controller_test.dart'
    show FailingStore, TestLocation, TestApi, until;

class ComparisonSource implements GhostComparisonSource {
  ComparisonSource(this.detail);
  final GhostComparison detail;
  Completer<GhostComparison>? gate;
  @override
  Future<GhostComparison> get(String owner, String id) async =>
      gate == null ? detail : gate!.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RunController runs;
  late TestLocation location;
  late TestApi api;
  late ComparisonServer server;
  late ComparisonSource source;
  late GoRouter router;
  var member = 'alice';
  setUp(() {
    sqfliteFfiInit();
    member = 'alice';
    api = TestApi();
    location = TestLocation();
    server = ComparisonServer();
    api.dio.httpClientAdapter = server;
    runs = RunController(
      FailingStore(),
      location,
      api,
      () async => member,
      automaticTicks: false,
      wait: (_) async {},
      utcNow: () => ghostEpoch,
      nowMs: location.nowMs,
    );
    final j = comparisonJson(kind: 'OWN_FREE')..['distanceMeters'] = 1112;
    j['segments'] = [
      {
        'number': 1,
        'fromMeters': 0,
        'toMeters': 1000,
        'fullKilometer': true,
        'ourSeconds': 180,
        'ghostSeconds': 200,
        'deltaSeconds': 20,
        'cumulativeDeltaSeconds': 20,
      },
      {
        'number': 2,
        'fromMeters': 1000,
        'toMeters': 1112,
        'fullKilometer': false,
        'ourSeconds': 20,
        'ghostSeconds': 30,
        'deltaSeconds': 10,
        'cumulativeDeltaSeconds': 30,
      },
    ];
    source = ComparisonSource(GhostComparison.fromJson(j));
    router = GoRouter(
      initialLocation: '/result',
      routes: [
        GoRoute(
          path: '/result',
          builder: (_, _) =>
              GhostResultEntryScreen(run: snapshot(source.detail.result)),
        ),
        GoRoute(
          path: Routes.run,
          builder: (_, _) => Scaffold(
            body: Text('준비 ${runs.selectedFreeGhost?.replay.sourceId}'),
          ),
        ),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    await until(() => !runs.syncing && !runs.loadingHistory);
    await runs.shutdown();
    runs.dispose();
    for (final stream in location.streams) {
      await stream.close();
    }
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.runAsync(() async => runs.bindOwner());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runControllerProvider.overrideWithValue(runs),
          ghostComparisonSourceProvider.overrideWithValue(source),
        ],
        child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'again returns to preparation with exact source and never starts measurement',
    (tester) async {
      server.data = preparation(version: 'GHOST_PLAYBACK_FREE_V2');
      await mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('다시 도전하기'));
      await tester.pumpAndSettle();
      expect(find.text('준비 $sourceId'), findsOneWidget);
      expect(runs.recorder.active, isFalse);
      expect(runs.run, isNull);
      expect(server.requests.single.method, 'GET');
      expect(runs.selectedFreeGhost!.owner, 'alice');
    },
  );
  testWidgets(
    'account switch discards a delayed comparison and hides previous result',
    (tester) async {
      source.gate = Completer<GhostComparison>();
      await mount(tester);
      member = 'bob';
      await tester.runAsync(() async => runs.accountChanged());
      await tester.pump();
      source.gate!.complete(source.detail);
      await tester.pumpAndSettle();
      expect(find.text('계정이 바뀌었어요. 내 기록에서 다시 열어 주세요.'), findsOneWidget);
      expect(find.text('어제의 나를 앞질렀어요.'), findsNothing);
      expect(find.text('다시 도전하기'), findsNothing);
      expect(runs.selectedFreeGhost, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
