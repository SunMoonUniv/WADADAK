package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.RoadLayers.Layer;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.DoubleFunction;
import java.util.function.Supplier;

/**
 * 모양별 후보 경로를 만든다. 고르기 전 원재료라 거리 · 되돌아감은 {@link CandidateSelector}가 본다.
 * 상수와 계산은 검증 스크립트({@code utilfile/_스크립트/course_planner/gh_national.py} · {@code e2e.py})와 같다.
 * 왕복은 스크립트와 달리 한 바퀴처럼 반환점 거리를 고친다(고르기가 목표 ±10%만 남기므로).
 * 길찾기 호출 전마다 기한을 보고, 지났으면 그때까지 만든 후보만 돌려준다(앱 대기 15초 안에 답하려고).
 * 길찾기가 실패한 방향(바다 · 고립된 길 · 타임아웃)은 버리고 다음 방향으로 간다.
 *
 * <p>원하는 길 중 큰길 피하기 · 강변은 길찾기 비용에 넣어 처음부터 그 길로 가게 하고({@link RoutingClient#costModel}),
 * 강변은 한 바퀴의 경유점 · 왕복의 반환점도 가까운 하천으로 옮긴다({@link RoadLayers#snap}). 그다음 {@link CandidateSelector}가
 * 모든 원하는 길로 점수를 매긴다. 인도 · 밝은 길은 비용에 넣지 않는다: 5곳 실측에서 점수만으로 인도 0.95 · 밝은 길 0.86이던 비율이
 * 0.96 · 0.88로만 오르고 응답은 3~4배(최대 6.8초) 느려졌다(구역이 잘게 쪼개져 크다). 하천은 0.32 → 0.44였다.
 * 평지 · 오르막도 넣지 않는다: 표고점으로 경사를 넣은 그래프에서 12곳을 재 보니 1km당 오르막이 평지 7.8 → 7.6m · 오르막 29.4 → 27.0m로
 * 나아지지 않았다. 원 위 경유점이 경로 모양을 거의 정해 방향별 평균만 줄고, 고르는 데 쓰는 가장 좋은 방향은 그대로였다.
 */
@Component
@RequiredArgsConstructor
class CandidateGenerator {

    /** 한 바퀴: 한 라운드에 30°마다 원 하나 */
    static final int LOOP_HEADING_STEP = 30;
    /** 한 방향에서 반지름 · 반환점 거리를 고치는 최대 횟수 */
    static final int MAX_TRIES = 5;
    /** 한 바퀴: 한 라운드에 엔진의 round_trip으로 더 만드는 후보 수 */
    static final int ROUND_TRIP_SEEDS = 12;
    /** 왕복: 한 라운드에 60°마다 */
    static final int OUT_AND_BACK_HEADING_STEP = 60;
    /**
     * 라운드 수. 둘째 라운드는 방향을 반 칸(한 바퀴 15° · 왕복 30°) 비키고 round_trip 씨앗도 새로 쓴다. 그래서 한 바퀴는 24방향 + round_trip 24개,
     * 왕복은 12방향이다. 기본 방향을 먼저 다 돌아 기한에 걸려도 첫 라운드 후보는 남는다.
     * 라운드가 하나면 학교 · 산 옆처럼 길이 적은 곳(선문대 4km)에서 거리 · 되돌아감을 통과하는 후보가 1개뿐이었다
     */
    static final int ROUNDS = 2;
    /** 길은 직선보다 약 25% 길다. 첫 반지름 · 왕복 반환점 거리를 이만큼 줄여 잡는다 */
    static final double DETOUR = 1.25;
    /** 경유: 경유지에서 옆으로 비켜 돌아오는 점. 같은 길로 되돌아오지 않게 한다 */
    static final int VIA_SIDE_STEP_METERS = 400;
    static final int VIA_CANDIDATES = 3;
    /** 강변: 경유점 · 반환점에서 원 반지름 · 반환점 거리의 이 비율 안에 하천이 있으면 그리로 옮긴다 */
    static final double RIVER_SNAP_RATIO = 0.5;
    /** 편도 · 경유의 비용 구역 반경: 출발에서 도착 · 경유지까지 거리 + 이만큼(m). 경유는 옆으로 최대 1,200m 비켜 돈다 */
    private static final double PLACE_AREA_MARGIN_METERS = 1_500;

