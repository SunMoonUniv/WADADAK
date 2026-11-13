import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/dev_map_view.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/create/auto_course_view.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

/// B3 `자동 생성`(Figma A1 · A7-1 · A7-2 · A2 · A3 · A4 · A6 · A8). 서버 대신 [FakeCourseApi]가 답한다.
void main() {
  late FakeCourseApi courses;

  const sunmoon = GeoPoint(36.7983, 127.0746);

  /// 선문대에서 출발해 돌아오는 후보. [shift]마다 다른 방향이고, 두 점 사이는 1km가 넘는다.
  PlanCandidate candidate(int meters, double arterial, int stores, double retrace, double shift,
          {int toilets = 0, int? ascent, double? river}) =>
      PlanCandidate(
        anchorPoints: [
          sunmoon,
          GeoPoint(36.8083 + shift, 127.0746),
          GeoPoint(36.8083 + shift, 127.0846 + shift),
          sunmoon,
        ],
        distanceMeters: meters,
        retraceRatio: retrace,
        arterialRatio: arterial,
        storeCount: stores,
        toiletCount: toilets,
        ascentMeters: ascent,
        riverRatio: river,
      );

  final first = candidate(5140, 0.24, 3, 0.02, 0, toilets: 1, ascent: 32, river: 0.35);
  final second = candidate(4930, 0.31, 1, 0.06, 0.01);
  final third = candidate(5210, 0.18, 0, 0.09, -0.02);

  Future<void> openAuto(WidgetTester tester, {bool enabled = true}) async {
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
        myLocationProvider.overrideWithValue(FakeMyLocation(location: sunmoon, allowed: true)),
        autoCourseProvider.overrideWithValue(enabled),
        usualPaceProvider.overrideWithValue(() async => 360),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋ 코스 만들기'));
    await tester.pumpAndSettle();
    if (enabled) {
      await tester.tap(find.text('자동 생성'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  VoidCallback? button(WidgetTester tester, String label) =>
      tester.widget<WdButton>(find.widgetWithText(WdButton, label)).onPressed;

  String summary(WidgetTester tester, String label) =>
      tester.widget<WdSummaryTile>(find.widgetWithText(WdSummaryTile, label)).value;

  setUp(() => courses = FakeCourseApi());

  testWidgets('a sentence fills the conditions, finds candidates and fills the drawing (A1 → A7-1 → A2 → A3 → A4)',
      (tester) async {
    courses.parsed = const PlanForm(
      start: PlanStart.place,
      startQuery: '선문대',
      shape: PlanShape.loop,
      prefer: {PlanPref.avoidArterial},
    );
    courses.planned = PlanResult(candidates: [first, second, third], startName: '선문대학교 아산캠퍼스');
    await openAuto(tester);

    // A1
    expect(find.text('오늘 남은 코스 추천 19회'), findsOneWidget);
    expect(find.text('입력한 문장은 조건을 읽기 위해 외부 AI로 보내고, 서비스 개선을 위해 저장해요.\n위치는 보내지 않아요.'), findsOneWidget);
    expect(button(tester, '조건 자동 채우기'), isNull, reason: '문장이 비면 누를 수 없다');
    await tester.enterText(find.byType(TextField), '선문대에서 큰길 피해서 한 바퀴');
    await tester.pump();
    await tap(tester, find.text('조건 자동 채우기'));
    expect(courses.parsedTexts, ['선문대에서 큰길 피해서 한 바퀴']);

    // A7-1: 읽은 칸은 골라 두고, 비어 있는 거리 · 시간에 `골라 주세요`
    expect(find.text('선문대에서 큰길 피해서 한 바퀴'), findsOneWidget, reason: '보낸 문장');
    expect(find.text('문장에서 읽은 조건이에요. 빈 칸은 골라 주세요.'), findsOneWidget);
    expect(find.text('골라 주세요'), findsOneWidget);
    expect(button(tester, '코스 찾기'), isNull);
    await tap(tester, find.text('5km'));
    expect(find.text('골라 주세요'), findsNothing);
    // 평지와 오르막은 하나만 고른다
    await tap(tester, find.text('평지'));
    await tap(tester, find.text('오르막'));
    await tap(tester, find.text('화장실 들르기'));
    await tester.ensureVisible(find.text('강변'));
    await tap(tester, find.text('강변'));

    // A2: 응답을 기다리는 동안
    courses.planGate = Completer();
    await tap(tester, find.text('코스 찾기'));
    expect(find.text('코스를 찾고 있어요'), findsOneWidget);
    expect(find.text('출발지 찾기'), findsOneWidget);
    expect(button(tester, '코스 찾는 중…'), isNull);
    courses.planGate!.complete();
    await tester.pumpAndSettle();

    final sent = courses.plans.single;
    expect(sent.form.start, PlanStart.place);
    expect(sent.form.startQuery, '선문대');
    expect(sent.form.shape, PlanShape.loop);
    expect(sent.form.distanceM, 5000);
    expect(sent.form.prefer, {PlanPref.avoidArterial, PlanPref.hilly, PlanPref.toiletOnRoute, PlanPref.river});
    expect(sent.currentLocation, sunmoon);
    expect(sent.paceSecPerKm, 360);

    // A3
    expect(find.text('선문대학교 아산캠퍼스 출발 · 5km · 한 바퀴'), findsOneWidget);
    expect(find.text('5.14km · 한 바퀴 · 오르막 32m'), findsOneWidget);
    expect(find.text('강변 35% · 화장실 1곳 · 큰길 24% · 편의점 3곳 · 같은 길 2%'), findsOneWidget,
        reason: '강변 · 화장실은 골랐을 때만, 앞에 보인다');
    expect(find.text('4.93km · 한 바퀴'), findsOneWidget);
    expect(find.text('5.21km · 한 바퀴'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

    // 두 번째 후보로 만든다 → A4
    await tap(tester, find.text('4.93km · 한 바퀴'));
    await tap(tester, find.text('이 코스로 만들기'));
    expect(summary(tester, '입력점 (자동 생성)'), '${second.anchorPoints.length}');
    expect(find.text('자동 생성 경로 · 탭하면 이어 그려요'), findsOneWidget);
    expect(find.byType(WdRouteEndpoint), findsOneWidget, reason: '출발점으로 돌아오는 한 바퀴라 출발만 그린다');
    expect(find.byWidgetPredicate((widget) => widget is WdIcon && widget.icon == WdIcons.routePoint), findsNothing,
        reason: '채운 점은 작성점으로 그리지 않는다');
    expect(tester.widget<WdButton>(find.widgetWithText(WdButton, '다음 · 코스 정보 입력')).onPressed, isNotNull);

    // 되돌리기 한 번이 채운 점 전체를 지운다
    await tap(tester, find.text('↺  되돌리기'));
    expect(summary(tester, '찍은 점'), '0');
  });

  testWidgets('zooming in shows the filled points on screen, and one can be picked and moved (A4 · B3-09)',
      (tester) async {
    final filledPoint = find.byWidgetPredicate((widget) => widget is WdIcon && widget.icon == WdIcons.routePoint);
    courses.planned = PlanResult(candidates: [first]);
    await openAuto(tester);
    await tap(tester, find.text('직접 조건 고르기'));
    await tap(tester, find.text('5km'));
    await tap(tester, find.text('코스 찾기'));
    await tap(tester, find.text('이 코스로 만들기'));
    expect(filledPoint, findsNothing, reason: '코스 전체가 보이는 축척에서는 출발만 그린다');

    // 축척 50m 이하로 확대하면 화면 안의 채운 점만 그린다. 다른 두 점은 1km 넘게 떨어져 화면 밖이다.
    final map = tester.state(find.byType(DevMapView)) as MapController;
    await map.moveTo(first.anchorPoints[1], zoom: 17);
    await tester.pumpAndSettle();
    expect(filledPoint, findsOneWidget);
    final at = tester.getCenter(filledPoint);

    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected-point')), findsOneWidget);
    expect(summary(tester, '입력점 (자동 생성)'), '4', reason: '채운 점을 누르면 이어 찍지 않고 고른다');

    await tester.tapAt(at + const Offset(60, 40));
    await tester.pumpAndSettle();
    expect(tester.getCenter(filledPoint), offsetMoreOrLessEquals(at + const Offset(60, 40), epsilon: 0.5));
    expect(summary(tester, '입력점 (자동 생성)'), '4');

    await map.moveTo(first.anchorPoints[1], zoom: 14);
    await tester.pumpAndSettle();
    expect(filledPoint, findsNothing, reason: '축소하면 다시 숨긴다');

    // 옮긴 점만 바뀐 채로 서버에 간다.
    await tap(tester, find.text('다음 · 코스 정보 입력'));
    final sent = courses.sentPoints!;
    expect(sent, hasLength(4));
    expect([sent[0], sent[2], sent[3]], [first.anchorPoints[0], first.anchorPoints[2], first.anchorPoints[3]]);
    expect(sent[1], isNot(first.anchorPoints[1]));
  });

  testWidgets('direct conditions: point to point asks for the end place instead of a distance (A7 · A7-2)',
      (tester) async {
    courses.planned = PlanResult(candidates: [first]);
    await openAuto(tester);

    await tap(tester, find.text('직접 조건 고르기'));
    expect(find.text('문장에서 읽은 조건이에요. 빈 칸은 골라 주세요.'), findsNothing);
    expect(find.text('골라 주세요'), findsNothing, reason: '직접 고를 때는 달지 않는다');
    expect(button(tester, '코스 찾기'), isNull, reason: '한 바퀴는 거리 · 시간이 필요하다');

    await tap(tester, find.text('편도'));
    expect(find.text('거리 · 시간'), findsNothing);
    expect(find.text('도착'), findsOneWidget);
    expect(button(tester, '코스 찾기'), isNull);
    await tester.enterText(find.byType(TextField).last, '아산역');
    await tester.pump();
    await tap(tester, find.text('코스 찾기'));

    final sent = courses.plans.single.form;
    expect(sent.start, PlanStart.current);
    expect(sent.shape, PlanShape.pointToPoint);
    expect(sent.endQuery, '아산역');
    expect(sent.distanceM, isNull);
    expect(find.text('현재 위치 출발 · 편도 · 아산역 도착'), findsOneWidget);
    expect(find.text('5.14km · 편도 · 오르막 32m'), findsOneWidget, reason: '후보가 1개면 카드도 1개');
  });

  testWidgets('a place problem stays on the form with the server message; no roads for a loop suggests out-and-back',
      (tester) async {
    courses.planned = const PlanResult(
      candidates: [],
      reason: PlanReason.placeNotFound,
      message: "'없는 곳'을 찾지 못했어요. 이름을 다시 확인해 주세요.",
    );
    await openAuto(tester);
    await tap(tester, find.text('직접 조건 고르기'));
    await tester.enterText(find.byType(TextField).first, '없는 곳');
    await tap(tester, find.text('3km'));
    await tap(tester, find.text('코스 찾기'));

    expect(courses.plans.single.form.start, PlanStart.place, reason: '장소 이름을 쓰면 장소에서 출발한다');
    expect(find.text("'없는 곳'을 찾지 못했어요. 이름을 다시 확인해 주세요."), findsOneWidget);
    expect(find.text('없는 곳'), findsOneWidget, reason: '폼은 고른 값을 그대로 둔다');
    expect(button(tester, '코스 찾기'), isNotNull);

    // A6: 한 바퀴를 만들 길이 없다
    courses.planned = const PlanResult(
      candidates: [],
      reason: PlanReason.noCandidates,
      message: '이 근처에서는 길을 따라 한 바퀴 코스를 만들지 못했어요. 왕복으로 바꿔 보세요.',
    );
    await tap(tester, find.text('코스 찾기'));
    expect(find.text('한 바퀴로 돌 길이 부족해요'), findsOneWidget);
    expect(find.text('이 근처에서는 길을 따라 한 바퀴 코스를 만들지 못했어요. 왕복으로 바꿔 보세요.'), findsOneWidget);

    courses.planned = PlanResult(candidates: [first]);
    await tap(tester, find.text('왕복으로 만들기'));
    expect(courses.plans.last.form.shape, PlanShape.outAndBack);
    expect(courses.plans.last.form.distanceM, 3000);
    expect(find.text('5.14km · 왕복 · 오르막 32m'), findsOneWidget);
  });

  testWidgets('similar courses already exist: only 다시 입력, back to the same conditions (A6)', (tester) async {
    courses.planned = const PlanResult(
      candidates: [],
      reason: PlanReason.similarExists,
      message: '비슷한 코스가 이미 있어요. 거리나 출발지를 바꿔 보세요.',
    );
    await openAuto(tester);
    await tap(tester, find.text('직접 조건 고르기'));
    await tap(tester, find.text('7km'));
    await tap(tester, find.text('코스 찾기'));

    expect(find.text('이미 있는 코스와 겹쳐요'), findsOneWidget);
    expect(find.text('비슷한 코스가 이미 있어요. 거리나 출발지를 바꿔 보세요.'), findsOneWidget);
    expect(find.text('왕복으로 만들기'), findsNothing);

    await tap(tester, find.text('다시 입력'));
    expect(button(tester, '코스 찾기'), isNotNull, reason: '7km를 고른 폼으로 돌아온다');
  });

  testWidgets('daily limits: COURSE-013 stays on A1 with the message, COURSE-012 opens A8', (tester) async {
    courses.parseError = const ApiException('COURSE-013', '오늘 조건 자동 채우기 횟수를 넘었습니다.');
    await openAuto(tester);
    await tester.enterText(find.byType(TextField), '선문대 5km');
    await tester.pump();
    await tap(tester, find.text('조건 자동 채우기'));
    expect(find.text('오늘 조건 자동 채우기 횟수를 넘었습니다.'), findsOneWidget);

    courses.planError = const ApiException('COURSE-012', '오늘 코스 자동 생성 횟수를 넘었습니다.');
    await tap(tester, find.text('직접 조건 고르기'));
    await tap(tester, find.text('5km'));
    await tap(tester, find.text('코스 찾기'));
    expect(find.text('오늘 코스 추천을 모두 썼어요'), findsOneWidget);

    await tap(tester, find.text('직접 그리기'));
    expect(summary(tester, '찍은 점'), '0', reason: '경로 그리기로 간다');
  });

  testWidgets('opens A8 at once when today\'s plans are used up', (tester) async {
    courses.planLimit = const TypeQuota(limit: 20, remaining: 0);
    await openAuto(tester);

    expect(find.text('오늘 코스 추천을 모두 썼어요'), findsOneWidget);
  });

  testWidgets('an off-topic sentence shows the message on A1', (tester) async {
    courses.parsed = const PlanForm(message: '코스와 관련된 문장이 아니에요. 출발지 · 거리 · 모양을 말해 주세요.');
    await openAuto(tester);
    await tap(tester, find.text('30분 조깅 코스'));
    await tap(tester, find.text('조건 자동 채우기'));

    expect(courses.parsedTexts, ['30분 조깅 코스'], reason: '예시를 누르면 입력란을 채운다');
    expect(find.text('코스와 관련된 문장이 아니에요. 출발지 · 거리 · 모양을 말해 주세요.'), findsOneWidget);
    expect(find.text('조건 자동 채우기'), findsOneWidget);
  });

  testWidgets('a server error goes back to the form and can be retried', (tester) async {
    courses.planError = const ApiException('COMMON-006', '서버 오류가 발생했습니다.');
    await openAuto(tester);
    await tap(tester, find.text('직접 조건 고르기'));
    await tap(tester, find.text('30분'));
    await tap(tester, find.text('코스 찾기'));

    expect(find.text('서버 오류가 발생했습니다.'), findsOneWidget);
    expect(find.text('코스 찾기'), findsOneWidget);
    expect(courses.plans.single.form.durationMin, 30);

    courses
      ..planError = null
      ..planned = PlanResult(candidates: [first]);
    await tap(tester, find.text('다시 시도'));
    expect(courses.plans, hasLength(2));
    expect(find.text('5.14km · 한 바퀴 · 오르막 32m'), findsOneWidget);
  });

  testWidgets('the tab stays hidden while the build flag is off', (tester) async {
    await openAuto(tester, enabled: false);

    expect(find.text('경로 그리기'), findsOneWidget);
    expect(find.text('자동 생성'), findsNothing);
  });
}
