import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../data/run_splits_api.dart';
import '../domain/run_lap.dart';
import '../domain/run_models.dart';
import 'run_result_details.dart';

/// 페이스 유지력·케이던스 안정도(%): `100 − 8 × 변동계수(%)`, 0 아래는 0. 완성 구간 2개 미만이면 null.
/// 8은 실제 기록으로 맞출 초기값이다(2026-10-29 사용자 결정)
int? steadinessPercent(List<double> values) {
  if (values.length < 2) return null;
  final mean = values.reduce((a, b) => a + b) / values.length;
  if (mean <= 0) return null;
  final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
  return math.max(0, 100 - 8 * math.sqrt(variance) / mean * 100).round();
}

/// 경사도(고도 변화 ÷ 구간 거리): 내리막 −0.5% 미만, 평지 ±0.5%, 완만 3% 미만, 가파름 3% 이상(2026-10-29 사용자 결정)
String slopeLabel(double changeM, double distanceM) {
  final grade = changeM / distanceM * 100;
  if (grade < -.5) return '내리막';
  if (grade <= .5) return '평지';
  return grade < 3 ? '완만' : '가파름';
}

String _signedMeters(double m) {
  final r = m.round();
  return r > 0 ? '+$r m' : r < 0 ? '−${-r} m' : '0 m';
}

/// D3 / D5 / D6 구간 분석. 차트·카드는 완성된 1 km 구간만, 표는 마지막 부분 구간도 넣는다.
/// 케이던스·고도는 서버 구간 값(`splits`)이라 서버에 올린 뒤 보인다. 고스트 대비는 F9에서 붙인다
class RunSegmentAnalysisScreen extends ConsumerStatefulWidget {
  const RunSegmentAnalysisScreen({super.key, required this.run});
  final RunSnapshot run;

  @override
  ConsumerState<RunSegmentAnalysisScreen> createState() => _RunSegmentAnalysisScreenState();
}

