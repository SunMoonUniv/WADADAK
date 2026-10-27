package com.wadadak.run.internal.ghost;

import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.run.internal.GpsQuality;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.judging.CourseJudge;
import com.wadadak.run.internal.judging.CourseJudge.CourseSample;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.stream.Collectors;

/** Read-only F9 derivation from the immutable source and its original course snapshot. */
public final class GhostPlaybackBuilder {
    public static final String VERSION = "GHOST_PLAYBACK_V1";
    public static final String FREE_VERSION = "GHOST_PLAYBACK_FREE_V1";
    private static final String SOURCE_POLICY_VERSION = "2026-10-14";
    private static final double EPSILON = 1e-6;

    public GhostPlayback build(Result source, CourseSnapshot snapshot, List<Input> inputs) {
        if (source.course() == null || !source.course().completed()) return unavailable(source, snapshot, "NOT_COMPLETED");
        if (snapshot == null) return unavailable(source, null, "MISSING_COURSE_SNAPSHOT");
        if (!source.course().courseId().equals(snapshot.courseId())
                || source.course().courseVersion() != snapshot.version()
                || source.course().courseDistanceMeters() != snapshot.totalDistanceMeters())
            return unavailable(source, snapshot, "COURSE_VERSION_MISMATCH");
        if (!SOURCE_POLICY_VERSION.equals(source.policyVersion()))
            return unavailable(source, snapshot, "UNSUPPORTED_SOURCE_POLICY");
        if (!complete(inputs)) return unavailable(source, snapshot, "MISSING_SOURCE_INPUTS");
        if (!Objects.equals(inputs.getFirst().reason(), source.calculationVersion()))
            return unavailable(source, snapshot, "SOURCE_RESULT_MISMATCH");

        var route = new CourseRouteSnapshot(snapshot.courseId(), snapshot.name(), snapshot.route(),
                snapshot.totalDistanceMeters(), snapshot.version());
        var analysis = new CourseJudge().analyze(route, inputs);
        var judgement = analysis.judgement();
        if (!judgement.completed() || judgement.courseElapsedSeconds() != source.course().courseElapsedSeconds()
                || !Objects.equals(judgement.completedAt(), source.course().completedAt()))
            return unavailable(source, snapshot, "SOURCE_RESULT_MISMATCH");
        return compose(source,snapshot,inputs,analysis,VERSION);
    }

    public GhostPlayback buildReference(Result source, CourseSnapshot snapshot, List<Input> inputs) {
        var analysis = new CourseJudge().analyze(snapshot.route(),snapshot.breaks(),inputs);
        if (!analysis.judgement().completed()) return unavailableReference(source,snapshot,"REFERENCE_NOT_REPRODUCIBLE");
        return compose(source,snapshot,inputs,analysis,FREE_VERSION);
    }

    public GhostPlayback unavailableReference(Result source, CourseSnapshot snapshot, String reason) {
        return new GhostPlayback(source.id(),snapshot,FREE_VERSION,source.policyVersion(),source.calculationVersion(),
                0,null,false,List.of(reason),null,List.of(),List.of());
    }

