import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/api/review_api_client.dart';
import '../../../core/map/map_view.dart';
import '../course_format.dart';

/// B1 코스 상세 — 정보. 코스 정보는 코스 API, 평점 · 리뷰 수 · 러너 평가는 리뷰 API에서 받는다(B1-01).
///
/// - 리뷰(B8) · 랭킹(B9) 탭과 이 코스로 달리기(C6) · 고스트 대결(C1)은 아직 없어 누르면 준비 중이라고 알린다.
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
  static const runNotReadyMessage = '코스 러닝은 아직 준비 중이에요.';
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

  /// 리뷰 요약. 받지 못했으면 [_summaryFailed]이고 평점 · 러너 평가 대신 다시 시도를 보인다.
  ReviewSummary? _summary;
  var _summaryFailed = false;

  /// Figma B1 지도 높이.
  static const _mapHeight = 150.0;

  /// 지도 위쪽은 안내 문구(위 12 + 높이 26) 자리라 비워 두고 경로를 그 아래에 맞춘다(Figma B1).
  static const _mapPadding = EdgeInsets.only(top: WdSpace.s24);

  @override
  void initState() {
    super.initState();
    _load();
    _loadSummary();
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

  Future<void> _loadSummary() async {
    setState(() => _summaryFailed = false);
    try {
      final summary = await ref.read(reviewApiClientProvider).summary(widget.courseId);
      if (mounted) setState(() => _summary = summary);
    } on ApiException {
      if (mounted) setState(() => _summaryFailed = true);
    }
  }

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

  /// 리뷰 · 랭킹 탭은 아직 없어 정보 탭에 머문다.
  void _onTab(int index) {
    if (index == 0) return;
    _tabs.index = 0;
    _notReady(index == 1 ? '리뷰 탭은 아직 준비 중이에요.' : '랭킹 탭은 아직 준비 중이에요.');
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
    final summary = _summary;
    final rating = summary?.averageRating;
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
      body: ListView(
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
                  tabs: ['정보', summary == null ? '리뷰' : '리뷰 ${formatCount(summary.reviewCount)}', '랭킹'],
                ),
                _info(summary),
                WdInfoBanner(publicPeriodText(course.expiresAt, widget.now()), plain: true),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: WdBottomBar.dual(
        secondary: WdButton(
          '이 코스로 달리기',
          variant: WdButtonVariant.secondary,
          onPressed: () => _notReady(CourseDetailScreen.runNotReadyMessage),
        ),
        // Figma B1 · 디자인 시스템 Dual CTA와 같은 `고스트 대결 ▶`.
        primary: WdButton('고스트 대결 ▶', onPressed: () => _notReady(CourseDetailScreen.runNotReadyMessage)),
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
  Widget _info(ReviewSummary? summary) {
    if (_summaryFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s8,
        children: [
          WdSectionHeading('러너 평가', actionLabel: '다시 시도', onAction: _loadSummary),
          Text('평가를 불러오지 못했어요.', style: WdText.ko13.copyWith(color: WdColors.muted)),
        ],
      );
    }
    if (summary == null) {
      return const SizedBox(
        height: 96,
        child: Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (summary.reviewCount == 0) {
      return WdSurface(
        padding: const EdgeInsets.symmetric(horizontal: WdSpace.s16, vertical: WdSpace.s24),
        child: Column(
          spacing: WdSpace.s8,
          children: [
            const WdIcon(WdIcons.ghostInfo, size: 24),
            Text(CourseDetailScreen.noRunnerTitle,
                textAlign: TextAlign.center, style: WdText.ko15Bold.copyWith(color: WdColors.ink)),
            Text(CourseDetailScreen.noRunnerMessage,
                textAlign: TextAlign.center, style: WdText.ko12.copyWith(color: WdColors.muted)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WdSpace.s12,
      children: [
        const WdSectionHeading('러너 평가'),
        for (final (label, value) in [
          ('안전성', summary.safety),
          ('도로 상태', summary.road),
          ('야간 조명', summary.lighting),
          ('편의시설', summary.amenity),
        ])
          Row(
            spacing: WdSpace.s12,
            children: [
              SizedBox(width: 64, child: Text(label, style: WdText.ko12.copyWith(color: WdColors.muted))),
              Expanded(child: WdProgressBar(value: (value ?? 0) / 5)),
              SizedBox(
                width: 28,
                child: Text(
                  value?.toStringAsFixed(1) ?? CourseDetailScreen.noValue,
                  textAlign: TextAlign.end,
                  style: WdText.ko12Bold.copyWith(color: WdColors.ink),
                ),
              ),
            ],
          ),
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
