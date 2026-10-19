package com.wadadak.run.internal.judging;

import com.wadadak.run.internal.GpsQuality;
import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.RunContracts.Kind;
import com.wadadak.run.internal.judging.RouteGeometry.Projection;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * 판정 3단계 — 윈도우 추적. GPS 표본마다 코스상 위치 s를 하나로 정하고 직전 표본과 이어지는지 표시한다.
 * 거리 합산은 하지 않는다(4단계는 연결된 두 표본 사이만 인정한다).
 *
 * <ul>
 *   <li>기준(직전 s)이 있으면 창(직전 s ± 속도 상한 × 시간 차 + 경로 오차) 안 후보 중 정방향을 먼저, 그중 가장 가까운 것을 고른다.
 *       창 안에 없으면 직전 s에 가장 가까운 후보로 옮기고(점프) 연결을 끊는다</li>
 *   <li>기준이 없을 때(첫 표본, PAUSE·GAP 뒤) 후보가 여럿이면 보류한다. 가설을 모두 들고 다음 표본으로 늘려 가다가
 *       하나만 남으면 그 가설로 보류했던 표본까지 소급해 정한다. 순환 코스 출발점(s = 0과 끝)이 이렇게 갈린다</li>
 *   <li>연결을 끊는 것: 코스 밖·나쁜 GPS 표본, 점프, PAUSE~RESUME, GAP, 10초 초과 GPS 공백, 속도 상한 초과. PAUSE~RESUME 사이 GPS와
 *       SEGMENT_END·END 이후는 버린다</li>
 * </ul>
 */
final class CourseTracker {

    /**
     * 표본 하나의 추적 결과.
     *
     * @param s         코스상 위치(m). 코스 밖·나쁜 GPS·끝내 정하지 못한 보류 표본은 null
     * @param connected 직전 표본과 이어진다. true일 때만 4단계가 그 사이를 인정한다
     */
    record Point(long seq, long elapsedMs, Instant measuredAt, Double s, boolean connected) {
    }

    private final RouteGeometry route;
    private final JudgingConfig config;

    CourseTracker(RouteGeometry route, JudgingConfig config) {
        this.route = route;
        this.config = config;
    }

    List<Point> track(List<Input> inputs) {
        Tracking tracking = new Tracking();
        boolean paused = false;
        for (Input input : inputs) {
            if (input.kind() == Kind.SEGMENT_END || input.kind() == Kind.END) {
                break;
            }
            switch (input.kind()) {
                case GPS -> {
                    if (!paused) { // 일시정지 중 이동은 인정하지 않는다(RUN-06·RCR-04)
                        tracking.sample(input);
                    }
                }
                case PAUSE -> {
                    paused = true;
                    tracking.forget();
                }
                case RESUME -> paused = false;
                case GAP -> tracking.forget();
                default -> {
                }
            }
        }
        tracking.forget(); // 끝까지 정하지 못한 보류 표본은 s 없이 남는다
        return tracking.points;
    }

    /** 한 번의 추적 상태. track() 호출마다 새로 만든다 */
    private final class Tracking {

        final List<Point> points = new ArrayList<>();

        /** 마지막으로 s를 정한 표본. null이면 기준 없음 */
        Input anchor;
        double anchorS;
        /** 다음 표본을 anchor와 이어도 되는지. 코스 밖 표본 뒤에는 false */
        boolean linkable;

        /** 보류 중인 표본과 그 points 안 위치 */
        final List<Input> held = new ArrayList<>();
        final List<Integer> heldIndexes = new ArrayList<>();
        List<Hypothesis> hypotheses = new ArrayList<>();

        /** PAUSE·GAP·10초 초과 GPS 공백: 기준과 보류 가설을 버린다. 정지·공백 전후는 잇지 않는다 */
        void forget() {
            anchor = null;
            linkable = false;
            clearHeld();
        }

        void sample(Input input) {
            Input previous = anchor != null ? anchor : held.isEmpty() ? null : held.getLast();
            if (previous != null && input.elapsedMs() - previous.elapsedMs() > GpsQuality.MAX_INTERVAL_MS) {
                // A silent GPS gap has the same boundary as GAP. Old anchors/hypotheses
                // must not resolve an ambiguous loop/crossing after reception resumes.
                forget();
            }
            List<Projection> candidates = GpsQuality.good(input) // 자유 러닝 거리와 같은 GPS 품질 기준
                    ? route.candidates(route.toLocal(input.location()), config.routeToleranceM())
                    : List.of();

            if (candidates.isEmpty()) { // 코스 밖·나쁜 GPS
                points.add(new Point(input.seq(), input.elapsedMs(), input.measuredAt(), null, false));
                linkable = false;
                clearHeld();
                return;
            }
            if (anchor != null) {
                Double next = choose(candidates, anchor, anchorS, input);
                if (next == null) { // 점프: 건너뛴 구간은 인정하지 않는다
                    place(input, nearest(candidates, anchorS), false);
                } else {
                    place(input, next, linkable && withinSpeed(anchor, input));
                }
                return;
            }
            if (hypotheses.isEmpty()) {
                if (candidates.size() == 1) {
                    place(input, candidates.getFirst().s(), false);
                } else {
                    hold(input);
                    for (Projection candidate : candidates) {
                        hypotheses.add(new Hypothesis(candidate.s()));
                    }
                }
                return;
            }
            extendHypotheses(input, candidates);
        }