    private GhostPlayback compose(Result source, CourseSnapshot snapshot, List<Input> inputs,
                                  CourseJudge.Analysis analysis, String version) {
        long duration = analysis.courseElapsedMs();
        var points = playbackSamples(analysis.samples(), inputs, duration);
        List<Pause> pauses = pauses(inputs, points, duration);
        List<GhostSpan> spans = spans(points, pauses, duration);
        TreeMap<Long, Double> sampled = new TreeMap<>();
        for (var p : points) sampled.put(p.elapsedMs(), p.positionM());
        var samples = sampled.entrySet().stream().map(e -> new GhostSample(e.getKey(), e.getValue())).toList();

        long pausedMs = pauses.stream().mapToLong(p -> p.to - p.from).sum();
        long active = duration - pausedMs, totalGap = 0, longest = 0, openGap = 0;
        int pauseIndex = 0;
        for (GhostSpan span : spans) {
            while (pauseIndex < pauses.size() && pauses.get(pauseIndex).to <= span.fromMs()) pauseIndex++;
            boolean manuallyPaused = pauseIndex < pauses.size() && pauses.get(pauseIndex).from <= span.fromMs()
                    && pauses.get(pauseIndex).to >= span.toMs();
            if (manuallyPaused) continue;
            if (span.state() == GhostSpanState.UNKNOWN) {
                long length = span.toMs() - span.fromMs();
                totalGap += length;
                openGap += length;
                longest = Math.max(longest, openGap);
            } else {
                openGap = 0;
            }
        }
        List<String> reasons = new ArrayList<>();
        if (active <= 0) reasons.add("NO_ACTIVE_DURATION");
        if (longest > 30_000) reasons.add("CONTINUOUS_GAP_EXCEEDED");
        if (active > 0 && totalGap * 100 > active * 5) reasons.add("TOTAL_GAP_EXCEEDED");
        if (points.stream().anyMatch(CourseSample::ambiguous)) reasons.add("AMBIGUOUS_POSITION");
        if (pauses.stream().anyMatch(p -> p.position == null)) reasons.add("PAUSE_POSITION_UNAVAILABLE");
        if (samples.isEmpty() || samples.getLast().elapsedMs() != duration || samples.getLast().coursePositionM() == null)
            reasons.add("FINISH_POSITION_UNAVAILABLE");
        return new GhostPlayback(source.id(), snapshot, version, source.policyVersion(), source.calculationVersion(),
                analysis.judgement().courseElapsedSeconds(), duration, reasons.isEmpty(), List.copyOf(reasons),
                new GhostQuality(active, totalGap, longest), samples, spans);
    }

    public GhostPlayback unavailable(Result source, CourseSnapshot snapshot, String reason) {
        return new GhostPlayback(source.id(), snapshot, VERSION, source.policyVersion(), source.calculationVersion(),
                source.course() == null ? 0 : source.course().courseElapsedSeconds(), null, false,
                List.of(reason), null, List.of(), List.of());
    }

    private boolean complete(List<Input> inputs) {
        if (inputs == null || inputs.size() < 3 || inputs.getFirst().kind() != Kind.START
                || inputs.getFirst().elapsedMs() != 0 || inputs.getLast().kind() != Kind.END) return false;
        long previous = 0;
        for (int i = 0; i < inputs.size(); i++) {
            Input input = inputs.get(i);
            if (input.seq() != i || input.elapsedMs() < previous || i > 0 && input.kind() == Kind.START
                    || i < inputs.size() - 1 && input.kind() == Kind.END) return false;
            previous = input.elapsedMs();
        }
        return true;
    }

    private record Pause(long from, long to, Double position) {}

    private List<CourseSample> playbackSamples(List<CourseSample> tracked, List<Input> inputs, long duration) {
        Map<Long, Input> bySeq = inputs.stream().collect(Collectors.toMap(Input::seq, p -> p));
        List<CourseSample> samples = new ArrayList<>();
        Input previous = null;
        for (CourseSample p : tracked) {
            if (p.elapsedMs() > duration) break;
            Input raw = bySeq.get(p.seq());
            if (previous != null) {
                for (long seq = previous.seq() + 1; seq < raw.seq(); seq++) {
                    Kind kind = inputs.get(Math.toIntExact(seq)).kind();
                    if (kind == Kind.PAUSE || kind == Kind.RESUME || kind == Kind.GAP) {
                        previous = null;
                        break;
                    }
                }
            }
            long dt = previous == null ? 0 : raw.elapsedMs() - previous.elapsedMs();
            // A projection is not a trusted position at a raw speed-jump fix. Reuse the existing hard limit.
            boolean jump = previous != null && GpsQuality.good(previous) && GpsQuality.good(raw)
                    && dt > 0 && dt <= GpsQuality.MAX_INTERVAL_MS
                    && previous.location().distanceMeters(raw.location()) * 1000 / dt > GpsQuality.MAX_SPEED_MPS;
            samples.add(jump ? new CourseSample(p.seq(), p.elapsedMs(), null, false, p.ambiguous()) : p);
            previous = raw;
        }
        return List.copyOf(samples);
    }

