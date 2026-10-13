import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/create/course_info_screen.dart';
import 'package:wadadak/features/course/create/route_draw_screen.dart';
import 'package:wadadak/features/home/home_screen.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseApi courses;

  // route_draw_flow_test와 같은 두 점(약 1.7km).
  const first = Offset(200, 300);
  const second = Offset(230, 520);
  const name = '성북천 벚꽃길 3K';

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 홈 → B3에서 점 두 개 → 다음 → B4.
  Future<void> openCourseInfo(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        memberApiClientProvider.overrideWithValue(FakeMemberApi()),
        tokenStorageProvider.overrideWithValue(MemoryTokenStorage(testTokens)),
        socialLoginProvider.overrideWithValue(FakeSocialLogin()),
        runPermissionsProvider.overrideWithValue(FakeRunPermissions()),
        mapEngineProvider.overrideWithValue(MapEngine.dev),
        courseApiClientProvider.overrideWithValue(courses),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
    await tap(tester, find.text('＋ 코스 만들기'));
    for (final point in [first, second]) {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
    }
    await tap(tester, find.text('다음 · 코스 정보 입력'));
  }

  /// 이름을 넣고 서버 이름 확인까지 기다린다.
  Future<void> enterName(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Future<void> fillIn(WidgetTester tester) async {
    await enterName(tester, name);
    await tap(tester, find.text('중'));
  }

  VoidCallback? register(WidgetTester tester) =>
      tester.widget<WdButton>(find.widgetWithText(WdButton, '코스 등록하기')).onPressed;

  bool selected(WidgetTester tester, String label) =>
      tester.widget<WdFilterChip>(find.widgetWithText(WdFilterChip, label)).selected;

  setUp(() => courses = FakeCourseApi());

  testWidgets('needs a name and a difficulty, registers, then shows the new course on home', (tester) async {
    await openCourseInfo(tester);
    expect(find.text('그려서 만든 코스'), findsOneWidget);
    expect(register(tester), isNull);

    await enterName(tester, '성');
    expect(find.text('2자 이상 입력해 주세요'), findsOneWidget);
    expect(register(tester), isNull);

    await enterName(tester, '  성북천   벚꽃길 3K ');
    expect(find.text('2자 이상 입력해 주세요'), findsNothing);
    expect(register(tester), isNull, reason: '난이도는 필수');

    await tap(tester, find.text('하'));
    await tap(tester, find.text('중'));
    expect(selected(tester, '하'), isFalse, reason: '난이도는 하나만');
    expect(selected(tester, '중'), isTrue);

    // 특징은 고르지 않아도 되고 여러 개를 고를 수 있다.
    expect(register(tester), isNotNull);
    await tap(tester, find.text('평지'));
    await tap(tester, find.text('트랙'));
    await tap(tester, find.text('평지'));
    expect(selected(tester, '평지'), isFalse);
    expect(selected(tester, '트랙'), isTrue);

    await tap(tester, find.text('코스 등록하기'));
    final sent = courses.registrations.single;
    expect(sent.name, name, reason: '서버처럼 공백을 정리해 보낸다');
    expect(sent.difficulty, Difficulty.medium);
    expect(sent.tags, {CourseTag.track});
    expect(sent.anchorPoints, courses.sentPoints, reason: '경로를 만든 입력점을 다시 보낸다');
    expect(sent.idempotencyKey, isNotEmpty);

    expect(find.text('코스를 등록했어요'), findsOneWidget);
    // 서버에 새 코스가 생겼다. 홈 지도는 출발점으로 옮긴 범위에서 다시 받는다.
    courses.onMap = [MapCourse(courseId: 'course-1', name: name, route: sent.anchorPoints)];
    await tap(tester, find.text('확인'));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CourseInfoScreen), findsNothing);
    expect(find.byType(RouteDrawScreen), findsNothing);
    expect(find.widgetWithText(WdMapCourseLabel, name), findsOneWidget);

    // 홈 지도가 새 코스 출발점으로 옮겨져, 다음 코스 만들기도 그곳에서 열린다.
    await tap(tester, find.text('＋ 코스 만들기'));
    expect(tester.widget<MapView>(find.byType(MapView)).initialCenter, sent.anchorPoints.first);
  });

  testWidgets('tells when the name is taken, also when the server finds it on registering', (tester) async {
    courses.takenNames = {'성북천벚꽃길3k'};
    await openCourseInfo(tester);

    await fillIn(tester);
    expect(find.text('이미 있는 코스 이름이에요'), findsOneWidget, reason: '공백 · 대소문자만 다르면 같은 이름');
    expect(register(tester), isNull);

    await enterName(tester, '성북천 벚꽃길 5K');
    expect(find.text('이미 있는 코스 이름이에요'), findsNothing);
    expect(register(tester), isNotNull);

    // 그사이 다른 러너가 같은 이름으로 등록했다.
    courses.registerError = const ApiException('COURSE-006', '이미 사용 중인 코스 이름입니다.');
    await tap(tester, find.text('코스 등록하기'));
    expect(find.text('이미 있는 코스 이름이에요'), findsOneWidget);
    expect(register(tester), isNull);
    expect(find.byType(CourseInfoScreen), findsOneWidget);
  });

  testWidgets('keeps the input when registering fails and retries with the same key', (tester) async {
    const offline = '네트워크에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.';
    courses.registerError = const ApiException(ApiException.network, offline);
    await openCourseInfo(tester);
    await fillIn(tester);

    await tap(tester, find.text('코스 등록하기'));
    expect(find.text(offline), findsOneWidget);
    expect(find.text(name), findsOneWidget, reason: '입력 유지');
    expect(selected(tester, '중'), isTrue);

    courses.registerError = null;
    await tap(tester, find.text('다시 시도'));
    expect(find.text('코스를 등록했어요'), findsOneWidget);
    final [failed, retried] = courses.registrations;
    expect(retried.idempotencyKey, failed.idempotencyKey, reason: '같은 등록은 같은 멱등 키');
  });

  testWidgets('explains a route problem without a retry and goes back to edit the points', (tester) async {
    const similar = '기존 코스와 85% 이상 겹쳐 등록할 수 없습니다.';
    courses.registerError = const ApiException('COURSE-007', similar);
    await openCourseInfo(tester);
    await fillIn(tester);

    await tap(tester, find.text('코스 등록하기'));
    expect(find.text(similar), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));
    expect(find.text('경로 그리기'), findsOneWidget);
    expect(tester.widget<WdSummaryTile>(find.widgetWithText(WdSummaryTile, '찍은 점')).value, '2');
  });

  testWidgets('blocks registering when today\'s drawn course is already registered', (tester) async {
    courses.registerError = const ApiException('COURSE-008', '오늘 등록할 수 있는 코스 수를 넘었습니다.', status: 429);
    await openCourseInfo(tester);
    await fillIn(tester);

    await tap(tester, find.text('코스 등록하기'));
    expect(find.text('오늘은 그려서 만든 코스를 이미 등록했어요. 내일 다시 만들 수 있어요.'), findsOneWidget);
    expect(find.text('오늘 등록할 수 있는 코스 수를 넘었습니다.'), findsOneWidget, reason: '스낵바');
    expect(register(tester), isNull);
  });

  testWidgets('cannot register twice or leave while registering', (tester) async {
    courses.registerGate = Completer();
    await openCourseInfo(tester);
    await fillIn(tester);

    await tester.tap(find.text('코스 등록하기'));
    await tester.pump();
    expect(register(tester), isNull);

    await tester.tap(find.bySemanticsLabel('뒤로 가기'));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(CourseInfoScreen), findsOneWidget);

    courses.registerGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('코스를 등록했어요'), findsOneWidget);
    expect(courses.registrations, hasLength(1));
  });
}
