import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../application/own_ghost_controller.dart';
import '../domain/own_ghost.dart';

/// Figma C9 (1453:4494). An independent selection view; navigation/start belongs to the caller.
class OwnGhostSelectionView extends StatefulWidget {
  const OwnGhostSelectionView({
    super.key,
    required this.controller,
    required this.courseName,
    required this.onBack,
    required this.onPrepared,
    this.onOtherRunners,
  });
  final OwnGhostController controller;
  final String courseName;
  final VoidCallback onBack;
  final ValueChanged<PreparedOwnGhost> onPrepared;
  final VoidCallback? onOtherRunners;
  @override
  State<OwnGhostSelectionView> createState() => _OwnGhostSelectionViewState();
}

class _OwnGhostSelectionViewState extends State<OwnGhostSelectionView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static String time(num? seconds) {
    if (seconds == null) return '—';
    final s = seconds.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  static String date(DateTime at) {
    // Dates use the same Asia/Seoul day as the server's own-record period filter.
    final kst = at.toUtc().add(const Duration(hours: 9));
    return '${kst.year}.${kst.month.toString().padLeft(2, '0')}.${kst.day.toString().padLeft(2, '0')}';
  }

  static String pace(OwnGhostCandidate c) {
    final s = (c.seconds * 1000 / c.distanceM).round();
    return '${s ~/ 60}′${(s % 60).toString().padLeft(2, '0')}″/km';
  }

  WdRank row(OwnGhostCandidate c, {bool best = false}) => WdRank(
    rank: best
        ? '★'
        : widget.controller.prepared?.candidate.id == c.id
        ? '✓'
        : '',
    name: best ? '내 최고 기록' : date(c.startedAt),
    meta: best
        ? '${date(c.startedAt)} · ${pace(c)}'
        : '${pace(c)} · 케이던스 ${c.averageCadence?.round() ?? '—'}',
    value: time(c.seconds),
  );

  static String unavailable(List<String> reasons) {
    if (reasons.any(
      (r) => r == 'CONTINUOUS_GAP_EXCEEDED' || r == 'TOTAL_GAP_EXCEEDED',
    )) {
      return 'GPS 공백이 많은 기록이에요. 다른 기록을 선택해 주세요.';
    }
    return '이 기록은 고스트로 사용할 수 없어요. 다른 기록을 선택해 주세요.';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller, best = c.summary.best;
      final ready = c.prepared;
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
        body: Column(
          children: [
            IgnorePointer(
              ignoring: widget.onOtherRunners == null,
              child: WdTabBar(
                tabs: const ['내 기록', '다른 러너'],
                controller: _tabs,
                onTap: (index) {
                  if (index == 1) {
                    _tabs.index = 0;
                    widget.onOtherRunners?.call();
                  }
                },
              ),
            ),
            const Divider(height: 1, thickness: 1, color: WdColors.map),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  WdSpace.s24,
                  WdSpace.s20,
                  WdSpace.s24,
                  WdSpace.s24,
                ),
                children: [
                  Row(
                    spacing: WdSpace.s6,
                    children: [
                      for (final p in OwnGhostPeriod.values)
                        WdFilterChip(
                          switch (p) {
                            OwnGhostPeriod.all => '전체 기간',
                            OwnGhostPeriod.month => '이번 달',
                            OwnGhostPeriod.week => '이번 주',
                          },
                          height: 36,
                          selected: c.period == p,
                          onTap: () => c.load(period: p),
                        ),
                    ],
                  ),
                  const SizedBox(height: WdSpace.s16),
                  WdStatSummary([
                    ('이 코스 주행', '${c.summary.count}회'),
                    ('내 최고', time(best?.seconds)),
                    ('평균', time(c.summary.averageSeconds)),
                  ]),
                  if (best != null) ...[
                    const SizedBox(height: WdSpace.s16),
                    WdMyRankCard(
                      row(best, best: true),
                      onTap: c.loading ? null : () => c.select(best),
                    ),
                  ],
                  const SizedBox(height: WdSpace.s16),
                  LayoutBuilder(
                    builder: (context, constraints) => WdSectionHeading(
                      '내 기록 ${c.summary.count}개',
                      actionLabel: constraints.maxWidth < 300
                          ? null
                          : '탭하면 고스트로 선택 ›',
                    ),
                  ),
                  const SizedBox(height: WdSpace.s16),
                  if (c.loading)
                    const Center(child: CircularProgressIndicator())
                  else if (c.candidates.isNotEmpty)
                    WdRankList(
                      ranks: [for (final record in c.candidates) row(record)],
                      onTap: (index) => c.select(c.candidates[index]),
                    )
                  else if (c.error == null)
                    const WdInfoBanner('이 코스의 완주 기록이 없어요. 먼저 코스를 완주해 보세요.'),
                  if (c.error != null) ...[
                    const SizedBox(height: WdSpace.s16),
                    WdButton(
                      '다시 시도',
                      onPressed: c.retry,
                      variant: WdButtonVariant.secondary,
                    ),
                  ],
                  if (c.nextCursor != null && c.error == null) ...[
                    const SizedBox(height: WdSpace.s16),
                    WdButton(
                      c.loadingMore ? '불러오는 중' : '기록 더 보기',
                      onPressed: c.loadingMore ? null : c.loadMore,
                      variant: WdButtonVariant.secondary,
                    ),
                  ],
                  const SizedBox(height: WdSpace.s16),
                  const WdInfoBanner(
                    '이 코스의 완주 기록을 선택하면 고스트로 사용할 수 있는지 확인해요.',
                    plain: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: WdColors.paper,
            border: Border(top: BorderSide(color: WdColors.map)),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                WdSpace.s16,
                WdSpace.s10,
                WdSpace.s16,
                0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.error != null)
                    WdInfoBanner(c.error!, tone: WdBannerTone.warning),
                  if (c.unavailableReasons.isNotEmpty)
                    WdInfoBanner(
                      unavailable(c.unavailableReasons),
                      tone: WdBannerTone.warning,
                    ),
                  if (ready != null)
                    WdInfoBanner(
                      '${date(ready.candidate.startedAt)} · ${time(ready.candidate.seconds)} 기록을 선택했어요.',
                    ),
                  WdButton(
                    c.selectingId != null ? '재생 자료 확인 중' : '이 고스트와 대결하기',
                    variant: WdButtonVariant.secondary,
                    onPressed: ready == null
                        ? null
                        : () => widget.onPrepared(ready),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
