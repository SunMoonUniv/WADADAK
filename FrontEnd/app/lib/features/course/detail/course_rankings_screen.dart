import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/ranking_api_client.dart';
import '../../ranking/ranking_widgets.dart';
import '../../run/application/course_run_entry.dart';
import '../../run/domain/course_run.dart';
import '../course_format.dart';
import 'course_ranking_state.dart';
import 'course_ranking_tab.dart';
import 'course_reviews_tab.dart';
import 'course_run_bar.dart';

/// G3을 여는 값. B9 `전체 순위 N명 보기`가 넘긴다.
typedef CourseRankingsArgs = ({String courseName, RankingPeriod period});

/// G3 코스 전체 순위. 기간 칩, 코스 통계, 내 순위, 전체 순위 순서다(Figma G3).
///
/// - B9에서 고른 기간으로 연다. 여기서 바꾼 기간은 B9에 넘기지 않는다.
/// - 들어올 때 · 기간을 바꿀 때 · 당겨서 새로고침할 때 1위부터 다시 받고, 끝 가까이에서 다음 순위를 받는다(G3-04).
///   기간을 바꿔 받는 동안에는 보이던 순위를 그대로 둔다(B9와 같다).
/// - 러너 줄은 I3(다른 러너 프로필)가 생길 때까지 누를 수 없어 Figma의 `러너를 탭하면 프로필 ›`도 두지 않는다.
///   내 줄은 늘 누를 수 없다(G3-03).
/// - 이 코스로 달리기는 그 코스를 골라 달리기 탭의 코스 러닝(C6)으로 간다. 고스트 대결(C1)은 그 화면이 생길 때까지 누르면 준비 중이라고 알린다.
class CourseRankingsScreen extends ConsumerStatefulWidget {
  const CourseRankingsScreen({super.key, required this.courseId, required this.courseName, required this.period});

  final String courseId;
  final String courseName;
  final RankingPeriod period;

  @override
  ConsumerState<CourseRankingsScreen> createState() => _CourseRankingsScreenState();
}

class _CourseRankingsScreenState extends ConsumerState<CourseRankingsScreen> {
  late var _period = widget.period;

  /// 마지막으로 보인 순위와 그 기간.
  (RankingPeriod, CourseRankingFeed)? _shown;

  void _notReady() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(CourseRunBar.ghostNotReadyMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = courseRankingFeedProvider((courseId: widget.courseId, period: _period));
    final feed = ref.watch(provider);
    if (feed.value case final value?) _shown = (_period, value);
    final (shownPeriod, value) = switch ((feed, _shown)) {
      (AsyncValue(:final value?), _) => (_period, value),
      (AsyncValue(hasError: false), (final period, final value)?) => (period, value),
      _ => (_period, null),
    };
    void retry() => ref.invalidate(provider);
    return Scaffold(
      appBar: WdAppBar(
        title: '전체 순위',
        onBack: () => context.pop(),
        action: WdAppBarAction.text(widget.courseName, onTap: null),
      ),
      body: RankingScrollView(
        // 실패하면 받아 둔 순위 아래에 다시 시도를 보인다.
        onRefresh: () => ref.refresh(provider.future).then((_) {}, onError: (_) {}),
        onEnd: () => ref.read(provider.notifier).loadMore(),
        children: [
          CourseRankingPeriodChips(period: _period, onPeriod: (period) => setState(() => _period = period)),
          ...switch (value) {
            null when feed.hasError => [CourseRankingFailure(onRetry: retry)],
            null => const [
                SizedBox(
                  height: 96,
                  child: Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                ),
              ],
            final value => [
                CourseRankingStats(value.summary),
                CourseMyRankCard(value.summary.me, period: shownPeriod),
                if (feed.hasError) CourseRefreshFailed(CourseRankingTab.staleMessage, onRetry: retry),
                WdSectionHeading('전체 순위 ${formatCount(value.summary.participantCount)}명'),
                if (value.entries.isEmpty)
                  CourseRankingNoRunner(shownPeriod)
                else
                  WdRankList(ranks: [for (final entry in value.entries) courseRank(entry, withDate: true)]),
              ],
          },
        ],
      ),
      bottomNavigationBar: CourseRunBar(
        ranking: feed.whenData((feed) => feed.summary),
        period: _period,
        onRun: () => runCourse(context, ref, CourseSelection(widget.courseId, widget.courseName)),
        onGhost: (_) => _notReady(),
      ),
    );
  }
}
