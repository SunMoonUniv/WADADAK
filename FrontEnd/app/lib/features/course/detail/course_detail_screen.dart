import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/api/ranking_api_client.dart';
import '../../../core/api/review_api_client.dart';
import '../../../core/map/map_view.dart';
import '../../../routes.dart';
import '../../review/review_state.dart';
import '../course_format.dart';
import 'course_empty_card.dart';
import 'course_ranking_state.dart';
import 'course_ranking_tab.dart';
import 'course_reviews_tab.dart';
import 'course_run_bar.dart';

/// B1 코스 상세 — 정보 · B8 리뷰 · B9 랭킹 탭. 코스 정보는 코스 API, 평점 · 리뷰 수 · 러너 평가 · 리뷰는 리뷰 API,
/// 랭킹 · 고스트는 랭킹 API에서 받는다(B1-01).
///
/// - 이 코스로 달리기(C6) · 고스트 대결(C1)은 아직 없어 누르면 준비 중이라고 알린다.
/// - 평균 페이스 · 현재 러너는 코스 통계(F11)가, 고도 프로필은 GPS 코스 등록(F7)이 생기면 붙인다.
/// - 공유(B1-08)는 공유 링크를 정할 때까지 두지 않는다.
/// - 비공개 · 삭제된 코스는 열지 않는다(B1-04).
class CourseDetailScreen extends ConsumerStatefulWidget {
  const CourseDetailScreen({super.key, required this.courseId, this.now = DateTime.now});

  final String courseId;

  /// 공개 기간이 며칠 남았는지 세는 기준 시각. 테스트가 바꾼다.
  final DateTime Function() now;

  static const unavailableTitle = '볼 수 없는 코스예요';
  static const unavailableMessage = '비공개되었거나 삭제된 코스예요.';
  static const loadFailedTitle = '코스를 불러오지 못했어요';
  static const loadFailedMessage = '네트워크를 확인하고 다시 시도해 주세요.';
  static const noRunnerTitle = '아직 이 코스를 달린 사람이 없어요';
  static const noRunnerMessage = '처음 완주하면 평균 페이스 · 평점 · 랭킹이 만들어져요.\n첫 번째 기록의 주인공이 되어 보세요.';

  /// 값이 아직 없을 때(Figma B1-1 `—`).
  static const noValue = '—';

