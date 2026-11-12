import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/create/auto_course_view.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';

import '../../fakes.dart';

/// B3 `자동 생성` 화면을 실제 폰트로 그려 `build/auto-course-ui/*.png`로 남긴다. Figma A1 · A7-1 · A2 · A3 · A4 · A7-2 · A6 · A8과 나란히 놓고 본다.
void main() {
  setUpAll(() async {
    final fonts = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      fonts.addFont(rootBundle.load('packages/wadadak_design_system/assets/fonts/Pretendard-$weight.otf'));
    }
    await fonts.load();
  });

  const sunmoon = GeoPoint(36.7983, 127.0746);
  PlanCandidate candidate(int meters, double arterial, int stores, double retrace, double shift) => PlanCandidate(
        anchorPoints: [
          sunmoon,
          GeoPoint(36.8083 + shift, 127.0746 + shift),
          GeoPoint(36.8083 + shift, 127.0946 + shift),
          GeoPoint(36.7983 - shift, 127.0946),
          sunmoon,
        ],
        distanceMeters: meters,
        retraceRatio: retrace,
        arterialRatio: arterial,
        storeCount: stores,
        toiletCount: stores > 0 ? 1 : 0,
        ascentMeters: (retrace * 1000).round(),
      );

  testWidgets('draws every auto-generation screen', (tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final capture = GlobalKey();
    final courses = FakeCourseApi()
      ..parsed = const PlanForm(start: PlanStart.place, startQuery: '선문대학교 아산캠퍼스', shape: PlanShape.loop, prefer: {
        PlanPref.avoidArterial,
        PlanPref.flat,
      })
      ..planned = PlanResult(
        candidates: [
          candidate(5140, 0.24, 3, 0.02, 0),
          candidate(4930, 0.31, 1, 0.06, -0.006),
          candidate(5210, 0.18, 0, 0.09, 0.006),
        ],
        startName: '선문대학교 아산캠퍼스',
        notApplied: const {PlanPref.park},
      );

    Future<void> shot(String name) async {
      await tester.runAsync(() async {
        final image = await (capture.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/auto-course-ui/$name.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> tap(String text) async {
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(ProviderScope(
      overrides: [
        memberApiClientProvider.overrideWithValue(FakeMemberApi()),
        tokenStorageProvider.overrideWithValue(MemoryTokenStorage(testTokens)),
        socialLoginProvider.overrideWithValue(FakeSocialLogin()),
        runPermissionsProvider.overrideWithValue(FakeRunPermissions()),
        mapEngineProvider.overrideWithValue(MapEngine.dev),
        courseApiClientProvider.overrideWithValue(courses),
        myLocationProvider.overrideWithValue(FakeMyLocation(location: sunmoon, allowed: true)),
        autoCourseProvider.overrideWithValue(true),
        usualPaceProvider.overrideWithValue(() async => null),
      ],
      child: RepaintBoundary(key: capture, child: const WadadakApp()),
    ));
    await tester.pumpAndSettle();
    await tap('＋ 코스 만들기');
    await tap('자동 생성');
    await tester.enterText(find.byType(TextField), '선문대에서 5km 평지로 한 바퀴');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shot('a1-input');

    await tap('조건 자동 채우기');
    await shot('a7-1-filled');

    await tap('5km');
    courses.planGate = Completer();
    await tap('코스 찾기');
    await tester.pump(const Duration(seconds: 1));
    await shot('a2-searching');
    courses.planGate!.complete();
    await tester.pumpAndSettle();
    await shot('a3-candidates');

    await tap('이 코스로 만들기');
    await shot('a4-filled');

    await tap('자동 생성');
    await tap('직접 조건 고르기');
    await tap('편도');
    await tester.enterText(find.byType(TextField).last, '아산역');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shot('a7-2-point-to-point');

    courses.planned = const PlanResult(
      candidates: [],
      reason: PlanReason.noCandidates,
      message: '이 근처에서는 길을 따라 한 바퀴 코스를 만들지 못했어요. 왕복으로 바꿔 보세요.',
    );
    await tap('한 바퀴');
    await tap('5km');
    await tap('코스 찾기');
    await shot('a6-no-candidates');

    courses.planError = const ApiException('COURSE-012', '오늘 코스 자동 생성 횟수를 넘었습니다.');
    await tap('왕복으로 만들기');
    await shot('a8-limit');
  });
}
