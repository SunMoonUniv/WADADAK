package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.time.Clock;
import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 실제 GraphHopper로 확인한다. CI에서는 돌지 않는다.
 * 로컬: {@code docker compose -f BackEnd/compose.yaml --profile planner up -d graphhopper} 후 {@code GRAPHHOPPER_URL=http://localhost:8989}.
 */
@EnabledIfEnvironmentVariable(named = "GRAPHHOPPER_URL", matches = ".+")
class RoutingClientIT {

    private static final GeoPoint SUNMOON = new GeoPoint(36.7983, 127.0746);

    private final RoutingClient routing = new RoutingClient(System.getenv("GRAPHHOPPER_URL"), Duration.ofSeconds(5));

    @Test
    void routesWithRoadClasses() {
        RoutedPath path = routing.route(List.of(SUNMOON, new GeoPoint(36.8050, 127.0800)), false);

        assertThat(path.distanceMeters()).isPositive();
        assertThat(path.points()).hasSizeGreaterThan(2);
        assertThat(path.roadClasses()).isNotEmpty();
    }

    @Test
    void sunmoon5kmLoopHasAtLeastThreeGoodCandidates() {
        Clock clock = Clock.systemUTC();
        List<RoutedPath> paths = new CandidateGenerator(routing, clock).generate(Shape.LOOP, SUNMOON, null, 5_000, clock.instant().plusSeconds(10));

        // 거리 ±5% · 되돌아감 20% 이하(검증 때 24개 중 6개 통과, 겹치지 않는 3개)
        long good = paths.stream()
                .filter(p -> Math.abs(p.distanceMeters() - 5_000) <= 250 && RouteMetrics.retraceRatio(p.points()) <= 0.2)
                .count();
        assertThat(good).isGreaterThanOrEqualTo(3);
    }
}