  @override
  ConsumerState<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends ConsumerState<CourseDetailScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);

  CourseDetail? _course;
  Object? _error;

  /// 지금 보이는 탭. 0 정보, 1 리뷰(B8), 2 랭킹(B9).
  var _tab = 0;

  /// 리뷰 탭을 한 번이라도 열었다. 그때부터 미리보기를 받고, 탭을 오가도 다시 받지 않는다.
  var _reviewsOpened = false;

  /// B8 정렬 · 사진 조건. 탭을 오가도 그대로다(B8-03).
  var _reviewSort = ReviewSort.latest;
  var _reviewPhotoOnly = false;

  /// 마지막으로 보인 리뷰 미리보기. 조건을 바꿔 새로 받는 동안 그대로 두어, 목록이 잠깐 줄며 화면이 위로 튀지 않게 한다.
  List<ReviewCard>? _shownReviews;

  CourseReviewQuery get _reviewQuery => (courseId: widget.courseId, sort: _reviewSort, photoOnly: _reviewPhotoOnly);

  /// B9 기간. 탭을 오가도 그대로다. 정보 · 리뷰 탭의 고스트는 늘 전체 기간이다(정책 공통 6).
  var _rankingPeriod = RankingPeriod.all;

  /// 마지막으로 보인 랭킹과 그 기간. 기간을 바꿔 새로 받는 동안 그대로 두어 화면이 튀지 않게 한다(B8과 같다).
  (RankingPeriod, CourseRankingSummary)? _shownRanking;

  CourseRankingKey get _rankingKey => (courseId: widget.courseId, period: _rankingPeriod);

  /// Figma B1 지도 높이.
  static const _mapHeight = 150.0;

  /// 지도 위쪽은 안내 문구(위 12 + 높이 26) 자리라 비워 두고 경로를 그 아래에 맞춘다(Figma B1).
  static const _mapPadding = EdgeInsets.only(top: WdSpace.s24);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final course = await ref.read(courseApiClientProvider).courseDetail(widget.courseId);
      if (mounted) setState(() => _course = course);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// 리뷰 요약은 G2와 같은 것을 쓴다. G2에서 리뷰를 쓰거나 지우면 여기도 바뀐다.
  void _retrySummary() => ref.invalidate(reviewSummaryProvider(widget.courseId));

  bool get _unavailable => switch (_error) {
        ApiException(:final code) =>
          code == CourseApiClient.courseNotFoundCode || code == CourseApiClient.courseNotAvailableCode,
        _ => false,
      };

  void _notReady(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onTab(int index) {
    setState(() {
      _tab = index;
      if (index == 1) _reviewsOpened = true;
    });
  }

  /// B8-05 모두 보기 → G2. 돌아오면 미리보기를 다시 받는다(G2에서 쓰거나 지웠을 수 있다).
  /// 요약은 G2가 바꿀 때 직접 새로 받게 한다.
  Future<void> _seeAllReviews(CourseDetail course) async {
    await context.push(Routes.courseReviews(course.courseId), extra: course.name);
    if (mounted) ref.invalidate(courseReviewPreviewProvider);
  }

  /// B9-01 기간을 바꾸면 그 기간을 새로 받는다(받아 둔 것이 있어도).
  void _selectRankingPeriod(RankingPeriod period) {
    if (period == _rankingPeriod) return;
    ref.invalidate(courseRankingProvider((courseId: widget.courseId, period: period)));
    setState(() => _rankingPeriod = period);
  }

  /// 랭킹 탭에서 당겨서 새로고침(B9-01). 실패하면 받아 둔 랭킹 아래에 다시 시도를 보인다.
  Future<void> _refreshRanking() =>
      ref.refresh(courseRankingProvider(_rankingKey).future).then((_) {}, onError: (_) {});

  /// B9-05 전체 순위 보기 → G3. 지금 고른 기간으로 연다.
  void _seeAllRankings(CourseDetail course) {
    context.push(Routes.courseRankings(course.courseId), extra: (courseName: course.name, period: _rankingPeriod));
  }

  @override
  Widget build(BuildContext context) {
    final course = _course;
    if (course == null) {
      return Scaffold(
        appBar: WdAppBar(title: '', onBack: () => context.pop()),
        body: switch (_error) {
          null => const Center(child: CircularProgressIndicator(color: WdColors.ink)),
          _ when _unavailable => const Center(
              child: WdStateMessage(
                title: CourseDetailScreen.unavailableTitle,
                message: CourseDetailScreen.unavailableMessage,
                icon: WdIcons.ghostInfo,
              ),
            ),
          _ => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WdStateMessage(
                    title: CourseDetailScreen.loadFailedTitle,
                    message: CourseDetailScreen.loadFailedMessage,
                    icon: WdIcons.ghostWarning,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: WdSpace.s24),
                    child: WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: _load),
                  ),
                ],
              ),
            ),
        },
      );
    }
    final summary = ref.watch(reviewSummaryProvider(widget.courseId));
    final rating = summary.value?.averageRating;
    final reviewCount = summary.value?.reviewCount;
    // 리뷰 탭을 연 뒤에는 정보 탭에 있어도 미리보기를 붙잡아 둔다. 돌아와도 다시 받지 않는다.
    // 리뷰가 없으면 B8-1 안내만 보여 받지 않는다.
    final watched = _reviewsOpened && (reviewCount ?? 0) > 0
        ? ref.watch(courseReviewPreviewProvider(_reviewQuery))
        : const AsyncLoading<List<ReviewCard>>();
    if (watched.value case final cards?) _shownReviews = cards;
    final preview = switch ((watched, _shownReviews)) {
      (AsyncValue(hasValue: false, hasError: false), final shown?) => AsyncData(shown),
      _ => watched,
    };
    // 정보 · 리뷰 탭의 고스트 대결 버튼은 늘 전체 기간, 랭킹 탭은 고른 기간을 쓴다(정책 공통 6).
    final allRanking = ref.watch(courseRankingProvider((courseId: widget.courseId, period: RankingPeriod.all)));
    final ranking = ref.watch(courseRankingProvider(_rankingKey));
    if (ranking.value case final value?) _shownRanking = (_rankingPeriod, value);
    return Scaffold(
      // 등록자 닉네임은 제목 아래에(정책 공통 4 · B1-01). 탈퇴했으면 서버가 `탈퇴한 사용자`로 준다.
      appBar: WdAppBar(
        title: course.name,
        subtitle: switch (course.creatorNickname) {
          final nickname? => '등록자 $nickname',
          null => null,
        },
        onBack: () => context.pop(),
      ),
      body: RefreshIndicator(
        color: WdColors.ink,
        // 당겨서 새로고침은 랭킹 탭에서만 한다(4.1 B9-01).
        notificationPredicate: (notification) => _tab == 2 && notification.depth == 0,
        onRefresh: _refreshRanking,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: WdSpace.s24),
          children: [
            _map(course),
            Padding(
              padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s16, WdSpace.s24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WdSpace.s16,
                children: [
                  Wrap(
                    children: [
                      WdTag(course.courseType.label, filled: false),
                      for (final tag in course.tags) WdTag(tag.label, filled: false),
                    ],
                  ),
                  WdSummaryTiles([
                    ('거리', formatKm(course.distanceMeters)),
                    ('난이도', course.difficulty.label),
                    ('평점', rating == null ? CourseDetailScreen.noValue : '★ ${rating.toStringAsFixed(1)}'),
                    // 코스 통계(F11)가 생기면 붙인다.
                    ('평균 페이스', CourseDetailScreen.noValue),
                  ]),
                  WdTabBar(
                    controller: _tabs,
                    onTap: _onTab,
                    tabs: ['정보', reviewCount == null ? '리뷰' : '리뷰 ${formatCount(reviewCount)}', '랭킹'],
                  ),
                  if (_tab == 0)
                    _info(summary)
                  else if (_tab == 1)
                    CourseReviewsTab(
                      summary: summary,
                      preview: preview,
                      sort: _reviewSort,
                      photoOnly: _reviewPhotoOnly,
                      onSort: (sort) => setState(() => _reviewSort = sort),
                      onPhotoOnly: (photoOnly) => setState(() => _reviewPhotoOnly = photoOnly),
                      onRetrySummary: _retrySummary,
                      onRetryPreview: () => ref.invalidate(courseReviewPreviewProvider(_reviewQuery)),
                      onSeeAll: () => _seeAllReviews(course),
                    )
                  else
                    CourseRankingTab(
                      ranking: ranking,
                      shown: _shownRanking,
                      period: _rankingPeriod,
                      onPeriod: _selectRankingPeriod,
                      onRetry: () => ref.invalidate(courseRankingProvider(_rankingKey)),
                      onSeeAll: () => _seeAllRankings(course),
                    ),
                  // 공개 기간은 어느 탭에서나 맨 아래에 보인다(4.1 B8).
                  WdInfoBanner(publicPeriodText(course.expiresAt, widget.now()), plain: true),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CourseRunBar(
        ranking: _tab == 2 ? ranking : allRanking,
        period: _tab == 2 ? _rankingPeriod : RankingPeriod.all,
        onRun: () => _notReady(CourseRunBar.notReadyMessage),
        onGhost: (_) => _notReady(CourseRunBar.notReadyMessage),
      ),
    );
  }

  /// 코스 경로와 1km 표지(B1-02). 출발점에 점을 둔다(코스 방향, Figma B1).
  Widget _map(CourseDetail course) => SizedBox(
        height: _mapHeight,
        child: Stack(
          children: [
            MapView(
              initialCenter: course.route.first,
              padding: _mapPadding,
              lines: [MapLine(id: 'route', points: course.route)],
              markers: [
                for (final marker in course.distanceMarkers)
                  MapMarker(
                    id: 'km-${marker.km}',
                    position: marker.point,
                    child: WdKmMarker('${marker.km} km'),
                    imageKey: 'km:${marker.km}',
                  ),
                MapMarker(
                  id: 'start',
                  position: course.route.first,
                  child: const WdCourseStartDot(),
                  imageKey: 'course-start',
                ),
              ],
              onCreated: (map) => map.fitPoints(course.route),
            ),
            Positioned(
              left: WdSpace.s16,
              top: WdSpace.s12,
              child: WdMapHint('1 km마다 지점 표시 · 총 ${formatKm(course.distanceMeters)}'),
            ),
          ],
        ),
      );

  /// 정보 탭. 리뷰가 있으면 러너 평가(항목 평균), 없으면 아직 달린 사람이 없다는 안내(Figma B1-1).
  /// 고도 프로필은 GPS 코스만 보이는데(B1-03) GPS 코스 등록(F7)이 생기면 붙인다.
  /// 받아 둔 요약이 있으면 다시 받다 실패해도 그대로 보이고, 그 아래에 다시 시도를 준다(B8-02와 같다).
  Widget _info(AsyncValue<ReviewSummary> summary) {
    final value = summary.value;
    if (value == null && summary.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s8,
        children: [
          WdSectionHeading('러너 평가', actionLabel: '다시 시도', onAction: _retrySummary),
          Text('평가를 불러오지 못했어요.', style: WdText.ko13.copyWith(color: WdColors.muted)),
        ],
      );
    }
    if (value == null) {
      return const SizedBox(
        height: 96,
        child: Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final stale = summary.hasError
        ? CourseRefreshFailed(CourseReviewsTab.staleSummaryMessage, onRetry: _retrySummary)
        : null;
    if (value.reviewCount == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s16,
        children: [
          const CourseEmptyCard(
            title: CourseDetailScreen.noRunnerTitle,
            message: CourseDetailScreen.noRunnerMessage,
          ),
          ?stale,
        ],
      );
    }
    // Figma B1: 이름 70 · 간격 10 · 줄 사이 7, 점수는 12 Medium
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WdSpace.s16,
      children: [
        const WdSectionHeading('러너 평가'),
        Column(
          spacing: 7,
          children: [
            for (final (label, average) in [
              ('안전성', value.safety),
              ('도로 상태', value.road),
              ('야간 조명', value.lighting),
              ('편의시설', value.amenity),
            ])
              Row(
                spacing: WdSpace.s10,
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(label, style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted)),
                  ),
                  Expanded(child: WdProgressBar(value: (average ?? 0) / 5, trackColor: WdColors.soft)),
                  Text(
                    average?.toStringAsFixed(1) ?? CourseDetailScreen.noValue,
                    style: WdText.raw(12, FontWeight.w500, 18).copyWith(color: WdColors.ink),
                  ),
                ],
              ),
          ],
        ),
        ?stale,
      ],
    );
  }
}

/// 공개 기간 안내(B1-04). 남은 날과 만료일을 함께 보인다. 만료일 당일은 오늘까지라고 한다.
String publicPeriodText(DateTime expiresAt, DateTime now) {
  final daysLeft = daysUntilExpiry(expiresAt, now);
  // 만료 시각은 만료일 23:59:59(Asia/Seoul). 한국은 서머타임이 없어 UTC+9로 날짜를 센다.
  final seoul = expiresAt.toUtc().add(const Duration(hours: 9));
  final period = daysLeft <= 0 ? '오늘까지 공개돼요' : '공개 기간이 $daysLeft일 남았어요(${seoul.month}월 ${seoul.day}일까지)';
  return '$period · 누군가 완주하면 30일 연장돼요';
}