    private final RoutingClient routing;
    private final RoadLayers layers;
    private final Clock clock;

    /**
     * @param place        편도의 도착지 또는 경유의 경유지. 한 바퀴 · 왕복은 null
     * @param targetMeters 한 바퀴 · 왕복의 목표 거리(m). 편도 · 경유는 쓰지 않는다
     * @param prefer       원하는 길. null이면 없음
     */
    List<RoutedPath> generate(Shape shape, GeoPoint start, GeoPoint place, Integer targetMeters, Set<Pref> prefer, Instant deadline) {
        Set<Pref> wants = prefer == null ? Set.of() : prefer;
        boolean river = wants.contains(Pref.RIVER);
        // 한 바퀴 · 왕복은 출발에서 목표의 절반 넘게 멀어지지 않는다
        double reach = place == null ? targetMeters / 2.0 : start.distanceMeters(place) + PLACE_AREA_MARGIN_METERS;
        Map<String, Object> cost = costModel(wants, start, reach);
        List<RoutedPath> paths = new ArrayList<>();
        switch (shape) {
            case LOOP -> loops(start, targetMeters, cost, river, deadline, paths);
            case OUT_AND_BACK -> {
                for (int round = 0; round < ROUNDS; round++) {
                    for (int heading = round * OUT_AND_BACK_HEADING_STEP / ROUNDS; heading < 360; heading += OUT_AND_BACK_HEADING_STEP) {
                        int h = heading;
                        addIfPresent(paths, fit(targetMeters / 2.0 / DETOUR, targetMeters, CandidateSelector.OUT_AND_BACK_TOLERANCE,
                                deadline, half -> routing.route(List.of(start, toRiver(river, destination(start, half, h), half), start),
                                        false, cost)));
                    }
                }
            }
            case POINT_TO_POINT -> {
                if (!expired(deadline)) {
                    addIfRouted(paths, () -> routing.route(List.of(start, place), false, cost));
                }
            }
            case VIA -> {
                for (int i = 0; i < VIA_CANDIDATES && !expired(deadline); i++) {
                    GeoPoint side = destination(place, VIA_SIDE_STEP_METERS * (i + 1), i * 120);
                    addIfRouted(paths, () -> routing.route(List.of(start, place, side, start), true, cost));
                }
            }
        }
        return paths;
    }

    /** 출발점을 지나는 원 위의 경유점 3개로 돈다 */
    private void loops(GeoPoint start, int targetMeters, Map<String, Object> cost, boolean river, Instant deadline, List<RoutedPath> paths) {
        for (int round = 0; round < ROUNDS; round++) {
            for (int heading = round * LOOP_HEADING_STEP / ROUNDS; heading < 360; heading += LOOP_HEADING_STEP) {
                int h = heading;
                addIfPresent(paths, fit(targetMeters / (2 * Math.PI * DETOUR), targetMeters, CandidateSelector.LOOP_TOLERANCE,
                        deadline, radius -> routing.route(circle(start, radius, h).stream()
                                .map(p -> p.equals(start) ? p : toRiver(river, p, radius)).toList(), true, cost)));
            }
            for (long seed = (long) round * ROUND_TRIP_SEEDS; seed < (round + 1L) * ROUND_TRIP_SEEDS && !expired(deadline); seed++) {
                long s = seed;
                addIfRouted(paths, () -> routing.roundTrip(start, targetMeters, s, cost));
            }
        }
    }

