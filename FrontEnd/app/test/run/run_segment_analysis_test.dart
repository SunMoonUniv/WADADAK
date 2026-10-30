import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/features/run/data/run_splits_api.dart';
import 'package:wadadak/features/run/domain/run_lap.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/domain/run_result_stats.dart';
import 'package:wadadak/features/run/presentation/run_segment_analysis_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

/// D3·D5·D6 구간 분석(2026-10-29 결정): 서버 구간 값 · 유지력/안정도 · 경사도 · 해설
void main() {
  test('steadiness is 100 − 8 × coefficient of variation, needs two segments', () {
    expect(steadinessPercent([318, 308, 322, 302, 314]), 82); // Figma D3 페이스
    expect(steadinessPercent([172, 178, 175, 186, 179]), 79);
    expect(steadinessPercent([300, 300]), 100);
    expect(steadinessPercent([300, 600]), 0); // 0 아래는 0
    expect(steadinessPercent([300]), isNull);
  });

  test('slope by elevation change over segment distance', () {
    expect(slopeLabel(-8, 1000), '내리막'); // Figma D6
    expect(slopeLabel(12, 1000), '완만');
    expect(slopeLabel(24, 1000), '완만');
    expect(slopeLabel(32, 1000), '가파름');
    expect(slopeLabel(3, 1000), '평지');
    expect(slopeLabel(-5, 1000), '평지');
  });

  final paces = [318, 308, 322, 302, 314];
  final run = RunSnapshot(
    state: RunState.finished,
    sessionId: 'r1',
    startedAt: DateTime.utc(2026, 10, 30),
    elapsed: const Duration(minutes: 27),
    active: const Duration(minutes: 27),
    distanceMeters: 5210,
    inputs: const [],
    averageCadence: 178,
    resultStats: const RunResultStats(elevationGainM: 86, bestLapNumber: 4),
    laps: [
      for (var i = 0; i < 5; i++)
        RunLap(number: i + 1, distanceM: 1000, movingMs: paces[i] * 1000, elapsedMs: paces[i] * 1000, complete: true),
      const RunLap(number: 6, distanceM: 210, movingMs: 66000, elapsedMs: 66000, complete: false),
    ],
  );
  const splits = [
    RunSplit(number: 1, cadence: 172, elevationChangeM: 18, cumulativeGainM: 18),
    RunSplit(number: 2, cadence: 178, elevationChangeM: 24, cumulativeGainM: 42),
    RunSplit(number: 3, cadence: 175, elevationChangeM: 32, cumulativeGainM: 74),
    RunSplit(number: 4, cadence: 186, elevationChangeM: -8, cumulativeGainM: 74),
    RunSplit(number: 5, cadence: 179, cumulativeGainM: 86), // 고도 자료가 끊긴 구간
    RunSplit(number: 6, cadence: 180, elevationChangeM: 0, cumulativeGainM: 86),
  ];

  Future<void> show(WidgetTester tester, Future<List<RunSplit>> Function() load) async {
    tester.view.physicalSize = const Size(402, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [runSplitsProvider.overrideWith((ref, id) => load())],
      child: MaterialApp(theme: WdTheme.light(), home: RunSegmentAnalysisScreen(run: run)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('pace tab: policy best segment, steadiness, cadence column, no ghost column', (tester) async {
    await show(tester, () async => splits);
    expect(find.text('4구간 5′02″'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('고스트 대비'), findsNothing);
    expect(find.text('186'), findsOneWidget); // 4 km 케이던스
    expect(find.text('마지막 0.21 km'), findsOneWidget); // 부분 구간은 표에만
    expect(find.text('4구간에서 가장 빨랐어요(5′02″).'), findsOneWidget);
  });

  testWidgets('cadence tab: highest segment and steadiness', (tester) async {
    await show(tester, () async => splits);
    await tester.tap(find.text('케이던스').first);
    await tester.pumpAndSettle();
    expect(find.text('구간별 케이던스 (1km 단위)'), findsOneWidget);
    expect(find.text('4구간 186spm'), findsOneWidget);
    expect(find.text('79%'), findsOneWidget);
    expect(find.text('4구간에서 186spm으로 가장 높았어요.'), findsOneWidget);
  });

  testWidgets('elevation tab: change with downhill, gaps as —, slope words', (tester) async {
    await show(tester, () async => splits);
    await tester.tap(find.text('고도').first);
    await tester.pumpAndSettle();
    expect(find.text('구간별 고도 변화 (1km 단위)'), findsOneWidget);
    expect(find.text('3구간 +32 m'), findsOneWidget);
    expect(find.text('+86 m'), findsOneWidget); // 누적 상승고도 = 결과 상승 고도
    expect(find.text('−8 m'), findsWidgets); // 내리막 변화(표·축)
    expect(find.text('내리막'), findsOneWidget);
    expect(find.text('가파름'), findsOneWidget);
    expect(find.text('완만'), findsNWidgets(2));
    expect(find.text('평지'), findsOneWidget); // 마지막 부분 구간 0 m
    expect(find.text('3구간에서 가장 많이 올랐어요. 전체 상승 86 m.'), findsOneWidget);
    expect(find.text('고도 자료가 끊긴 구간은 변화를 표시할 수 없어요.'), findsOneWidget);
  });

  testWidgets('record not on the server yet shows sync waiting for cadence and elevation', (tester) async {
    await show(tester, () async => throw const ApiException('RUN-002', '기록을 찾을 수 없어요.'));
    expect(find.text('4구간 5′02″'), findsOneWidget); // 페이스는 기기 랩으로 보인다
    await tester.tap(find.text('케이던스').first);
    await tester.pumpAndSettle();
    expect(find.text('기록을 서버에 올린 뒤 볼 수 있어요.'), findsOneWidget);
    await tester.tap(find.text('고도').first);
    await tester.pumpAndSettle();
    expect(find.text('기록을 서버에 올린 뒤 볼 수 있어요.'), findsOneWidget);
    expect(find.text('+86 m'), findsOneWidget);
  });
}
