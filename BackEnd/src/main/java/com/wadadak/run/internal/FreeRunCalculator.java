package com.wadadak.run.internal;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.RunContracts.*;
import com.wadadak.run.RunErrorCode;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

final class FreeRunCalculator {
    record Calculation(Metrics metrics, List<List<GeoPoint>> segments, Instant endedAt, String endReason, List<Lap> laps) {}
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
    static Calculation calculate(Instant startedAt, List<Input> inputs) {
        if (inputs.size() < 2 || inputs.getFirst().kind() != Kind.START ||
            inputs.getFirst().elapsedMs() != 0 || inputs.getLast().kind() != Kind.END) invalid();
        long lastMs = 0, activeMs = 0;
        boolean v2 = "PACE_V2".equals(inputs.getFirst().reason());
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
        for (int i = 0; i < inputs.size(); i++) {
            Input p = inputs.get(i);
            if (p.seq() != i || p.elapsedMs() < lastMs || p.elapsedMs() > 7L*86400000 ||
                Math.abs(Duration.between(startedAt.plusMillis(p.elapsedMs()), p.measuredAt()).toMillis()) > 1000 ||
                (i > 0 && p.kind() == Kind.START) || (i < inputs.size()-1 && p.kind() == Kind.END)) invalid();
            if (!paused) activeMs += p.elapsedMs() - lastMs;
            lastMs = p.elapsedMs();
            if (v2) motion.add(p);
            switch (p.kind()) {
                case START -> {}
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
                    if (!good(p)) {
                        if (!inGap) gaps++;
                        inGap = true; previous = null; segment = null; continue;
                    }
                    if (previous != null) {
                        long dt = p.elapsedMs()-previous.elapsedMs();
                        double d = distance(previous.location(), p.location());
                        if (dt <= 0 || dt > 10000 || d/(dt/1000.0) > 12) {
                            if (!inGap) gaps++;
                            segment = null;
                        } else { distanceM += d; travels.add(new Travel(previous.elapsedMs(),p.elapsedMs(),d)); }
                    }
                    if (segment == null) { segment = new ArrayList<>(); segments.add(segment); }
                    segment.add(p.location()); previous = p; inGap = false;
                }
            }
        }
        Input end = inputs.getLast();
        if (v2) { distanceM = motion.distanceM; segments = motion.segments; }
        long movingMs = v2 ? motion.movingMs(lastMs, activeMs) : activeMs;
        return new Calculation(new Metrics(distanceM, lastMs, activeMs, gaps,
            distanceM > 0 && movingMs > 0 ? movingMs/distanceM : null, movingMs,
            distanceM > 0 ? lastMs/distanceM : null, coverage>0?steps*60000.0/coverage:null, coverage, steps),
            segments, end.measuredAt(), end.reason(), laps(v2?motion.travels:travels,distanceM,lastMs,pauses,motion,v2));
    }
    static boolean good(Input p) {
        return p.location()!=null && p.accuracyM()!=null && Double.isFinite(p.accuracyM()) && p.accuracyM()>=0 && p.accuracyM()<=30;
    }
    static double distance(GeoPoint a, GeoPoint b) {
        double x=Math.toRadians(a.lat()), y=Math.toRadians(b.lat());
        double h=Math.pow(Math.sin((y-x)/2),2)+Math.cos(x)*Math.cos(y)*Math.pow(Math.sin(Math.toRadians(b.lng()-a.lng())/2),2);
        return 2*6371008.8*Math.asin(Math.sqrt(Math.clamp(h,0,1)));
    }
    static void invalid() { throw new AppException(RunErrorCode.INVALID); }
}
