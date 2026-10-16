package com.wadadak.run.internal;

import com.wadadak.run.RunContracts.*;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** RESULT_V1. Keep thresholds, interpolation and tie handling identical to Dart. */
final class RunResultStatsCalculator {
    static ResultStats calculate(List<Input> inputs, List<List<Input>> segments, List<Lap> laps) {
        if (inputs.isEmpty() || !"PACE_V2".equals(inputs.getFirst().reason())) {
            MotionPace motion = new MotionPace();
            for (Input p : inputs) motion.add(p);
            segments = motion.samples;
        }
        List<Long> gaps = gapTimes(inputs);
        Lap best = null;
        long lapStart = 0;
        for (Lap lap : laps) {
            long end = lapStart + lap.elapsedMs();
            boolean gap = false;
            for (long t : gaps) if (t > lapStart && t <= end) { gap = true; break; }
            Double pace = lap.paceSecondsPerKm();
            if (lap.complete() && pace != null && pace > 0 && !gap &&
                (best == null || pace < best.paceSecondsPerKm() - 1e-9)) best = lap;
            lapStart = end;
        }
        Double bestPace = null;
        double distance = 0, covered = 0, gain = 0;
        boolean measured = false;
        for (List<Input> segment : segments) {
            if (segment.isEmpty()) continue;
            double[] distances = new double[segment.size()];
            for (int i = 1; i < segment.size(); i++)
                distances[i] = distances[i - 1] + FreeRunCalculator.distance(segment.get(i - 1).location(), segment.get(i).location());
            distance += distances[distances.length - 1];
            for (Input p : segment) {
                for (long end : new long[] {p.elapsedMs(), p.elapsedMs() + 30000}) {
                    if (end > segment.getLast().elapsedMs() || end - 30000 < segment.getFirst().elapsedMs()) continue;
                    double d = distanceAt(segment, distances, end) - distanceAt(segment, distances, end - 30000);
                    if (d > 0) {
                        double pace = 30000 / d;
                        if (bestPace == null || pace < bestPace) bestPace = pace;
                    }
                }
            }
            List<Input> block = new ArrayList<>();
            double blockDistance = 0;
            // The sentinel closes the last altitude block without joining segments.
            for (int i = 0; i <= segment.size(); i++) {
                Input p = i == segment.size() ? null : segment.get(i);
                Double accuracy = p == null ? null : p.altitudeAccuracyM();
                boolean usable = p != null && p.altitudeM() != null && Double.isFinite(p.altitudeM()) &&
                    (accuracy == null || (Double.isFinite(accuracy) && accuracy >= 0 && accuracy <= 20));
                boolean jump = false;
                if (usable && !block.isEmpty()) {
                    Input previous = block.getLast();
                    long dt = p.elapsedMs() - previous.elapsedMs();
                    double delta = Math.abs(p.altitudeM() - previous.altitudeM());
                    double uncertainty = (accuracy == null ? 0 : accuracy) +
                        (previous.altitudeAccuracyM() == null ? 0 : previous.altitudeAccuracyM());
                    jump = dt <= 0 || dt > 10000 || (delta > Math.max(10, uncertainty) && delta * 1000 / dt > 3);
                }
                if (!usable || jump) {
                    if (block.size() >= 3 && block.getLast().elapsedMs() - block.getFirst().elapsedMs() >= 2000) {
                        measured = true; covered += blockDistance; gain += gain(block);
                    }
                    block.clear(); blockDistance = 0;
                    continue;
                }
                if (!block.isEmpty()) blockDistance += FreeRunCalculator.distance(block.getLast().location(), p.location());
                block.add(p);
            }
        }
        return new ResultStats("RESULT_V1", measured ? gain : null,
            measured && (!gaps.isEmpty() || covered + .001 < distance), best == null ? null : best.number(),
            best == null ? null : best.paceSecondsPerKm(), bestPace);
    }

    private static double distanceAt(List<Input> points, double[] distances, long ms) {
        int lo = 0, hi = points.size() - 1;
        while (lo < hi) {
            int mid = (lo + hi + 1) / 2;
            if (points.get(mid).elapsedMs() <= ms) lo = mid; else hi = mid - 1;
        }
        if (lo == points.size() - 1) return distances[lo];
        long a = points.get(lo).elapsedMs(), b = points.get(lo + 1).elapsedMs();
        return distances[lo] + (distances[lo + 1] - distances[lo]) * (ms - a) / (b - a);
    }

    private static List<Long> gapTimes(List<Input> inputs) {
        List<Long> result = new ArrayList<>();
        boolean v2 = !inputs.isEmpty() && "PACE_V2".equals(inputs.getFirst().reason()), paused = false;
        Input previous = null;
        for (Input p : inputs) {
            if (p.kind() == Kind.PAUSE) { paused = true; previous = null; }
            if (p.kind() == Kind.RESUME) { paused = false; previous = null; }
            if (p.kind() == Kind.GAP) { if (!paused) result.add(p.elapsedMs()); previous = null; }
            if (p.kind() != Kind.GPS || paused) continue;
            if (!FreeRunCalculator.good(p) || (v2 && p.accuracyM() > 15)) {
                result.add(p.elapsedMs()); previous = null; continue;
            }
            if (previous != null) {
                long dt = p.elapsedMs() - previous.elapsedMs();
                if (dt <= 0 || dt > 10000 || FreeRunCalculator.distance(previous.location(), p.location()) * 1000 / dt > 12) {
                    result.add(previous.elapsedMs() + 1); result.add(p.elapsedMs());
                }
            }
            previous = p;
        }
        return result;
    }

    private static double gain(List<Input> points) {
        List<Double> heights = new ArrayList<>();
        int low = 0, high = 0;
        for (Input p : points) {
            while (points.get(low).elapsedMs() < p.elapsedMs() - 2500) low++;
            while (high < points.size() && points.get(high).elapsedMs() <= p.elapsedMs() + 2500) high++;
            List<Double> window = new ArrayList<>();
            for (int i = low; i < high; i++) window.add(points.get(i).altitudeM());
            window.sort(Comparator.naturalOrder());
            int m = window.size() / 2;
            heights.add(window.size() % 2 == 1 ? window.get(m) : (window.get(m - 1) + window.get(m)) / 2);
        }
        double valley = heights.getFirst(), peak = valley, total = 0;
        boolean rising = false;
        for (double h : heights.subList(1, heights.size())) {
            if (!rising) {
                valley = Math.min(valley, h);
                if (h - valley >= 10) { rising = true; peak = h; }
            } else {
                peak = Math.max(peak, h);
                if (peak - h >= 10) { total += peak - valley; valley = h; rising = false; }
            }
        }
        return total + (rising ? peak - valley : 0);
    }
}
