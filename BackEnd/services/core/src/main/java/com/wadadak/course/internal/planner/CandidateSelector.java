package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanResult.PlanCandidate;
import com.wadadak.course.internal.planner.PlannerRepository.PoiCounts;
import com.wadadak.course.internal.planner.RoadLayers.Layer;
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
import java.util.function.Function;

/**
 * 후보 경로를 거르고 순위를 매겨 최대 3개를 고른다(정책 B3-A03). 기준은 검증 스크립트 {@code e2e.py}와 같다.
 * <ol>
 *     <li>1~100km 밖을 뺀다. 한 바퀴는 목표 ±5% · 되돌아감 20% 이하, 왕복은 목표 ±10%만 남긴다</li>
 *     <li>점수 = −30×되돌아감. 큰길 피하기 −30×큰길 비율, 같은 길 반복 없이 −30×되돌아감 한 번 더, 편의점 · 화장실 들르기 1곳 이상 +10 ·
 *     없으면 −50, 평지 −2×(1km당 오르막 m) · 오르막 +2×(1km당 오르막 m), 인도 · 강변 · 밝은 길 +30×그 길의 비율.
 *     오르막이나 비율을 모르는 후보는 그 점수가 없다</li>
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

    /** 평지 · 오르막 점수: 1km당 오르막 1m마다 */
    static final double CLIMB_WEIGHT = 2;
    /** 인도 · 강변 · 밝은 길 점수: 그 길의 비율(0~1)에 곱한다. 되돌아감 · 큰길과 같은 크기다 */
    static final double LAYER_WEIGHT = 30;

    private final SimilarityChecker similarity;
    private final RouteService routeService;
    private final SpotHeights spotHeights;
    private final RoadLayers layers;

    /**
     * @param targetMeters 한 바퀴 · 왕복의 목표 거리. 편도 · 경유는 null이어도 된다
     * @param pois         경로 근처 편의점 · 화장실 수(DB 조회)
     * @return 후보가 없고, 거리 · 되돌아감 조건을 통과한 후보가 모두 기존 코스와 겹쳐서 빠졌으면 {@code allSimilarToExisting}
     */
    Selection select(Shape shape, Integer targetMeters, List<RoutedPath> paths, Set<Pref> prefer, Function<LineString, PoiCounts> pois) {
        Set<Pref> wants = prefer == null ? Set.of() : prefer;
        // 편의점 · 화장실 수(DB 조회)와 오르막은 점수에 쓸 때만 후보마다 구하고, 아니면 고른 후보만 구한다
        boolean scorePois = wants.contains(Pref.STORE_ON_ROUTE) || wants.contains(Pref.TOILET_ON_ROUTE);
        boolean scoreClimb = wants.contains(Pref.FLAT) || wants.contains(Pref.HILLY);
        List<Scored> passed = new ArrayList<>();
        for (RoutedPath path : paths) {
            int meters = (int) Math.round(path.distanceMeters());
            double retrace = RouteMetrics.retraceRatio(path.points());
            if (meters < MIN_METERS || meters > MAX_METERS || !fitsShape(shape, targetMeters, meters, retrace)) {
                continue;
            }
            LineString line = CourseGeometry.lineString(path.points());
            double arterial = RouteMetrics.arterialRatio(path);
            PoiCounts counts = scorePois ? pois.apply(line) : null;
            Integer ascent = scoreClimb ? spotHeights.ascentMeters(path.points()) : null;
            Double sidewalk = layers.ratio(Layer.SIDEWALK, path.points());
            Double river = layers.ratio(Layer.RIVER, path.points());
            Double lit = layers.ratio(Layer.LAMPS, path.points());
            passed.add(new Scored(path, line, meters, retrace, arterial, counts, ascent, sidewalk, river, lit,
                    score(wants, meters, retrace, arterial, counts, ascent) + layerScore(wants, sidewalk, river, lit)));
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
        List<PlanCandidate> candidates = picked.stream().map(c -> {
            PoiCounts counts = scorePois ? c.pois() : pois.apply(c.line());
            Integer ascent = scoreClimb ? c.ascent() : spotHeights.ascentMeters(c.path().points());
            return new PlanCandidate(anchors(c.path().points()), c.meters(), c.retrace(), c.arterial(), counts.stores(), counts.toilets(),
                    ascent, c.sidewalk(), c.river(), c.lit());
        }).toList();
        return new Selection(candidates, picked.isEmpty() && !passed.isEmpty(), Pref.notApplied(wants, noData(passed)));
    }

    /** 지원하지만 지금 반영하지 못하는 조건: 파일이 없거나, 통과한 후보 어디에도 등이 없다(등 자료가 없는 지역일 수 있다) */
    private Set<Pref> noData(List<Scored> passed) {
        Set<Pref> noData = EnumSet.noneOf(Pref.class);
        if (!spotHeights.available()) {
            noData.addAll(Set.of(Pref.FLAT, Pref.HILLY));
        }
        if (!layers.available(Layer.SIDEWALK)) {
            noData.add(Pref.SIDEWALK);
        }
        if (!layers.available(Layer.RIVER)) {
            noData.add(Pref.RIVER);
        }
        if (!layers.available(Layer.LAMPS) || passed.stream().allMatch(c -> c.lit() == 0)) {
            noData.add(Pref.LIT);
        }
        return noData;
    }

    /** @param notApplied 요청한 원하는 길 중 반영하지 못한 것 */
    record Selection(List<PlanCandidate> candidates, boolean allSimilarToExisting, Set<Pref> notApplied) {
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

    private static double score(Set<Pref> wants, int meters, double retrace, double arterial, PoiCounts pois, Integer ascent) {
        double score = -30 * retrace;
        if (wants.contains(Pref.AVOID_ARTERIAL)) {
            score -= 30 * arterial;
        }
        if (wants.contains(Pref.NO_RETRACE)) {
            score -= 30 * retrace;
        }
        if (wants.contains(Pref.STORE_ON_ROUTE)) {
            score += pois.stores() > 0 ? 10 : -50;
        }
        if (wants.contains(Pref.TOILET_ON_ROUTE)) {
            score += pois.toilets() > 0 ? 10 : -50;
        }
        if (ascent != null) {
            double climbPerKm = ascent / (meters / 1000.0);
            if (wants.contains(Pref.FLAT)) {
                score -= CLIMB_WEIGHT * climbPerKm;
            }
            if (wants.contains(Pref.HILLY)) {
                score += CLIMB_WEIGHT * climbPerKm;
            }
        }
        return score;
    }

    private static double layerScore(Set<Pref> wants, Double sidewalk, Double river, Double lit) {
        double score = 0;
        if (wants.contains(Pref.SIDEWALK) && sidewalk != null) {
            score += LAYER_WEIGHT * sidewalk;
        }
        if (wants.contains(Pref.RIVER) && river != null) {
            score += LAYER_WEIGHT * river;
        }
        if (wants.contains(Pref.LIT) && lit != null) {
            score += LAYER_WEIGHT * lit;
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

    /** @param pois 점수에 쓰지 않았으면 null */
    private record Scored(RoutedPath path, LineString line, int meters, double retrace, double arterial, PoiCounts pois, Integer ascent,
                          Double sidewalk, Double river, Double lit, double score) {
    }
}
