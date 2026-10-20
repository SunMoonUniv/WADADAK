import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/run_lap.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/run_lap_list.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

void main() {
  for (final phase in [RunState.running, RunState.paused, RunState.finished]) {
    testWidgets('lap times and pace both use moving time in ${phase.name}', (
      tester,
    ) async {
      final run = RunSnapshot(
        state: phase,
        sessionId: 'lap-time',
        startedAt: DateTime.utc(2026, 10, 20),
        elapsed: const Duration(seconds: 240),
        active: const Duration(seconds: 160),
        moving: const Duration(seconds: 100),
        distanceMeters: 1500,
        inputs: const [],
        laps: const [
          RunLap(
            number: 1,
            distanceM: 1000,
            movingMs: 60000,
            elapsedMs: 120000,
            complete: true,
          ),
          RunLap(
            number: 2,
            distanceM: 500,
            movingMs: 40000,
            elapsedMs: 120000,
            complete: false,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: WdTheme.light(),
          home: Scaffold(body: RunLapList(run: run)),
        ),
      );
      expect(find.text('이동 시간'), findsOneWidget);
      expect(find.text('시간'), findsNothing);
      expect(find.text('01:00'), findsOneWidget);
      expect(find.text('00:40'), findsOneWidget);
      expect(find.text('02:00'), findsNothing);
      expect(find.text('02:40'), findsNothing);
      expect(find.text('1′00″'), findsOneWidget);
      expect(find.text('1′20″'), findsOneWidget);
    });
  }
}