    /** 원하는 길의 길찾기 비용. 강변은 출발에서 reach 안의 하천을 구역으로 보낸다(파일이 없거나 하천이 없으면 뺀다). 없으면 null */
    private Map<String, Object> costModel(Set<Pref> wants, GeoPoint start, double reach) {
        List<List<List<List<Double>>>> river = wants.contains(Pref.RIVER) ? layers.area(Layer.RIVER, start, reach) : null;
        return RoutingClient.costModel(wants.contains(Pref.AVOID_ARTERIAL), river == null ? Map.of() : Map.of("river", river));
    }

    /** 강변을 원하면 point를 size × {@value #RIVER_SNAP_RATIO} 안의 하천 가까운 점으로 옮긴다. 하천이 없으면 그대로 */
    private GeoPoint toRiver(boolean river, GeoPoint point, double size) {
        return river ? layers.snap(Layer.RIVER, point, size * RIVER_SNAP_RATIO) : point;
    }

    /**
     * 한 방향의 경로. 거리가 목표 ±tolerance에 들 때까지 크기(원 반지름 · 반환점 거리)를 목표/실제 비율로 고친다(최대 {@value #MAX_TRIES}회).
     * 길은 방향마다 직선보다 길어지는 정도가 달라(선문대 왕복 실측 +16~72%) 한 번에 맞지 않는다.
     *
     * @return 목표에 가장 가까운 경로. 길이 없거나 기한이 먼저 지나면 null
     */
    private RoutedPath fit(double size, int targetMeters, double tolerance, Instant deadline, DoubleFunction<RoutedPath> routeFor) {
        RoutedPath best = null;
        for (int i = 0; i < MAX_TRIES && !expired(deadline); i++) {
            double s = size;
            RoutedPath path = routeOrNull(() -> routeFor.apply(s));
            if (path == null) {
                break;
            }
            if (best == null || Math.abs(error(path, targetMeters)) < Math.abs(error(best, targetMeters))) {
                best = path;
            }
            if (Math.abs(error(path, targetMeters)) <= tolerance) {
                break;
            }
            size *= targetMeters / path.distanceMeters();
        }
        return best;
    }

    /** 출발 → 원 위 경유점 3개 → 출발. 원의 중심은 출발점에서 heading 방향으로 radius만큼 */
    static List<GeoPoint> circle(GeoPoint start, double radius, int heading) {
        GeoPoint center = destination(start, radius, heading);
        int back = heading + 180;
        List<GeoPoint> points = new ArrayList<>(List.of(start));
        for (int i = 1; i <= 3; i++) {
            points.add(destination(center, radius, back + 90 * i));
        }
        points.add(start);
        return points;
    }

    /** from에서 bearing(도, 북쪽 0 · 시계 방향)으로 meters만큼 간 점. 구면 공식 */
    static GeoPoint destination(GeoPoint from, double meters, double bearing) {
        double b = Math.toRadians(bearing);
        double lat1 = Math.toRadians(from.lat());
        double lng1 = Math.toRadians(from.lng());
        double d = meters / GeoPoint.EARTH_RADIUS_M;
        double lat2 = Math.asin(Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(b));
        double lng2 = lng1 + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(lat1), Math.cos(d) - Math.sin(lat1) * Math.sin(lat2));
        return new GeoPoint(Math.toDegrees(lat2), Math.toDegrees(lng2));
    }

    private static double error(RoutedPath path, int targetMeters) {
        return (path.distanceMeters() - targetMeters) / targetMeters;
    }

    private static void addIfRouted(List<RoutedPath> paths, Supplier<RoutedPath> call) {
        addIfPresent(paths, routeOrNull(call));
    }

    private static void addIfPresent(List<RoutedPath> paths, RoutedPath path) {
        if (path != null) {
            paths.add(path);
        }
    }

    /** 실패하거나 길이가 0이면(경유점이 모두 출발점에 붙은 고립된 길) null */
    private static RoutedPath routeOrNull(Supplier<RoutedPath> call) {
        try {
            RoutedPath path = call.get();
            return path.distanceMeters() > 0 ? path : null;
        } catch (RuntimeException e) {
            return null;
        }
    }

    private boolean expired(Instant deadline) {
        return !clock.instant().isBefore(deadline);
    }
}
