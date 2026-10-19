import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/api/upload_form.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/core/upload/photo_uploader.dart';
import 'package:wadadak/features/home/home_screen.dart';
import 'package:wadadak/features/review/review_entry.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak/router.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'fakes.dart';

const _course = 'course-1';
const _courseName = '한강 야경 5K';

/// 2026.09.08(Asia/Seoul) 완주 100% · 27:14 기록.
const _record = {
  'runRecordId': 'record-1',
  'courseDistanceMeters': 5200,
  'courseElapsedSeconds': 1634,
  'progressPercent': 100,
  'completed': true,
  'endedAt': '2026-09-08T03:00:00Z',
};

Map<String, Object?> _card(
  String id,
  String nickname,
  int rating, {
  bool mine = false,
  int progress = 100,
  int completed = 4,
}) => {
  'reviewId': id,
  'memberId': 'member-$id',
  'nickname': nickname,
  'profileImageUrl': null,
  'mine': mine,
  'rating': rating,
  'safetyRating': 4,
  'roadRating': 3,
  'lightingRating': 5,
  'amenityRating': 2,
  'content': '$nickname 후기',
  'tags': ['NIGHT_VIEW'],
  'photos': const [],
  'bestProgressPercent': progress,
  'completedCount': completed,
  'createdAt': '2026-09-06T03:00:00Z',
};

/// 리뷰 3개(내 리뷰 포함) 코스. [my]로 내 리뷰 상태를 바꾼다.
class FakeReviewApi implements ReviewApiClient {
  final calls = <String>[];
  Map<String, Object?> my = {
    'review': null,
    'sourceRecord': null,
    'sourceRecordDeleted': false,
    'eligibleRecord': null,
  };
  ({String courseId, String source, ReviewInput input})? written;
  ({String reviewId, ReviewInput input})? edited;
  String? deleted;

  @override
  Future<ReviewSummary> summary(String courseId) async {
    calls.add('summary');
    return ReviewSummary.fromJson({
      'reviewCount': 3,
      'averageRating': 4.3,
      'ratingCounts': {'five': 1, 'four': 2, 'three': 0, 'two': 0, 'one': 0},
      'itemAverages': {'safety': 4.7, 'road': 4.4, 'lighting': 4.8, 'amenity': 4.1},
    });
  }

  @override
  Future<ReviewPage> list(
    String courseId, {
    ReviewSort sort = ReviewSort.latest,
    bool photoOnly = false,
    bool excludeMine = false,
    String? cursor,
  }) async {
    calls.add('list ${sort.apiName} photoOnly=$photoOnly excludeMine=$excludeMine');
    final cards = [_card('r1', '러너_하늘', 5), _card('r2', '달리는곰', 3, progress: 62, completed: 0)];
    return (
      cards: [for (final card in sort == ReviewSort.lowest ? cards.reversed : cards) ReviewCard.fromJson(card)],
      nextCursor: null,
    );
  }

  @override
  Future<MyReview> mine(String courseId) async {
    calls.add('mine');
    return MyReview.fromJson(my);
  }

  @override
  Future<Map<String, double?>> ratings(Iterable<String> courseIds) async => {};

  @override
  Future<void> write(String courseId, String sourceRunRecordId, ReviewInput input) async =>
      written = (courseId: courseId, source: sourceRunRecordId, input: input);

  @override
  Future<void> edit(String reviewId, ReviewInput input) async => edited = (reviewId: reviewId, input: input);

  @override
  Future<void> delete(String reviewId) async => deleted = reviewId;

  @override
  Future<UploadForm> photoUploadForm() async =>
      UploadForm.fromJson({'url': 'https://files.test/wadadak', 'key': 'review/new.jpg', 'fields': <String, String>{}});
}

/// 의미 라벨로 찾는다(별 · 사진 추가 버튼은 글자가 겹친다).
Finder _labeled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

