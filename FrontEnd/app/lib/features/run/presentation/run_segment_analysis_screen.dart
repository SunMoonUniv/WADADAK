import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/run_models.dart';
import 'run_result_details.dart';

/// D3 / D5 / D6. Missing per-segment sensor or opponent data stays unavailable.
class RunSegmentAnalysisScreen extends StatefulWidget {
  const RunSegmentAnalysisScreen({super.key, required this.run});
  final RunSnapshot run;

  @override
  State<RunSegmentAnalysisScreen> createState() =>
      _RunSegmentAnalysisScreenState();
}

class _RunSegmentAnalysisScreenState extends State<RunSegmentAnalysisScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final complete = run.laps
        .where((l) => l.complete && l.paceSecondsPerKm != null)
        .toList();
    final values = complete.map((l) => l.paceSecondsPerKm!).toList();
    final min = values.isEmpty ? 0.0 : values.reduce(math.min);
    final max = values.isEmpty ? 0.0 : values.reduce(math.max);
    final best = values.isEmpty ? null : complete[values.indexOf(min)];
    final summaries = switch (tab) {
      0 => [
        (
          '가장 빠른 구간',
          best == null ? '—' : '${best.number}구간 ${formatRunPace(min)}',
        ),
        ('페이스 유지력', '—'),
      ],
      1 => [
        (
          '평균 케이던스',
          run.averageCadence == null
              ? '—'
              : '${run.averageCadence!.round()} spm',
        ),
        ('케이던스 안정도', '—'),
      ],
      _ => [
        ('최대 상승 구간', '—'),
        (
          '누적 상승고도',
          run.resultStats?.elevationGainM == null
              ? '—'
              : '+${run.resultStats!.elevationGainM!.round()} m',
        ),
      ],
    };
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: WdColors.paper,
        appBar: WdAppBar(
          title: '구간 분석',
          onBack: () => Navigator.pop(context),
          action: WdAppBarAction.text(
            run.course?.courseName ?? '자유 러닝',
            onTap: null,
          ),
        ),
        body: Column(
          children: [
            WdTabBar(
              tabs: const ['페이스', '케이던스', '고도'],
              onTap: (i) => setState(() => tab = i),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                children: [
                  if (tab == 0 && values.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(
                          MediaQuery.sizeOf(context).width - 48,
                          complete.length * 58.0 + 64,
                        ),
                        child: WdSegmentChart(
                          title: '구간별 페이스 (1km 단위)',
                          values: [
                            for (final v in values)
                              max == min
                                  ? 1
                                  : .35 + .65 * (max - v) / (max - min),
                          ],
                          labels: [for (final l in complete) '${l.number} km'],
                          maxLabel: formatRunPace(min),
                          minLabel: formatRunPace(max),
                          highlightIndex: values.indexOf(min),
                          legend: const ('나', '비교 데이터 없음'),
                        ),
                      ),
                    )
                  else
                    WdSurface(
                      height: 172,
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(switch (tab) {
                          0 => '완성된 1km 구간이 없어요.',
                          1 => '구간별 케이던스 데이터가 없어요.',
                          _ => '구간별 고도 데이터가 없어요.',
                        }, style: WdText.ko12.copyWith(color: WdColors.muted)),
                      ),
                    ),
                  const SizedBox(height: WdSpace.s16),
                  WdSummaryTiles(summaries),
                  const SizedBox(height: WdSpace.s16),
                  Text(
                    '구간 기록',
                    style: WdText.ko16Bold.copyWith(color: WdColors.muted),
                  ),
                  const SizedBox(height: WdSpace.s16),
                  if (run.laps.isNotEmpty)
                    WdSegmentTable(
                      columns: tab == 2
                          ? const ['구간', '고도 변화', '누적 상승', '경사도']
                          : const ['구간', '페이스', '케이던스', '고스트 대비'],
                      rows: [
                        for (final lap in run.laps)
                          WdSegmentRow(
                            lap.complete
                                ? '${lap.number} km'
                                : '마지막 ${(lap.distanceM / 1000).toStringAsFixed(2)} km',
                            tab == 2
                                ? '—'
                                : formatRunPace(lap.paceSecondsPerKm),
                            '—',
                            '—',
                          ),
                      ],
                    )
                  else
                    Text(
                      '측정된 구간이 없어요.',
                      style: WdText.ko12.copyWith(color: WdColors.muted),
                    ),
                  const SizedBox(height: WdSpace.s16),
                  if (best != null && tab == 0)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const WdIcon(WdIcons.ghostInfo, size: 16),
                        const SizedBox(width: WdSpace.s8),
                        Expanded(
                          child: Text(
                            '${best.number}구간에서 가장 빨랐어요.',
                            style: WdText.ko12.copyWith(color: WdColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('측정 상세 및 기준', style: WdText.ko14Bold),
                    children: [RunResultDetails(run: run)],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
