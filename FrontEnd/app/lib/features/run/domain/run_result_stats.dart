import 'dart:math' as math;

import 'recording_models.dart' as recording;
import 'motion_pace.dart';
import 'run_lap.dart';

/// RESULT_V3 adds barometric elevation only; historical distance/time/laps stay intact.
class RunResultStats {
  static const currentVersion = 'RESULT_V3';
  const RunResultStats({
    this.version = currentVersion,
    this.elevationGainM,
    this.elevationPartial = false,
    this.elevationSource,
    this.bestLapNumber,
    this.bestLapPaceSecondsPerKm,
    this.bestPaceSecondsPerKm,
  });
  final String version;
  final String? elevationSource;
  final double? elevationGainM, bestLapPaceSecondsPerKm, bestPaceSecondsPerKm;
  final bool elevationPartial;
  final int? bestLapNumber;

  factory RunResultStats.fromJson(Map<String, dynamic> j) => RunResultStats(
    version: j['version'] as String? ?? 'RESULT_V1',
    elevationGainM: (j['elevationGainM'] as num?)?.toDouble(),
    elevationPartial: j['elevationPartial'] == true,
    elevationSource: j['elevationSource'] as String?,
    bestLapNumber: (j['bestLapNumber'] as num?)?.toInt(),
    bestLapPaceSecondsPerKm: (j['bestLapPaceSecondsPerKm'] as num?)?.toDouble(),
    bestPaceSecondsPerKm: (j['bestPaceSecondsPerKm'] as num?)?.toDouble(),
  );
  Map<String, dynamic> toJson() => {
    'version': version,
    'elevationGainM': elevationGainM,
    'elevationPartial': elevationPartial,
    'elevationSource': elevationSource,
    'bestLapNumber': bestLapNumber,
    'bestLapPaceSecondsPerKm': bestLapPaceSecondsPerKm,
    'bestPaceSecondsPerKm': bestPaceSecondsPerKm,
  };