void main() {
  late FakeReviewApi api;
  late FakePhotoUploader photos;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 로그인한 앱을 띄운다(홈).
  Future<void> openApp(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(MemoryTokenStorage(testTokens)),
          memberApiClientProvider.overrideWithValue(FakeMemberApi()),
          mapEngineProvider.overrideWithValue(MapEngine.dev),
          courseApiClientProvider.overrideWithValue(FakeCourseApi()),
          reviewApiClientProvider.overrideWithValue(api),
          photoUploaderProvider.overrideWithValue(photos),
        ],
        child: const WadadakApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 로그인한 앱을 띄우고 G2로 간다(B8 "모두 보기"가 하는 일).
  Future<void> openReviews(WidgetTester tester) async {
    await openApp(tester);
    ProviderScope.containerOf(tester.element(find.byType(WadadakApp)))
        .read(routerProvider)
        .push(Routes.courseReviews(_course), extra: _courseName);
    await tester.pumpAndSettle();
  }

  /// 다른 화면(마이페이지 내 기록 등)이 하듯 홈에서 [openReviewWriter]를 부른다.
  Future<void> openWriter(WidgetTester tester) async {
    await openApp(tester);
    // Consumer 화면의 Element가 곧 WidgetRef다
    final home = tester.element(find.byType(HomeScreen));
    openReviewWriter(home, home as WidgetRef, courseId: _course, courseName: _courseName).ignore();
    await tester.pumpAndSettle();
  }

  setUp(() {
    api = FakeReviewApi();
    photos = FakePhotoUploader();
  });

  testWidgets('G2 shows the summary, other runners and asks the list without my review', (tester) async {
    await openReviews(tester);

    expect(find.text('리뷰 3'), findsOneWidget);
    expect(find.text(_courseName), findsOneWidget);
    expect(find.text('4.3'), findsOneWidget);
    expect(find.text('4.7'), findsOneWidget); // 안전성 평균
    expect(find.text('다른 러너 리뷰 3'), findsOneWidget);
    expect(find.text('내 리뷰'), findsNothing); // 내 리뷰가 없으면 칩도 없다
    expect(find.text('러너_하늘'), findsOneWidget);
    expect(find.text('완주 100%'), findsOneWidget);
    expect(find.text('2026.09.06 · 4회 주행'), findsOneWidget);
    expect(find.text('62% 주행'), findsOneWidget);
    expect(find.text('2026.09.06'), findsOneWidget); // 완주 0회는 날짜만
    expect(api.calls, contains('list LATEST photoOnly=false excludeMine=true'));

    await tap(tester, find.text('낮은 평점'));
    await tap(tester, find.text('사진 리뷰만'));
    expect(
      api.calls,
      containsAll(['list LOWEST photoOnly=false excludeMine=true', 'list LOWEST photoOnly=true excludeMine=true']),
    );
  });

  testWidgets('G2 has no write button even when I can write one', (tester) async {
    // 리뷰 작성은 마이페이지 내 기록에서 openReviewWriter로 연다
    api.my = {...api.my, 'eligibleRecord': _record};
    await openReviews(tester);

    expect(find.text('리뷰 작성하기'), findsNothing);
  });

  testWidgets('without eligibility the writer explains how to get it', (tester) async {
    await openWriter(tester);

    expect(api.calls, ['mine']);
    expect(find.text(reviewEligibilityGuide), findsOneWidget);
    expect(find.text('리뷰 쓰기'), findsNothing);
  });

  testWidgets('the writer opens B10 when I already wrote a review', (tester) async {
    api.my = {...api.my, 'review': _card('mine', '원세찬', 4, mine: true), 'sourceRecord': _record};
    await openWriter(tester);

    expect(find.text('리뷰 수정'), findsOneWidget);
    expect(find.text('5.2km · 2026.09.08 완주 100% · 27:14'), findsOneWidget);
    expect(find.text('원세찬 후기'), findsOneWidget);
  });

  testWidgets('B2 writes a review with every rating, a tag and a new photo', (tester) async {
    api.my = {...api.my, 'eligibleRecord': _record};
    photos.photo = testPhoto;
    await openWriter(tester);

    expect(find.text('리뷰 쓰기'), findsOneWidget);
    expect(find.text('5.2km · 2026.09.08 완주 100% · 27:14'), findsOneWidget);

    // 별점 5개를 다 골라야 등록된다
    await tap(tester, _labeled('전체 별점 4점'));
    await tap(tester, find.text('리뷰 등록'));
    expect(api.written, isNull);
    for (final row in ['안전성 (차량 · 인적)', '도로 상태', '야간 조명', '편의시설 (화장실/편의점)']) {
      await tap(tester, find.descendant(of: find.widgetWithText(WdRatingRow, row), matching: _labeled('5점')));
    }
    await tester.enterText(find.byType(TextField), '  야경이 좋아요  ');
    await tap(tester, find.text('붐빔'));
    await tap(tester, _labeled('사진 추가'));
    await tap(tester, find.text('리뷰 등록'));

    final written = api.written!;
    expect(written.courseId, _course);
    expect(written.source, 'record-1');
    expect(written.input.rating, 4);
    expect(
      [written.input.safetyRating, written.input.roadRating, written.input.lightingRating, written.input.amenityRating],
      [5, 5, 5, 5],
    );
    expect(written.input.content, '  야경이 좋아요  '); // 앞뒤 공백은 서버가 지운다
    expect(written.input.tags, {ReviewTag.crowded});
    expect(written.input.photoKeys, ['review/new.jpg']);
    expect(photos.uploaded, [testPhoto]);
    // 등록하면 닫히고 원래 화면으로 돌아간다
    expect(find.text('리뷰를 등록했어요.'), findsOneWidget);
    expect(find.text('리뷰 쓰기'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('B10-1 edits my review whose source record was deleted', (tester) async {
    api.my = {
      'review': _card('mine', '원세찬', 4, mine: true),
      'sourceRecord': null,
      'sourceRecordDeleted': true,
      'eligibleRecord': null,
    };
    await openReviews(tester);

    expect(find.text('나 (원세찬)'), findsOneWidget);
    expect(find.text('2026.09.06 작성'), findsOneWidget);
    expect(find.text('다른 러너 리뷰 2'), findsOneWidget);

    await tap(tester, find.text('수정하기'));
    expect(find.text('리뷰 수정'), findsOneWidget);
    expect(find.text('근거 기록이 삭제됐어요 · 리뷰 수정은 가능해요'), findsOneWidget);
    expect(find.text('원세찬 후기'), findsOneWidget); // 기존 후기로 채운다

    await tap(tester, _labeled('전체 별점 2점'));
    await tap(tester, find.text('수정 완료'));

    final edited = api.edited!;
    expect(edited.reviewId, 'mine');
    expect(edited.input.rating, 2);
    expect(edited.input.safetyRating, 4);
    expect(edited.input.tags, {ReviewTag.nightView});
    expect(find.text('리뷰를 수정했어요.'), findsOneWidget);
  });

  testWidgets('my review is deleted only after confirming', (tester) async {
    api.my = {...api.my, 'review': _card('mine', '원세찬', 4, mine: true), 'sourceRecord': _record};
    await openReviews(tester);

    await tap(tester, find.text('삭제하기'));
    await tap(tester, find.text('취소'));
    expect(api.deleted, isNull);

    await tap(tester, find.text('삭제하기'));
    await tap(tester, find.text('삭제'));
    expect(api.deleted, 'mine');
    expect(find.text('리뷰를 삭제했어요.'), findsOneWidget);
  });
}
