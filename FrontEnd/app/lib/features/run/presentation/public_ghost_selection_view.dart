import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/ranking_api_client.dart';
import '../../course/detail/course_ranking_state.dart';
import '../application/public_ghost_candidates_controller.dart';
import '../domain/run_models.dart';

/// C10. The caller owns account/course lifetime and revalidates the chosen source.
class PublicGhostSelectionView extends ConsumerStatefulWidget {
  const PublicGhostSelectionView({
    super.key,
    required this.controller,
    required this.courseName,
    required this.onBack,
    required this.onOwn,
    required this.onSelected,
  });
  final PublicGhostCandidatesController controller;
  final String courseName;
  final VoidCallback onBack, onOwn;
  final ValueChanged<PublicGhostChoice> onSelected;
  @override
  ConsumerState<PublicGhostSelectionView> createState() =>
      _PublicGhostSelectionViewState();
}

class _PublicGhostSelectionViewState
    extends ConsumerState<PublicGhostSelectionView>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 2, initialIndex: 1, vsync: this);
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  String time(int? seconds) =>
      seconds == null ? '—' : formatRunTime(Duration(seconds: seconds));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final key = (courseId: c.courseId, period: c.period);
      final summary = ref.watch(courseRankingProvider(key));
      final me = summary.value?.me;
      return Scaffold(
        backgroundColor: WdColors.paper,
        appBar: WdAppBar(title: '고스트 선택', onBack: widget.onBack),
        body: Column(
          children: [
            WdTabBar(
              tabs: const ['내 기록', '다른 러너'],
              controller: tabs,
              onTap: (index) {
                if (index == 0) {
                  tabs.index = 1;
                  widget.onOwn();
                }
              },
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(WdSpace.s24),
                children: [
                  Text(widget.courseName, style: WdText.ko16Bold),
                  const SizedBox(height: WdSpace.s16),
                  Wrap(
                    spacing: WdSpace.s6,
                    children: [
                      for (final p in [
                        RankingPeriod.all,
                        RankingPeriod.month,
                        RankingPeriod.week,
                      ])
                        WdFilterChip(
                          switch (p) {
                            RankingPeriod.all => '전체 기간',
                            RankingPeriod.month => '이번 달',
                            RankingPeriod.week => '이번 주',
                          },
                          selected: c.period == p,
                          onTap: () => c.load(period: p),
                        ),
                    ],
                  ),
                  const SizedBox(height: WdSpace.s16),
                  WdStatSummary([
                    (
                      '참여 러너',
                      summary.value == null
                          ? '—'
                          : '${summary.value!.participantCount}명',
                    ),
                    (
                      '1위 기록',
                      time(
                        summary.value?.top.firstOrNull?.courseElapsedSeconds,
                      ),
                    ),
                    (
                      '내 순위',
                      me?.status == MyRankStatus.private
                          ? '비공개 중'
                          : me?.rank == null
                          ? '—'
                          : '${me!.rank}위',
                    ),
                  ]),
                  if (me?.courseElapsedSeconds != null) ...[
                    const SizedBox(height: WdSpace.s16),
                    WdMyRankCard(
                      WdRank(
                        rank: me!.rank?.toString() ?? '—',
                        name:
                            '나${me.nickname == null ? '' : ' (${me.nickname})'}',
                        meta: '내 최고 기록',
                        value: time(me.courseElapsedSeconds),
                      ),
                    ),
                  ],
                  const SizedBox(height: WdSpace.s16),
                  Wrap(
                    spacing: WdSpace.s6,
                    children: [
                      WdFilterChip(
                        '빠른 순',
                        selected: c.sort == PublicGhostSort.fastest,
                        onTap: () => c.load(sort: PublicGhostSort.fastest),
                      ),
                      WdFilterChip(
                        '나와 비슷한 기록',
                        selected: c.sort == PublicGhostSort.similar,
                        onTap: () => c.load(sort: PublicGhostSort.similar),
                      ),
                    ],
                  ),
                  if (c.sort == PublicGhostSort.similar) ...[
                    const SizedBox(height: WdSpace.s8),
                    WdInfoBanner(
                      me?.courseElapsedSeconds == null
                          ? '이 기간의 내 완주 기록이 없으면 빠른 순으로 보여드려요.'
                          : '이 기간의 내 최고 총 소요시간과 차이가 작은 순이에요.',
                      plain: true,
                    ),
                  ],
                  const SizedBox(height: WdSpace.s16),
                  WdSectionHeading(
                    '다른 러너 ${c.rows.length}명',
                    actionLabel: '탭하면 고스트로 선택',
                  ),
                  const SizedBox(height: WdSpace.s16),
                  if (c.loading)
                    const Center(child: CircularProgressIndicator())
                  else if (c.rows.isEmpty && c.error == null)
                    const WdInfoBanner(
                      '선택할 수 있는 다른 러너의 공개 기록이 없어요.',
                      plain: true,
                    )
                  else
                    WdSurface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WdSpace.s14,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < c.rows.length; i++) ...[
                            if (i > 0)
                              const Divider(height: 1, color: WdColors.map),
                            Semantics(
                              selected: c.selectedId == c.rows[i].runRecordId,
                              button: true,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.selectedId == c.rows[i].runRecordId
                                      ? WdColors.recordSelfSurface
                                      : null,
                                  borderRadius: BorderRadius.circular(
                                    WdRadius.r12,
                                  ),
                                ),
                                child: WdRankRow(
                                  WdRank(
                                    rank: '${c.rows[i].rank}',
                                    name: c.rows[i].nickname ?? '공개 고스트',
                                    meta:
                                        '${formatRunPace(c.rows[i].paceSecondsPerKm.toDouble())}/km',
                                    value: time(c.rows[i].courseElapsedSeconds),
                                    avatar: c.rows[i].profileImageUrl == null
                                        ? null
                                        : NetworkImage(
                                            c.rows[i].profileImageUrl!,
                                          ),
                                  ),
                                  key: ValueKey(
                                    'public-ghost-${c.rows[i].runRecordId}',
                                  ),
                                  onTap: () => c.select(c.rows[i]),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (c.error != null) ...[
                    const SizedBox(height: WdSpace.s12),
                    WdInfoBanner(c.error!, tone: WdBannerTone.warning),
                    WdButton(
                      '공개 기록 다시 확인',
                      variant: WdButtonVariant.secondary,
                      onPressed: () => c.load(
                        append: c.rows.isNotEmpty && c.nextCursor != null,
                      ),
                    ),
                  ],
                  if (c.nextCursor != null) ...[
                    const SizedBox(height: WdSpace.s16),
                    WdButton(
                      c.loadingMore ? '불러오는 중' : '러너 더 보기',
                      variant: WdButtonVariant.secondary,
                      onPressed: c.loadingMore
                          ? null
                          : () => c.load(append: true),
                    ),
                  ],
                  const SizedBox(height: WdSpace.s16),
                  const WdInfoBanner(
                    '다른 러너의 과거 공개 완주 기록만 사용해요. 선택 후 경로와 시간의 재생 가능 여부를 확인해요.',
                    plain: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: WdBottomBar.pinned(
          primary: WdButton(
            '이 고스트와 대결하기',
            onPressed: c.selected == null
                ? null
                : () => widget.onSelected((
                    candidate: c.selected!,
                    period: c.period,
                  )),
          ),
        ),
      );
    },
  );
}
