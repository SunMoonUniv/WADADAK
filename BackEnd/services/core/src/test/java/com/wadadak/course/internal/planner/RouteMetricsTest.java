package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.RoutedPath.RoadClassSpan;
import org.junit.jupiter.api.Test;

import java.util.List;

import static com.wadadak.course.internal.planner.CandidateGenerator.destination;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

class RouteMetricsTest {

    private static final GeoPoint START = new GeoPoint(36.7983, 127.0746);

    @Test
    void outAndBackOnSameRoadIsAlmostAllRetrace() {
        GeoPoint turn = destination(START, 2_000, 0);

        // 반환점 앞뒤 75m(경로 150m 안)만 빠진다
        assertThat(RouteMetrics.retraceRatio(List.of(START, turn, START))).isGreaterThan(0.9);
    }

    @Test
    void squareLoopHasAlmostNoRetrace() {
        GeoPoint north = destination(START, 1_000, 0);
        GeoPoint northEast = destination(north, 1_000, 90);
        GeoPoint east = destination(START, 1_000, 90);

        // 출발과 도착이 만나는 곳(앞뒤 몇 점)만 세진다. 검증 스크립트도 같다(선문대 5km 실측 0.4%)
        assertThat(RouteMetrics.retraceRatio(List.of(START, north, northEast, east, START))).isLessThan(0.02);
    }

    @Test
    void shortUTurnIsNotRetrace() {
        // 1km 직진 끝에서 60m 골목에 들어갔다 나온다. 경로를 따라 150m 안이라 세지 않는다
        GeoPoint end = destination(START, 1_000, 0);
        GeoPoint alley = destination(end, 60, 90);

        assertThat(RouteMetrics.retraceRatio(List.of(START, end, alley, end))).isZero();
    }

    @Test
    void arterialRatioCountsTrunkPrimarySecondaryOnly() {
        GeoPoint a = destination(START, 100, 0);
        GeoPoint b = destination(a, 300, 0);
        List<GeoPoint> points = List.of(START, a, b);

        assertThat(RouteMetrics.arterialRatio(new RoutedPath(points, 400, List.of(new RoadClassSpan(1, 2, "primary")))))
                .isCloseTo(0.75, within(0.01));
        assertThat(RouteMetrics.arterialRatio(new RoutedPath(points, 400,
                List.of(new RoadClassSpan(0, 1, "residential"), new RoadClassSpan(1, 2, "tertiary"))))).isZero();
    }
}
