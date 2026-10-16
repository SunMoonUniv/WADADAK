import 'dart:math' as math;

import 'recording_models.dart' as recording;
import 'motion_pace.dart';
import 'run_lap.dart';

/// RESULT_V1 is independent of PACE_V2: historical distance is never rewritten.
class RunResultStats {
  const RunResultStats({
    this.elevationGainM,
    this.elevationPartial = false,
    this.bestLapNumber,
    this.bestLapPaceSecondsPerKm,
    this.bestPaceSecondsPerKm,
  });
  final double? elevationGainM, bestLapPaceSecondsPerKm, bestPaceSecondsPerKm;
  final bool elevationPartial;
  final int? bestLapNumber;

  factory RunResultStats.fromJson(Map<String, dynamic> j) => RunResultStats(
    elevationGainM: (j['elevationGainM'] as num?)?.toDouble(),
    elevationPartial: j['elevationPartial'] == true,
    bestLapNumber: (j['bestLapNumber'] as num?)?.toInt(),
    bestLapPaceSecondsPerKm: (j['bestLapPaceSecondsPerKm'] as num?)?.toDouble(),
    bestPaceSecondsPerKm: (j['bestPaceSecondsPerKm'] as num?)?.toDouble(),
  );
  Map<String, dynamic> toJson() => {
    'version': 'RESULT_V1',
    'elevationGainM': elevationGainM,
    'elevationPartial': elevationPartial,
    'bestLapNumber': bestLapNumber,
    'bestLapPaceSecondsPerKm': bestLapPaceSecondsPerKm,
    'bestPaceSecondsPerKm': bestPaceSecondsPerKm,
  };

  static RunResultStats calculate(
    List<recording.RunInput> inputs,
    List<List<recording.RunInput>> segments,
    List<RunLap> laps,
  ) {
    // Old records keep their original distance/time/laps, but new vertical and
    // 30-second stats still require positively confirmed continuous movement.
    if (inputs.firstOrNull?.reason != 'PACE_V2') {
      final motion = MotionPace();
      for (final p in inputs) {
        motion.add(p);
      }
      segments = motion.segments;
    }
    final gaps = _gapTimes(inputs);
    RunLap? best;
    var lapStart = 0;
    for (final lap in laps) {
      final end = lapStart + lap.elapsedMs;
      final pace = lap.paceSecondsPerKm;
      if (lap.complete &&
          pace != null &&
          pace > 0 &&
          !gaps.any((t) => t > lapStart && t <= end) &&
          (best == null || pace < best.paceSecondsPerKm! - 1e-9)) {
        best = lap;
      }
      lapStart = end;
    }

    double? bestPace;
    var totalDistance = 0.0, coveredDistance = 0.0, gain = 0.0;
    var measured = false;
    for (final segment in segments) {
      // Each segment is already confirmed movement, split at stops/pauses/gaps.
      final distances = <double>[0];
      for (var i = 1; i < segment.length; i++) {
        distances.add(distances.last + segment[i - 1].distanceTo(segment[i]));
      }
      if (segment.isEmpty) continue;
      totalDistance += distances.last;
      double distanceAt(int ms) {
        var lo = 0, hi = segment.length - 1;
        while (lo < hi) {
          final mid = (lo + hi + 1) ~/ 2;
          if (segment[mid].elapsedMs <= ms) {
            lo = mid;
          } else {
            hi = mid - 1;
          }
        }
        if (lo == segment.length - 1) return distances[lo];
        final a = segment[lo].elapsedMs, b = segment[lo + 1].elapsedMs;
        return distances[lo] +
            (distances[lo + 1] - distances[lo]) * (ms - a) / (b - a);
      }

      for (final p in segment) {
        // Both ends of each linear piece are candidates for the maximum window.
        for (final end in [p.elapsedMs, p.elapsedMs + 30000]) {
          if (end > segment.last.elapsedMs ||
              end - 30000 < segment.first.elapsedMs) {
            continue;
          }
          final d = distanceAt(end) - distanceAt(end - 30000);
          if (d > 0) {
            final pace = 30000 / d;
            if (bestPace == null || pace < bestPace) bestPace = pace;
          }
        }
      }

      var block = <recording.RunInput>[];
      var blockDistance = 0.0;
      void finishBlock() {
        if (block.length >= 3 &&
            block.last.elapsedMs - block.first.elapsedMs >= 2000) {
          measured = true;
          coveredDistance += blockDistance;
          gain += _gain(block);
        }
        block = [];
        blockDistance = 0;
      }

      for (final p in segment) {
        final accuracy = p.altitudeAccuracyM;
        final usable =
            p.altitudeM != null &&
            p.altitudeM!.isFinite &&
            (accuracy == null ||
                (accuracy.isFinite && accuracy >= 0 && accuracy <= 20));
        if (!usable) {
          finishBlock();
          continue;
        }
        if (block.isNotEmpty) {
          final previous = block.last;
          final dt = p.elapsedMs - previous.elapsedMs;
          final delta = (p.altitudeM! - previous.altitudeM!).abs();
          final uncertainty =
              (accuracy ?? 0) + (previous.altitudeAccuracyM ?? 0);
          if (dt <= 0 ||
              dt > 10000 ||
              (delta > math.max(10, uncertainty) && delta * 1000 / dt > 3)) {
            finishBlock();
            // Do not use an isolated jump as the next baseline.
            continue;
          }
          blockDistance += previous.distanceTo(p);
        }
        block.add(p);
      }
      finishBlock();
    }
    return RunResultStats(
      elevationGainM: measured ? gain : null,
      elevationPartial:
          measured &&
          (gaps.isNotEmpty || coveredDistance + .001 < totalDistance),
      bestLapNumber: best?.number,
      bestLapPaceSecondsPerKm: best?.paceSecondsPerKm,
      bestPaceSecondsPerKm: bestPace,
    );
  }

