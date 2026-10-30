import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/ghost_comparison.dart';
import 'package:wadadak/features/run/presentation/ghost_segment_comparison_screen.dart';
import 'package:wadadak/features/run/presentation/ghost_gap_chart.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'ghost_comparison_test.dart' show comparisonJson, snapshot;

GhostComparison visualFixture({bool missing = false}) {
  final j = comparisonJson();
  (j['result'] as Map)['courseElapsedSeconds'] = 1634;
  (j['result'] as Map)['sourceElapsedSeconds'] = 1652;
  final own = [318, 308, 322, 302, 314, 70],
      ghost = [312, 316, 325, 313, 315, 71];
  var cumulative = 0;
  for (var i = 0; i < 6; i++) {
    final s = (j['segments'] as List)[i] as Map;
    cumulative += ghost[i] - own[i];
    s['ourSeconds'] = missing && i == 1 ? null : own[i];
    s['ghostSeconds'] = ghost[i];
    s['deltaSeconds'] = missing && i == 1 ? null : ghost[i] - own[i];
    s['cumulativeDeltaSeconds'] = missing && i == 1 ? null : cumulative;
    s['unavailableReason'] = missing && i == 1 ? 'GPS_GAP' : null;
  }
  return GhostComparison.fromJson(j);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      font.addFont(
        rootBundle.load(
          'packages/wadadak_design_system/assets/fonts/Pretendard-$weight.otf',
        ),
      );
    }
    await font.load();
  });
  Future<GlobalKey> mount(
    WidgetTester tester, {
    double width = 402,
    double scale = 1,
    bool missing = false,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey(), d = visualFixture(missing: missing);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: WdTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: key,
            child: GhostSegmentComparisonScreen(
              run: snapshot(d.result),
              comparison: d,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    const directory = String.fromEnvironment('D2S_CAPTURE_DIR');
    if (directory.isEmpty) return;
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [320.0, 402.0]) {
    testWidgets('D2-S visual chart and selection fit ${width.toInt()}px', (
      tester,
    ) async {
      final key = await mount(tester, width: width);
      expect(find.text('4구간 5′02″'), findsOneWidget);
      expect(find.text('5 / 6 구간'), findsOneWidget);
      expect(
        tester
            .widget<GhostSegmentPaceChart>(find.byType(GhostSegmentPaceChart))
            .selected,
        3,
      );
      await capture(tester, key, 'd2s-pace-${width.toInt()}');
      await tester.tap(find.byKey(const ValueKey('ghost-pace-hit-1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GhostSegmentPaceChart>(find.byType(GhostSegmentPaceChart))
            .selected,
        0,
      );
      final row = find.byKey(const ValueKey('ghost-segment-1'));
      expect(
        find.descendant(of: row, matching: find.text('05:18')),
        findsOneWidget,
      );
      await tester.tap(find.text('누적 격차'));
      await tester.pumpAndSettle();
      expect(find.byType(GhostGapChart), findsOneWidget);
      expect(find.byType(GhostSegmentPaceChart), findsNothing);
      await capture(tester, key, 'd2s-gap-${width.toInt()}');
      await tester.tap(find.text('페이스'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GhostSegmentPaceChart>(find.byType(GhostSegmentPaceChart))
            .selected,
        0,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'partial segment compares normalized pace and preserves short elapsed time',
    (tester) async {
      await mount(tester);
      final tail = find.text('5–5.2km · 마지막 구간');
      await tester.scrollUntilVisible(tail, 350);
      await tester.tap(tail);
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('ghost-segment-6'));
      expect(
        find.descendant(of: row, matching: find.text('01:10')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('페이스 나 5′50″')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('BEST')),
        findsNothing,
      );
    },
  );
  testWidgets('missing GPS does not become a zero bar or a counted loss', (
    tester,
  ) async {
    await mount(tester, missing: true);
    expect(find.text('4 / 5 구간'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ghost-pace-hit-2')));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('ghost-segment-2'));
    expect(find.descendant(of: row, matching: find.text('—')), findsWidgets);
    expect(
      find.descendant(
        of: row,
        matching: find.text('GPS 공백으로 구간 시간을 확인할 수 없어요.'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'large text keeps partial segment selection and bottom actions usable',
    (tester) async {
      await mount(tester, width: 320, scale: 1.6);
      final tail = find.text('5–5.2km · 마지막 구간');
      await tester.scrollUntilVisible(tail, 350);
      await tester.tap(tail);
      await tester.pumpAndSettle();
      expect(find.text('결과로'), findsOneWidget);
      expect(find.text('전체 러닝 분석'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
