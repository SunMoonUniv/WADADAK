package com.wadadak.run.internal.metrics;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.GpsQuality;
import com.wadadak.run.internal.RunContracts.*;
import java.util.ArrayList;
import java.util.List;

/** Versioned motion replay; PACE_V3 rejects isolated speed-inconsistent fixes. */
final class MotionPace {
    static boolean usesMotion(String version) {
        return "PACE_V2".equals(version) || "PACE_V3".equals(version);
    }
    private boolean balanced;
    private Input suspect;
    private Input rawPrevious;
    double distanceM;
    private long stoppedMs;
    final List<FreeRunCalculator.Travel> travels = new ArrayList<>();
    final List<FreeRunCalculator.Span> stops = new ArrayList<>();
    private Long stationarySince;
    private Input previous;
    private final List<Input> pending = new ArrayList<>();
    final List<List<GeoPoint>> segments = new ArrayList<>();
    final List<List<Input>> samples = new ArrayList<>();
    private List<Input> sampleSegment;
    private List<GeoPoint> segment;
    private boolean paused, ended;

    void add(Input p) {
        if (ended) return;
        if (p.kind() == Kind.START) balanced = "PACE_V3".equals(p.reason());
        if (!balanced || p.kind() == Kind.START || p.kind() == Kind.CADENCE ||
            p.kind() == Kind.BAROMETER || p.kind() == Kind.SEGMENT_END) {
            accept(p); return;
        }
        if (p.kind() != Kind.GPS || paused) {
            suspect = null; rawPrevious = null; accept(p); return;
        }
        // Check hard boundaries on consecutive RAW fixes before removing outliers.
        Input raw = rawPrevious;
        rawPrevious = GpsQuality.good(p) && p.accuracyM() <= 15 ? p : null;
        long dt = raw == null ? 0 : p.elapsedMs() - raw.elapsedMs();
        if (!GpsQuality.good(p) || p.accuracyM() > 15 ||
            (raw != null && (dt <= 0 || dt > GpsQuality.MAX_INTERVAL_MS ||
                distance(raw,p) * 1000 / dt > GpsQuality.MAX_SPEED_MPS))) {
            suspect = null;
            closeStop(previous == null ? null : previous.elapsedMs());
            resetWindow(); accept(p); return;
        }
        Input candidate = suspect;
        suspect = null;
        if (candidate != null) {
            if (previous != null && isolated(previous, candidate, p)) {
                accept(p); return;
            }
            accept(candidate);
        }
        if (previous != null && suspectLeg(previous, p)) {
            suspect = p; return;
        }
        accept(p);
    }
    private static boolean suspectLeg(Input a, Input b) {
        long dt = b.elapsedMs() - a.elapsedMs();
        if (!GpsQuality.good(a) || !GpsQuality.good(b) || a.accuracyM() > 15 || b.accuracyM() > 15 ||
            dt <= 0 || dt > 3000 || !reliableSpeed(a) || !reliableSpeed(b)) return false;
        double expected = (a.speedMps() + b.speedMps() + a.speedAccuracyMps() + b.speedAccuracyMps()) * .5 * dt / 1000;
        return distance(a,b) > expected + Math.max(6, a.accuracyM() + b.accuracyM());
    }
    private static boolean isolated(Input a, Input b, Input c) {
        if (!suspectLeg(b,c) || !GpsQuality.good(c) || !reliableSpeed(c)) return false;
        long dt = c.elapsedMs() - a.elapsedMs();
        double direct = distance(a,c);
        double expected = (a.speedMps() + c.speedMps() + a.speedAccuracyMps() + c.speedAccuracyMps()) * .5 * dt / 1000;
        return direct <= expected + Math.max(6, a.accuracyM() + c.accuracyM()) &&
            distance(a,b) + distance(b,c) - direct > Math.max(8, a.accuracyM() + b.accuracyM() + c.accuracyM());
    }
    private void accept(Input p) {
        if (ended) return;
        if (p.kind() != Kind.GPS) {
            // 코스 구간 종료(SEGMENT_END)는 코스 판정 경계일 뿐 자유 러닝 이동·정지와 무관하다
            if (p.kind() == Kind.START || p.kind() == Kind.CADENCE || p.kind() == Kind.BAROMETER || p.kind() == Kind.SEGMENT_END) return;
            closeStop(p.kind() == Kind.GAP ? previous == null ? null : previous.elapsedMs() : p.elapsedMs());
            resetWindow();
            if (p.kind() == Kind.PAUSE) paused = true;
            if (p.kind() == Kind.RESUME) paused = false;
            if (p.kind() == Kind.END) ended = true;
            return;
        }
        if (paused) return;
        if (!GpsQuality.good(p) || p.accuracyM() > 15) {
            closeStop(previous == null ? null : previous.elapsedMs()); resetWindow(); return;
        }
        if (previous != null) {
            long dt = p.elapsedMs() - previous.elapsedMs();
            if (dt <= 0 || dt > GpsQuality.MAX_INTERVAL_MS || distance(previous, p) / (dt / 1000.0) > GpsQuality.MAX_SPEED_MPS) {
                closeStop(previous.elapsedMs()); resetWindow();
            }
        }
        previous = p;
        if (pending.isEmpty()) { pending.add(p); return; }
        pending.add(p);
        Input anchor = pending.getFirst();
        long span = p.elapsedMs() - anchor.elapsedMs();
        double displacement = distance(anchor, p), path = 0;
        for (int i = 1; i < pending.size(); i++) path += distance(pending.get(i - 1), pending.get(i));
        boolean speedEvidence = pending.size() >= 3 && pending.subList(pending.size() - 3, pending.size())
            .stream().allMatch(f -> reliableSpeed(f) && f.speedMps() >= .3);
        boolean speedSaysStopped = pending.size() >= 3 && pending.subList(pending.size() - 3, pending.size())
            .stream().allMatch(f -> reliableSpeed(f) && f.speedMps() <= .2);
        double threshold = speedEvidence ? 3 : Math.max(5, anchor.accuracyM() + p.accuracyM());
        if (pending.size() >= 3 && span >= 2000 && anchor.accuracyM() <= 15 && p.accuracyM() <= 15 &&
            !speedSaysStopped && (speedEvidence ? path + .001 >= threshold :
                displacement + .001 >= threshold && path > 0 && displacement / path >= .7)) {
            closeStop(anchor.elapsedMs());
            if (segment == null) {
                segment = new ArrayList<>(); segment.add(anchor.location()); segments.add(segment);
                sampleSegment = new ArrayList<>(); sampleSegment.add(anchor); samples.add(sampleSegment);
            }
            for (int i = 1; i < pending.size(); i++) {
                double d = distance(pending.get(i - 1), pending.get(i));
                distanceM += d; segment.add(pending.get(i).location());
                sampleSegment.add(pending.get(i));
                travels.add(new FreeRunCalculator.Travel(pending.get(i-1).elapsedMs(),pending.get(i).elapsedMs(),d));
            }
            pending.clear(); pending.add(p); return;
        }
        double radius = Math.max(3, Math.min(6, anchor.accuracyM()));
        boolean confined = pending.stream().allMatch(f -> f.accuracyM() <= 15 && distance(anchor, f) <= radius);
        boolean speedSaysMoving = pending.subList(Math.max(0, pending.size() - 3), pending.size()).stream()
            .anyMatch(f -> reliableSpeed(f) && f.speedMps() >= .3) ||
            (!speedSaysStopped && span >= 2000 && displacement >= Math.max(1.5, radius * .5) && path > 0 &&
             displacement / path >= .7 && displacement / (span / 1000.0) >= .3);
        if (pending.size() >= 3 && span >= 5000 && confined && !speedSaysMoving) {
            if (stationarySince == null) stationarySince = anchor.elapsedMs();
            segment = null; pending.clear(); pending.add(p);
        } else if (span > 10000 || pending.size() > 30) {
            closeStop(anchor.elapsedMs()); resetWindow(); previous = p; pending.add(p);
        }
    }
    private static double distance(Input a, Input b) { return FreeRunCalculator.distance(a.location(), b.location()); }
    private static boolean reliableSpeed(Input p) {
        return p.speedMps() != null && p.speedAccuracyMps() != null && Double.isFinite(p.speedMps()) &&
            p.speedMps() >= 0 && p.speedMps() <= 12 && Double.isFinite(p.speedAccuracyMps()) &&
            p.speedAccuracyMps() > 0 && p.speedAccuracyMps() <= .5;
    }
    private void closeStop(Long ms) {
        if (stationarySince != null && ms != null) {
            long knownEnd = previous == null ? ms : Math.min(ms, previous.elapsedMs() + 10000);
            stoppedMs += Math.max(0, knownEnd - stationarySince);
            if (knownEnd > stationarySince) stops.add(new FreeRunCalculator.Span(stationarySince,knownEnd));
        }
        stationarySince = null;
    }
    private void resetWindow() { pending.clear(); previous = null; segment = null; }
    long stoppedBefore(long ms) { return stops.stream().mapToLong(s -> s.before(ms)).sum(); }
    long movingMs(long ms, long activeMs) {
        long stopEnd = previous == null ? ms : Math.min(ms, previous.elapsedMs() + 10000);
        long ongoing = stationarySince == null ? 0 : Math.max(0, stopEnd - stationarySince);
        return Math.clamp(activeMs - stoppedMs - ongoing, 0, activeMs);
    }
}
