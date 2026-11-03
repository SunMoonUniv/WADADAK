import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/core/permissions/device_setup.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/my/my_courses_screen.dart';
import 'package:wadadak/features/my/saved_courses_tab.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';

/// G5 · 저장한 코스(Figma G5 · G5-1, 정책 문서 4.1 `저장한 코스 API` · `G5 편집`).
void main() {
  // 2026-11-02 12:00 (Asia/Seoul)
  final now = DateTime.utc(2026, 11, 2, 3);
  const here = GeoPoint(37.5593, 126.9784);

  late FakeCourseApi courses;
  late FakeMyLocation location;

  /// E3 `저장한 코스`처럼 G4 화면을 저장 탭으로 연다. B1은 이름만 보이는 화면이다.
  Future<void> openG5(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, _) =>
              TextButton(onPressed: () => context.push(Routes.mySavedCourses), child: const Text('E3')),
        ),
        GoRoute(
          path: Routes.myCourses,
          builder: (_, state) => MyCoursesScreen(now: () => now, saved: state.uri.queryParameters['tab'] == 'saved'),
        ),
        GoRoute(path: '/course/:courseId', builder: (_, state) => Text('B1 ${state.pathParameters['courseId']}')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(MemoryTokenStorage(testTokens)),
          courseApiClientProvider.overrideWithValue(courses),
          reviewApiClientProvider.overrideWithValue(FakeCourseReviewApi(reviewSummary())),
          mapEngineProvider.overrideWithValue(MapEngine.dev),
          myLocationProvider.overrideWithValue(location),
        ],
        child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
      ),
    );
    await tester.tap(find.text('E3'));
    await tester.pumpAndSettle();
  }

  Finder inCard(String name, String text) => find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(SavedCourseCard)),
        matching: find.text(text),
      );

  setUp(() {
    courses = FakeCourseApi()
      ..bookmarkRows = [
        testBookmark('한강 다리 왕복 8K', distanceMeters: 8100, difficulty: 'HARD', rating: 4.4,
            expiresAt: '2026-11-20T14:59:59Z'),
        testBookmark('북악산 둘레길 3K', distanceMeters: 3200, rating: 4.6, creator: '성북러너', expiresAt: '2026-11-03T14:59:59Z'),
        testBookmark('안암 골목길 2K', creator: null, pendingDelete: true),
      ]
      ..expiringSoonBookmarks = 1;
    location = FakeMyLocation(location: here);
  });

  testWidgets('opens on the saved tab with totals, sort chips and saved cards (Figma G5)', (tester) async {
    await openG5(tester);

    expect(find.text('저장한 코스 2'), findsNWidgets(2), reason: '탭과 목록 머리글 · 삭제 예정은 세지 않는다');
    expect(tester.widget<WdStatSummary>(find.byType(WdStatSummary)).items, [('저장한 코스', '2개'), ('만료 임박', '1개')]);
    expect(find.textContaining('저장만으로는 공개 기간이 늘지 않아요'), findsOneWidget);
    expect([for (final chip in tester.widgetList<WdFilterChip>(find.byType(WdFilterChip))) '${chip.label}${chip.selected ? '*' : ''}'],
        ['최근 저장순*', '가까운순', '평점순', '만료 임박']);
    expect(inCard('한강 다리 왕복 8K', '8.1km · 난이도 상 · ★ 4.4'), findsOneWidget);
    expect(inCard('한강 다리 왕복 8K', '만든 사람 러너_하늘'), findsOneWidget);
    expect(inCard('한강 다리 왕복 8K', '만료 D-18'), findsOneWidget);
    expect(inCard('한강 다리 왕복 8K', '이 코스로 달리기 ›'), findsOneWidget);
    expect(tester.widget<WdTag>(find.descendant(of: find.ancestor(of: find.text('북악산 둘레길 3K'), matching: find.byType(SavedCourseCard)),
        matching: find.byType(WdTag))).tone, WdTone.warning, reason: '만료 D-1은 주황');
    expect(inCard('안암 골목길 2K', '삭제 예정'), findsOneWidget);
    expect(inCard('안암 골목길 2K', '이 코스로 달리기 ›'), findsNothing, reason: '삭제 예정 코스는 달릴 수 없다');
    expect(find.descendant(of: find.ancestor(of: find.text('안암 골목길 2K'), matching: find.byType(SavedCourseCard)),
        matching: find.byType(Opacity)), findsOneWidget);
    expect(find.textContaining('목록에서 자동으로 사라져요'), findsOneWidget);
    expect(courses.bookmarkRequests, [(BookmarkSort.recent, null, null)]);
  });

  testWidgets('sorts by the chips, asking the location for the nearest', (tester) async {
    await openG5(tester);

    await tester.tap(find.text('평점순'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가까운순'));
    await tester.pumpAndSettle();

    expect(courses.bookmarkRequests.skip(1), [(BookmarkSort.rating, null, null), (BookmarkSort.nearest, here, null)]);
    expect(tester.widget<WdFilterChip>(find.widgetWithText(WdFilterChip, '가까운순')).selected, isTrue);
  });

  testWidgets('selects the nearest chip and shows loading while the location is read', (tester) async {
    await openG5(tester);
    location.fix = Completer();

    await tester.tap(find.text('가까운순'));
    await tester.pump();

    expect(tester.widget<WdFilterChip>(find.widgetWithText(WdFilterChip, '가까운순')).selected, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SavedCourseCard), findsNothing);

    location.fix!.complete();
    await tester.pumpAndSettle();

    expect(courses.bookmarkRequests.last, (BookmarkSort.nearest, here, null));
    expect(find.byType(SavedCourseCard), findsNWidgets(3));
  });

  testWidgets('keeps the sort when the location cannot be read', (tester) async {
    location.error = const DeviceSetupException('현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
    await openG5(tester);

    await tester.tap(find.text('가까운순'));
    await tester.pumpAndSettle();

    expect(courses.bookmarkRequests, hasLength(1));
    expect(find.text('현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(tester.widget<WdFilterChip>(find.widgetWithText(WdFilterChip, '최근 저장순')).selected, isTrue);
  });

  testWidgets('a card opens its detail and the list is asked again on the way back', (tester) async {
    await openG5(tester);

    await tester.tap(find.text('한강 다리 왕복 8K'));
    await tester.pumpAndSettle();
    expect(find.text('B1 한강 다리 왕복 8K'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(courses.bookmarkRequests, hasLength(2), reason: 'B1에서 저장을 풀었을 수 있다');
  });

  testWidgets('edit picks several cards and unsaves them at once after asking (G5-1)', (tester) async {
    await openG5(tester);

    await tester.tap(find.text('편집'));
    await tester.pumpAndSettle();
    expect(find.text('0개 선택됨'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
    expect(find.text('이 코스로 달리기 ›'), findsNothing, reason: '편집 중에는 달리기를 숨긴다');
    expect(tester.widget<WdButton>(find.widgetWithText(WdButton, '저장 해제')).onPressed, isNull);

    await tester.tap(find.text('한강 다리 왕복 8K'));
    await tester.tap(find.text('안암 골목길 2K'));
    await tester.pumpAndSettle();
    expect(find.text('2개 선택됨'), findsOneWidget);
    expect(find.text('B1 한강 다리 왕복 8K'), findsNothing, reason: '편집 중 카드는 고르기만 한다');

    await tester.tap(find.text('2개 저장 해제'));
    await tester.pumpAndSettle();
    expect(find.text('코스 2개의 저장을 풀까요?'), findsOneWidget);
    await tester.tap(find.text('저장 해제').last);
    await tester.pumpAndSettle();

    expect(courses.removedBookmarks.single, unorderedEquals(['한강 다리 왕복 8K', '안암 골목길 2K']));
    expect(find.byType(SavedCourseCard), findsOneWidget);
    expect(find.text('편집'), findsOneWidget, reason: '풀고 나면 편집을 마친다');
    expect(find.text('코스 2개의 저장을 풀었어요.'), findsOneWidget);
    expect(find.text('저장한 코스 1'), findsNWidgets(2));
  });

  testWidgets('cancelling the question keeps the saved courses', (tester) async {
    await openG5(tester);

    await tester.tap(find.text('편집'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한강 다리 왕복 8K'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1개 저장 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(courses.removedBookmarks, isEmpty);
    expect(find.byType(SavedCourseCard), findsNWidgets(3));
    expect(find.text('1개 선택됨'), findsOneWidget);
  });

  testWidgets('shows an empty state without edit when nothing is saved', (tester) async {
    courses.bookmarkRows = [];
    await openG5(tester);

    expect(find.text(SavedCoursesTab.emptyTitle), findsOneWidget);
    expect(find.text('편집'), findsNothing);
  });
}
