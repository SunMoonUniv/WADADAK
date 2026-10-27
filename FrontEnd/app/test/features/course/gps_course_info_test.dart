import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/course_format.dart';
import 'package:wadadak/features/course/create/course_info_inputs.dart';
import 'package:wadadak/features/course/create/gps_course_info_screen.dart';
import 'package:wadadak/features/course/create/run_course_source_api.dart';
import 'package:wadadak/features/home/home_screen.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/domain/free_run_session.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak/router.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

/// D4 달린 경로를 코스로 등록. 달리기 탭에서 기록 ID로 연다(달리기 결과의 `달린 경로로 코스 만들기`처럼).
void main() {
  late FakeCourseApi courses;
  late FakeRunCourseSource records;
  late FreeRunController run;

  const recordId = 'record-1';
  const name = '반포 한 바퀴 4K';
  const offline = '네트워크에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.';

  // 일시정지한 곳에서 끊긴 두 조각.
  const segments = [
    [GpsSourcePoint(37.5100, 126.9950, accuracyM: 5, altitudeM: 12), GpsSourcePoint(37.5150, 126.9990, accuracyM: 6)],
    [GpsSourcePoint(37.5160, 127.0000, accuracyM: 5), GpsSourcePoint(37.5200, 127.0100, accuracyM: 4)],
  ];
  final start = GeoPoint(segments.first.first.lat, segments.first.first.lng);

  setUp(() {
    courses = FakeCourseApi();
    records = FakeRunCourseSource()..records = {recordId: segments};
    run = FreeRunController(
      createSession: () => FreeRunSession(monotonicNow: () => Duration.zero, utcNow: () => DateTime.utc(2026)),
      createId: () => 'session-1',
    );
  });
  tearDown(() => run.dispose());

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  GoRouter router(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(WadadakApp))).read(routerProvider);

  /// 홈 → 달리기 탭 → D4.
  Future<void> openFromRunTab(WidgetTester tester) async {
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
        freeRunControllerProvider.overrideWithValue(run),
        runCourseSourceApiProvider.overrideWithValue(records),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
    await tap(tester, find.text('달리기'));
    unawaited(router(tester).push(Routes.gpsCourseInfo(recordId)));
    await tester.pumpAndSettle();
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

  testWidgets('previews the run route, registers, then shows the new course on the home tab', (tester) async {
    await openFromRunTab(tester);

    expect(records.requests, [recordId]);
    final preview = courses.gpsPreviews.single;
    expect(preview.recordId, recordId);
    expect(preview.segments, segments, reason: '기록 경로 조각을 그대로 보낸다');

    // 서버가 만든 최종 경로와 1 km 지점만 보인다.
    final map = tester.widget<MapView>(find.byType(MapView));
    expect(map.lines.single.points, [for (final segment in segments) for (final p in segment) GeoPoint(p.lat, p.lng)]);
    expect(map.markers.map((marker) => marker.id), ['km-1']);

    expect(find.text('코스로 등록'), findsOneWidget);
    expect(find.text(GpsCourseInfoScreen.routeNotice), findsOneWidget);
    expect(find.text('달려서 만든 코스'), findsOneWidget);
    expect(find.text('모든 러너에게 공개'), findsOneWidget);
    expect(find.text(coursePublicPeriodNotice), findsOneWidget);
    expect(find.text(gpsQuotaUsedUpMessage), findsNothing);
    for (final tag in CourseTag.values) {
      expect(find.widgetWithText(WdFilterChip, tag.label), findsOneWidget, reason: '특징은 모두 고를 수 있다');
    }
    expect(register(tester), isNull, reason: '이름 · 난이도는 필수');

    await enterName(tester, '  반포   한 바퀴 4K ');
    await tap(tester, find.text('하'));
    await tap(tester, find.text('중'));
    expect(selected(tester, '하'), isFalse, reason: '난이도는 하나만');
    await tap(tester, find.text('강변'));
    expect(register(tester), isNotNull);

    await tap(tester, find.text('코스 등록하기'));
    final sent = courses.gpsRegistrations.single;
    expect(sent.recordId, recordId);
    expect(sent.segments, segments, reason: '미리본 경로 조각을 다시 보낸다');
    expect(sent.name, name, reason: '서버처럼 공백을 정리해 보낸다');
    expect(sent.difficulty, Difficulty.medium);
    expect(sent.tags, {CourseTag.riverside});
    expect(sent.idempotencyKey, isNotEmpty);
    expect(courses.registrations, isEmpty, reason: '사용자 지정 코스 등록은 부르지 않는다');

    expect(find.text('코스를 등록했어요'), findsOneWidget);
    // 서버에 새 코스가 생겼다. 홈 지도는 출발점으로 옮긴 범위에서 다시 받는다.
    courses.onMap = [testCourse(name, courseId: 'gps-course-1', route: [start, GeoPoint(37.5200, 127.0100)])];
    await tap(tester, find.text('확인'));
    expect(find.byType(GpsCourseInfoScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget, reason: '홈 탭으로 간다');
    expect(find.widgetWithText(WdMapCourseLabel, name), findsOneWidget);

    // 홈 지도가 새 코스 출발점으로 옮겨져, 다음 코스 만들기도 그곳에서 열린다.
    await tap(tester, find.text('＋ 코스 만들기'));
    expect(tester.widget<MapView>(find.byType(MapView)).initialCenter, start);
  });

  testWidgets('keeps the run tab under the new course', (tester) async {
    await openFromRunTab(tester);
    await fillIn(tester);
    await tap(tester, find.text('코스 등록하기'));
    await tap(tester, find.text('확인'));
    expect(find.byType(HomeScreen), findsOneWidget);

    await tap(tester, find.text('달리기'));
    expect(find.byType(FreeRunScreen), findsOneWidget);
    expect(find.byType(GpsCourseInfoScreen), findsNothing);
  });

  for (final (code, message, reason) in [
    ('COURSE-010', '이미 코스로 등록한 러닝 기록입니다.', '이미 코스로 등록한 기록이에요. 같은 기록은 한 번만 코스로 등록할 수 있어요.'),
    ('COURSE-003', '경로 지점은 2개 이상이어야 합니다.', '1km 이상 달린 기록만 코스로 등록할 수 있어요.'),
    ('COURSE-004', '코스 거리는 1km 이상이어야 합니다.', '1km 이상 달린 기록만 코스로 등록할 수 있어요.'),
    ('COURSE-011', 'GPS 정확도가 부족해 코스로 등록할 수 없습니다.', 'GPS가 끊긴 구간이 있어 코스로 등록할 수 없어요.'),
  ]) {
    testWidgets('tells why the record cannot become a course before asking a name ($code)', (tester) async {
      courses.gpsRouteError = ApiException(code, message);
      await openFromRunTab(tester);

      expect(find.text(GpsCourseInfoScreen.blockedTitle), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: '이름을 쓰기 전에 막는다');
      expect(find.text('코스 등록하기'), findsNothing);
      expect(find.text('다시 시도'), findsNothing, reason: '다시 받아도 같다');

      await tap(tester, find.text('돌아가기'));
      expect(find.byType(GpsCourseInfoScreen), findsNothing);
      expect(find.byType(FreeRunScreen), findsOneWidget);
    });
  }

  testWidgets('retries loading the route when it fails', (tester) async {
    records.error = const ApiException(ApiException.network, offline);
    await openFromRunTab(tester);

    expect(find.text(GpsCourseInfoScreen.loadFailedTitle), findsOneWidget);
    expect(find.text(GpsCourseInfoScreen.offlineMessage), findsOneWidget, reason: 'B1과 같은 짧은 안내');
    expect(find.text('코스 등록하기'), findsNothing);
    expect(courses.gpsPreviews, isEmpty);

    records.error = null;
    await tap(tester, find.text('다시 시도'));
    expect(records.requests, [recordId, recordId]);
    expect(find.text('코스 이름'), findsOneWidget);
    expect(register(tester), isNull);
  });

  testWidgets('tells when the record is gone', (tester) async {
    records.records = {};
    await openFromRunTab(tester);

    expect(find.text(GpsCourseInfoScreen.loadFailedTitle), findsOneWidget);
    expect(find.text('러닝 기록을 찾을 수 없어요.'), findsOneWidget, reason: '달리기 서버 문구');
  });

  testWidgets('switches to the reason when the record became a course meanwhile', (tester) async {
    await openFromRunTab(tester);
    await fillIn(tester);

    // 그사이 다른 기기에서 같은 기록으로 등록했다.
    courses.registerError = const ApiException('COURSE-010', '이미 코스로 등록한 러닝 기록입니다.');
    await tap(tester, find.text('코스 등록하기'));
    expect(find.text(GpsCourseInfoScreen.blockedTitle), findsOneWidget);
    expect(find.text('코스 등록하기'), findsNothing);
    expect(find.text('코스를 등록했어요'), findsNothing);
  });

  testWidgets('keeps the input when registering fails and retries with the same key', (tester) async {
    courses.registerError = const ApiException(ApiException.network, offline);
    await openFromRunTab(tester);
    await fillIn(tester);

    await tap(tester, find.text('코스 등록하기'));
    expect(find.text(offline), findsOneWidget);
    expect(find.text(name), findsOneWidget, reason: '입력 유지');
    expect(selected(tester, '중'), isTrue);

    courses.registerError = null;
    await tap(tester, find.text('다시 시도'));
    expect(find.text('코스를 등록했어요'), findsOneWidget);
    final [failed, retried] = courses.gpsRegistrations;
    expect(retried.idempotencyKey, failed.idempotencyKey, reason: '같은 등록은 같은 멱등 키');
  });

  testWidgets('tells when the name is taken, also when the server finds it on registering', (tester) async {
    courses.takenNames = {'반포한바퀴4k'};
    await openFromRunTab(tester);

    await fillIn(tester);
    expect(find.text('이미 있는 코스 이름이에요'), findsOneWidget);
    expect(register(tester), isNull);

    await enterName(tester, '반포 한 바퀴 5K');
    expect(register(tester), isNotNull);
    courses.registerError = const ApiException('COURSE-006', '이미 사용 중인 코스 이름입니다.');
    await tap(tester, find.text('코스 등록하기'));
    expect(find.text('이미 있는 코스 이름이에요'), findsOneWidget);
    expect(register(tester), isNull);
  });

  testWidgets('explains an overlapping route without a retry', (tester) async {
    const similar = '기존 코스와 85% 이상 겹쳐 등록할 수 없습니다.';
    courses.registerError = const ApiException('COURSE-007', similar);
    await openFromRunTab(tester);
    await fillIn(tester);

    await tap(tester, find.text('코스 등록하기'));
    expect(find.text(similar), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
    expect(find.byType(GpsCourseInfoScreen), findsOneWidget);
  });

  testWidgets('blocks registering when today\'s GPS courses are used up', (tester) async {
    courses.registerError = const ApiException('COURSE-008', '오늘 등록할 수 있는 코스 수를 넘었습니다.', status: 429);
    await openFromRunTab(tester);
    await fillIn(tester);

    await tap(tester, find.text('코스 등록하기'));
    await tester.scrollUntilVisible(
      find.text(gpsQuotaUsedUpMessage),
      100,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
    );
    expect(find.text(gpsQuotaUsedUpMessage), findsOneWidget);
    expect(find.text('오늘 등록할 수 있는 코스 수를 넘었습니다.'), findsOneWidget, reason: '스낵바');
    expect(register(tester), isNull);
  });

  testWidgets('leaves without asking, keeping the run tab', (tester) async {
    await openFromRunTab(tester);
    await fillIn(tester);

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));
    expect(find.byType(AlertDialog), findsNothing, reason: '묻지 않는다');
    expect(find.byType(GpsCourseInfoScreen), findsNothing);
    expect(find.byType(FreeRunScreen), findsOneWidget);
    expect(courses.gpsRegistrations, isEmpty);
  });

  testWidgets('cannot register twice or leave while registering', (tester) async {
    courses.registerGate = Completer();
    await openFromRunTab(tester);
    await fillIn(tester);

    await tester.tap(find.text('코스 등록하기'));
    await tester.pump();
    expect(register(tester), isNull);

    await tester.tap(find.bySemanticsLabel('뒤로 가기'));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(GpsCourseInfoScreen), findsOneWidget);

    courses.registerGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('코스를 등록했어요'), findsOneWidget);
    expect(courses.gpsRegistrations, hasLength(1));
  });
}
