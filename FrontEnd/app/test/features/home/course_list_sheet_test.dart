import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/course_format.dart';
import 'package:wadadak/features/course/course_list_card.dart';
import 'package:wadadak/features/home/course_list_sheet.dart';
import 'package:wadadak/features/home/home_screen.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseApi courses;

  /// 2026-10-14 12:00(Asia/Seoul).
  final now = DateTime.utc(2026, 10, 14, 3);

  /// [daysLeft]일 뒤 23:59:59(Asia/Seoul)에 만료되는 코스.
  CourseListItem course(
    String name, {
    int distanceMeters = 3400,
    Difficulty difficulty = Difficulty.easy,
    List<CourseTag> tags = const [CourseTag.shade, CourseTag.riverside],
    CourseType courseType = CourseType.custom,
    int daysLeft = 20,
  }) =>
      CourseListItem(
        courseId: 'id-$name',
        name: name,
        distanceMeters: distanceMeters,
        difficulty: difficulty,
        tags: tags,
        courseType: courseType,
        expiresAt: DateTime.utc(2026, 10, 14 + daysLeft, 14, 59, 59),
        route: const [GeoPoint(37.5666, 126.9784), GeoPoint(37.5700, 126.9800), GeoPoint(37.5690, 126.9830)],
      );

  Future<void> openHome(WidgetTester tester) async {
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
      child: MaterialApp(theme: WdTheme.light(), home: HomeScreen(now: () => now)),
    ));
    await tester.pumpAndSettle();
  }

  Finder sheetTitle(String title) => find.descendant(of: find.byType(CourseListSheet), matching: find.text(title));

  setUp(() => courses = FakeCourseApi());

  testWidgets('lists the latest courses in the map area on the half sheet', (tester) async {
    courses
      ..onMap = const [MapCourse(courseId: 'm', name: '지도 코스', route: [MapView.seoulCityHall, GeoPoint(37.57, 126.98)])]
      ..listed = [
        course('성북천 벚꽃길 3K', daysLeft: 1),
        course('한강 야경 5K', distanceMeters: 5249, difficulty: Difficulty.medium, tags: const [CourseTag.flat],
            courseType: CourseType.gps),
      ];
    await openHome(tester);

    expect(sheetTitle('지금 달리기 좋은 코스'), findsOneWidget);
    expect(sheetTitle('코스 1'), findsOneWidget, reason: '지도가 센 범위 안 코스 수');
    expect(find.widgetWithText(WdFilterChip, '최신순'), findsOneWidget);

    final [first, second] = tester.widgetList<CourseListCard>(find.byType(CourseListCard)).toList();
    expect(first.course.name, '성북천 벚꽃길 3K');
    expect(second.course.name, '한강 야경 5K');
    // Figma A6 카드: 거리 · 난이도 · 첫 특징, 유형, 만료.
    expect(find.text('3.4km · 난이도 하 · 그늘'), findsOneWidget);
    expect(find.text('5.2km · 난이도 중 · 평지'), findsOneWidget);
    expect(find.text('그려서 만든 코스'), findsOneWidget);
    expect(find.text('달려서 만든 코스'), findsOneWidget);
    expect(tester.widget<WdTag>(find.widgetWithText(WdTag, '만료 D-1')).tone, WdTone.warning);
    expect(tester.widget<WdTag>(find.widgetWithText(WdTag, '만료 D-20')).tone, WdTone.neutral);

    // 지도와 같은 범위, 최신순(MAP-07).
    final list = courses.listRequests.single;
    final map = courses.mapRequests.single;
    expect((list.southWest, list.northEast), (map.southWest, map.northEast));
    expect(list.sort, CourseListSort.latest);
    expect(list.cursor, isNull);
  });

  testWidgets('lists again for the new area when the map stops moving', (tester) async {
    courses.listed = [course('성북천 벚꽃길 3K')];
    await openHome(tester);

    courses.listed = [course('정릉 오르막 4K')];
    await tester.dragFrom(const Offset(200, 150), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(find.text('성북천 벚꽃길 3K'), findsNothing);
    expect(find.text('정릉 오르막 4K'), findsOneWidget);
    final [first, second] = courses.listRequests;
    expect(second.southWest.lng, greaterThan(first.southWest.lng));
    expect(second.cursor, isNull);
  });

  testWidgets('loads the next page when scrolled to the end', (tester) async {
    courses
      ..listPageSize = 5
      ..listed = [for (var i = 1; i <= 8; i++) course('코스 $i')];
    await openHome(tester);
    expect(find.byType(CourseListCard), findsAtLeastNWidgets(1));

    await tester.fling(find.byType(CourseListCard).first, const Offset(0, -2000), 3000);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CourseListCard).last, const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(courses.listRequests.map((request) => request.cursor), [null, '5']);
    final names = [for (final card in tester.widgetList<CourseListCard>(find.byType(CourseListCard))) card.course.name];
    expect(names.last, '코스 8');
    expect(names.toSet(), hasLength(names.length), reason: '같은 코스가 두 번 나오지 않는다');
  });

  testWidgets('tells when the list cannot be loaded at first, and retries', (tester) async {
    courses.listError = const ApiException(ApiException.network, '네트워크에 연결할 수 없어요.');
    await openHome(tester);
    expect(find.text(CourseListSheet.loadFailedMessage), findsWidgets);

    courses
      ..listError = null
      ..listed = [course('성북천 벚꽃길 3K')];
    await tester.tap(find.widgetWithText(WdButton, '다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('성북천 벚꽃길 3K'), findsOneWidget);
  });

  testWidgets('keeps the list it has when a later load fails', (tester) async {
    courses.listed = [course('성북천 벚꽃길 3K')];
    await openHome(tester);

    courses.listError = const ApiException(ApiException.network, '네트워크에 연결할 수 없어요.');
    await tester.dragFrom(const Offset(200, 150), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(courses.listRequests, hasLength(2));
    expect(find.text('성북천 벚꽃길 3K'), findsOneWidget, reason: '갱신 실패는 전에 받은 목록을 둔다(QST-02)');
  });

  testWidgets('offers to widen the map when there are no courses', (tester) async {
    await openHome(tester);
    expect(find.text(CourseListSheet.emptyMessage), findsOneWidget);
    final before = courses.mapRequests.single;

    await tester.tap(find.widgetWithText(WdButton, '지도 범위 넓히기'));
    await tester.pumpAndSettle();

    final after = courses.mapRequests.last;
    expect(after.northEast.lat - after.southWest.lat, greaterThan(before.northEast.lat - before.southWest.lat),
        reason: '한 단계 축소한다(STA-01)');
  });

  testWidgets('drags between the peek, half and full sheet', (tester) async {
    courses.listed = [course('성북천 벚꽃길 3K')];
    await openHome(tester);
    final handle = sheetTitle('지금 달리기 좋은 코스');

    // 아래로 내리면 피크(A5).
    await tester.drag(handle, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(sheetTitle('↑ 위로 올려 코스 목록 보기'), findsOneWidget);
    expect(find.text('성북천 벚꽃길 3K').hitTestable(), findsNothing);

    // 제목 줄을 누르면 다시 반(A2).
    await tester.tap(sheetTitle('↑ 위로 올려 코스 목록 보기'));
    await tester.pumpAndSettle();
    expect(sheetTitle('지금 달리기 좋은 코스'), findsOneWidget);
    expect(find.text('＋ 코스 만들기').hitTestable(), findsOneWidget, reason: '지도 위 버튼');

    // 위로 올리면 전체 보기(A6). 지도 위 버튼은 숨기고 제목 줄에 코스 만들기가 있다.
    await tester.drag(handle, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(WdMapPillButton, '＋ 코스 만들기').hitTestable(), findsNothing);
    expect(sheetTitle('＋ 코스 만들기'), findsOneWidget);
  });

  testWidgets('lowers the sheet when the map is tapped', (tester) async {
    await openHome(tester);

    await tester.tapAt(const Offset(200, 150));
    await tester.pumpAndSettle();

    expect(sheetTitle('↑ 위로 올려 코스 목록 보기'), findsOneWidget, reason: '지도 전체 보기(A2-03)');
    expect(tester.getTopLeft(find.byType(CourseListSheet)).dy, closeTo(874 - CourseListSheet.peekHeight, 1));
  });

  group('expiry', () {
    test('counts the days left in Seoul dates', () {
      // 만료일 23:59:59(Asia/Seoul) = 14:59:59Z.
      final expiresAt = DateTime.utc(2026, 10, 15, 14, 59, 59);
      expect(daysUntilExpiry(expiresAt, DateTime.utc(2026, 10, 14, 14, 59)), 1, reason: '10-14 23:59 서울');
      expect(daysUntilExpiry(expiresAt, DateTime.utc(2026, 10, 14, 15)), 0, reason: '10-15 00:00 서울은 만료일 당일');
      expect(formatExpiry(1), '만료 D-1');
      expect(formatExpiry(0), '만료 D-day');
    });
  });
}
