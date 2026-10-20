import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_live_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'run_distance_marker_test.dart' as fixture;

RunSnapshot run(
  double distance, {
  String id = 'live',
  RunState state = RunState.running,
}) => RunSnapshot(
  state: state,
  sessionId: id,
  startedAt: DateTime.utc(2026, 10, 20),
  elapsed: const Duration(minutes: 12),
  active: const Duration(minutes: 11),
  distanceMeters: distance,
  inputs: const [],
  segments: [
    [fixture.point(0), fixture.point(900)],
    [
      fixture.point(10000),
      fixture.point(10000 + (distance - 900).clamp(0, 10000)),
    ],
  ],
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
    testWidgets(
      'live map updates km labels, preserves gaps and resets for a new run at ${width}px',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final capture = GlobalKey();
        Future<void> show(RunSnapshot value) => tester.pumpWidget(
          ProviderScope(
            overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
            child: MaterialApp(
              theme: WdTheme.light(),
              home: RepaintBoundary(
                key: capture,
                child: FreeRunLiveView(
                  run: value,
                  onPause: () {},
                  onResume: () {},
                  onStop: () {},
                ),
              ),
            ),
          ),
        );
        await show(run(1100));
        // The actual live screen opts into markers; start on its left map page.
        await tester.drag(find.byType(PageView), const Offset(700, 0));
        await tester.pumpAndSettle();
        expect(find.text('1 km'), findsOneWidget);
        expect(find.text('2 km'), findsNothing);
        var map = tester.widget<MapView>(find.byType(MapView));
        expect(map.lines.length, 2);
        expect(map.lines[0].points.last.lat, fixture.point(900).latitude);
        expect(map.lines[1].points.first.lat, fixture.point(10000).latitude);
        expect(
          map.markers.singleWhere((m) => m.id == 'run-km-1').position.lat,
          closeTo(fixture.point(10100).latitude, .00000001),
        );
        await show(run(2100));
        await tester.pumpAndSettle();
        expect(find.text('1 km'), findsOneWidget);
        expect(find.text('2 km'), findsOneWidget);
        expect(find.text('3 km'), findsNothing);
        await show(run(2100, state: RunState.paused));
        await tester.pumpAndSettle();
        expect(find.text('2 km'), findsOneWidget);
        expect(tester.takeException(), isNull);
        const out = String.fromEnvironment('RUN_KM_CAPTURE_DIR');
        if (out.isNotEmpty) {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$out/km-map-${width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await show(run(900, id: 'next'));
        await tester.pumpAndSettle();
        map = tester.widget<MapView>(find.byType(MapView));
        expect(map.markers.where((m) => m.id.startsWith('run-km-')), isEmpty);
        expect(find.byType(WdKmMarker), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('existing result route keeps its endpoint-only display', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
        child: MaterialApp(
          home: Scaffold(
            body: RunRouteView(run: run(2100, state: RunState.finished)),
          ),
        ),
      ),
    );
    final map = tester.widget<MapView>(find.byType(MapView));
    expect(map.markers.map((m) => m.id), ['run-start', 'run-finish']);
  });
}
