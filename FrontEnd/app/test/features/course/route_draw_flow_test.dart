import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/course_public_period_sheet.dart';
import 'package:wadadak/features/home/home_screen.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseApi courses;

  // 402 × 874 화면에서 B3 지도는 대략 y 131~653이다. 두 점은 줌 14에서 약 1.7km 떨어져 있다.
  const first = Offset(200, 300);
  const second = Offset(230, 520);

  Future<void> openCourseCreate(WidgetTester tester) async {
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
        myLocationProvider.overrideWithValue(FakeMyLocation()),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋ 코스 만들기'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapMap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pumpAndSettle();
  }

  String summary(WidgetTester tester, String label) =>
      tester.widget<WdSummaryTile>(find.widgetWithText(WdSummaryTile, label)).value;

  VoidCallback? next(WidgetTester tester) =>
      tester.widget<WdButton>(find.widgetWithText(WdButton, '다음 · 코스 정보 입력')).onPressed;

  setUp(() => courses = FakeCourseApi());

  testWidgets('draws a route, opens course info and comes back to keep editing', (tester) async {
    await openCourseCreate(tester);
    expect(find.text('경로 그리기'), findsOneWidget);
    expect(summary(tester, '총 거리'), '0.0km');
    expect(summary(tester, '찍은 점'), '0');
    expect(next(tester), isNull);

    await tapMap(tester, first);
    expect(summary(tester, '찍은 점'), '1');
    expect(find.byType(WdRouteEndpoint), findsOneWidget, reason: '점이 하나면 출발만');
    expect(next(tester), isNull, reason: '입력점 2개 이상');

    await tapMap(tester, second);
    expect(summary(tester, '찍은 점'), '2');
    expect(summary(tester, '총 거리'), matches(RegExp(r'^1\.\dkm$')));
    expect(find.byType(WdRouteEndpoint), findsNWidgets(2), reason: '출발·도착');
    expect(next(tester), isNotNull);

    await tap(tester, find.text('다음 · 코스 정보 입력'));
    expect(courses.sentPoints, hasLength(2));
    // 경로를 만들면 B4로 가기 전에 공개 기간(B11)을 알린다(4.1 B11).
    expect(find.text(CoursePublicPeriodSheet.title), findsOneWidget);
    for (final rule in CoursePublicPeriodSheet.rules) {
      expect(find.text(rule), findsOneWidget);
    }
    expect(find.text('코스 정보'), findsNothing);
    await tap(tester, find.text('확인'));
    // B4에는 최종 경로와 1km 표지만 있고 입력점은 없다.
    expect(find.text('코스 정보'), findsOneWidget);
    expect(find.byType(WdRouteEndpoint), findsNothing);
    expect(find.byType(WdKmMarker), findsOneWidget);

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));
    expect(find.text('경로 그리기'), findsOneWidget);
    expect(summary(tester, '찍은 점'), '2');
  });

  testWidgets('closing the public period sheet stays drawing, and it shows again every time', (tester) async {
    await openCourseCreate(tester);
    await tapMap(tester, first);
    await tapMap(tester, second);

    await tap(tester, find.text('다음 · 코스 정보 입력'));
    await tap(tester, find.byTooltip('닫기'));
    expect(find.text(CoursePublicPeriodSheet.title), findsNothing);
    expect(find.text('코스 정보'), findsNothing, reason: 'X는 B3에 머문다');
    expect(summary(tester, '찍은 점'), '2');

    await tap(tester, find.text('다음 · 코스 정보 입력'));
    expect(find.text(CoursePublicPeriodSheet.title), findsOneWidget, reason: '한 번 봤어도 매번 띄운다');
    // 휴대폰 뒤로 가기도 시트만 닫는다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(CoursePublicPeriodSheet.title), findsNothing);
    expect(find.text('경로 그리기'), findsOneWidget);
    expect(courses.sentPoints, hasLength(2));

    await tap(tester, find.text('다음 · 코스 정보 입력'));
    await tap(tester, find.text('확인'));
    expect(find.text('코스 정보'), findsOneWidget);
  });

  testWidgets('undo and clear all, which asks first and can be undone', (tester) async {
    await openCourseCreate(tester);
    await tapMap(tester, first);
    await tapMap(tester, second);

    await tap(tester, find.text('↺  되돌리기'));
    expect(summary(tester, '찍은 점'), '1');

    await tap(tester, find.text('✕  전체 지우기'));
    expect(find.text('찍은 점을 모두 지울까요?'), findsOneWidget);
    await tap(tester, find.text('취소'));
    expect(summary(tester, '찍은 점'), '1');

    await tap(tester, find.text('✕  전체 지우기'));
    await tap(tester, find.text('지우기'));
    expect(summary(tester, '찍은 점'), '0');
    expect(summary(tester, '총 거리'), '0.0km');

    await tap(tester, find.text('↺  되돌리기'));
    expect(summary(tester, '찍은 점'), '1');

    // 점이 없으면 묻지 않는다.
    await tap(tester, find.text('↺  되돌리기'));
    await tap(tester, find.text('✕  전체 지우기'));
    expect(find.text('찍은 점을 모두 지울까요?'), findsNothing);
  });

  testWidgets('tapping a point picks it, the next tap moves it there, and undo puts it back (B3-09)', (tester) async {
    const ring = ValueKey('selected-point');
    const start = ValueKey('point-0');
    await openCourseCreate(tester);
    await tapMap(tester, first);
    await tapMap(tester, second);
    final drawn = summary(tester, '총 거리');

    // 점에서 22dp 안을 누르면 새 점을 찍지 않고 그 점을 고른다.
    await tapMap(tester, first + const Offset(12, 12));
    expect(summary(tester, '찍은 점'), '2');
    expect(find.byKey(ring), findsOneWidget);
    expect(find.text('옮길 곳을 탭하세요 · 점을 다시 탭하면 취소'), findsOneWidget);

    // 고른 점 위(10dp 안)를 다시 누르면 옮기지 않고 고르기만 푼다.
    await tapMap(tester, first + const Offset(6, 0));
    expect(find.byKey(ring), findsNothing);
    expect(find.text('지도를 탭해 경로 그리기 · 점을 순서대로 연결'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(start)), offsetMoreOrLessEquals(first, epsilon: 0.5));

    // 점 바로 옆(10dp 밖)은 고르는 범위(22dp) 안이어도 옮긴다.
    await tapMap(tester, first);
    await tapMap(tester, first + const Offset(15, 0));
    expect(find.byKey(ring), findsNothing);
    expect(tester.getTopLeft(find.byKey(start)), offsetMoreOrLessEquals(first + const Offset(15, 0), epsilon: 0.5));
    await tap(tester, find.text('↺  되돌리기'));
    expect(tester.getTopLeft(find.byKey(start)), offsetMoreOrLessEquals(first, epsilon: 0.5));

    await tapMap(tester, first);
    await tapMap(tester, const Offset(100, 200));
    expect(summary(tester, '찍은 점'), '2', reason: '옮기기는 점을 늘리지 않는다');
    expect(tester.getTopLeft(find.byKey(start)), offsetMoreOrLessEquals(const Offset(100, 200), epsilon: 0.5));
    expect(summary(tester, '총 거리'), isNot(drawn), reason: '선과 거리도 따라온다');
    expect(find.byKey(ring), findsNothing, reason: '옮기면 고르기가 풀린다');

    await tap(tester, find.text('↺  되돌리기'));
    expect(tester.getTopLeft(find.byKey(start)), offsetMoreOrLessEquals(first, epsilon: 0.5));
    expect(summary(tester, '총 거리'), drawn);

    // 22dp 밖은 지금처럼 새 점을 찍는다.
    await tapMap(tester, second + const Offset(30, 0));
    expect(summary(tester, '찍은 점'), '3');

    // 고른 점이 되돌리기로 없어져도 고르기가 풀려 있다.
    await tapMap(tester, second + const Offset(30, 0));
    expect(find.byKey(ring), findsOneWidget);
    await tap(tester, find.text('↺  되돌리기'));
    expect(summary(tester, '찍은 점'), '2');
    expect(find.byKey(ring), findsNothing);
  });

  testWidgets('leaving with points asks before throwing them away', (tester) async {
    await openCourseCreate(tester);
    await tapMap(tester, first);

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));
    expect(find.text('코스 만들기를 그만둘까요?'), findsOneWidget);
    await tap(tester, find.text('계속 작성'));
    expect(summary(tester, '찍은 점'), '1');

    // 휴대폰 뒤로 가기도 같다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('코스 만들기를 그만둘까요?'), findsOneWidget);
    await tap(tester, find.text('나가기'));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('경로 그리기'), findsNothing);
  });

  testWidgets('leaves at once when nothing is drawn', (tester) async {
    await openCourseCreate(tester);

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));

    expect(find.text('코스 만들기를 그만둘까요?'), findsNothing);
    expect(find.text('경로 그리기'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('stays with the points when the route cannot be made, and retries', (tester) async {
    courses.routeError = const ApiException('COURSE-004', '코스 거리는 1km 이상이어야 합니다.');
    await openCourseCreate(tester);
    await tapMap(tester, first);
    await tapMap(tester, second);

    await tap(tester, find.text('다음 · 코스 정보 입력'));
    expect(find.text('코스 거리는 1km 이상이어야 합니다.'), findsOneWidget);
    expect(find.text(CoursePublicPeriodSheet.title), findsNothing, reason: '경로를 못 만들면 공개 기간을 알리지 않는다');
    expect(find.text('경로 그리기'), findsOneWidget);
    expect(summary(tester, '찍은 점'), '2');

    courses.routeError = null;
    await tap(tester, find.text('다시 시도'));
    await tap(tester, find.text('확인'));
    expect(find.text('코스 정보'), findsOneWidget);
  });

  testWidgets('blocks drawing when today\'s drawn course is already registered', (tester) async {
    courses.quota = const RegistrationQuota(
      custom: TypeQuota(limit: 1, remaining: 0),
      gps: TypeQuota(limit: 3, remaining: 3),
    );
    await openCourseCreate(tester);
    const message = '오늘은 그려서 만든 코스를 이미 등록했어요. 내일 다시 만들 수 있어요.';
    expect(find.text(message), findsOneWidget);

    await tapMap(tester, first);

    expect(summary(tester, '찍은 점'), '0');
    expect(find.text(message), findsNWidgets(2), reason: '안내 + 스낵바');
    expect(next(tester), isNull);
  });

  testWidgets('switching to the run tab asks first and drops the drawn points', (tester) async {
    await openCourseCreate(tester);
    await tapMap(tester, first);

    await tap(tester, find.text('내가 달려서 등록'));
    expect(find.text('생성 방식을 바꿀까요?'), findsOneWidget);
    await tap(tester, find.text('계속 작성'));
    expect(summary(tester, '찍은 점'), '1');

    await tap(tester, find.text('내가 달려서 등록'));
    await tap(tester, find.text('방식 변경'));
    expect(find.text('직접 달린 경로가 그대로 코스가 돼요'), findsOneWidget, reason: 'B5 내가 달려서 등록');

    await tap(tester, find.text('경로 그리기'));
    expect(summary(tester, '찍은 점'), '0');
  });
}