    private List<Pause> pauses(List<Input> inputs, List<CourseSample> points, long duration) {
        Map<Long, CourseSample> bySeq = points.stream().collect(Collectors.toMap(CourseSample::seq, p -> p));
        List<Pause> pauses = new ArrayList<>();
        Long start = null;
        Double held = null, last = null;
        long lastFix = -GpsQuality.MAX_INTERVAL_MS - 1;
        for (Input input : inputs) {
            if (input.elapsedMs() > duration || input.kind() == Kind.SEGMENT_END || input.kind() == Kind.END) break;
            switch (input.kind()) {
                case GPS -> {
                    if (start == null) {
                        CourseSample p = bySeq.get(input.seq());
                        last = p == null ? null : p.positionM();
                        lastFix = input.elapsedMs();
                    }
                }
                case GAP -> {
                    last = null;
                }
                case PAUSE -> {
                    if (start == null) {
                        start = input.elapsedMs();
                        held = input.elapsedMs() - lastFix <= GpsQuality.MAX_INTERVAL_MS ? last : null;
                    }
                }
                case RESUME -> {
                    if (start != null) {
                        pauses.add(new Pause(start, input.elapsedMs(), held));
                        start = null;
                        last = null;
                    }
                }
                default -> {}
            }
        }
        if (start != null && start < duration) pauses.add(new Pause(start, duration, held));
        return pauses;
    }

    private List<GhostSpan> spans(List<CourseSample> points, List<Pause> pauses, long duration) {
        TreeSet<Long> boundaries = new TreeSet<>(List.of(0L, duration));
        List<GhostSpan> movement = new ArrayList<>();
        CourseSample previous = null;
        for (var p : points) {
            boundaries.add(p.elapsedMs());
            if (previous != null && p.connected() && previous.positionM() != null && p.positionM() != null
                    && p.elapsedMs() > previous.elapsedMs()) {
                movement.add(new GhostSpan(previous.elapsedMs(), p.elapsedMs(), previous.positionM(), p.positionM(),
                        GhostSpanState.TRACKED));
            }
            previous = p;
        }
        for (Pause pause : pauses) {
            boundaries.add(pause.from);
            boundaries.add(pause.to);
        }
        List<Long> edges = new ArrayList<>(boundaries);
        List<GhostSpan> spans = new ArrayList<>();
        int m = 0, p = 0;
        for (int i = 1; i < edges.size(); i++) {
            long from = edges.get(i - 1), to = edges.get(i);
            if (to <= from) continue;
            while (p < pauses.size() && pauses.get(p).to <= from) p++;
            while (m < movement.size() && movement.get(m).toMs() <= from) m++;
            GhostSpan next;
            if (p < pauses.size() && pauses.get(p).from <= from && pauses.get(p).to >= to) {
                Double position = pauses.get(p).position;
                next = new GhostSpan(from, to, position, position,
                        position == null ? GhostSpanState.UNKNOWN : GhostSpanState.PAUSED);
            } else if (m < movement.size() && movement.get(m).fromMs() <= from && movement.get(m).toMs() >= to) {
                GhostSpan link = movement.get(m);
                next = new GhostSpan(from, to, positionAt(link, from), positionAt(link, to), GhostSpanState.TRACKED);
            } else {
                next = new GhostSpan(from, to, null, null, GhostSpanState.UNKNOWN);
            }
            append(spans, next);
        }
        return List.copyOf(spans);
    }

    private double positionAt(GhostSpan span, long ms) {
        return span.fromPositionM() + (span.toPositionM() - span.fromPositionM())
                * (ms - span.fromMs()) / (span.toMs() - span.fromMs());
    }

    private void append(List<GhostSpan> spans, GhostSpan next) {
        if (!spans.isEmpty()) {
            GhostSpan previous = spans.getLast();
            boolean same = previous.state() == next.state() && previous.toMs() == next.fromMs();
            // Preserve pause boundaries even when its held position is unavailable.
            if (previous.state() == GhostSpanState.UNKNOWN) same = false;
            if (same && previous.state() != GhostSpanState.UNKNOWN) {
                same = Math.abs(previous.toPositionM() - next.fromPositionM()) < EPSILON
                        && Math.abs((previous.toPositionM() - previous.fromPositionM()) / (previous.toMs() - previous.fromMs())
                        - (next.toPositionM() - next.fromPositionM()) / (next.toMs() - next.fromMs())) < 1e-10;
            }
            if (same) {
                spans.set(spans.size() - 1, new GhostSpan(previous.fromMs(), next.toMs(), previous.fromPositionM(),
                        next.toPositionM(), next.state()));
                return;
            }
        }
        spans.add(next);
    }
}
