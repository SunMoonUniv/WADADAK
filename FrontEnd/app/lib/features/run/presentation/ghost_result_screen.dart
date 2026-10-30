import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/ghost_comparison.dart';
import '../domain/run_models.dart';
import 'ghost_segment_comparison_screen.dart';
import 'ghost_gap_chart.dart';
export 'ghost_segment_comparison_screen.dart';
export 'ghost_gap_chart.dart';

/// D2: the immutable server verdict and metrics for START → first confirmed finish.
class GhostResultScreen extends StatelessWidget {
  const GhostResultScreen({
    super.key,
    required this.run,
    this.comparison,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onAgain,
    this.preparing = false,
  });
  final RunSnapshot run;
  final GhostComparison? comparison;
  final bool loading, preparing;
  final String? error;
  final VoidCallback? onRetry, onAgain;

  @override
  Widget build(BuildContext context) {
    final detail = comparison;
    final result = detail?.result ?? run.ghost;
    final completed =
        result?['completed'] == true && result?['outcome'] != 'INVALID';
    final ours = completed
        ? (result?['courseElapsedSeconds'] as num?)?.toInt()
        : null;
    final theirs = (result?['sourceElapsedSeconds'] as num?)?.toInt();
    final delta = ours == null || theirs == null ? null : theirs - ours;
    final ownSource =
        detail?.kind == 'OWN_FREE' || detail?.kind == 'OWN_COURSE';
    final title = switch (result?['outcome']) {
      'WIN' => '승리',
      'LOSE' => '패배',
      'DRAW' => '무승부',
      'INVALID' => '대결 무효',
      _ => '서버 판정 대기',
    };
    final message = !completed && result != null
        ? ghostVerdictReason(result['reason'] as String?)
        : switch (result?['outcome']) {
            'WIN' => ownSource ? '어제의 나를 앞질렀어요.' : '고스트보다 빨랐어요.',
            'LOSE' => '다음 대결을 향해 한 걸음 더.',
            'DRAW' => '같은 시간에 도착했어요.',
            _ => '기록을 서버에서 확인하고 있어요.',
          };
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(title: '대결 결과', onBack: () => Navigator.pop(context)),
      body: ListView(
        children: [
          Container(
            color: WdColors.lime,
            padding: const EdgeInsets.all(24),
            child: Column(
              spacing: 12,
              children: [
                WdSurface(
                  color: WdColors.ink,
                  radius: WdRadius.full,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    detail?.personalBest == 'IMPROVED'
                        ? '내 코스 최고 기록 경신'
                        : title,
                    style: WdText.ko12Medium.copyWith(color: WdColors.lime),
                  ),
                ),
                Text(
                  delta == null ? '—' : '${delta.abs()}초',
                  style: WdText.run56W800H74,
                ),
                Text(
                  message,
                  style: WdText.ko22Bold,
                  textAlign: TextAlign.center,
                ),
                if (detail?.personalBest == 'FIRST_COMPLETION')
                  const Text('이 코스의 첫 완주를 기록했어요.', style: WdText.ko12),
                if (detail?.kind == 'OWN_FREE' && delta != null && delta > 0)
                  Text('선택한 내 기록보다 $delta초 빨랐어요.', style: WdText.ko12),
                if (theirs != null)
                  Text(
                    '상대 ${_time(theirs)}',
                    style: WdText.ko12.copyWith(color: WdColors.green),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Text(
                  detail?.courseName ?? run.course?.courseName ?? '자유 러닝',
                  style: WdText.ko16Bold,
                ),
                if (detail?.available == true)
                  Text(
                    completed
                        ? '${(detail!.distanceM / 1000).toStringAsFixed(2)}km 완주'
                        : '확인된 도달 위치 ${(detail!.reachedM / 1000).toStringAsFixed(2)} / ${(detail.distanceM / 1000).toStringAsFixed(2)}km',
                    style: WdText.ko12,
                  ),
                WdSurface(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _timeCard('나의 완주 기록', ours, WdColors.ink),
                      ),
                      Expanded(
                        child: _timeCard('고스트 완주 기록', theirs, WdColors.muted),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  const Row(
                    spacing: 12,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      Expanded(child: Text('상세 비교 확인 중', style: WdText.ko12)),
                    ],
                  ),
                if (error != null)
                  WdInfoBanner(error!, tone: WdBannerTone.warning),
                if (!loading &&
                    (error != null || result == null) &&
                    onRetry != null)
                  WdButton(
                    result == null ? '판정 다시 확인' : '상세 비교 다시 확인',
                    variant: WdButtonVariant.secondary,
                    onPressed: onRetry,
                  ),
                if (detail != null && !detail.available)
                  WdInfoBanner(ghostComparisonUnavailable(detail.status)),
                if (detail?.sourceState != null &&
                    !['AVAILABLE', 'UNKNOWN'].contains(detail!.sourceState))
                  const WdInfoBanner(
                    '상대 원본이 삭제·비공개되었거나 사용할 수 없어요. 대결 당시의 비교 결과는 보존돼요. 재도전 시 다시 확인해요.',
                  ),
                const Text('기록 비교', style: WdText.ko14Bold),
                WdSurface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    spacing: 12,
                    children: [
                      _metric('항목', '나', '고스트'),
                      _metric('총 소요시간', _time(ours), _time(theirs)),
                      _metric(
                        '수동 정지 제외',
                        _ms(detail?.ours?.activeMs),
                        _ms(detail?.ghost?.activeMs),
                      ),
                      _metric(
                        '평균 페이스',
                        _pace(detail?.ours?.pace),
                        _pace(detail?.ghost?.pace),
                      ),
                      _metric(
                        '평균 케이던스',
                        _cadence(detail?.ours?.cadence),
                        _cadence(detail?.ghost?.cadence),
                      ),
                      _metric(
                        '대결 중 최고 구간',
                        _best(detail?.ours?.bestSegment),
                        _best(detail?.ghost?.bestSegment),
                      ),
                    ],
                  ),
                ),
                const Text(
                  '측정 시작부터 서버가 확인한 첫 완주까지 비교해요. 총 소요시간과 페이스에는 수동 정지가 포함돼요. 완주 뒤 이어 달린 기록은 제외해요.',
                  style: WdText.ko12,
                ),
                if (detail?.kind == 'PUBLIC_COURSE')
                  const Text(
                    '상대의 정지 제외 시간·케이던스는 공개되지 않아요.',
                    style: WdText.ko12,
                  ),
                const Text(
                  '— 는 미완주·센서 자료 부족 또는 확인할 수 없는 값이에요. 최고 구간은 완전한 1km 구간만 비교해요.',
                  style: WdText.ko12,
                ),
                if (detail?.available == true) ...[
                  const Text('고스트와의 누적 격차', style: WdText.ko14Bold),
                  GhostGapChart(
                    segments: detail!.segments,
                    distanceM: detail.distanceM,
                  ),
                  const Text(
                    '+ 는 내가 앞섬 · − 는 고스트가 앞섬\n그래프는 경계별 누적 차이, 아래 표는 각 구간의 시간 차이예요. GPS 공백은 연결하지 않아요.',
                    style: WdText.ko12,
                  ),
                  const Text('구간별 결과', style: WdText.ko14Bold),
                  for (final s in detail.segments) _segment(s),
                  if (completed &&
                      detail.segments.isNotEmpty &&
                      detail.segments.every((s) => s.delta != null))
                    WdInfoBanner(
                      '구간 시간 차이의 합 ${ghostDelta(detail.segments.fold<int>(0, (v, s) => v + s.delta!))} · 최종 ${ghostDelta(delta)}',
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: WdBottomBar.dual(
        secondary: WdButton(
          '구간 상세',
          variant: WdButtonVariant.secondary,
          onPressed: detail?.available != true
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => GhostSegmentComparisonScreen(
                      run: run,
                      comparison: detail!,
                    ),
                  ),
                ),
        ),
        primary: WdButton(
          preparing ? '기록 확인 중' : '다시 도전하기',
          onPressed: preparing ? null : onAgain,
        ),
      ),
    );
  }

  static Widget _timeCard(String label, int? seconds, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text(label, style: WdText.ko12.copyWith(color: WdColors.muted)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _time(seconds),
          style: WdText.run34W700H39.copyWith(color: color),
        ),
      ),
    ],
  );
  static Widget _metric(String label, String ours, String ghost) => Row(
    children: [
      Expanded(flex: 2, child: Text(label, style: WdText.ko12)),
      Expanded(
        child: Text(ours, textAlign: TextAlign.right, style: WdText.ko12Medium),
      ),
      Expanded(
        child: Text(
          ghost,
          textAlign: TextAlign.right,
          style: WdText.ko12.copyWith(color: WdColors.muted),
        ),
      ),
    ],
  );
  static Widget _segment(GhostComparisonSegment s) => WdSurface(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          children: [
            Expanded(child: Text(s.label, style: WdText.ko12Medium)),
            Text(ghostDelta(s.delta), style: WdText.ko14Bold),
          ],
        ),
        Text('나 ${_time(s.ours)} · 고스트 ${_time(s.ghost)}', style: WdText.ko12),
        if (s.reason != null)
          Text(
            s.explanation,
            style: WdText.ko12.copyWith(color: WdColors.muted),
          ),
      ],
    ),
  );
  static String _time(int? s) =>
      s == null ? '—' : formatRunTime(Duration(seconds: s));
  static String _ms(int? ms) =>
      ms == null ? '—' : formatRunTime(Duration(milliseconds: ms));
  static String _pace(double? p) => p == null ? '—' : formatRunPace(p);
  static String _cadence(double? v) => v == null ? '—' : '${v.round()}';
  static String _best(int? n) => n == null ? '—' : '$n구간';
}