class _RunSegmentAnalysisScreenState extends ConsumerState<RunSegmentAnalysisScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final id = run.sessionId;
    final value = id == null ? null : ref.watch(runSplitsProvider(id));
    final splits = {for (final s in value?.value ?? const <RunSplit>[]) s.number: s};
    // 케이던스·고도를 못 보이는 사유. 없으면 받았다
    final unavailable = switch (value) {
      null => '기록을 서버에 올린 뒤 볼 수 있어요.',
      _ when value.hasValue => null,
      AsyncError(:final error) =>
        error is ApiException && error.code == 'RUN-002' ? '기록을 서버에 올린 뒤 볼 수 있어요.' : '구간 데이터를 불러오지 못했어요.',
      _ => '구간 데이터를 불러오는 중이에요.',
    };
    final complete = run.laps.where((l) => l.complete && l.paceSecondsPerKm != null).toList();
    final view = switch (tab) {
      0 => _pace(run, complete),
      1 => _cadence(run, complete, splits, unavailable),
      _ => _elevation(run, complete, splits, unavailable),
    };
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: WdColors.paper,
        appBar: WdAppBar(
          title: '구간 분석',
          onBack: () => Navigator.pop(context),
          action: WdAppBarAction.text(run.course?.courseName ?? '자유 러닝', onTap: null),
        ),
        body: Column(
          children: [
            WdTabBar(tabs: const ['페이스', '케이던스', '고도'], onTap: (i) => setState(() => tab = i)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                children: [
                  if (view.chart case final chart?)
                    // 구간이 많으면 막대 폭을 유지하고 가로로 넘긴다
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(MediaQuery.sizeOf(context).width - 48, complete.length * 58.0 + 64),
                        child: chart,
                      ),
                    )
                  else
                    WdSurface(
                      height: 172,
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(view.empty, style: WdText.ko12.copyWith(color: WdColors.muted)),
                      ),
                    ),
                  const SizedBox(height: WdSpace.s16),
                  WdSummaryTiles(view.summaries),
                  const SizedBox(height: WdSpace.s16),
                  Text('구간 기록', style: WdText.ko16Bold.copyWith(color: WdColors.muted)),
                  const SizedBox(height: WdSpace.s16),
                  if (run.laps.isNotEmpty)
                    WdSegmentTable(
                      columns: tab == 2 ? const ['구간', '고도 변화', '누적 상승', '경사도'] : const ['구간', '페이스', '케이던스'],
                      rows: [for (final lap in run.laps) _row(lap, splits[lap.number])],
                    )
                  else
                    Text('측정된 구간이 없어요.', style: WdText.ko12.copyWith(color: WdColors.muted)),
                  const SizedBox(height: WdSpace.s16),
                  for (final line in view.notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: WdSpace.s8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const WdIcon(WdIcons.ghostInfo, size: 16),
                          const SizedBox(width: WdSpace.s8),
                          Expanded(child: Text(line, style: WdText.ko12.copyWith(color: WdColors.muted))),
                        ],
                      ),
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

  WdSegmentRow _row(RunLap lap, RunSplit? split) {
    final label = lap.complete ? '${lap.number} km' : '마지막 ${(lap.distanceM / 1000).toStringAsFixed(2)} km';
    if (tab != 2) {
      final cadence = split?.cadence;
      return WdSegmentRow(label, formatRunPace(lap.paceSecondsPerKm), cadence == null ? '—' : '${cadence.round()}', null);
    }
    final change = split?.elevationChangeM, gain = split?.cumulativeGainM;
    final slope = change == null || lap.distanceM <= 0 ? null : slopeLabel(change, lap.distanceM);
    return WdSegmentRow(
      label,
      change == null ? '—' : _signedMeters(change),
      gain == null ? '—' : '${gain.round()} m',
      slope ?? '—',
      deltaColor: switch (slope) {
        '완만' => WdColors.green,
        '가파름' => WdColors.warningText,
        _ => WdColors.muted,
      },
    );
  }

  _TabView _pace(RunSnapshot run, List<RunLap> complete) {
    if (complete.isEmpty) {
      return const _TabView(empty: '완성된 1km 구간이 없어요.', summaries: [('가장 빠른 구간', '—'), ('페이스 유지력', '—')]);
    }
    final paces = [for (final l in complete) l.paceSecondsPerKm!];
    final fastest = paces.reduce(math.min), slowest = paces.reduce(math.max);
    // 정책의 최고 구간(GPS 공백 랩 제외)을 먼저 쓴다
    final bestIndex = switch (complete.indexWhere((l) => l.number == run.resultStats?.bestLapNumber)) {
      -1 => paces.indexOf(fastest),
      final i => i,
    };
    final best = complete[bestIndex];
    final steady = steadinessPercent(paces);
    return _TabView(
      chart: WdSegmentChart(
        title: '구간별 페이스 (1km 단위)',
        values: [for (final v in paces) fastest == slowest ? 1 : .35 + .65 * (slowest - v) / (slowest - fastest)],
        labels: [for (final l in complete) '${l.number} km'],
        maxLabel: formatRunPace(fastest),
        minLabel: formatRunPace(slowest),
        highlightIndex: bestIndex,
      ),
      summaries: [
        ('가장 빠른 구간', '${best.number}구간 ${formatRunPace(best.paceSecondsPerKm)}'),
        ('페이스 유지력', steady == null ? '—' : '$steady%'),
      ],
      notes: ['${best.number}구간에서 가장 빨랐어요(${formatRunPace(best.paceSecondsPerKm)}).'],
    );
  }

  _TabView _cadence(RunSnapshot run, List<RunLap> complete, Map<int, RunSplit> splits, String? unavailable) {
    final cadences = [for (final l in complete) splits[l.number]?.cadence];
    final measured = cadences.nonNulls.toList();
    if (unavailable != null || measured.isEmpty) {
      return _TabView(
        empty: unavailable ?? '구간별 케이던스 데이터가 없어요.',
        summaries: const [('최고 케이던스 구간', '—'), ('케이던스 안정도', '—')],
      );
    }
    final average = run.averageCadence;
    final top = math.max(measured.reduce(math.max), average ?? 0);
    final bottom = math.min(measured.reduce(math.min), average ?? double.infinity);
    double scale(double v) => top == bottom ? 1 : .35 + .65 * (v - bottom) / (top - bottom);
    final highest = cadences.indexOf(measured.reduce(math.max));
    final steady = steadinessPercent(measured);
    final best = '${complete[highest].number}구간 ${measured.reduce(math.max).round()}spm';
    return _TabView(
      chart: WdSegmentChart(
        title: '구간별 케이던스 (1km 단위)',
        values: [for (final c in cadences) c == null ? 0 : scale(c)],
        labels: [for (final l in complete) '${l.number} km'],
        maxLabel: '${top.round()}',
        minLabel: '${bottom.round()}',
        highlightIndex: highest,
        reference: average == null ? null : [scale(average)],
        legend: const ('나', '평균 케이던스'),
      ),
      summaries: [('최고 케이던스 구간', best), ('케이던스 안정도', steady == null ? '—' : '$steady%')],
      notes: ['${complete[highest].number}구간에서 ${measured.reduce(math.max).round()}spm으로 가장 높았어요.'],
    );
  }

  _TabView _elevation(RunSnapshot run, List<RunLap> complete, Map<int, RunSplit> splits, String? unavailable) {
    final gain = run.resultStats?.elevationGainM;
    final total = ('누적 상승고도', gain == null ? '—' : _signedMeters(gain));
    final changes = [for (final l in complete) splits[l.number]?.elevationChangeM];
    final measured = changes.nonNulls.toList();
    if (unavailable != null || measured.isEmpty) {
      return _TabView(empty: unavailable ?? '구간별 고도 데이터가 없어요.', summaries: [('최대 상승 구간', '—'), total]);
    }
    final top = math.max(0.0, measured.reduce(math.max)), bottom = math.min(0.0, measured.reduce(math.min));
    final span = top == bottom ? 1.0 : top - bottom;
    double scale(double v) => (v - bottom) / span;
    final highest = measured.reduce(math.max);
    final climb = highest > 0 ? changes.indexOf(highest) : null;
    return _TabView(
      chart: WdSegmentChart(
        title: '구간별 고도 변화 (1km 단위)',
        // 끊긴 구간은 막대 없이 둔다
        values: [for (final c in changes) scale(c ?? 0)],
        labels: [for (final l in complete) '${l.number} km'],
        maxLabel: _signedMeters(top),
        minLabel: _signedMeters(bottom),
        baseline: scale(0),
        highlightIndex: climb,
        reference: [scale(0)],
        legend: const ('고도 변화', '시작 고도'),
      ),
      summaries: [('최대 상승 구간', climb == null ? '—' : '${complete[climb].number}구간 ${_signedMeters(highest)}'), total],
      notes: [
        if (climb != null)
          '${complete[climb].number}구간에서 가장 많이 올랐어요.${gain == null ? '' : ' 전체 상승 ${gain.round()} m.'}',
        if (measured.length < changes.length) '고도 자료가 끊긴 구간은 변화를 표시할 수 없어요.',
      ],
    );
  }
}

class _TabView {
  const _TabView({this.chart, this.empty = '', required this.summaries, this.notes = const []});
  final WdSegmentChart? chart;

  /// [chart]가 없을 때 차트 자리 안내
  final String empty;
  final List<(String, String)> summaries;

  /// 맨 아래 한 줄 해설(이번 기록 사실만)
  final List<String> notes;
}
