import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/run_share_screen.dart';

void main() {
  final run = RunSnapshot(
    state: RunState.finished,
    sessionId: 'run-1',
    startedAt: DateTime.utc(2026, 11, 3),
    elapsed: const Duration(minutes: 30),
    active: const Duration(minutes: 30),
    distanceMeters: 5000,
    inputs: const [],
    segments: const [
      [RunPoint(37.5, 127), RunPoint(37.51, 127.01), RunPoint(37.52, 127)],
    ],
  );

  testWidgets(
    'result image places stickers, adds the region and shares a png',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shared = <Uint8List>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RunShareScreen(
            run: run,
            region: (_) async => '서울특별시 서초구',
            share: (png) async => shared.add(png),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 사진 없이: 경로 · 거리 · 기록 스티커가 미리 놓인다
      for (final name in ['route', 'distance', 'stats']) {
        expect(find.byKey(ValueKey('sticker-$name')), findsOneWidget);
      }
      expect(find.text('30:00'), findsOneWidget);
      expect(tester.getSize(find.byType(AspectRatio)).aspectRatio, 1);

      // 지역 이름은 찾은 뒤에 고를 수 있고, 누르면 얹는다
      await tester.tap(find.byKey(const ValueKey('chip-region')));
      await tester.pump();
      expect(find.text('서울특별시 서초구'), findsOneWidget);

      final before = tester.getCenter(
        find.byKey(const ValueKey('sticker-region')),
      );
      await tester.drag(
        find.byKey(const ValueKey('sticker-region')),
        const Offset(0, 60),
      );
      await tester.pump();
      expect(
        tester.getCenter(find.byKey(const ValueKey('sticker-region'))).dy,
        greaterThan(before.dy + 40),
      );

      await tester.tap(find.text('9:16'));
      await tester.pump();
      expect(
        tester.getSize(find.byType(AspectRatio)).aspectRatio,
        closeTo(9 / 16, 1e-3),
      );

      await tester.tap(
        find.byKey(const ValueKey('chip-distance')),
      ); // 다시 누르면 뺀다
      await tester.pump();
      expect(find.byKey(const ValueKey('sticker-distance')), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.text('공유하기'));
        for (var i = 0; i < 50 && shared.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(shared, hasLength(1));
      expect(shared.single.sublist(1, 4), 'PNG'.codeUnits);
    },
  );
}
