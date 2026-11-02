import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/my/course_edit_screen.dart';
import 'package:wadadak/features/my/my_courses_screen.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';

void main() {
  // 2026-11-02 12:00 (Asia/Seoul)
  final now = DateTime.utc(2026, 11, 2, 3);

  late FakeCourseApi courses;
  late FakeCourseReviewApi reviews;

  /// 만료 D-1 · 29일 전 완주 214회
  final sungbuk = testMyCourse(
    '성북천 벚꽃길 3K',
    courseId: 'c1',
    difficulty: Difficulty.easy,
    tags: const [CourseTag.flat, CourseTag.shade, CourseTag.restroom],
    expiresAt: DateTime.utc(2026, 11, 3, 14, 59, 59),
    completionCount: 214,
    lastCompletedOn: DateTime(2026, 10, 4),
  );

  /// D-30 · 오늘 완주, 달려서 만든 코스
  final hangang = testMyCourse(
    '한강 야경 5K',
    courseId: 'c2',
    courseType: CourseType.gps,
    expiresAt: DateTime.utc(2026, 12, 2, 14, 59, 59),
    completionCount: 1204,
    lastCompletedOn: DateTime(2026, 11, 2),
  );

  /// 내가 삭제해 23시간 30분 뒤 지워진다
  final deleted = testMyCourse(
    '개운산 숲길 4K',
    courseId: 'c3',
    hiddenReason: CourseHiddenReason.userDeleted,
    deleteAt: now.add(const Duration(hours: 23, minutes: 30)),
  );

  /// G4를 띄운다. B3 · B1은 이름만 보이는 화면으로 바꿔 어디로 갔는지만 본다.
  Future<void> openG4(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, _) => TextButton(onPressed: () => context.push(Routes.myCourses), child: const Text('E3')),
        ),
        GoRoute(path: Routes.myCourses, builder: (_, _) => MyCoursesScreen(now: () => now)),
        GoRoute(
          path: Routes.myCourseEdit,
          builder: (_, state) => CourseEditScreen(course: state.extra! as MyCourseItem, now: () => now),
        ),
        GoRoute(path: Routes.courseCreate, builder: (_, _) => const Text('B3')),
        GoRoute(path: '/course/:courseId', builder: (_, state) => Text('B1 ${state.pathParameters['courseId']}')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(MemoryTokenStorage(testTokens)),
          courseApiClientProvider.overrideWithValue(courses),
          reviewApiClientProvider.overrideWithValue(reviews),
          mapEngineProvider.overrideWithValue(MapEngine.dev),
        ],
        child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
      ),
    );
    await tester.tap(find.text('E3'));
    await tester.pumpAndSettle();
  }

  /// [name] 카드 안의 [text].
  Finder inCard(String name, String text) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(MyCourseCard)),
    matching: find.text(text),
  );

  Future<void> openEdit(WidgetTester tester, String name) async {
    await tester.tap(inCard(name, '수정'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    courses = FakeCourseApi()
      ..now = (() => now)
      ..mine = [sungbuk, hangang, deleted]
      ..mySummary = const MyCourseSummary(courseCount: 2, completionCount: 1480, expiringSoonCount: 1);
    reviews = FakeCourseReviewApi(reviewSummary(count: 76, average: 4.8));
  });

  group('G4', () {
    testWidgets('shows totals, the public period notice and my course cards', (tester) async {
      await openG4(tester);

      expect(find.text('등록한 코스 2'), findsOneWidget);
      expect(find.text('2개'), findsOneWidget);
      expect(find.text('1,480회'), findsOneWidget);
      expect(find.text('1개'), findsOneWidget);
      expect(find.textContaining('등록한 날부터 30일 동안 공개돼요'), findsOneWidget);

      expect(inCard('성북천 벚꽃길 3K', '최근 주행 29일 전 · 누적 214회'), findsOneWidget);
      expect(inCard('성북천 벚꽃길 3K', '만료 D-1'), findsOneWidget);
      expect(inCard('성북천 벚꽃길 3K', '그려서 만든 코스'), findsOneWidget);
      expect(inCard('한강 야경 5K', '최근 주행 오늘 · 누적 1,204회'), findsOneWidget);
      expect(inCard('한강 야경 5K', 'D-30'), findsOneWidget);
      expect(inCard('한강 야경 5K', '달려서 만든 코스'), findsOneWidget);
    });

    testWidgets('a course waiting to be deleted is dimmed without edit or delete', (tester) async {
      await openG4(tester);

      expect(inCard('개운산 숲길 4K', '삭제 예정'), findsOneWidget);
      expect(inCard('개운산 숲길 4K', '내가 삭제함 · 23시간 뒤 삭제'), findsOneWidget);
      expect(inCard('개운산 숲길 4K', '최근 주행 없음 · 누적 0회'), findsOneWidget);
      expect(inCard('개운산 숲길 4K', '수정'), findsNothing);
      expect(inCard('개운산 숲길 4K', '삭제'), findsNothing);
      expect(find.descendant(of: find.byType(MyCourseCard).last, matching: find.byType(Opacity)), findsOneWidget);
    });

    testWidgets('delete asks first, then the card turns into a pending delete', (tester) async {
      await openG4(tester);

      await tester.tap(inCard('성북천 벚꽃길 3K', '삭제'));
      await tester.pumpAndSettle();
      expect(find.text('성북천 벚꽃길 3K 코스를 삭제할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(courses.deletes, isEmpty);

      await tester.tap(inCard('성북천 벚꽃길 3K', '삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '삭제'));
      await tester.pumpAndSettle();

      expect(courses.deletes, ['c1']);
      expect(inCard('성북천 벚꽃길 3K', '삭제 예정'), findsOneWidget);
      expect(inCard('성북천 벚꽃길 3K', '내가 삭제함 · 24시간 뒤 삭제'), findsOneWidget);
      // 위 칸 · E3 합계를 다시 받는다
      expect(courses.summaryRequests, 2);
    });

    testWidgets('scrolling to the end loads the next page', (tester) async {
      courses
        ..myPageSize = 2
        ..mine = [sungbuk, hangang, deleted];
      await openG4(tester);
      await tester.pumpAndSettle();

      expect(courses.mineCursors, [null, '2']);
      expect(find.text('개운산 숲길 4K'), findsOneWidget);
    });

    testWidgets('no courses shows how to make one', (tester) async {
      courses.mine = [];
      await openG4(tester);

      expect(find.text('등록한 코스가 없어요'), findsOneWidget);
    });

    testWidgets('a failed list can be loaded again', (tester) async {
      courses.mineError = const ApiException(ApiException.network, '오프라인');
      await openG4(tester);
      expect(find.text('코스를 불러오지 못했어요.'), findsOneWidget);

      courses.mineError = null;
      await tester.tap(find.text('다시 불러오기'));
      await tester.pumpAndSettle();
      expect(find.text('성북천 벚꽃길 3K'), findsOneWidget);
    });

    testWidgets('saved courses tab is coming soon', (tester) async {
      await openG4(tester);

      await tester.tap(find.text('저장한 코스'));
      await tester.pumpAndSettle();
      expect(find.text('준비 중이에요'), findsOneWidget);
    });

    testWidgets('make opens B3 and a card opens its detail', (tester) async {
      await openG4(tester);

      await tester.tap(find.text('한강 야경 5K'));
      await tester.pumpAndSettle();
      expect(find.text('B1 c2'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ 만들기'));
      await tester.pumpAndSettle();
      expect(find.text('B3'), findsOneWidget);
    });
  });

  group('B7', () {
    testWidgets('is filled with the course and its status', (tester) async {
      await openG4(tester);
      await openEdit(tester, '성북천 벚꽃길 3K');

      expect(find.text('코스 수정'), findsOneWidget);
      expect(find.text('경로는 바꿀 수 없어요'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '성북천 벚꽃길 3K');
      for (final (label, selected) in [('하', true), ('중', false), ('평지', true), ('그늘', true), ('화장실', true), ('강변', false)]) {
        expect(tester.widget<WdFilterChip>(find.widgetWithText(WdFilterChip, label)).selected, selected, reason: label);
      }
      expect(find.text('214회'), findsOneWidget);
      expect(find.text('★ 4.8 (76)'), findsOneWidget);
      expect(find.text('D-1'), findsOneWidget);
    });

    testWidgets('save stays off until something changes, then saves and updates the card', (tester) async {
      await openG4(tester);
      await openEdit(tester, '성북천 벚꽃길 3K');

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(courses.edits, isEmpty);

      await tester.enterText(find.byType(TextField), '성북천 야경길 3K');
      await tester.pump(const Duration(milliseconds: 300));
      // 이 코스의 지금 이름은 빼고 확인한다
      expect(courses.nameCheckCourseIds, ['c1']);
      await tester.tap(find.widgetWithText(WdFilterChip, '중'));
      await tester.tap(find.widgetWithText(WdFilterChip, '그늘'));
      await tester.pump();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(courses.edits.single.name, '성북천 야경길 3K');
      expect(courses.edits.single.difficulty, Difficulty.medium);
      expect(courses.edits.single.tags, {CourseTag.flat, CourseTag.restroom});
      expect(find.text('코스 수정'), findsNothing);
      expect(find.text('성북천 야경길 3K'), findsOneWidget);
      expect(courses.summaryRequests, 2);
    });

    testWidgets('a name another course already has is shown under the name', (tester) async {
      courses.editError = const ApiException('COURSE-006', '이미 있는 코스 이름입니다.');
      await openG4(tester);
      await openEdit(tester, '성북천 벚꽃길 3K');

      await tester.enterText(find.byType(TextField), '한강 야경 5K');
      await tester.pump();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.text('이미 있는 코스 이름이에요'), findsOneWidget);
      expect(find.text('코스 수정'), findsOneWidget);
    });

    testWidgets('delete asks first and goes back with the card pending delete', (tester) async {
      await openG4(tester);
      await openEdit(tester, '성북천 벚꽃길 3K');

      await tester.scrollUntilVisible(
        find.text('코스 삭제'),
        200,
        scrollable: find.descendant(of: find.byType(CourseEditScreen), matching: find.byType(Scrollable)).first,
      );
      await tester.tap(find.text('코스 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '삭제'));
      await tester.pumpAndSettle();

      expect(courses.deletes, ['c1']);
      expect(find.text('코스 수정'), findsNothing);
      expect(inCard('성북천 벚꽃길 3K', '삭제 예정'), findsOneWidget);
    });

    testWidgets('leaving with changes asks once', (tester) async {
      await openG4(tester);
      await openEdit(tester, '성북천 벚꽃길 3K');

      await tester.tap(find.widgetWithText(WdFilterChip, '상'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('뒤로 가기'));
      await tester.pumpAndSettle();
      expect(find.text('저장하지 않고 나갈까요?'), findsOneWidget);

      await tester.tap(find.text('나가기'));
      await tester.pumpAndSettle();
      expect(find.text('코스 수정'), findsNothing);
      expect(courses.edits, isEmpty);
    });
  });
}
