import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/dev_map_view.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/course_list_card.dart';
import 'package:wadadak/features/home/course_list_sheet.dart';
import 'package:wadadak/features/home/home_screen.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

/// 지도 코스 선택(MAP-03 · A5-01, 정책 문서 제4부 4.5).
void main() {
  late FakeCourseApi courses;

  final cityHall = testCourse('시청 한 바퀴 1K', courseId: 'a', route: const [MapView.seoulCityHall, GeoPoint(37.5700, 126.9800)]);
  final jeongneung =
      testCourse('정릉 오르막 4K', courseId: 'b', route: const [GeoPoint(37.5680, 126.9760), GeoPoint(37.5720, 126.9750)]);

  /// 시청에서 남쪽으로 약 2.2km. 줌 14에서 지도 위쪽 끝부터 600쯤 아래라 피크에서는 보이고 반 시트에는 가린다.
  final south = testCourse('남산 둘레 3K', courseId: 'c', route: const [GeoPoint(37.5467, 126.9784), GeoPoint(37.5500, 126.9800)]);

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
      child: MaterialApp(theme: WdTheme.light(), home: HomeScreen(now: () => DateTime.utc(2026, 10, 14, 3))),
    ));
    await tester.pumpAndSettle();
  }

  MapView map(WidgetTester tester) => tester.widget<MapView>(find.byType(MapView));
  Finder label(String name) => find.widgetWithText(WdMapCourseLabel, name);
  Finder sheetText(String text) => find.descendant(of: find.byType(CourseListSheet), matching: find.text(text));
  List<String> cards(WidgetTester tester) =>
      [for (final card in tester.widgetList<CourseListCard>(find.byType(CourseListCard))) card.course.name];

  Future<void> tapLabel(WidgetTester tester, String name) async {
    await tester.tap(label(name));
    await tester.pumpAndSettle();
  }

  setUp(() => courses = FakeCourseApi()
    ..onMap = [cityHall, jeongneung]
    ..listed = [jeongneung, cityHall]);

  testWidgets('tapping a name label keeps only that course on the map and in the list', (tester) async {
    await openHome(tester);
    expect(cards(tester), ['정릉 오르막 4K', '시청 한 바퀴 1K']);

    await tapLabel(tester, '시청 한 바퀴 1K');

    // 지도: 고른 코스만, 이름표 배경은 파랑. 선 색은 그대로(같은 코스 선).
    expect([for (final line in map(tester).lines) line.points], [cityHall.route]);
    expect(map(tester).lines.single.style, MapLineStyle.course);
    expect(label('정릉 오르막 4K'), findsNothing);
    expect(tester.widget<WdMapCourseLabel>(label('시청 한 바퀴 1K')).selected, isTrue);
    // 목록: 고른 코스 카드 하나, 정렬 칩은 숨긴다.
    expect(sheetText('선택한 코스'), findsOneWidget);
    expect(cards(tester), ['시청 한 바퀴 1K']);
    expect(find.widgetWithText(WdFilterChip, '최신순'), findsNothing);
    expect(find.text('1.0km · 난이도 하'), findsOneWidget);
  });

  testWidgets('keeps the selection while the map moves or zooms out', (tester) async {
    courses.regions = [const RegionCount(code: '1114000000', name: '중구', count: 7, center: MapView.seoulCityHall)];
    await openHome(tester);
    await tapLabel(tester, '시청 한 바퀴 1K');

    courses.onMap = [jeongneung];
    await tester.dragFrom(const Offset(200, 150), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect([for (final line in map(tester).lines) line.points], [cityHall.route], reason: '범위가 바뀌어도 고른 코스만');

    // 축척 1km: 고르지 않았으면 구 단위 배지지만, 고른 동안은 그 코스를 그대로 둔다.
    await (tester.state(find.byType(DevMapView)) as MapController).moveTo(MapView.seoulCityHall, zoom: 12);
    await tester.pumpAndSettle();
    expect(courses.regionRequests, isNotEmpty);
    expect(find.byType(WdRegionCountBubble), findsNothing);
    expect(label('시청 한 바퀴 1K'), findsOneWidget);
    expect(cards(tester), ['시청 한 바퀴 1K']);
  });

  testWidgets('tapping elsewhere on the map clears the selection, and the next tap lowers the sheet', (tester) async {
    await openHome(tester);
    await tapLabel(tester, '시청 한 바퀴 1K');

    await tester.tapAt(const Offset(350, 180));
    await tester.pumpAndSettle();

    expect(label('정릉 오르막 4K'), findsOneWidget);
    expect(tester.widget<WdMapCourseLabel>(label('시청 한 바퀴 1K')).selected, isFalse);
    expect(sheetText('지금 달리기 좋은 코스 2'), findsOneWidget, reason: '선택을 풀어도 시트는 반 그대로');
    expect(cards(tester), ['정릉 오르막 4K', '시청 한 바퀴 1K']);
    expect(find.widgetWithText(WdFilterChip, '최신순'), findsOneWidget);

    await tester.tapAt(const Offset(350, 180));
    await tester.pumpAndSettle();
    expect(sheetText('↑ 위로 올려 코스 목록 보기'), findsOneWidget, reason: '지도 전체 보기(A2-03)');
  });

  testWidgets('tapping the selected label again keeps it selected', (tester) async {
    await openHome(tester);
    await tapLabel(tester, '시청 한 바퀴 1K');
    await tapLabel(tester, '시청 한 바퀴 1K');

    expect(tester.widget<WdMapCourseLabel>(label('시청 한 바퀴 1K')).selected, isTrue);
    expect(label('정릉 오르막 4K'), findsNothing);
  });

  testWidgets('selecting from the peek raises the list and moves the map if the sheet would hide the start',
      (tester) async {
    courses.onMap = [cityHall, south];
    await openHome(tester);
    // 지도를 눌러 피크(A5)로 내린다.
    await tester.tapAt(const Offset(350, 180));
    await tester.pumpAndSettle();
    expect(sheetText('↑ 위로 올려 코스 목록 보기'), findsOneWidget);
    final sheetHalfTop = 122.5 + (874 - 122.5) / 2;
    expect(tester.getBottomLeft(label('남산 둘레 3K')).dy, greaterThan(sheetHalfTop), reason: '반 시트가 올라오면 가릴 자리');

    await tapLabel(tester, '남산 둘레 3K');

    expect(sheetText('선택한 코스'), findsOneWidget, reason: '목록 시트가 반으로 올라온다');
    expect(tester.getTopLeft(find.byType(CourseListSheet)).dy, closeTo(sheetHalfTop, 1));
    expect(tester.getBottomLeft(label('남산 둘레 3K')).dy, lessThan(sheetHalfTop), reason: '지도를 옮겨 출발점이 보인다');
    expect(cards(tester), ['남산 둘레 3K']);
  });
}
