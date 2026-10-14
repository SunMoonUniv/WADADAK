
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/features/run/domain/recording_models.dart' as recording;
import 'package:wadadak/features/run/domain/run_voice.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/presentation/free_run_result_view.dart';
import 'package:wadadak/features/run/presentation/run_history_screen.dart';
import 'package:wadadak/features/run/presentation/run_settings_screen.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'recording/run_controller_test.dart' as fake;

final record = <String, dynamic>{
  'id': 'remote',
  'startedAt': '2026-10-14T00:00:00Z',
  'endReason': 'USER',
  'metrics': {
    'distanceM': 1234.0,
    'elapsedMs': 400000,
    'activeMs': 380000,
    'movingMs': 360000,
    'paceSecondsPerKm': 360000 / 1234,
    'gapCount': 1,
    'averageCadence': 180,
    'cadenceCoverageMs': 300000,
  },
  'routeSegments': [
    [
      {'lat': 36.0, 'lng': 127.0},
      {'lat': 36.001, 'lng': 127.0},
    ],
  ],
  'laps': [
    {
      'number': 1,
      'distanceM': 1000.0,
      'movingMs': 300000,
      'elapsedMs': 320000,
      'complete': true,
    },
    {
      'number': 2,
      'distanceM': 234.0,
      'movingMs': 60000,
      'elapsedMs': 80000,
      'complete': false,
    },
  ],
};

class HistoryApi extends fake.TestApi {
  final deleted = <String>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> history(String owner, {String? cursor}) async {
    if (fail) throw StateError('offline');
    return {
      'items': cursor == null
          ? [record]
          : [
              record,
              {...record, 'id': 'older', 'startedAt': '2026-10-13T00:00:00Z'},
            ],
      'nextCursor': cursor == null ? 'next' : null,
    };
  }

  @override
  Future<Map<String, dynamic>> result(String owner, String id) async => {
    ...record,
    'id': id,
  };
  @override
  Future<void> delete(String owner, String id) async {
    deleted.add(id);
  }
}

class HistoryStore extends fake.FailingStore {
  final removed = <String>{}, pending = <String>{};
  RunVoiceSettings settings = const RunVoiceSettings();
  @override
  Future<List<recording.LocalRun>> list(String owner) async => [];
  @override
  Future<Set<String>> deletedIds(String owner) async => {...removed};
  @override
  Future<List<String>> pendingDeletions(String owner) async => pending.toList();
  @override
  Future<void> deleteRecord(String owner, String id) async {
    removed.add(id);
    pending.add(id);
  }

  @override
  Future<void> deletionSynced(String owner, String id) async {
    pending.remove(id);
  }

  @override
  Future<RunVoiceSettings> voiceSettings(String owner) async => settings;
  @override
  Future<void> saveVoiceSettings(String owner, RunVoiceSettings value) async {
    settings = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [320.0, 402.0]) {
    testWidgets(
      'remote route, lap and cadence result render at ${width.toInt()}px without GPS inputs',
      (tester) async {
        tester.view.physicalSize = Size(width, 874);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
            child: MaterialApp(
              theme: WdTheme.light(),
              home: FreeRunResultView(
                run: remoteRunSnapshot(record),
                onConfirm: () {},
                history: true,
                onDelete: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('1.23 km'), findsOneWidget);
        await tester.ensureVisible(find.text('케이던스'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('180 spm'), findsOneWidget);
        await tester.ensureVisible(find.text('랩 기록'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('마지막 0.23 km'), findsOneWidget);
        expect(find.text('1 km'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'history pagination deduplicates and confirmed deletion stays hidden after refresh; settings persist',
    (tester) async {
      final store = HistoryStore();
      final gps = fake.TestLocation();
      final api = HistoryApi();
      final c = RunController(
        store,
        gps,
        api,
        () async => 'alice',
        automaticTicks: false,
      );
      final ui = FreeRunController.recording(c);
      await tester.pump();
      final bound = c.bindOwner();
      await tester.pump();
      await bound;
      final router = GoRouter(
        initialLocation: Routes.runHistory,
        routes: [
          GoRoute(
            path: Routes.runHistory,
            builder: (_, _) => const RunHistoryScreen(),
          ),
          GoRoute(
            path: '/my/runs/:id',
            builder: (_, s) => RunRecordScreen(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.runSettings,
            builder: (_, _) => const RunSettingsScreen(),
          ),
        ],
      );
      tester.view.physicalSize = const Size(320, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() {
        ui.dispose();
        c.dispose();
        router.dispose();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runControllerProvider.overrideWithValue(c),
            freeRunControllerProvider.overrideWithValue(ui),
            mapEngineProvider.overrideWithValue(MapEngine.dev),
          ],
          child: MaterialApp.router(
            theme: WdTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('내 러닝 1개'), findsOneWidget);
      await tester.tap(find.text('이전 기록 더 보기'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('내 러닝 2개'), findsOneWidget);
      await tester.tap(find.text('1.23 km · 자유 러닝').first);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('기록 삭제'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('취소'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.deleted, isEmpty);
      await tester.tap(find.text('기록 삭제'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('삭제'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('내 러닝 1개'), findsOneWidget);
      await tester.tap(find.text('동기화'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.remoteRecords.where((r) => r['id'] == 'remote'), isEmpty);
      router.push(Routes.runSettings);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('5 km'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(store.settings.distanceKm, 5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

    },
  );
}
