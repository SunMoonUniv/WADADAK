import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/features/run/application/own_ghost_controller.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';
import 'package:wadadak/features/run/presentation/ghost_runner_selection_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';
import 'own_ghost_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final w in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      font.addFont(
        rootBundle.load(
          'packages/wadadak_design_system/assets/fonts/Pretendard-$w.otf',
        ),
      );
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  Future<
    ({OwnGhostController choices, FakeOwnGhostSource source, GlobalKey capture})
  >
  mount(
    WidgetTester tester, {
    double width = 402,
    FakeCourseRankingApi? rankings,
    ValueChanged<PreparedOwnGhost>? onPrepared,
    ValueChanged<GhostCandidate>? onPublic,
    VoidCallback? onMore,
  }) async {
    tester.view.physicalSize = Size(width, 995);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = FakeOwnGhostSource();
    final choices = OwnGhostController(
      source,
      owner: 'owner-a',
      course: fixtureCourse(),
    );
    addTearDown(choices.dispose);
    await choices.load();
    final capture = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rankingApiClientProvider.overrideWithValue(
            rankings ?? FakeCourseRankingApi(),
          ),
        ],
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: WdTheme.light(),
            home: GhostRunnerSelectionView(
              controller: choices,
              courseName: '한강 야경 5K',
              onBack: () {},
              onMoreOwn: onMore ?? () {},
              onPrepared: onPrepared ?? (_) {},
              onPublic: onPublic ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (choices: choices, source: source, capture: capture);
  }

  for (final width in [320.0, 402.0]) {
    testWidgets('C2 summary selects a verified own record and fits $width', (
      tester,
    ) async {
      PreparedOwnGhost? chosen;
      var more = 0;
      final mounted = await mount(
        tester,
        width: width,
        onPrepared: (p) => chosen = p,
        onMore: () => more++,
      );
      expect(find.text('내 과거 기록'), findsOneWidget);
      expect(find.text('다른 러너 기록'), findsOneWidget);
      expect(find.byType(WdTabBar), findsNothing);
      expect(
        tester
            .widget<WdButton>(find.widgetWithText(WdButton, '이 고스트와 대결하기'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('ghost-choice-best')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이 고스트와 대결하기'));
      expect(chosen!.candidate.id, mounted.choices.summary.best!.id);
      expect(mounted.source.playbackRequests, [chosen!.candidate.id]);
      await tester.tap(find.text('내 기록 전체 보기'));
      expect(more, 1);
      expect(find.textContaining('예상 승률'), findsNothing);
      expect(tester.takeException(), isNull);
      const dir = String.fromEnvironment('GHOST_UI_CAPTURE_DIR');
      if (dir.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary =
              mounted.capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/ghost-runner-${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  testWidgets(
    'public choice suppresses an older own replay and submits the exact public candidate',
    (tester) async {
      GhostCandidate? selected;
      final rankings = FakeCourseRankingApi({
        RankingPeriod.all: courseRankingSummary(ghost: 1),
      });
      final m = await mount(
        tester,
        rankings: rankings,
        onPublic: (c) => selected = c,
      );
      final pending = Completer<OwnGhostReplay>();
      m.source.onPlayback = (_, _) => pending.future;
      await tester.tap(find.byKey(const ValueKey('ghost-choice-best')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('ghost-choice-public')),
      );
      await tester.tap(find.byKey(const ValueKey('ghost-choice-public')));
      pending.complete(
        OwnGhostReplay.fromJson(replayJson(m.choices.summary.best!)),
      );
      await tester.pumpAndSettle();
      expect(m.choices.prepared, isNull);
      await tester.tap(find.text('이 고스트와 대결하기'));
      expect(selected!.runRecordId, 'run-1');
      expect(selected!.memberId, 'member-1');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unavailable public ranking still allows a verified own record', (
    tester,
  ) async {
    final api = FakeCourseRankingApi()
      ..error = const ApiException('NETWORK', '연결 실패');
    PreparedOwnGhost? selected;
    await mount(tester, rankings: api, onPrepared: (p) => selected = p);
    expect(find.text('공개 기록을 불러오지 못했어요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ghost-choice-best')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 고스트와 대결하기'));
    expect(selected, isNotNull);
  });
}