  static List<int> _gapTimes(List<recording.RunInput> inputs) {
    final result = <int>[];
    final v2 = inputs.firstOrNull?.reason == 'PACE_V2';
    recording.RunInput? previous;
    var paused = false;
    for (final p in inputs) {
      if (p.kind == recording.RunKind.pause) {
        paused = true;
        previous = null;
      }
      if (p.kind == recording.RunKind.resume) {
        paused = false;
        previous = null;
      }
      if (p.kind == recording.RunKind.gap) {
        if (!paused) result.add(p.elapsedMs);
        previous = null;
      }
      if (p.kind != recording.RunKind.gps || paused) continue;
      if (!p.good || (v2 && p.accuracyM! > 15)) {
        result.add(p.elapsedMs);
        previous = null;
        continue;
      }
      if (previous != null) {
        final dt = p.elapsedMs - previous.elapsedMs;
        if (dt <= 0 || dt > 10000 || previous.distanceTo(p) * 1000 / dt > 12) {
          // The unknown interval belongs to every lap that overlaps it.
          result.add(previous.elapsedMs + 1);
          result.add(p.elapsedMs);
        }
      }
      previous = p;
    }
    return result;
  }

  static double _gain(List<recording.RunInput> points) {
    // Centred 5-second median; a 10m reversal closes an ascent. Small dips are
    // ignored, and the entire confirmed rise (not just its excess) is counted.
    var low = 0, high = 0;
    final heights = <double>[];
    for (final p in points) {
      while (points[low].elapsedMs < p.elapsedMs - 2500) {
        low++;
      }
      while (high < points.length &&
          points[high].elapsedMs <= p.elapsedMs + 2500) {
        high++;
      }
      final window = points.sublist(low, high).map((p) => p.altitudeM!).toList()
        ..sort();
      final m = window.length ~/ 2;
      heights.add(
        window.length.isOdd ? window[m] : (window[m - 1] + window[m]) / 2,
      );
    }
    var valley = heights.first, peak = heights.first, total = 0.0;
    var rising = false;
    for (final h in heights.skip(1)) {
      if (!rising) {
        valley = math.min(valley, h);
        if (h - valley >= 10) {
          rising = true;
          peak = h;
        }
      } else {
        peak = math.max(peak, h);
        if (peak - h >= 10) {
          total += peak - valley;
          valley = h;
          rising = false;
        }
      }
    }
    return total + (rising ? peak - valley : 0);
  }
}
