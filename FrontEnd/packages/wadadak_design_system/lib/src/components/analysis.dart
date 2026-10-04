import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'surface.dart';

/// Analysis / Segment chart — 구간별 막대 차트 (페이스 · 케이던스 · 고도), h172.
///
/// 값은 모두 그림 영역 안의 위치(0 = 아래, 1 = 위)다. 단위 변환은 화면에서 한다
/// (페이스처럼 작을수록 좋은 값은 뒤집어서 넘긴다).
class WdSegmentChart extends StatelessWidget {
  const WdSegmentChart({
    super.key,
    required this.title,
    required this.values,
    required this.labels,
    required this.maxLabel,
    required this.minLabel,
    this.baseline = 0,
    this.highlightIndex,
    this.reference,
    this.legend = ('나', '고스트'),
  });

  /// 예: "구간별 페이스 (1km 단위)"
  final String title;

  /// 막대 끝 위치 (0–1).
  final List<double> values;

  /// x축 라벨 (예: "1 km"). [values]와 길이가 같아야 한다.
  final List<String> labels;

  /// y축 위·아래 라벨 (예: "5′02″", "5′22″").
  final String maxLabel;
  final String minLabel;

  /// 막대가 시작하는 위치 (0–1). 고도처럼 ± 값이면 0보다 크게 (기준 아래 막대는 아래로 자란다).
  final double baseline;

  /// 라임으로 강조할 막대.
  final int? highlightIndex;

  /// 점선 — 값 1개: 가로선(평균 케이던스·시작 고도) / 막대 수만큼: 막대 중심을 잇는 선(고스트 페이스).
  final List<double>? reference;

  /// 범례 (막대, 점선). 예: ('나', '고스트')
  final (String, String) legend;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final axis = WdText.raw(11, FontWeight.w400).copyWith(color: WdColors.muted);
    return WdSurface(
      height: 172,
      child: LayoutBuilder(builder: (context, c) {
        final plotW = c.maxWidth - 16 - 58; // Figma: 354 = 16 + 280 + 58
        final barW = (plotW - _gap * (values.length - 1)) / values.length;
        return Stack(
          children: [
            Positioned(
              left: 16,
              top: 12,
              right: 16,
              child: Text(title, style: WdText.label12.copyWith(color: WdColors.muted)),
            ),
            Positioned(
              left: 16,
              top: 38,
              width: plotW,
              height: 84,
              child: CustomPaint(painter: _ChartPainter(values, baseline, highlightIndex, reference, _gap)),
            ),
            Positioned(
              left: 16,
              top: 127,
              child: Row(
                spacing: _gap,
                children: [
                  for (final l in labels)
                    SizedBox(width: barW, child: Text(l, textAlign: TextAlign.center, maxLines: 1, style: axis)),
                ],
              ),
            ),
            Positioned(left: 16 + plotW + 8, top: 36, child: Text(maxLabel, style: axis)),
            Positioned(left: 16 + plotW + 8, top: 108, child: Text(minLabel, style: axis)),
            Positioned(
              left: 16,
              top: 149,
              child: Row(
                spacing: WdSpace.s12,
                children: [
                  Text('▮ ${legend.$1}', style: WdText.caption11.copyWith(color: WdColors.muted)),
                  Text('--- ${legend.$2}', style: WdText.caption11.copyWith(color: WdColors.muted)),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, this.baseline, this.highlight, this.reference, this.gap);

  final List<double> values;
  final double baseline;
  final int? highlight;
  final List<double>? reference;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final w = (size.width - gap * (n - 1)) / n;
    double y(double f) => size.height * (1 - f.clamp(0, 1));

    for (var i = 0; i < n; i++) {
      final x = i * (w + gap);
      final rect = Rect.fromLTRB(x, y(math.max(values[i], baseline)), x + w, y(math.min(values[i], baseline)));
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..color = i == highlight ? WdColors.lime : WdColors.chartBar);
    }

    final ref = reference;
    if (ref == null || ref.isEmpty) return;
    final line = Path();
    if (ref.length == 1) {
      line
        ..moveTo(0, y(ref.first))
        ..lineTo(size.width, y(ref.first));
    } else {
      line.moveTo(w / 2, y(ref.first));
      for (var i = 1; i < ref.length; i++) {
        line.lineTo(i * (w + gap) + w / 2, y(ref[i]));
      }
    }
    // stroke 2 · dash 5 5
    final dashed = Path();
    for (final m in line.computeMetrics()) {
      for (double d = 0; d < m.length; d += 10) {
        dashed.addPath(m.extractPath(d, math.min(d + 5, m.length)), Offset.zero);
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = WdColors.muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.values != values || old.baseline != baseline || old.highlight != highlight || old.reference != reference;
}

class WdSegmentRow {
  const WdSegmentRow(this.segment, this.pace, this.cadence, this.delta, {this.faster = true});

  final String segment;
  final String pace;
  final String cadence;

  /// 예: "8초 빠름"
  final String delta;

  /// false면 [delta]가 빨간색.
  final bool faster;
}

/// Analysis / Segment table — 구간 · 페이스 · 케이던스 · 고스트 대비.
class WdSegmentTable extends StatelessWidget {
  const WdSegmentTable({super.key, required this.rows, this.columns = const ['구간', '페이스', '케이던스', '고스트 대비']});

  final List<WdSegmentRow> rows;
  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    final cell = WdText.raw(12, FontWeight.w400, 18);
    return WdSurface(
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 13),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: WdSpace.s8,
        children: [
          _row([for (final c in columns) Text(c, style: WdText.section12.copyWith(color: WdColors.muted))]),
          for (final r in rows) ...[
            const Divider(height: 1, thickness: 1, color: WdColors.map),
            _row([
              Text(r.segment, style: WdText.raw(12, FontWeight.w500, 18).copyWith(color: WdColors.ink)),
              Text(r.pace, style: cell.copyWith(color: WdColors.ink)),
              Text(r.cadence, style: cell.copyWith(color: WdColors.muted)),
              Text(r.delta, style: cell.copyWith(color: r.faster ? WdColors.green : WdColors.negative)),
            ]),
          ],
        ],
      ),
    );
  }

  /// 첫 열은 왼쪽, 나머지는 오른쪽 정렬, 같은 너비.
  Widget _row(List<Widget> cells) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(child: Align(alignment: i == 0 ? Alignment.centerLeft : Alignment.centerRight, child: cells[i])),
          ],
        ),
      );
}
