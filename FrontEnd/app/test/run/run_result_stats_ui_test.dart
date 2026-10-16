import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/domain/run_result_stats.dart';
import 'package:wadadak/features/run/presentation/free_run_result_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

RunSnapshot snapshot(RunResultStats? stats, {double distance = 3200}) =>
    RunSnapshot(
      state: RunState.finished,
      sessionId: 'result',
      startedAt: DateTime.utc(2026, 10, 16),
      elapsed: const Duration(minutes: 20),
      active: const Duration(minutes: 19),
      distanceMeters: distance,
      inputs: const [],
      resultStats: stats,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      fonts.addFont(
        rootBundle.load(
          'packages/wadadak_design_system/assets/fonts/Pretendard-$weight.otf',
        ),
      );
    }
    await fonts.load();
  });
  for (final width in [320.0, 402.0]) {
    testWidgets('real result values and explanations fit ${width}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
          child: MaterialApp(
            theme: WdTheme.light(),
            home: RepaintBoundary(
              key: capture,
              child: FreeRunResultView(
                run: snapshot(
                  const RunResultStats(
                    elevationGainM: 42,
                    elevationPartial: true,
                    bestLapNumber: 3,
                    bestLapPaceSecondsPerKm: 310,
                    bestPaceSecondsPerKm: 275,
                  ),
                ),
                onConfirm: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('42 m'), findsOneWidget);
      expect(find.text('2–3 km'), findsOneWidget);
      expect(find.text('4′35″'), findsOneWidget);
      expect(find.text('최고 구간 페이스 5′10″/km'), findsOneWidget);
      expect(find.textContaining('연속 30초 평균'), findsOneWidget);
      expect(find.text('상승 고도는 고도가 측정된 일부 구간만 포함해요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      const out = String.fromEnvironment('RUN_RESULT_CAPTURE_DIR');
      if (out.isNotEmpty) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$out/result-${width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  testWidgets('missing, flat zero and short runs have distinct messages', (
    tester,
  ) async {
    Future<void> show(RunResultStats? stats) => tester.pumpWidget(
      ProviderScope(
        overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
        child: MaterialApp(
          theme: WdTheme.light(),
          home: FreeRunResultView(
            run: snapshot(stats, distance: 100),
            onConfirm: () {},
          ),
        ),
      ),
    );
    await show(const RunResultStats(elevationGainM: 0));
    await tester.scrollUntilVisible(find.text('0 m'), 150);
    expect(find.text('0 m'), findsOneWidget);
    expect(find.text('최고 구간은 1km 완주 후 표시돼요.'), findsOneWidget);
    expect(find.text('최고 페이스를 계산할 연속 30초 이동 기록이 없어요.'), findsOneWidget);
    expect(find.text('상승 고도를 계산할 고도 측정 데이터가 없어요.'), findsNothing);
    await show(const RunResultStats());
    expect(find.text('상승 고도를 계산할 고도 측정 데이터가 없어요.'), findsOneWidget);
    await show(null);
    expect(find.text('이 기록의 상세 지표를 계산할 원본 데이터가 없어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
