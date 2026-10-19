import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/ranking_api_client.dart';
import '../../run/domain/run_models.dart';
import '../course_format.dart';
import 'course_empty_card.dart';
import 'course_reviews_tab.dart';

/// B9 · G3 기간 칩 순서(Figma B9).
const courseRankingPeriods = [RankingPeriod.all, RankingPeriod.month, RankingPeriod.week];

String courseRankingPeriodLabel(RankingPeriod period) => switch (period) {
      RankingPeriod.all => '전체 기간',
      RankingPeriod.month => '이번 달',
      RankingPeriod.week => '이번 주',
    };

/// 코스 총 소요시간. 예: `24:12`, 1시간이 넘으면 `01:02:03`.
String formatCourseTime(int seconds) => formatRunTime(Duration(seconds: seconds));

/// 완주 페이스. 예: `4′39″/km`.
String formatCoursePace(int secondsPerKm) => '${formatRunPace(secondsPerKm.toDouble())}/km';

/// B9 코스 상세 — 랭킹 탭. 기간 칩, 내 순위, 코스 통계, 상위 5명, `전체 순위 N명 보기`(G3) 순서다(Figma B9).
///
/// - 전체 기간에 완주 기록이 없으면 Figma B9-1 안내만 보인다. 이번 달 · 이번 주만 없으면 `참여 0명 · —`다(B9-03).
/// - 받아 둔 랭킹이 있으면 다시 받다 실패해도 그대로 보이고 그 아래에 다시 시도를 준다.
/// - 상위 5명은 I3(다른 러너 프로필)가 생길 때까지 누를 수 없다. 내 순위는 늘 누를 수 없다(B9-02).
class CourseRankingTab extends StatelessWidget {
  const CourseRankingTab({
    super.key,
    required this.ranking,
    required this.shown,
    required this.period,
    required this.onPeriod,
    required this.onRetry,
    required this.onSeeAll,
  });

  static const emptyTitle = '아직 완주 기록이 없어요';
  static const emptyMessage = '첫 완주자가 1위가 돼요.\n지금 달려서 첫 기록을 남겨 보세요.';
  static const failedMessage = '랭킹을 불러오지 못했어요.';
  static const staleMessage = '랭킹을 새로 받지 못했어요.';

  /// 고른 기간의 랭킹.
  final AsyncValue<CourseRankingSummary> ranking;

  /// 마지막으로 보인 랭킹과 그 기간. 기간을 바꿔 새로 받는 동안 그대로 두어 화면이 튀지 않게 한다.
  final (RankingPeriod, CourseRankingSummary)? shown;
  final RankingPeriod period;
  final ValueChanged<RankingPeriod> onPeriod;
  final VoidCallback onRetry;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final (shownPeriod, value) = switch ((ranking, shown)) {
      (AsyncValue(:final value?), _) => (period, value),
      (AsyncValue(hasError: false), (final p, final v)?) => (p, v),
      _ => (period, null),
    };
    final chips = CourseRankingPeriodChips(period: period, onPeriod: onPeriod);
    if (value == null) {
      if (!ranking.hasError) return const _Loading();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s16,
        children: [chips, CourseRankingFailure(onRetry: onRetry)],
      );
    }
    if (shownPeriod == RankingPeriod.all && value.participantCount == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s16,
        children: [
          const CourseEmptyCard(title: emptyTitle, message: emptyMessage),
          if (ranking.hasError) CourseRefreshFailed(staleMessage, onRetry: onRetry),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WdSpace.s16,
      children: [
        chips,
        CourseMyRankCard(value.me, period: shownPeriod),
        CourseRankingStats(value),
        if (value.top.isEmpty)
          CourseRankingNoRunner(shownPeriod)
        else
          WdRankList(ranks: [for (final entry in value.top) courseRank(entry)]),
        if (ranking.hasError) CourseRefreshFailed(staleMessage, onRetry: onRetry),
        if (value.participantCount > 0)
          WdButton(
            '전체 순위 ${formatCount(value.participantCount)}명 보기',
            variant: WdButtonVariant.secondary,
            onPressed: onSeeAll,
          ),
      ],
    );
  }
}

/// 전체 기간 · 이번 달 · 이번 주 중 하나를 고른다(B9-01 · G3-01).
class CourseRankingPeriodChips extends StatelessWidget {
  const CourseRankingPeriodChips({super.key, required this.period, required this.onPeriod});

  final RankingPeriod period;
  final ValueChanged<RankingPeriod> onPeriod;

  @override
  Widget build(BuildContext context) => Row(
        spacing: WdSpace.s6,
        children: [
          for (final option in courseRankingPeriods)
            WdFilterChip(
              courseRankingPeriodLabel(option),
              height: 36,
              selected: option == period,
              onTap: () => onPeriod(option),
            ),
        ],
      );
}

