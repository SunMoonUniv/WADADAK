package com.wadadak.run.internal.metrics;

import com.wadadak.run.internal.RunContracts.*;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** RESULT_V2. Keep thresholds, interpolation and tie handling identical to Dart. */
public final class RunResultStatsCalculator {
    public static final String VERSION = "RESULT_V2";
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
        return new ResultStats(VERSION, measured ? gain : null,
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
        List<Double> errors = new ArrayList<>();
        List<Double> distances = new ArrayList<>();
        int low = 0, high = 0;
        for (Input p : points) {
            while (points.get(low).elapsedMs() < p.elapsedMs() - 2500) low++;
            while (high < points.size() && points.get(high).elapsedMs() <= p.elapsedMs() + 2500) high++;
            List<Double> window = new ArrayList<>();
            Double error = 0.0;
            for (int i = low; i < high; i++) {
                window.add(points.get(i).altitudeM());
                Double accuracy = points.get(i).altitudeAccuracyM();
                if (accuracy == null || accuracy <= 0) error = null;
                else if (error != null) error = Math.max(error, accuracy);
            }
            window.sort(Comparator.naturalOrder());
            int m = window.size() / 2;
            heights.add(window.size() % 2 == 1 ? window.get(m) : (window.get(m - 1) + window.get(m)) / 2);
            errors.add(error);
            int index = heights.size() - 1;
            distances.add(index == 0 ? 0.0 : distances.getLast() + FreeRunCalculator.distance(points.get(index - 1).location(), p.location()));
        }
        double total = 0;
        int initialEnd = -1;
        for (int i = 0; i < points.size(); i++) if (points.get(i).elapsedMs() - points.getFirst().elapsedMs() >= 5000) { initialEnd = i; break; }
        boolean steadyStart = initialEnd >= 0 && steadyRise(points,distances,heights,0,initialEnd);
        Integer valley = null, peak = null;
        int stableStart = 0;
        boolean rising = false;
        for (int i = 0; i < heights.size(); i++) {
            while (stableStart + 1 <= i && points.get(stableStart + 1).elapsedMs() <= points.get(i).elapsedMs() - 5000) stableStart++;
            if (points.get(i).elapsedMs() - points.getFirst().elapsedMs() < 5000 || i - stableStart + 1 < 3) continue;
            int floor = stableStart, crest = stableStart;
            for (int j = stableStart + 1; j <= i; j++) {
                if (heights.get(j) > heights.get(floor)) floor = j;
                if (heights.get(j) < heights.get(crest)) crest = j;
            }
            if (valley == null) valley = steadyStart ? 0 : floor;
            if (peak == null) peak = crest;
            if (!rising) {
                if (heights.get(floor) < heights.get(valley)) valley = floor;
                if (heights.get(crest) - heights.get(valley) >= threshold(errors,valley,crest) && supported(points,distances,valley,crest)) {
                    rising = true; peak = crest;
                }
            } else {
                if (heights.get(crest) > heights.get(peak)) peak = crest;
                if (heights.get(peak) - heights.get(floor) >= threshold(errors,peak,floor) && supported(points,distances,peak,floor)) {
                    if (heights.get(peak) - heights.get(valley) >= threshold(errors,valley,peak)) total += heights.get(peak) - heights.get(valley);
                    valley = floor; peak = crest; rising = false;
                }
            }
        }
        int last = heights.size() - 1;
        if (valley != null && steadyRise(points,distances,heights,stableStart,last) &&
            heights.get(last) - heights.get(valley) >= threshold(errors,valley,last) && supported(points,distances,valley,last)) {
            if (!rising || peak == null || heights.get(last) > heights.get(peak)) { rising = true; peak = last; }
        }
        return total + (rising && peak != null && valley != null && heights.get(peak) - heights.get(valley) >= threshold(errors,valley,peak)
            ? heights.get(peak) - heights.get(valley) : 0);
    }
    private static double threshold(List<Double> errors, int a, int b) {
        return Math.max(errors.get(a) == null || errors.get(b) == null ? 10 : 1.5,
            (errors.get(a) == null ? 0 : errors.get(a)) + (errors.get(b) == null ? 0 : errors.get(b)));
    }
    private static boolean supported(List<Input> points, List<Double> distances, int from, int to) {
        return points.get(to).elapsedMs() - points.get(from).elapsedMs() >= 5000 && distances.get(to) - distances.get(from) >= 5;
    }
    private static boolean steadyRise(List<Input> points, List<Double> distances, List<Double> heights, int from, int to) {
        if (!supported(points,distances,from,to)) return false;
        int increases = 0;
        Integer firstIncrease = null;
        int lastIncrease = from;
        for (int j = from + 1; j <= to; j++) {
            double delta = heights.get(j) - heights.get(j - 1);
            if (delta < -.05) return false;
            if (delta > .01) {
                if (firstIncrease == null) firstIncrease = j - 1;
                lastIncrease = j; increases++;
            }
        }
        return increases >= 3 && firstIncrease != null &&
            points.get(lastIncrease).elapsedMs() - points.get(firstIncrease).elapsedMs() >= 5000;
    }
}
