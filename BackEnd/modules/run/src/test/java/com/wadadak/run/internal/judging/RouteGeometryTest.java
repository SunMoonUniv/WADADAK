package com.wadadak.run.internal.judging;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.judging.RouteGeometry.Projection;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * 코스 모양은 판정 기대값(run/판정 기대값 - 2026-10-12) 3장의 K1·K3·K4·K5.
 */
class RouteGeometryTest {

    static final double LAT0 = 37.5;
    static final double LNG0 = 127.0;

    /** 로컬 평면(m, x = 동, y = 북) → GeoPoint. {@link RouteGeometry#toLocal}의 역변환, 원점 (37.5, 127.0) */
    static GeoPoint geo(double x, double y) {
        double r = GeoPoint.EARTH_RADIUS_M;
        return new GeoPoint(
                LAT0 + Math.toDegrees(y / r),
                LNG0 + Math.toDegrees(x / (r * Math.cos(Math.toRadians(LAT0)))));
    }

    /** 꼭짓점 (x, y) 쌍을 출발 → 도착 순서로 받아 코스를 만든다 */
    static RouteGeometry course(double... xy) {
        GeoPoint[] points = new GeoPoint[xy.length / 2];
        for (int i = 0; i < points.length; i++) {
            points[i] = geo(xy[2 * i], xy[2 * i + 1]);
        }
        return new RouteGeometry(Arrays.asList(points));
    }

    static final RouteGeometry K1 = course(0, 0, 0, 1000);
    static final RouteGeometry K3 = course(0, 0, 0, 1000, 0, 0);
    static final RouteGeometry K4 = course(0, 0, 500, 0, 500, 500, 0, 500, 0, 0);
    static final RouteGeometry K5 = course(0, 0, 300, 300, 300, 0, 0, 300);

    /** 경로에서 3m 안의 후보 s 목록 */
    static List<Double> candidateS(RouteGeometry route, double x, double y) {
        return route.candidates(route.toLocal(geo(x, y)), 3).stream().map(Projection::s).toList();
    }

    @Test
    void lengthsMatchExpectedCourses() {
        assertThat(K1.length()).isCloseTo(1000, within(1e-6));
        assertThat(K3.length()).isCloseTo(2000, within(1e-6));
        assertThat(K4.length()).isCloseTo(2000, within(1e-6));
        assertThat(K5.length()).isCloseTo(1148.5, within(0.1));
    }

    @Test
    void projectsPointBesideStraightRoute() {
        Projection p = K1.project(K1.toLocal(geo(3, 400)), 0);

        assertThat(p.s()).isCloseTo(400, within(1e-6));
        assertThat(p.d()).isCloseTo(3, within(1e-6));
    }

    @Test
    void pointBeforeStartClampsToStart() {
        Projection p = K1.project(K1.toLocal(geo(0, -10)), 0);

        assertThat(p.s()).isCloseTo(0, within(1e-6));
        assertThat(p.d()).isCloseTo(10, within(1e-6));
    }

    @Test
    void figureEightCrossingHasTwoCandidates() {
        assertThat(candidateS(K5, 150, 150)).satisfiesExactly(
                s -> assertThat(s).isCloseTo(212.1, within(0.1)),
                s -> assertThat(s).isCloseTo(936.4, within(0.1)));
    }

    @Test
    void outAndBackHasOutboundAndReturnCandidates() {
        assertThat(candidateS(K3, 0, 300)).satisfiesExactly(
                s -> assertThat(s).isCloseTo(300, within(1e-6)),
                s -> assertThat(s).isCloseTo(1700, within(1e-6)));
    }

    @Test
    void loopStartIsBothStartAndFinish() {
        assertThat(candidateS(K4, 0, 0)).satisfiesExactly(
                s -> assertThat(s).isCloseTo(0, within(1e-6)),
                s -> assertThat(s).isCloseTo(2000, within(1e-6)));
    }

    @Test
    void cornerIsOneCandidate() {
        assertThat(candidateS(K4, 500, 0)).satisfiesExactly(
                s -> assertThat(s).isCloseTo(500, within(1e-6)));
    }

    @Test
    void farFromRouteHasNoCandidate() {
        assertThat(candidateS(K1, 100, 500)).isEmpty();
    }

    @Test
    void haversineAgreesWithPlaneOverShortDistance() {
        GeoPoint a = geo(88.22, 100.08);
        GeoPoint b = geo(92.63, 105.64);
        assertThat(a.distanceMeters(b))
                .isCloseTo(K1.toLocal(a).distanceTo(K1.toLocal(b)), within(0.01));
    }
}
