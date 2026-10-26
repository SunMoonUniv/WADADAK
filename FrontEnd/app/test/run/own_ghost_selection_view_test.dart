import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/application/own_ghost_controller.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';
import 'package:wadadak/features/run/presentation/own_ghost_selection_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'own_ghost_test_support.dart';

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
  for (final size in [const Size(402, 1104), const Size(320, 640)]) {
    testWidgets(
      'Figma C9 selection and preparation remain usable at ${size.width}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = FakeOwnGhostSource();
        final c = OwnGhostController(
          source,
          owner: 'owner-a',
          course: fixtureCourse(),
        );
        addTearDown(c.dispose);
        await c.load();
        PreparedOwnGhost? submitted;
        final capture = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: WdTheme.light(),
            home: RepaintBoundary(
              key: capture,
              child: OwnGhostSelectionView(
                controller: c,
                courseName: '한강 야경 5K',
                onBack: () {},
                onPrepared: (p) => submitted = p,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WdStatSummary), findsOneWidget);
        expect(find.byType(WdMyRankCard), findsOneWidget);
        expect(find.byType(WdRankList), findsOneWidget);
        expect(find.text('내 기록 6개'), findsOneWidget);
        expect(
          tester
              .widget<WdButton>(find.widgetWithText(WdButton, '이 고스트와 대결하기'))
              .onPressed,
          isNull,
        );
        expect(source.playbackRequests, isEmpty);

        Future<void> png(String state) async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/own-ghost-check/${size.width.toInt()}-$state.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await png('selection');
        final best = c.summary.best!;
        await tester.ensureVisible(find.byType(WdMyRankCard));
        await tester.tap(find.byType(WdMyRankCard));
        await tester.pumpAndSettle();
        expect(c.prepared!.candidate.id, best.id);
        await png('ready');
        await tester.tap(find.text('이 고스트와 대결하기'));
        await tester.pump();
        expect(submitted!.candidate.id, best.id);
        expect(source.playbackRequests, [best.id]);
        await tester.drag(find.byType(ListView), const Offset(0, 800));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 800));
        await tester.pumpAndSettle();
        await tester.tap(find.text('이번 달'));
        await tester.pumpAndSettle();
        expect(source.requests.last.period, OwnGhostPeriod.month);
        expect(c.prepared, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'quality failure disables CTA and explains the restriction at the visible footer',
    (tester) async {
      final source = FakeOwnGhostSource();
      final c = OwnGhostController(
        source,
        owner: 'owner-a',
        course: fixtureCourse(),
      );
      addTearDown(c.dispose);
      await c.load();
      source.onPlayback = (_, id) async => OwnGhostReplay.fromJson({
        ...replayJson(c.summary.best!),
        'eligible': false,
        'unavailableReasons': ['CONTINUOUS_GAP_EXCEEDED'],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: WdTheme.light(),
          home: OwnGhostSelectionView(
            controller: c,
            courseName: '코스',
            onBack: () {},
            onPrepared: (_) => fail('unavailable'),
          ),
        ),
      );
      await tester.tap(find.byType(WdMyRankCard));
      await tester.pumpAndSettle();
      expect(find.text('GPS 공백이 많은 기록이에요. 다른 기록을 선택해 주세요.'), findsOneWidget);
      expect(
        tester
            .widget<WdButton>(find.widgetWithText(WdButton, '이 고스트와 대결하기'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty period and long course name have no overflow on narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = FakeOwnGhostSource()
        ..page = OwnGhostPage(const [], null, OwnGhostSummary.empty);
      final c = OwnGhostController(
        source,
        owner: 'owner-a',
        course: fixtureCourse(),
      );
      addTearDown(c.dispose);
      await c.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: WdTheme.light(),
          home: OwnGhostSelectionView(
            controller: c,
            courseName: '이름이 아주 길고 상세한 한강 야경을 달리는 아름다운 코스',
            onBack: () {},
            onPrepared: (_) => fail('empty'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('이 코스의 완주 기록이 없어요. 먼저 코스를 완주해 보세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
