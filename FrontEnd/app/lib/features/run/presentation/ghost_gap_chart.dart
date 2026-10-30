import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../domain/ghost_comparison.dart';

class GhostGapChart extends StatelessWidget {
  const GhostGapChart({
    super.key,
    required this.segments,
    required this.distanceM,
  });
  final List<GhostComparisonSegment> segments;
  final int distanceM;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '경계별 누적 시간 차이. 상세 값은 구간별 결과에서 확인할 수 있어요.',
    child: WdSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            height: 156,
            width: double.infinity,
            child: CustomPaint(painter: _GapPainter(segments, distanceM)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('출발', style: WdText.ko12),
              Text(
                '${(distanceM / 1000).toStringAsFixed(2)}km',
                style: WdText.ko12,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _GapPainter extends CustomPainter {
  _GapPainter(this.segments, this.distanceM);
  final List<GhostComparisonSegment> segments;
  final int distanceM;
  @override
  void paint(Canvas canvas, Size size) {
    final max = segments.fold<double>(
      5,
      (v, s) => math.max(v, (s.cumulative ?? 0).abs().toDouble()),
    );
    final mid = size.height / 2;
    final axis = Paint()
      ..color = WdColors.muted.withValues(alpha: .35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), axis);
    final line = Paint()
      ..color = WdColors.green
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    Offset? previous = Offset(0, mid);
    for (final s in segments) {
      if (s.cumulative == null) {
        previous = null;
        continue;
      }
      final point = Offset(
        size.width * s.toM / distanceM,
        mid - s.cumulative! / max * (mid - 14),
      );
      if (previous != null) canvas.drawLine(previous, point, line);
      canvas.drawCircle(point, 3, Paint()..color = WdColors.green);
      previous = point;
    }
    for (final (text, y) in [
      ('+${max.ceil()}초', 0.0),
      ('0', mid + 2),
      ('−${max.ceil()}초', size.height - 14),
    ]) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: WdText.ko12.copyWith(color: WdColors.muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(0, y));
    }
  }

  @override
  bool shouldRepaint(covariant _GapPainter old) =>
      old.segments != segments || old.distanceM != distanceM;
}
