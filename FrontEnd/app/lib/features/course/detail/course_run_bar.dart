import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/ranking_api_client.dart';

/// 코스 상세(B1 · B8 · B9)와 G3 아래 버튼. 공개 고스트는 랭킹 API가 높은 순위부터 고른다(정책 공통 6).
///
/// - 고스트가 있으면 `이 코스로 달리기` · `고스트 대결 ▶`(Figma B1 · B9 · G3).
/// - 없으면 Figma B9-1처럼 왼쪽 `고스트 없음`을 끄고 오른쪽에 달리기를 둔다.
///   전체 기간에 아무도 완주하지 않았으면 `첫 번째로 달리기 ▶`다.
/// - 받는 중이거나 받지 못했으면 `고스트 대결 ▶`을 끈다(B1-07 · B8-06 · B9-06 · G3-05).
class CourseRunBar extends StatelessWidget {
  const CourseRunBar({
    super.key,
    required this.ranking,
    required this.period,
    required this.onRun,
    required this.onGhost,
  });

  static const firstRunLabel = '첫 번째로 달리기 ▶';

  /// 코스 러닝(C6) · 고스트 대결(C1)이 생길 때까지 버튼을 누르면 알린다.
  static const notReadyMessage = '코스 러닝은 아직 준비 중이에요.';

  /// 고스트를 고른 랭킹. B1 · B8은 전체 기간, B9 · G3은 고른 기간이다.
  final AsyncValue<CourseRankingSummary> ranking;

  /// [ranking]의 기간.
  final RankingPeriod period;
  final VoidCallback onRun;
  final ValueChanged<GhostCandidate> onGhost;

  @override
  Widget build(BuildContext context) {
    final run = WdButton('이 코스로 달리기', variant: WdButtonVariant.secondary, onPressed: onRun);
    return switch (ranking) {
      AsyncValue(hasError: false, value: CourseRankingSummary(ghost: final ghost?)) =>
        WdBottomBar.dual(secondary: run, primary: WdButton('고스트 대결 ▶', onPressed: () => onGhost(ghost))),
      AsyncValue(hasError: false, :final value?) => WdBottomBar.dual(
          secondary: const WdButton('고스트 없음', onPressed: null),
          primary: WdButton(
            period == RankingPeriod.all && value.participantCount == 0 ? firstRunLabel : '이 코스로 달리기',
            onPressed: onRun,
          ),
        ),
      _ => WdBottomBar.dual(secondary: run, primary: const WdButton('고스트 대결 ▶', onPressed: null)),
    };
  }
}
