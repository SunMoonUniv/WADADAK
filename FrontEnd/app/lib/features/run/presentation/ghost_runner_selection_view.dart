import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/ranking_api_client.dart';
import '../../../routes.dart';
import '../application/own_ghost_controller.dart';
import '../application/public_ghost_candidates_controller.dart';
import '../domain/own_ghost.dart';
import '../domain/run_models.dart';

/// Figma C2: summary choices before the complete C9 own-record list.
class GhostRunnerSelectionView extends ConsumerStatefulWidget {
  const GhostRunnerSelectionView({
    super.key,
    required this.controller,
    required this.courseName,
    required this.onBack,
    required this.onPrepared,
    required this.onMoreOwn,
    required this.onPublic,
    this.onMorePublic,
  });
  final OwnGhostController controller;
  final String courseName;
  final VoidCallback onBack, onMoreOwn;
  final ValueChanged<PreparedOwnGhost> onPrepared;
  final ValueChanged<GhostCandidate> onPublic;
  final VoidCallback? onMorePublic;
  @override
  ConsumerState<GhostRunnerSelectionView> createState() =>
      _GhostRunnerSelectionViewState();
}

class _GhostRunnerSelectionViewState
    extends ConsumerState<GhostRunnerSelectionView> {
  late final publics = PublicGhostCandidatesController(
    ref.read(rankingApiClientProvider),
    owner: widget.controller.owner,
    courseId: widget.controller.course.id,
  );
  @override
  void initState() {
    super.initState();
    unawaited(publics.load());
  }

  @override
  void dispose() {
    publics.dispose();
    super.dispose();
  }

  static String time(int seconds) => formatRunTime(Duration(seconds: seconds));
  static String date(DateTime at) {
    final d = at.toUtc().add(const Duration(hours: 9));
    return '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  String ownMeta(OwnGhostCandidate c) =>
      '${time(c.seconds)} · ${formatRunPace(c.seconds * 1000 / c.distanceM)}/km'
      '${c.averageCadence == null ? '' : ' · 케이던스 ${c.averageCadence!.round()}'} · ${date(c.startedAt)}';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, publics]),
      builder: (context, _) {
        final c = widget.controller, best = c.summary.best;
        final recent = c.candidates.isEmpty
            ? null
            : c.candidates.reduce(
                (a, b) => a.startedAt.isAfter(b.startedAt) ? a : b,
              );
        final public = publics.selected;
        final publicSelected = public != null;
        final ready = c.prepared;
        void selectOwn(OwnGhostCandidate candidate) {
          publics.clearSelection();
          c.select(candidate);
        }

        return Scaffold(
          backgroundColor: WdColors.paper,
          appBar: WdAppBar(
            title: '고스트 선택',
            onBack: widget.onBack,
            action: WdAppBarAction.text(
              widget.courseName.runes.length > 10
                  ? '${String.fromCharCodes(widget.courseName.runes.take(9))}…'
                  : widget.courseName,
              onTap: null,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              WdSectionHeading(
                '내 과거 기록',
                actionLabel: '이 코스 기록 ${c.summary.count}건',
              ),
              const SizedBox(height: 16),
              if (best != null)
                GhostRunnerChoiceCard(
                  key: const ValueKey('ghost-choice-best'),
                  title: '내 최고 기록',
                  meta: ownMeta(best),
                  badge: '최고',
                  selected: !publicSelected && ready?.candidate.id == best.id,
                  checking: c.selectingId == best.id,
                  onTap: c.loading ? null : () => selectOwn(best),
                ),
              if (recent != null) ...[
                const SizedBox(height: 16),
                GhostRunnerChoiceCard(
                  key: const ValueKey('ghost-choice-recent'),
                  title: '내 최근 기록',
                  meta: ownMeta(recent),
                  selected: !publicSelected && ready?.candidate.id == recent.id,
                  checking: c.selectingId == recent.id,
                  onTap: c.loading ? null : () => selectOwn(recent),
                ),
              ],
              if (best == null && recent == null)
                const WdInfoBanner(
                  '이 코스의 완주 기록이 없어요. 먼저 코스를 완주해 보세요.',
                  plain: true,
                ),
              const SizedBox(height: 16),
              WdButton(
                '내 기록 전체 보기',
                variant: WdButtonVariant.secondary,
                onPressed: widget.onMoreOwn,
              ),
              const SizedBox(height: 16),
              const WdSectionHeading('다른 러너 기록', actionLabel: '공개 완주 기록'),
              const SizedBox(height: 16),
              if (publics.loading)
                const Center(child: CircularProgressIndicator())
              else if (publics.error != null) ...[
                const WdInfoBanner(
                  '공개 기록을 불러오지 못했어요.',
                  tone: WdBannerTone.warning,
                ),
                WdButton(
                  '공개 기록 다시 확인',
                  variant: WdButtonVariant.secondary,
                  onPressed: () => publics.load(),
                ),
              ] else if (publics.rows.isEmpty)
                const WdInfoBanner('선택할 수 있는 다른 러너의 공개 기록이 없어요.', plain: true)
              else
                for (var i = 0; i < publics.rows.take(3).length; i++) ...[
                  GhostRunnerChoiceCard(
                    key: ValueKey(
                      i == 0
                          ? 'ghost-choice-public'
                          : 'ghost-choice-public-${publics.rows[i].runRecordId}',
                    ),
                    title: publics.rows[i].nickname ?? '공개 고스트',
                    meta: time(publics.rows[i].courseElapsedSeconds),
                    badge: '${publics.rows[i].rank}위',
                    selected: publics.selectedId == publics.rows[i].runRecordId,
                    onTap: () {
                      c.clearSelection();
                      publics.select(publics.rows[i]);
                    },
                  ),
                  const SizedBox(height: WdSpace.s12),
                ],
              WdButton(
                '다른 러너 전체 보기',
                variant: WdButtonVariant.secondary,
                onPressed: widget.onMorePublic,
              ),
              const SizedBox(height: WdSpace.s16),
              WdButton(
                '코스 전체 순위 보기',
                variant: WdButtonVariant.secondary,
                onPressed: () => context.push(
                  Routes.courseRankings(c.course.id),
                  extra: (
                    courseName: widget.courseName,
                    period: RankingPeriod.all,
                  ),
                ),
              ),
              const SizedBox(height: WdSpace.s16),
              const WdSectionHeading('AI 추천 고스트', actionLabel: '준비 중'),
              const SizedBox(height: 16),
              WdSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 10,
                  children: [
                    Row(
                      spacing: 4,
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: WdColors.green,
                        ),
                        Text(
                          'AI 추천 라이벌',
                          style: WdText.ko16Bold.copyWith(
                            color: WdColors.green,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'AI 추천 고스트는 준비 중이에요.',
                      style: WdText.ko12.copyWith(color: WdColors.muted),
                    ),
                  ],
                ),
              ),
              if (c.error != null) ...[
                const SizedBox(height: 16),
                WdButton(
                  '다시 시도',
                  onPressed: c.retry,
                  variant: WdButtonVariant.secondary,
                ),
              ],
            ],
          ),
          bottomNavigationBar: WdBottomBar.pinned(
            primary: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.error != null)
                  WdInfoBanner(c.error!, tone: WdBannerTone.warning),
                if (c.unavailableReasons.isNotEmpty)
                  WdInfoBanner(
                    c.unavailableReasons.any(
                          (r) =>
                              r == 'CONTINUOUS_GAP_EXCEEDED' ||
                              r == 'TOTAL_GAP_EXCEEDED',
                        )
                        ? 'GPS 공백이 많은 기록이에요. 다른 기록을 선택해 주세요.'
                        : '이 기록은 고스트로 사용할 수 없어요. 다른 기록을 선택해 주세요.',
                    tone: WdBannerTone.warning,
                  ),
                WdButton(
                  c.selectingId != null ? '재생 자료 확인 중' : '이 고스트와 대결하기',
                  onPressed: publicSelected
                      ? () => widget.onPublic(public)
                      : ready == null
                      ? null
                      : () => widget.onPrepared(ready),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class GhostRunnerChoiceCard extends StatelessWidget {
  const GhostRunnerChoiceCard({
    super.key,
    required this.title,
    required this.meta,
    required this.onTap,
    this.badge,
    this.selected = false,
    this.checking = false,
  });
  final String title, meta;
  final String? badge;
  final bool selected, checking;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: WdSurface(
      color: WdColors.paper,
      border: BorderSide(
        color: selected ? WdColors.ink : WdColors.line,
        width: selected ? 1.5 : 1,
      ),
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        spacing: 10,
        children: [
          Icon(
            selected ? Icons.circle : Icons.radio_button_unchecked,
            size: 18,
            color: selected ? WdColors.ink : WdColors.line,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(title, style: WdText.ko14Bold),
                Text(meta, style: WdText.ko12.copyWith(color: WdColors.muted)),
              ],
            ),
          ),
          if (checking)
            Text('확인 중', style: WdText.ko11.copyWith(color: WdColors.muted))
          else if (badge != null)
            Text(badge!, style: WdText.ko12.copyWith(color: WdColors.muted)),
        ],
      ),
    ),
  );
}
