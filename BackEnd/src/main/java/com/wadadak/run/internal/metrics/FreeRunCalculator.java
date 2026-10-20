package com.wadadak.run.internal.metrics;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.GpsQuality;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.RunErrorCode;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

public final class FreeRunCalculator {
    public record Calculation(Metrics metrics, List<List<GeoPoint>> segments, Instant endedAt, String endReason, List<Lap> laps, ResultStats stats) {}
    record Travel(long start, long end, double distance) {}
    record Span(long start, long end) { long before(long ms) { return Math.clamp(ms-start,0,end-start); } }
    private static long movingAt(long ms, List<Span> pauses, MotionPace motion, boolean v2) {
        return Math.max(0,ms-pauses.stream().mapToLong(p -> p.before(ms)).sum()-(v2?motion.stoppedBefore(ms):0));
    }
    private static List<Lap> laps(List<Travel> travels, double distanceM, long lastMs, List<Span> pauses, MotionPace motion, boolean v2) {
        List<Lap> laps = new ArrayList<>();
        double distance = 0;
        long lastEnd = 0, lastMoving = 0;
        for (Travel t: travels) {
            double boundary = (laps.size()+1)*1000.0;
            while (t.distance()>0 && boundary <= distance+t.distance()+.000001) {
                double fraction = Math.clamp((boundary-distance)/t.distance(),0,1);
                long ms = Math.round(t.start()+(t.end()-t.start())*fraction);
                long moving = movingAt(ms,pauses,motion,v2);
                long duration = Math.max(0,moving-lastMoving);
                laps.add(new Lap(laps.size()+1,1000,duration,ms-lastEnd,true,duration/1000.0));
                lastEnd=ms; lastMoving=moving; boundary+=1000;
            }
            distance+=t.distance();
        }
        double partial = distanceM-laps.size()*1000;
        if (partial>.000001) {
            long duration = Math.max(0,movingAt(lastMs,pauses,motion,v2)-lastMoving);
            laps.add(new Lap(laps.size()+1,partial,duration,lastMs-lastEnd,false,duration/partial));
        }
        return List.copyOf(laps);
    }
    public static Calculation calculate(Instant startedAt, List<Input> inputs) {
        if (inputs.size() < 2 || inputs.getFirst().kind() != Kind.START ||
            inputs.getFirst().elapsedMs() != 0 || inputs.getLast().kind() != Kind.END) invalid();
        long lastMs = 0, activeMs = 0;
        boolean v2 = MotionPace.usesMotion(inputs.getFirst().reason());
        MotionPace motion = new MotionPace();
        boolean paused = false, inGap = false;
        double distanceM = 0;
        int gaps = 0;
        List<Travel> travels = new ArrayList<>();
        List<Span> pauses = new ArrayList<>();
        Long pauseAt = null;
        long lastResume = 0, cadenceEnd = 0, coverage = 0, steps = 0;
        Input previous = null;
        List<List<GeoPoint>> segments = new ArrayList<>();
        List<GeoPoint> segment = null;
        List<List<Input>> samples = new ArrayList<>();
        List<Input> sampleSegment = null;
        for (int i = 0; i < inputs.size(); i++) {
            Input p = inputs.get(i);
            if (p.seq() != i || p.elapsedMs() < lastMs || p.elapsedMs() > 7L*86400000 ||
                (p.kind() == Kind.GPS ? !freshFix(startedAt,p) : Math.abs(Duration.between(startedAt.plusMillis(p.elapsedMs()), p.measuredAt()).toMillis()) > 1000) ||
                (i > 0 && p.kind() == Kind.START) || (i < inputs.size()-1 && p.kind() == Kind.END)) invalid();
            if (!paused) activeMs += p.elapsedMs() - lastMs;
            lastMs = p.elapsedMs();
            if (v2) motion.add(p);
            switch (p.kind()) {
                case START, SEGMENT_END -> {}
                case BAROMETER -> {
                    if (p.pressureHpa()==null || !Double.isFinite(p.pressureHpa()) || p.pressureHpa()<=0 ||
                        p.pressureAccuracy()==null || p.pressureAccuracy()<0 || p.pressureAccuracy()>3 ||
                        p.sampleEndMs()==null || p.sampleEndMs()<0 || p.sampleEndMs()>p.elapsedMs() ||
                        p.elapsedMs()-p.sampleEndMs()>2000) invalid();
                }
                case CADENCE -> {
                    if (p.steps()==null || p.durationMs()==null || p.durationMs()<=0 || p.durationMs()>10000 || p.steps()<0 || p.steps()*1000L>p.durationMs()*5) invalid();
                    long sampleEnd = p.sampleEndMs()==null?p.elapsedMs():p.sampleEndMs();
                    if (sampleEnd>p.elapsedMs() || sampleEnd<p.durationMs()) invalid();
                    if (!paused && sampleEnd-p.durationMs()>=Math.max(lastResume,cadenceEnd)) {
                        coverage+=p.durationMs(); steps+=p.steps(); cadenceEnd=sampleEnd;
                    }
                }
                case PAUSE -> { if (paused) invalid(); paused = true; pauseAt = p.elapsedMs(); previous = null; segment = null; }
                case RESUME -> { if (!paused) invalid(); paused = false; pauses.add(new Span(pauseAt,p.elapsedMs())); pauseAt=null; lastResume=p.elapsedMs(); previous = null; segment = null; }
                case GAP -> { if (!paused && !inGap) gaps++; inGap = true; previous = null; segment = null; }
                case END -> {
                    if (pauseAt != null) pauses.add(new Span(pauseAt,p.elapsedMs()));
                    if ("USER".equals(p.reason()) && !paused) invalid();
                    if (!List.of("USER", "INTERRUPTED", "PERMISSION_REVOKED", "ACCOUNT_CHANGED").contains(p.reason()==null?"":p.reason())) invalid();
                }
                case GPS -> {
                    if (paused) { previous = null; segment = null; continue; }
                    if (!GpsQuality.good(p)) {
                        if (!inGap) gaps++;
                        inGap = true; previous = null; segment = null; continue;
                    }
                    if (previous != null) {
                        long dt = p.elapsedMs()-previous.elapsedMs();
                        double d = distance(previous.location(), p.location());
                        if (dt <= 0 || dt > GpsQuality.MAX_INTERVAL_MS || d/(dt/1000.0) > GpsQuality.MAX_SPEED_MPS) {
                            if (!inGap) gaps++;
                            segment = null;
                        } else { distanceM += d; travels.add(new Travel(previous.elapsedMs(),p.elapsedMs(),d)); }
                    }
                    if (segment == null) {
                        segment = new ArrayList<>(); segments.add(segment);
                        sampleSegment = new ArrayList<>(); samples.add(sampleSegment);
                    }
                    segment.add(p.location()); previous = p; inGap = false;
                    sampleSegment.add(p);
                }
            }
        }
        Input end = inputs.getLast();
        if (v2) { distanceM = motion.distanceM; segments = motion.segments; }
        long movingMs = v2 ? motion.movingMs(lastMs, activeMs) : activeMs;
        List<Lap> laps = laps(v2?motion.travels:travels,distanceM,lastMs,pauses,motion,v2);
        return new Calculation(new Metrics(distanceM, lastMs, activeMs, gaps,
            distanceM > 0 && movingMs > 0 ? movingMs/distanceM : null, movingMs,
            distanceM > 0 ? lastMs/distanceM : null, coverage>0?steps*60000.0/coverage:null, coverage, steps),
            segments, end.measuredAt(), end.reason(), laps,
            RunResultStatsCalculator.calculate(inputs,v2?motion.samples:samples,laps));
    }
    private static boolean freshFix(Instant start, Input p) {
        long age=Duration.between(p.measuredAt(),start.plusMillis(p.elapsedMs())).toMillis();
        return age>=-5000 && age<=10000;
    }
    static double distance(GeoPoint a, GeoPoint b) {
        return a.distanceMeters(b);
    }
    static void invalid() { throw new AppException(RunErrorCode.INVALID); }
}
