package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanResult.PlanCandidate;
import com.wadadak.course.internal.registration.SimilarityChecker;
import com.wadadak.course.internal.route.RouteService;
import lombok.RequiredArgsConstructor;
import org.locationtech.jts.geom.LineString;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import java.util.function.ToIntFunction;

/**
 * 후보 경로를 거르고 순위를 매겨 최대 3개를 고른다(정책 B3-A03). 기준은 검증 스크립트 {@code e2e.py}와 같다.
 * <ol>
 *     <li>1~100km 밖을 뺀다. 한 바퀴는 목표 ±5% · 되돌아감 20% 이하, 왕복은 목표 ±10%만 남긴다</li>
 *     <li>점수 = −30×되돌아감. 큰길 피하기 −30×큰길 비율, 같은 길 반복 없이 −30×되돌아감 한 번 더, 편의점 들르기 1곳 이상 +10 · 없으면 −50</li>
 *     <li>점수순으로, 기존 활성 코스와 85% 이상 겹치거나 이미 고른 후보와 85% 이상 겹치면 건너뛴다(정책 공통 3과 같은 계산)</li>
 *     <li>고른 경로를 B3 입력점으로 줄인다: 2m, 500개를 넘으면 4m · 8m …</li>
 * </ol>
 */
@Component
@RequiredArgsConstructor
class CandidateSelector {

    static final int MAX_CANDIDATES = 3;
    static final int MIN_METERS = 1_000;
    static final int MAX_METERS = 100_000;
    static final double LOOP_TOLERANCE = 0.05;
    static final double OUT_AND_BACK_TOLERANCE = 0.10;
    static final double MAX_LOOP_RETRACE = 0.2;
    static final double ANCHOR_TOLERANCE_METERS = 2;

    private final SimilarityChecker similarity;
    private final RouteService routeService;

    /**
     * @param targetMeters 한 바퀴 · 왕복의 목표 거리. 편도 · 경유는 null이어도 된다
     * @param stores       경로 근처 편의점 수
     * @return 후보가 없고, 거리 · 되돌아감 조건을 통과한 후보가 모두 기존 코스와 겹쳐서 빠졌으면 {@code allSimilarToExisting}
     */
    Selection select(Shape shape, Integer targetMeters, List<RoutedPath> paths, Set<Pref> prefer, ToIntFunction<LineString> stores) {
        Set<Pref> wants = prefer == null ? Set.of() : prefer;
        List<Scored> passed = new ArrayList<>();
        for (RoutedPath path : paths) {
            int meters = (int) Math.round(path.distanceMeters());
            double retrace = RouteMetrics.retraceRatio(path.points());
            if (meters < MIN_METERS || meters > MAX_METERS || !fitsShape(shape, targetMeters, meters, retrace)) {
                continue;
            }
            LineString line = CourseGeometry.lineString(path.points());
            double arterial = RouteMetrics.arterialRatio(path);
            int storeCount = stores.applyAsInt(line);
            passed.add(new Scored(path, line, meters, retrace, arterial, storeCount, score(wants, retrace, arterial, storeCount)));
        }
        passed.sort(Comparator.comparingDouble(Scored::score).reversed());

        List<Scored> picked = new ArrayList<>();
        for (Scored c : passed) {
            if (picked.size() == MAX_CANDIDATES) {
                break;
            }
            if (similarity.maxSimilarity(c.line()) < SimilarityChecker.MAX_SIMILARITY
                    && picked.stream().noneMatch(p -> overlaps(c.line(), p.line()))) {
                picked.add(c);
            }
        }
        Set<Pref> notApplied = EnumSet.noneOf(Pref.class);
        notApplied.addAll(wants);
        notApplied.removeAll(Pref.SUPPORTED);
        Set<Pref> notAppliedPrefs = Set.copyOf(notApplied);
        List<PlanCandidate> candidates = picked.stream().map(c -> new PlanCandidate(anchors(c.path().points()), c.meters(),
                c.retrace(), c.arterial(), c.stores(), PlanCandidate.summary(c.meters(), c.arterial(), c.stores()), notAppliedPrefs)).toList();
        return new Selection(candidates, picked.isEmpty() && !passed.isEmpty());
    }

    record Selection(List<PlanCandidate> candidates, boolean allSimilarToExisting) {
    }

    private static boolean fitsShape(Shape shape, Integer targetMeters, int meters, double retrace) {
        if (targetMeters == null) {
            return true;
        }
        double error = Math.abs(meters - targetMeters) / (double) targetMeters;
        return switch (shape) {
            case LOOP -> error <= LOOP_TOLERANCE && retrace <= MAX_LOOP_RETRACE;
            case OUT_AND_BACK -> error <= OUT_AND_BACK_TOLERANCE;
            case POINT_TO_POINT, VIA -> true;
        };
    }

    private static double score(Set<Pref> wants, double retrace, double arterial, int stores) {
        double score = -30 * retrace;
        if (wants.contains(Pref.AVOID_ARTERIAL)) {
            score -= 30 * arterial;
        }
        if (wants.contains(Pref.NO_RETRACE)) {
            score -= 30 * retrace;
        }
        if (wants.contains(Pref.STORE_ON_ROUTE)) {
            score += stores > 0 ? 10 : -50;
        }
        return score;
    }

    /** 어느 쪽 길이로 재도 85% 이상 겹치면 같은 후보로 본다 */
    private boolean overlaps(LineString a, LineString b) {
        return similarity.similarity(a, b) >= SimilarityChecker.MAX_SIMILARITY
                || similarity.similarity(b, a) >= SimilarityChecker.MAX_SIMILARITY;
    }

    private List<GeoPoint> anchors(List<GeoPoint> points) {
        double tolerance = ANCHOR_TOLERANCE_METERS;
        List<GeoPoint> anchors = routeService.simplify(points, tolerance);
        while (anchors.size() > RouteService.MAX_ANCHOR_POINTS) {
            tolerance *= 2;
            anchors = routeService.simplify(points, tolerance);
        }
        return anchors;
    }

    private record Scored(RoutedPath path, LineString line, int meters, double retrace, double arterial, int stores, double score) {
    }
}
