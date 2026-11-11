package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.function.DoubleFunction;
import java.util.function.Supplier;

/**
 * 모양별 후보 경로를 만든다. 고르기 전 원재료라 거리 · 되돌아감은 {@link CandidateSelector}가 본다.
 * 상수와 계산은 검증 스크립트({@code utilfile/_스크립트/course_planner/gh_national.py} · {@code e2e.py})와 같다.
 * 왕복은 스크립트와 달리 한 바퀴처럼 반환점 거리를 고친다(고르기가 목표 ±10%만 남기므로).
 * 길찾기 호출 전마다 기한을 보고, 지났으면 그때까지 만든 후보만 돌려준다(앱 대기 15초 안에 답하려고).
 * 길찾기가 실패한 방향(바다 · 고립된 길 · 타임아웃)은 버리고 다음 방향으로 간다.
 */
@Component
@RequiredArgsConstructor
class CandidateGenerator {

    /** 한 바퀴: 30°마다 원 하나 */
    static final int LOOP_HEADING_STEP = 30;
    /** 한 방향에서 반지름 · 반환점 거리를 고치는 최대 횟수 */
    static final int MAX_TRIES = 5;
    /** 한 바퀴: 엔진의 round_trip으로 더 만드는 후보 수 */
    static final int ROUND_TRIP_SEEDS = 12;
    /** 왕복: 60°마다 */
    static final int OUT_AND_BACK_HEADING_STEP = 60;
    /** 길은 직선보다 약 25% 길다. 첫 반지름 · 왕복 반환점 거리를 이만큼 줄여 잡는다 */
    static final double DETOUR = 1.25;
    /** 경유: 경유지에서 옆으로 비켜 돌아오는 점. 같은 길로 되돌아오지 않게 한다 */
    static final int VIA_SIDE_STEP_METERS = 400;
    static final int VIA_CANDIDATES = 3;

    private final RoutingClient routing;
    private final Clock clock;

    /**
     * @param place        편도의 도착지 또는 경유의 경유지. 한 바퀴 · 왕복은 null
     * @param targetMeters 한 바퀴 · 왕복의 목표 거리(m). 편도 · 경유는 쓰지 않는다
     */
    List<RoutedPath> generate(Shape shape, GeoPoint start, GeoPoint place, Integer targetMeters, Instant deadline) {
        List<RoutedPath> paths = new ArrayList<>();
        switch (shape) {
            case LOOP -> loops(start, targetMeters, deadline, paths);
            case OUT_AND_BACK -> {
                for (int heading = 0; heading < 360; heading += OUT_AND_BACK_HEADING_STEP) {
                    int h = heading;
                    addIfPresent(paths, fit(targetMeters / 2.0 / DETOUR, targetMeters, CandidateSelector.OUT_AND_BACK_TOLERANCE,
                            deadline, half -> routing.route(List.of(start, destination(start, half, h), start), false)));
                }
            }
            case POINT_TO_POINT -> {
                if (!expired(deadline)) {
                    addIfRouted(paths, () -> routing.route(List.of(start, place), false));
                }
            }
            case VIA -> {
                for (int i = 0; i < VIA_CANDIDATES && !expired(deadline); i++) {
                    GeoPoint side = destination(place, VIA_SIDE_STEP_METERS * (i + 1), i * 120);
                    addIfRouted(paths, () -> routing.route(List.of(start, place, side, start), true));
                }
            }
        }
        return paths;
    }

    /** 출발점을 지나는 원 위의 경유점 3개로 돈다 */
    private void loops(GeoPoint start, int targetMeters, Instant deadline, List<RoutedPath> paths) {
        for (int heading = 0; heading < 360; heading += LOOP_HEADING_STEP) {
            int h = heading;
            addIfPresent(paths, fit(targetMeters / (2 * Math.PI * DETOUR), targetMeters, CandidateSelector.LOOP_TOLERANCE,
                    deadline, radius -> routing.route(circle(start, radius, h), true)));
        }
        for (long seed = 0; seed < ROUND_TRIP_SEEDS && !expired(deadline); seed++) {
            long s = seed;
            addIfRouted(paths, () -> routing.roundTrip(start, targetMeters, s));
        }
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
