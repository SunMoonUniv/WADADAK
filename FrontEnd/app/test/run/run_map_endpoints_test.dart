import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_live_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

void main() {
  final a = RunPoint(36, 127), b = RunPoint(36.001, 127);
  final c = RunPoint(37, 128), d = RunPoint(37.001, 128);
  RunSnapshot snapshot(RunState state, List<List<RunPoint>> segments) =>
      RunSnapshot(
        state: state,
        sessionId: 'record',
        startedAt: DateTime.utc(2026, 10, 15),
        elapsed: const Duration(seconds: 30),
        active: const Duration(seconds: 25),
        distanceMeters: 222,
        inputs: const [],
        segments: segments,
      );
  Future<void> show(WidgetTester tester, RunSnapshot run) => tester.pumpWidget(
    ProviderScope(
      overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
      child: MaterialApp(
        theme: WdTheme.light(),
        home: Scaffold(
          body: SizedBox(height: 400, child: RunRouteView(run: run)),
        ),
      ),
    ),
  );

  testWidgets(
    'server-only historical route shows endpoints without joining GPS gaps',
    (tester) async {
      await show(
        tester,
        snapshot(RunState.finished, [
          [a, b],
          [],
          [c, d],
        ]),
      );
      final map = tester.widget<MapView>(find.byType(MapView));
      expect(map.lines.where((l) => l.points.length > 1).length, 2);
      expect(map.markers.map((m) => m.id), ['run-start', 'run-finish']);
      expect(map.markers.first.position.lat, a.latitude);
      expect(map.markers.last.position.lat, d.latitude);
      expect(find.text('출발'), findsOneWidget);
      expect(find.text('종료'), findsOneWidget);
    },
  );

  testWidgets(
    'active route has a start and current position but no finished marker',
    (tester) async {
      await show(
        tester,
        snapshot(RunState.running, [
          [a, b],
        ]),
      );
      final map = tester.widget<MapView>(find.byType(MapView));
      expect(map.markers.map((m) => m.id), ['run-start']);
      expect(map.myLocationSource, MyLocationSource.app);
      expect(map.myLocation!.lat, b.latitude);
    },
  );

  testWidgets(
    'loop endpoints stay distinguishable and empty route stays empty',
    (tester) async {
      await show(
        tester,
        snapshot(RunState.finished, [
          [a, b, a],
        ]),
      );
      final map = tester.widget<MapView>(find.byType(MapView));
      expect(map.markers.first.position, map.markers.last.position);
      expect(map.markers.first.anchor, isNot(map.markers.last.anchor));
      await show(tester, snapshot(RunState.finished, const []));
      expect(find.byType(MapView), findsNothing);
      expect(find.text('아직 위치 기록이 없어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
