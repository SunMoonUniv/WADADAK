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
import org.locationtech.jts.simplify.DouglasPeuckerSimplifier;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
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
        // 분석 로그: 만든 경로마다 어떻게 됐는지(뽑힘 · 걸러진 이유). 배열 칸 = 만든 순서
        PathLog[] pathLogs = new PathLog[paths.size()];
        for (int i = 0; i < paths.size(); i++) {
            RoutedPath path = paths.get(i);
            int meters = (int) Math.round(path.distanceMeters());
            double retrace = RouteMetrics.retraceRatio(path.points());
            double arterial = RouteMetrics.arterialRatio(path);
            if (meters < MIN_METERS || meters > MAX_METERS || !fitsShape(shape, targetMeters, meters, retrace)) {
                // 거리는 맞는데 걸렸으면 한 바퀴의 되돌아감 때문이다
                Fate fate = fitsShape(shape, targetMeters, meters, 0) && meters >= MIN_METERS && meters <= MAX_METERS
                        ? Fate.TOO_MUCH_RETRACE : Fate.OUT_OF_RANGE;
                pathLogs[i] = new PathLog(i + 1, fate, null, meters, retrace, arterial, null, null, null, null, null, null, null,
                        logPoints(path.points()));
                continue;
            }
            LineString line = CourseGeometry.lineString(path.points());
            PoiCounts counts = scorePois ? pois.apply(line) : null;
            Integer ascent = scoreClimb ? spotHeights.ascentMeters(path.points()) : null;
            Double sidewalk = layers.ratio(Layer.SIDEWALK, path.points());
            Double river = layers.ratio(Layer.RIVER, path.points());
            Double lit = layers.ratio(Layer.LAMPS, path.points());
            passed.add(new Scored(i, path, line, meters, retrace, arterial, counts, ascent, sidewalk, river, lit,
                    score(wants, meters, retrace, arterial, counts, ascent) + layerScore(wants, sidewalk, river, lit)));
        }
        passed.sort(Comparator.comparingDouble(Scored::score).reversed());

        List<Scored> picked = new ArrayList<>();
        // 겹쳐서 빠진 경로(만든 순서 → 이유). 3개를 다 고른 뒤의 경로는 겹침을 재지 않는다(DB 조회를 늘리지 않으려고)
        Map<Integer, Fate> skipped = new HashMap<>();
        for (Scored c : passed) {
            if (picked.size() == MAX_CANDIDATES) {
                break;
            }
            if (similarity.maxSimilarity(c.line()) >= SimilarityChecker.MAX_SIMILARITY) {
                skipped.put(c.order(), Fate.SIMILAR_TO_EXISTING);
            } else if (picked.stream().anyMatch(p -> overlaps(c.line(), p.line()))) {
                skipped.put(c.order(), Fate.SIMILAR_TO_PICKED);
            } else {
                picked.add(c);
            }
        }
        List<PlanCandidate> candidates = picked.stream().map(c -> {
            PoiCounts counts = scorePois ? c.pois() : pois.apply(c.line());
            Integer ascent = scoreClimb ? c.ascent() : spotHeights.ascentMeters(c.path().points());
            return new PlanCandidate(anchors(c.path().points()), c.meters(), c.retrace(), c.arterial(), counts.stores(), counts.toilets(),
                    ascent, c.sidewalk(), c.river(), c.lit());
        }).toList();

        for (Scored c : passed) {
            int rank = picked.indexOf(c);
            if (rank >= 0) {
                // 뽑힌 경로는 앱에 보낸 후보와 같은 값(편의점 · 오르막은 이때 구한 값)
                PlanCandidate sent = candidates.get(rank);
                pathLogs[c.order()] = new PathLog(c.order() + 1, Fate.PICKED, rank + 1, c.meters(), c.retrace(), c.arterial(), c.score(),
                        sent.storeCount(), sent.toiletCount(), sent.ascentMeters(), c.sidewalk(), c.river(), c.lit(), sent.anchorPoints());
            } else {
                pathLogs[c.order()] = new PathLog(c.order() + 1, skipped.getOrDefault(c.order(), Fate.NOT_EXAMINED), null, c.meters(),
                        c.retrace(), c.arterial(), c.score(), c.pois() == null ? null : c.pois().stores(),
                        c.pois() == null ? null : c.pois().toilets(), c.ascent(), c.sidewalk(), c.river(), c.lit(),
                        logPoints(c.path().points()));
            }
        }
        return new Selection(candidates, picked.isEmpty() && !passed.isEmpty(), Pref.notApplied(wants, noData(passed)),
                List.of(pathLogs));
    }

    /**
     * 로그용으로 줄인 경로 점. 뽑히지 않은 경로까지 수십 개라 2m 기준으로 점을 줄인다.
     * 뽑힌 경로의 {@link #anchors}와 달리 DB를 부르지 않고 JTS로 바로 줄인다(위경도 0.00002도 ≈ 2m).
     */
    private static List<GeoPoint> logPoints(List<GeoPoint> points) {
        if (points.size() < 3) {
            return points;
        }
        return Arrays.stream(DouglasPeuckerSimplifier.simplify(CourseGeometry.lineString(points), 0.00002).getCoordinates())
                .map(c -> new GeoPoint(c.y, c.x)).toList();
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

    /**
     * @param notApplied 요청한 원하는 길 중 반영하지 못한 것
     * @param paths      만든 경로 전부의 결과(만든 순서). 분석 로그에만 쓴다
     */
    record Selection(List<PlanCandidate> candidates, boolean allSimilarToExisting, Set<Pref> notApplied, List<PathLog> paths) {

        /** 경로 결과 없이(테스트 · 길을 찾지 않은 경우) */
        Selection(List<PlanCandidate> candidates, boolean allSimilarToExisting, Set<Pref> notApplied) {
            this(candidates, allSimilarToExisting, notApplied, List.of());
        }
    }

    /** 만든 경로 하나가 어떻게 됐는지 */
    enum Fate {
        /** 뽑혀서 앱에 보냄(rank 1~3) */
        PICKED,
        /** 거리가 1~100km 밖이거나 목표 거리 허용 범위(한 바퀴 ±5% · 왕복 ±10%) 밖 */
        OUT_OF_RANGE,
        /** 한 바퀴인데 같은 길을 20% 넘게 되돌아옴 */
        TOO_MUCH_RETRACE,
        /** 기존 활성 코스와 85% 이상 겹침 */
        SIMILAR_TO_EXISTING,
        /** 먼저 뽑힌 후보와 85% 이상 겹침 */
        SIMILAR_TO_PICKED,
        /** 조건은 통과했지만 점수가 낮아 3개를 다 고르기 전에 차례가 오지 않음 */
        NOT_EXAMINED
    }

    /**
     * 분석 로그의 경로 하나. 조건에서 걸러진 경로는 점수 · 편의점 · 오르막 · 길 비율을 재지 않아 null이다.
     * 편의점 · 화장실 · 오르막은 원하는 길로 고르지 않았으면 뽑힌 경로만 잰다.
     *
     * @param order  만든 순서(1부터)
     * @param rank   뽑힌 순위(1~3). 안 뽑혔으면 null
     * @param score  고르기 점수(클수록 앞). 조건에서 걸렸으면 null
     * @param points 경로 점(2m 기준으로 줄임. 뽑힌 경로는 앱에 보낸 입력점)
     */
    record PathLog(int order, Fate fate, Integer rank, int distanceMeters, double retraceRatio, double arterialRatio, Double score,
                   Integer storeCount, Integer toiletCount, Integer ascentMeters, Double sidewalkRatio, Double riverRatio,
                   Double litRatio, List<GeoPoint> points) {
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

    /**
     * @param order 만든 순서(0부터). 분석 로그 칸 번호
     * @param pois  점수에 쓰지 않았으면 null
     */
    private record Scored(int order, RoutedPath path, LineString line, int meters, double retrace, double arterial, PoiCounts pois, Integer ascent,
                          Double sidewalk, Double river, Double lit, double score) {
    }
}
