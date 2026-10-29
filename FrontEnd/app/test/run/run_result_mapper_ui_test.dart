import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/application/run_result_mapper.dart';
import 'package:wadadak/features/run/presentation/free_run_result_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final missingMs in [0, 1]) {
    testWidgets(
      'sensor coverage warning follows every actual missing interval ($missingMs ms)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 874);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final value = <String, dynamic>{
          ...record,
          'metrics': {
            ...(record['metrics'] as Map),
            'cadenceCoverageMs': 380000 - missingMs,
          },
        };
        await tester.pumpWidget(
          ProviderScope(
            overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
            child: MaterialApp(
              theme: WdTheme.light(),
              home: FreeRunResultView(
                run: remoteRunSnapshot(value),
                onConfirm: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('구간 상세 분석'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('측정 상세 및 기준'));
        await tester.tap(find.text('측정 상세 및 기준'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('걸음 센서가 측정되지 않은 구간'),
          missingMs > 0 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

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
        await tester.tap(find.text('구간 상세 분석'));
        await tester.pumpAndSettle();
        expect(find.text('마지막 0.23 km'), findsOneWidget);
        expect(find.text('1 km'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