  static RunResultStats calculate(
    List<recording.RunInput> inputs,
    List<List<recording.RunInput>> segments,
    List<RunLap> laps, {
    bool elevationOnly = false,
  }) {
    // Old records keep their original distance/time/laps, but new vertical and
    // 30-second stats still require positively confirmed continuous movement.
    if (!MotionPace.usesMotion(inputs.firstOrNull?.reason)) {
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
    var measured = false, usedPressure = false, usedGps = false;
    final pressure = _pressureSamples(inputs);
    var pressureIndex = 0;
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

      if (!elevationOnly) {
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
      }

      // Select one source per continuous movement segment, never join datum offsets.
      while (pressureIndex < pressure.length &&
          pressure[pressureIndex].sampleEndMs! < segment.first.elapsedMs) {
        pressureIndex++;
      }
      final pressureStart = pressureIndex;
      while (pressureIndex < pressure.length &&
          pressure[pressureIndex].sampleEndMs! <= segment.last.elapsedMs) {
        pressureIndex++;
      }
      final barometer = _barometerElevation(
        pressure.sublist(pressureStart, pressureIndex),
        distanceAt,
      );
      if (barometer.gainM != null) {
        measured = true;
        usedPressure = true;
        coveredDistance += barometer.coveredM;
        gain += barometer.gainM!;
        continue;
      }
      var block = <recording.RunInput>[];
      var blockDistance = 0.0;
      void finishBlock() {
        if (block.length >= 3 &&
            block.last.elapsedMs - block.first.elapsedMs >= 2000) {
          measured = true;
          usedGps = true;
          coveredDistance += blockDistance;
          gain += _gain(_gpsPoints(block));
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
      elevationSource: usedPressure
          ? (usedGps ? 'MIXED' : 'BAROMETER')
          : (usedGps ? 'GPS' : null),
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
    final v2 = MotionPace.usesMotion(inputs.firstOrNull?.reason);
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

  static List<recording.RunInput> _pressureSamples(
    List<recording.RunInput> inputs,
  ) {
    final samples = <recording.RunInput>[];
    var paused = false, boundary = 0, previous = -1;
    for (final p in inputs) {
      if (p.kind == recording.RunKind.pause) paused = true;
      if (p.kind == recording.RunKind.resume) paused = false;
      if (p.kind == recording.RunKind.pause ||
          p.kind == recording.RunKind.resume ||
          p.kind == recording.RunKind.gap) {
        boundary = p.elapsedMs;
      }
      if (p.kind != recording.RunKind.barometer || paused) continue;
      final ms = p.sampleEndMs;
      if (ms == null ||
          ms < boundary ||
          ms <= previous ||
          ms > p.elapsedMs ||
          p.elapsedMs - ms > 2000) {
        continue;
      }
      previous = ms;
      samples.add(p);
    }
    return samples;
  }

  static _ElevationResult _barometerElevation(
    List<recording.RunInput> samples,
    double Function(int) distanceAt,
  ) {
    var block = <_ElevationPoint>[];
    var gain = 0.0, covered = 0.0;
    var measured = false;
    void finish() {
      if (block.length >= 3 &&
          block.last.elapsedMs - block.first.elapsedMs >= 2000) {
        measured = true;
        gain += _gain(block, barometric: true);
        covered += block.last.distanceM - block.first.distanceM;
      }
      block = [];
    }

    for (final p in samples) {
      final pressure = p.pressureHpa;
      final accuracy = p.pressureAccuracy;
      if (pressure == null ||
          !pressure.isFinite ||
          pressure < 300 ||
          pressure > 1100 ||
          accuracy == null ||
          accuracy < 1 ||
          accuracy > 3) {
        finish();
        continue;
      }
      // Standard atmosphere is sufficient for differences; this is not GPS altitude.
      final height = 44330.0 * (1 - math.pow(pressure / 1013.25, 1 / 5.255));
      final ms = p.sampleEndMs!;
      if (block.isNotEmpty) {
        final dt = ms - block.last.elapsedMs;
        if (dt <= 0 ||
            dt > 10000 ||
            (height - block.last.height).abs() * 1000 / dt > 3) {
          finish();
          continue;
        }
      }
      block.add(_ElevationPoint(ms, height, null, distanceAt(ms)));
    }
    finish();
    return _ElevationResult(measured ? gain : null, covered);
  }

  static List<_ElevationPoint> _gpsPoints(List<recording.RunInput> points) {
    var distance = 0.0;
    return [
      for (var i = 0; i < points.length; i++)
        _ElevationPoint(
          points[i].elapsedMs,
          points[i].altitudeM!,
          points[i].altitudeAccuracyM,
          i == 0 ? 0 : distance += points[i - 1].distanceTo(points[i]),
        ),
    ];
  }

  static double _gain(List<_ElevationPoint> points, {bool barometric = false}) {
    // Keep the 5s median and persistence checks for both sources. GPS also
    // requires a rise exceeding its endpoint errors; pressure uses 1.5m.
    var low = 0, high = 0;
    final heights = <double>[];
    final errors = <double?>[];
    final distances = <double>[];
    for (final p in points) {
      while (points[low].elapsedMs < p.elapsedMs - 2500) {
        low++;
      }
      while (high < points.length &&
          points[high].elapsedMs <= p.elapsedMs + 2500) {
        high++;
      }
      final samples = points.sublist(low, high);
      final window = samples.map((p) => p.height).toList()..sort();
      final m = window.length ~/ 2;
      heights.add(
        window.length.isOdd ? window[m] : (window[m - 1] + window[m]) / 2,
      );
      // Missing/zero accuracy is unknown, not perfect precision. Use the largest
      // reported error in the smoothing window rather than averaging it away.
      errors.add(
        samples.any((p) => p.accuracyM == null || p.accuracyM! <= 0)
            ? null
            : samples.map((p) => p.accuracyM!).reduce(math.max),
      );
      distances.add(p.distanceM);
    }
    double threshold(int a, int b) => barometric
        ? 1.5
        : math.max(
            errors[a] == null || errors[b] == null ? 10 : 1.5,
            (errors[a] ?? 0) + (errors[b] ?? 0),
          );
    bool supported(int from, int to) =>
        points[to].elapsedMs - points[from].elapsedMs >= 5000 &&
        distances[to] - distances[from] >= 5;
    bool steadyRise(int from, int to) {
      if (!supported(from, to)) return false;
      var increases = 0;
      int? firstIncrease;
      var lastIncrease = from;
      for (var j = from + 1; j <= to; j++) {
        final delta = heights[j] - heights[j - 1];
        if (delta < -.05) return false;
        if (delta > .01) {
          firstIncrease ??= j - 1;
          lastIncrease = j;
          increases++;
        }
      }
      return increases >= 3 &&
          firstIncrease != null &&
          points[lastIncrease].elapsedMs - points[firstIncrease].elapsedMs >=
              5000;
    }

    final initialEnd = points.indexWhere(
      (p) => p.elapsedMs - points.first.elapsedMs >= 5000,
    );
    final steadyStart = initialEnd >= 0 && steadyRise(0, initialEnd);
    int? valley, peak;
    var total = 0.0, stableStart = 0;
    var rising = false;
    for (var i = 0; i < heights.length; i++) {
      while (stableStart + 1 <= i &&
          points[stableStart + 1].elapsedMs <= points[i].elapsedMs - 5000) {
        stableStart++;
      }
      if (points[i].elapsedMs - points.first.elapsedMs < 5000 ||
          i - stableStart + 1 < 3) {
        continue;
      }
      // A trough must stay low and a summit stay high over the trailing 5s.
      // This rejects short downward spikes as well as short upward spikes.
      var floor = stableStart, crest = stableStart;
      for (var j = stableStart + 1; j <= i; j++) {
        if (heights[j] > heights[floor]) floor = j;
        if (heights[j] < heights[crest]) crest = j;
      }
      valley ??= steadyStart ? 0 : floor;
      peak ??= crest;
      if (!rising) {
        if (heights[floor] < heights[valley]) {
          valley = floor;
        }
        if (heights[crest] - heights[valley] >= threshold(valley, crest) &&
            supported(valley, crest)) {
          rising = true;
          peak = crest;
        }
      } else {
        if (heights[crest] > heights[peak]) peak = crest;
        if (heights[peak] - heights[floor] >= threshold(peak, floor) &&
            supported(peak, floor)) {
          if (heights[peak] - heights[valley] >= threshold(valley, peak)) {
            total += heights[peak] - heights[valley];
          }
          valley = floor;
          peak = crest;
          rising = false;
        }
      }
    }
    // Preserve a measured ramp that starts/ends with the run, where a complete
    // stable plateau cannot exist. Require 3 separate increases over 5s/5m;
    // a single step or short burst cannot satisfy this edge-only exception.
    final last = heights.length - 1;
    if (valley != null &&
        steadyRise(stableStart, last) &&
        heights[last] - heights[valley] >= threshold(valley, last) &&
        supported(valley, last)) {
      if (!rising || peak == null || heights[last] > heights[peak]) {
        rising = true;
        peak = last;
      }
    }
    return total +
        (rising &&
                peak != null &&
                valley != null &&
                heights[peak] - heights[valley] >= threshold(valley, peak)
            ? heights[peak] - heights[valley]
            : 0);
  }
}

class _ElevationPoint {
  const _ElevationPoint(
    this.elapsedMs,
    this.height,
    this.accuracyM,
    this.distanceM,
  );
  final int elapsedMs;
  final double height, distanceM;
  final double? accuracyM;
}

class _ElevationResult {
  const _ElevationResult(this.gainM, this.coveredM);
  final double? gainM;
  final double coveredM;
}