/// 순위 한 줄. 내 기록은 `나 (닉네임)`(B8 리뷰와 같다). G3은 [withDate]로 완주 날짜를 붙인다(Figma G3).
WdRank courseRank(CourseRankingEntry entry, {bool withDate = false}) {
  final nickname = entry.nickname ?? '러너';
  final pace = formatCoursePace(entry.paceSecondsPerKm);
  return WdRank(
    rank: '${entry.rank}',
    name: entry.mine ? '나 ($nickname)' : nickname,
    meta: withDate ? '$pace · ${formatMonthDay(entry.completedAt)}' : pace,
    value: formatCourseTime(entry.courseElapsedSeconds),
    avatar: entry.profileImageUrl == null ? null : NetworkImage(entry.profileImageUrl!),
  );
}

/// 내 순위(B9-02). 순위 · 페이스 · 날짜 · 상위 비율이고 누를 수 없다.
/// 이름은 순위 줄처럼 `나 (닉네임)`이고 닉네임이 없으면 `나`. 내 정보 비공개면 순위 자리에 `비공개 중`.
class CourseMyRankCard extends StatelessWidget {
  const CourseMyRankCard(this.me, {super.key, required this.period});

  final MyCourseRanking me;

  /// 기록이 없을 때 안내에 쓴다.
  final RankingPeriod period;

  @override
  Widget build(BuildContext context) {
    final record = switch (me) {
      MyCourseRanking(:final paceSecondsPerKm?, :final completedAt?) => [
          formatCoursePace(paceSecondsPerKm),
          formatMonthDay(completedAt),
          if (me.topPercent case final percent?) '상위 $percent%',
        ].join(' · '),
      _ => null,
    };
    return WdMyRankCard(
      WdRank(
        rank: switch (me) {
          MyCourseRanking(status: MyRankStatus.private) => '비공개 중',
          MyCourseRanking(:final rank?) => '$rank',
          _ => CourseRankingStats.noValue,
        },
        name: me.nickname == null ? '나' : '나 (${me.nickname})',
        avatar: me.profileImageUrl == null ? null : NetworkImage(me.profileImageUrl!),
        meta: record ??
            (period == RankingPeriod.all ? '아직 완주 기록이 없어요' : '${courseRankingPeriodLabel(period)} 완주 기록이 없어요'),
        value: switch (me.courseElapsedSeconds) {
          final seconds? => formatCourseTime(seconds),
          null => CourseRankingStats.noValue,
        },
      ),
    );
  }
}

/// 참여 러너 · 1위 기록 · 평균 기록(B9-03). [summary]가 없으면(처음 받기 실패) 모두 `—`다.
class CourseRankingStats extends StatelessWidget {
  const CourseRankingStats(this.summary, {super.key});

  /// 값이 없을 때(B1과 같다).
  static const noValue = '—';

  final CourseRankingSummary? summary;

  @override
  Widget build(BuildContext context) {
    final value = summary;
    return WdStatSummary([
      ('참여 러너', value == null ? noValue : '${formatCount(value.participantCount)}명'),
      ('1위 기록', switch (value?.top.firstOrNull) {
        final first? => formatCourseTime(first.courseElapsedSeconds),
        null => noValue,
      }),
      ('평균 기록', switch (value?.averageCourseElapsedSeconds) {
        final seconds? => formatCourseTime(seconds),
        null => noValue,
      }),
    ]);
  }
}

/// 그 기간에 완주한 러너가 없을 때 목록 자리.
class CourseRankingNoRunner extends StatelessWidget {
  const CourseRankingNoRunner(this.period, {super.key});

  final RankingPeriod period;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: WdSpace.s8),
        child: Text(
          period == RankingPeriod.all ? '아직 완주한 러너가 없어요' : '${courseRankingPeriodLabel(period)}에 완주한 러너가 아직 없어요',
          textAlign: TextAlign.center,
          style: WdText.label12.copyWith(color: WdColors.muted),
        ),
      );
}

/// 처음 받기에 실패했다. 통계는 `—`로 두고 다시 시도를 준다(B9-03).
class CourseRankingFailure extends StatelessWidget {
  const CourseRankingFailure({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s16,
        children: [
          const CourseRankingStats(null),
          Text(
            CourseRankingTab.failedMessage,
            textAlign: TextAlign.center,
            style: WdText.ko13.copyWith(color: WdColors.muted),
          ),
          WdButton('다시 시도', variant: WdButtonVariant.secondary, onPressed: onRetry),
        ],
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 96,
        child: Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
}
