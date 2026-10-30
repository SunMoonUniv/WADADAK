import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/ghost_comparison.dart';
import '../domain/run_models.dart';
import 'ghost_gap_chart.dart';
import 'run_segment_analysis_screen.dart';

/// D2-S: data-driven pace bars, gap view and one expanded reference segment.
class GhostSegmentComparisonScreen extends StatefulWidget {
  const GhostSegmentComparisonScreen({
    super.key,
    required this.run,
    required this.comparison,
  });
  final RunSnapshot run;
  final GhostComparison comparison;
  @override
  State<GhostSegmentComparisonScreen> createState() =>
      _GhostSegmentComparisonScreenState();
}

class _GhostSegmentComparisonScreenState
    extends State<GhostSegmentComparisonScreen> {
  late int _selected;
  bool _gap = false;
  @override
  void initState() {
    super.initState();
    _initialSelection();
  }

  @override
  void didUpdateWidget(covariant GhostSegmentComparisonScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.comparison, widget.comparison)) _initialSelection();
  }

  void _initialSelection() {
    final best = widget.comparison.ours?.bestSegment;
    final index = widget.comparison.segments.indexWhere(
      (s) => s.number == best,
    );
    _selected = index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.comparison, segments = d.segments;
    final known = segments.where((s) => s.delta != null).toList();
    final ahead = known.where((s) => s.delta! > 0).length;
    final best = segments
        .where(
          (s) => s.number == d.ours?.bestSegment && s.full && s.ours != null,
        )
        .firstOrNull;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(title: '대결 구간 상세', onBack: () => Navigator.pop(context)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          Text(
            '${d.courseName ?? '자유 러닝'} · ${(d.distanceM / 1000).toStringAsFixed(2)}km',
            style: WdText.ko12.copyWith(color: WdColors.muted),
          ),
          const SizedBox(height: 8),
          Text(
            '구간마다 달라진\n나의 레이스',
            style: WdText.ko22Bold.copyWith(fontSize: 26, height: 1.45),
          ),
          const SizedBox(height: 20),
          WdSummaryTiles([
            (
              '나의 최고 구간',
              best == null ? '—' : '${best.number}구간 ${_pace(best.pace(true))}',
            ),
            ('앞선 구간', known.isEmpty ? '—' : '$ahead / ${known.length} 구간'),
          ]),
          if (known.length < segments.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '앞선 구간은 격차를 확인할 수 있는 구간만 세었어요.',
                style: WdText.caption11.copyWith(color: WdColors.muted),
              ),
            ),
          const SizedBox(height: 20),
          WdSurface(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (final (label, gap) in [('페이스', false), ('누적 격차', true)])
                  Expanded(
                    child: Semantics(
                      selected: _gap == gap,
                      button: true,
                      child: WdSurface(
                        color: _gap == gap ? WdColors.ink : WdColors.soft,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        onTap: () => setState(() => _gap = gap),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: WdText.body13Bold.copyWith(
                            color: _gap == gap ? WdColors.lime : WdColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: duration,
            child: _gap
                ? Column(
                    key: const ValueKey('gap-view'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 8),
                        child: Text('고스트와의 누적 격차', style: WdText.ko14Bold),
                      ),
                      GhostGapChart(segments: segments, distanceM: d.distanceM),
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '+ 내가 앞섬 · − 고스트가 앞섬\n확인되지 않은 구간은 선을 연결하지 않아요.',
                          style: WdText.caption11,
                        ),
                      ),
                    ],
                  )
                : GhostSegmentPaceChart(
                    key: const ValueKey('pace-view'),
                    segments: segments,
                    selected: _selected,
                    onSelected: (index) => setState(() => _selected = index),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            _gap ? '구간을 눌러 상세 기록을 확인하세요.' : '막대나 구간을 누르면 기록이 펼쳐져요.',
            style: WdText.caption11.copyWith(color: WdColors.muted),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: Text('구간 기록', style: WdText.ko16Bold)),
              Flexible(
                child: Text(
                  '정지 포함 · 1km 기준',
                  textAlign: TextAlign.right,
                  style: WdText.caption11.copyWith(color: WdColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < segments.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SegmentCard(
                key: ValueKey('ghost-segment-${segments[i].number}'),
                segment: segments[i],
                selected: i == _selected,
                best: segments[i].number == d.ours?.bestSegment,
                duration: duration,
                onTap: () => setState(() => _selected = i),
              ),
            ),
          const SizedBox(height: 8),
          const Text('케이던스와 고도는 전체 러닝 분석에서 확인해요.', style: WdText.caption11),
        ],
      ),
      bottomNavigationBar: WdBottomBar.dual(
        secondary: WdButton(
          '결과로',
          variant: WdButtonVariant.secondary,
          onPressed: () => Navigator.pop(context),
        ),
        primary: WdButton(
          '전체 러닝 분석',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RunSegmentAnalysisScreen(run: widget.run),
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({
    super.key,
    required this.segment,
    required this.selected,
    required this.best,
    required this.onTap,
    required this.duration,
  });
  final GhostComparisonSegment segment;
  final bool selected, best;
  final VoidCallback onTap;
  final Duration duration;
  @override
  Widget build(BuildContext context) {
    final s = segment;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: duration,
        decoration: BoxDecoration(
          color: selected ? WdColors.limeSoft : WdColors.soft,
          borderRadius: BorderRadius.circular(WdRadius.r16),
        ),
        child: WdSurface(
          color: Colors.transparent,
          onTap: onTap,
          padding: const EdgeInsets.all(16),
          child: AnimatedSize(
            duration: duration,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Text(
                      s.number.toString().padLeft(2, '0'),
                      style: WdText.section12.copyWith(
                        color: selected ? WdColors.green : WdColors.muted,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${s.label}${s.full ? '' : ' · 마지막 구간'}',
                        style: WdText.body13Bold,
                      ),
                    ),
                    if (best)
                      Text(
                        'BEST',
                        style: WdText.micro10Bold.copyWith(
                          color: WdColors.green,
                        ),
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 88),
                      child: Text(
                        _advantage(s.delta),
                        textAlign: TextAlign.right,
                        style: WdText.section12.copyWith(
                          color: (s.delta ?? 0) > 0
                              ? WdColors.green
                              : WdColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!selected)
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('나 ${_pace(s.pace(true))}', style: WdText.ko14Bold),
                      Text(
                        '고스트 ${_pace(s.pace(false))}',
                        style: WdText.ko12.copyWith(color: WdColors.muted),
                      ),
                    ],
                  ),
                if (selected) ...[
                  Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: _record('나 · 구간 시간', s.ours, WdColors.ink),
                      ),
                      Expanded(
                        child: _record('고스트 · 구간 시간', s.ghost, WdColors.muted),
                      ),
                    ],
                  ),
                  if (!s.full)
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          '페이스 나 ${_pace(s.pace(true))}',
                          style: WdText.caption11,
                        ),
                        Text(
                          '고스트 ${_pace(s.pace(false))}',
                          style: WdText.caption11.copyWith(
                            color: WdColors.muted,
                          ),
                        ),
                      ],
                    ),
                  _TimeBar(
                    label: '나',
                    value: s.ours,
                    maximum: math.max(s.ours ?? 0, s.ghost ?? 0),
                    color: WdColors.green,
                  ),
                  _TimeBar(
                    label: '고스트',
                    value: s.ghost,
                    maximum: math.max(s.ours ?? 0, s.ghost ?? 0),
                    color: WdColors.ghostMarker,
                  ),
                  Text(
                    '구간 소요시간 · 짧을수록 빠름',
                    style: WdText.micro10.copyWith(color: WdColors.muted),
                  ),
                  Text(
                    '구간 ${_advantage(s.delta)} · 누적 ${_cumulative(s.cumulative)}',
                    style: WdText.caption11.copyWith(color: WdColors.green),
                  ),
                  if (s.reason != null)
                    Text(
                      s.explanation,
                      style: WdText.ko12.copyWith(color: WdColors.muted),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _record(String label, int? seconds, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text(label, style: WdText.caption11.copyWith(color: WdColors.muted)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          seconds == null ? '—' : formatRunTime(Duration(seconds: seconds)),
          style: WdText.ko22Bold.copyWith(fontSize: 24, color: color),
        ),
      ),
    ],
  );
}