        private void extendHypotheses(Input input, List<Projection> candidates) {
            Input previous = held.getLast();
            List<Hypothesis> alive = new ArrayList<>();
            for (Hypothesis hypothesis : hypotheses) {
                Double next = choose(candidates, previous, hypothesis.last(), input);
                // 정방향 가설만 남긴다. GPS 흔들림만큼(경로 오차) 뒤로 가는 것은 봐준다
                if (next != null && next >= hypothesis.max - config.routeToleranceM()) {
                    alive.add(hypothesis.extended(next));
                }
            }
            if (alive.isEmpty()) { // 어느 가설로도 이어지지 않으면 이 표본부터 새로 시작
                clearHeld();
                sample(input);
                return;
            }
            hold(input);
            hypotheses = alive;
            boolean converged = alive.stream().map(Hypothesis::last).distinct().count() == 1;
            if (alive.size() == 1 || converged) {
                // 같은 자리로 모이면 정방향으로 더 나아간 가설을 고른다(왕복 코스의 가는 길·돌아오는 길)
                resolve(alive.stream().max((a, b) -> Double.compare(a.max, b.max)).orElseThrow());
            }
        }

        /** 보류했던 표본들을 남은 가설의 s로 소급해 정한다 */
        private void resolve(Hypothesis hypothesis) {
            for (int i = 0; i < held.size(); i++) {
                Input input = held.get(i);
                double s = hypothesis.values.get(i);
                boolean connected = i > 0 && withinSpeed(held.get(i - 1), input);
                points.set(heldIndexes.get(i), new Point(input.seq(), input.elapsedMs(), input.measuredAt(), s, connected));
            }
            anchor = held.getLast();
            anchorS = hypothesis.last();
            linkable = true;
            clearHeld();
        }

        private void place(Input input, double s, boolean connected) {
            points.add(new Point(input.seq(), input.elapsedMs(), input.measuredAt(), s, connected));
            anchor = input;
            anchorS = s;
            linkable = true;
        }

        private void hold(Input input) {
            heldIndexes.add(points.size());
            held.add(input);
            points.add(new Point(input.seq(), input.elapsedMs(), input.measuredAt(), null, false));
        }

        private void clearHeld() {
            held.clear();
            heldIndexes.clear();
            hypotheses = new ArrayList<>();
        }
    }

    /** 보류 가설: 보류한 표본마다의 s와 지금까지 가장 앞선 s */
    private record Hypothesis(List<Double> values, double max) {

        Hypothesis(double s) {
            this(List.of(s), s);
        }

        double last() {
            return values.getLast();
        }

        Hypothesis extended(double s) {
            List<Double> next = new ArrayList<>(values);
            next.add(s);
            return new Hypothesis(List.copyOf(next), Math.max(max, s));
        }
    }

    /**
     * 창 안 후보 중 정방향(s ≥ 직전 s)을 먼저, 그중 직전 s에 가장 가까운 것. 창 안에 없으면 null.
     * 정방향 우선은 왕복 코스 반환점에서 같은 거리의 가는 길·돌아오는 길 중 돌아오는 길을 고르게 한다.
     */
    private Double choose(List<Projection> candidates, Input previous, double previousS, Input input) {
        double window = reach(previous, input) + config.routeToleranceM();
        Double forward = null;
        Double any = null;
        for (Projection candidate : candidates) {
            double gap = Math.abs(candidate.s() - previousS);
            if (gap > window) {
                continue;
            }
            if (candidate.s() >= previousS && (forward == null || gap < Math.abs(forward - previousS))) {
                forward = candidate.s();
            }
            if (any == null || gap < Math.abs(any - previousS)) {
                any = candidate.s();
            }
        }
        return forward != null ? forward : any;
    }

    private static double nearest(List<Projection> candidates, double s) {
        double best = candidates.getFirst().s();
        for (Projection candidate : candidates) {
            if (Math.abs(candidate.s() - s) < Math.abs(best - s)) {
                best = candidate.s();
            }
        }
        return best;
    }

    /** 두 표본 사이 속도 상한으로 갈 수 있는 거리(m). 시간이 거꾸로면 0 */
    private double reach(Input previous, Input input) {
        return Math.max(0, input.elapsedMs() - previous.elapsedMs()) / 1000.0 * config.maxSpeedMps();
    }

    /**
     * 실제 좌표 거리가 속도 상한 안이다. 경로를 따라 가까워 보여도 순간 이동한 표본을 걸러 낸다.
     * 두 표본의 GPS 정확도만큼 여유를 둔다. 표본 간격이 짧으면 오차만으로 상한을 넘을 수 있다.
     */
    private boolean withinSpeed(Input previous, Input input) {
        long interval = input.elapsedMs() - previous.elapsedMs();
        double allowance = previous.accuracyM() + input.accuracyM();
        return interval > 0 && interval <= GpsQuality.MAX_INTERVAL_MS
                && previous.location().distanceMeters(input.location()) <= reach(previous, input) + allowance;
    }
}