class _TimeBar extends StatelessWidget {
  const _TimeBar({
    required this.label,
    required this.value,
    required this.maximum,
    required this.color,
  });
  final String label;
  final int? value;
  final int maximum;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    spacing: 8,
    children: [
      SizedBox(
        width: 38,
        child: Text(
          label,
          style: WdText.caption11.copyWith(color: WdColors.muted),
        ),
      ),
      Expanded(
        child: value == null
            ? const Text('—', style: WdText.caption11)
            : ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  height: 7,
                  color: WdColors.line,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: maximum <= 0 ? 0 : value! / maximum,
                    child: ColoredBox(
                      color: color,
                      child: const SizedBox(height: 7),
                    ),
                  ),
                ),
              ),
      ),
    ],
  );
}

/// All bars use pace, including the final partial segment. Missing values are never zero bars.
class GhostSegmentPaceChart extends StatelessWidget {
  const GhostSegmentPaceChart({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });
  final List<GhostComparisonSegment> segments;
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => WdSurface(
    padding: const EdgeInsets.all(16),
    child: Column(
      spacing: 8,
      children: [
        Row(
          children: [
            const Expanded(child: Text('구간별 페이스', style: WdText.ko14Bold)),
            Text(
              '● 나',
              style: WdText.caption11.copyWith(color: WdColors.green),
            ),
            const SizedBox(width: 8),
            Text(
              '┄ 고스트',
              style: WdText.caption11.copyWith(color: WdColors.muted),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, box) => SizedBox(
            height: 192,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _PacePainter(segments, selected)),
                ),
                if (segments.isNotEmpty)
                  Positioned(
                    left: 36,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      children: [
                        for (var i = 0; i < segments.length; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: i == selected,
                              label:
                                  '${segments[i].number}구간, ${segments[i].label}, 나 ${_pace(segments[i].pace(true))}, 고스트 ${_pace(segments[i].pace(false))}',
                              child: GestureDetector(
                                key: ValueKey(
                                  'ghost-pace-hit-${segments[i].number}',
                                ),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onSelected(i),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('높을수록 빠름 · 마지막 짧은 구간도 페이스로 비교', style: WdText.micro10),
        ),
      ],
    ),
  );
}

class _PacePainter extends CustomPainter {
  _PacePainter(this.segments, this.selected);
  final List<GhostComparisonSegment> segments;
  final int selected;
  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;
    final values = [
      for (final s in segments) ...[?s.pace(true), ?s.pace(false)],
    ];
    final lower = values.isEmpty
        ? 0.0
        : math.max(0.0, (values.reduce(math.min) / 10).floor() * 10.0 - 10);
    final upper = values.isEmpty
        ? 360.0
        : math.max(lower + 30, (values.reduce(math.max) / 30).ceil() * 30.0);
    const left = 36.0, top = 18.0, bottom = 160.0;
    final width = math.max(0.0, size.width - left),
        cell = width / segments.length;
    double y(double p) => top + (p - lower) / (upper - lower) * (bottom - top);
    final ticks = [
      for (var p = (lower / 30).ceil() * 30.0; p <= upper; p += 30) p,
    ];
    final labels = ticks.length >= 2
        ? ticks
        : [lower, (lower + upper) / 2, upper];
    for (final p in labels) {
      final paint = Paint()
        ..color = WdColors.line
        ..strokeWidth = 1;
      for (var x = left; x < size.width; x += 7) {
        canvas.drawLine(
          Offset(x, y(p)),
          Offset(math.min(x + 3, size.width), y(p)),
          paint,
        );
      }
      _text(canvas, formatRunPace(p), Offset(0, y(p) - 7), WdColors.muted);
    }
    if (selected >= 0 && selected < segments.length) {
      final band = Rect.fromLTWH(
        left + cell * selected + cell * .1,
        12,
        cell * .8,
        bottom - 10,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(band, const Radius.circular(12)),
        Paint()..color = WdColors.limeSoft,
      );
    }
    final labelStep = math.max(1, (segments.length / 7).ceil());
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i], pace = s.pace(true), x = left + cell * (i + .5);
      if (pace != null) {
        final barWidth = math.min(18.0, cell * .45),
            barTop = math.min(bottom - 3, y(pace));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - barWidth / 2, barTop, barWidth, bottom - barTop),
            const Radius.circular(5),
          ),
          Paint()..color = i == selected ? WdColors.green : WdColors.lime,
        );
      } else {
        _text(canvas, '—', Offset(x - 4, 130), WdColors.muted);
      }
      if (i % labelStep == 0 || i == segments.length - 1) {
        final label = s.full ? '${s.number}' : s.label.replaceAll('km', '');
        _text(
          canvas,
          label,
          Offset(x, 170),
          i == selected ? WdColors.green : WdColors.muted,
          center: true,
        );
      }
    }
    Offset? previous;
    final ghost = Paint()
      ..color = WdColors.muted
      ..strokeWidth = 2;
    for (var i = 0; i < segments.length; i++) {
      final pace = segments[i].pace(false);
      if (pace == null) {
        previous = null;
        continue;
      }
      final point = Offset(left + cell * (i + .5), y(pace));
      if (previous != null) {
        final delta = point - previous, length = delta.distance;
        if (length > 0) {
          for (var d = 0.0; d < length; d += 7) {
            canvas.drawLine(
              previous + delta * (d / length),
              previous + delta * (math.min(d + 3, length) / length),
              ghost,
            );
          }
        }
      }
      canvas.drawCircle(point, 2, Paint()..color = WdColors.muted);
      previous = point;
    }
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at,
    Color color, {
    bool center = false,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: WdText.micro10.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(
      canvas,
      Offset(
        center ? (at.dx - p.width / 2).clamp(0, double.infinity) : at.dx,
        at.dy,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _PacePainter old) =>
      old.selected != selected || !identical(old.segments, segments);
}

String _pace(double? pace) => pace == null ? '—' : formatRunPace(pace);
String _advantage(int? delta) => delta == null
    ? '확인 불가'
    : delta == 0
    ? '동일'
    : '${delta.abs()}초 ${delta > 0 ? '빠름' : '느림'}';
String _cumulative(int? delta) => delta == null
    ? '확인 불가'
    : delta == 0
    ? '동일'
    : '${delta.abs()}초 ${delta > 0 ? '앞섬' : '뒤처짐'}';
