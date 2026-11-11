package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.atMost;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/** 가짜 길찾기: 길이 = 점을 직선으로 이은 길이 × 1.3(길은 직선보다 길다). 반지름에 비례하므로 반지름 고치기를 확인할 수 있다. */
class CandidateGeneratorTest {

    private static final GeoPoint START = new GeoPoint(36.7983, 127.0746);
    private static final Instant NOW = Instant.parse("2026-11-10T03:00:00Z");
    private static final Instant FAR = NOW.plusSeconds(60);

    private final RoutingClient routing = mock(RoutingClient.class);

    @Test
    void loopFitsTargetWithinFiveTries() {
        roadsAreLongerThanStraight();
        when(routing.roundTrip(any(), anyInt(), anyLong())).thenAnswer(a -> path(List.of(START, START), 4_900));

        List<RoutedPath> paths = generator(fixed()).generate(Shape.LOOP, START, null, 5_000, FAR);

        // 원 12개 + round_trip 12개
        assertThat(paths).hasSize(24);
        assertThat(paths.subList(0, 12)).allSatisfy(p -> assertThat(p.distanceMeters()).isCloseTo(5_000, within(250.0)));
        verify(routing, atMost(12 * CandidateGenerator.LOOP_MAX_TRIES)).route(any(), anyBoolean());
    }

    @Test
    void dropsFailedAndZeroLengthDirections() {
        // 출발점보다 북쪽 500m 넘는 경유점이 있으면 길이 없다(바다), round_trip은 길이 0(고립된 길)
        when(routing.route(any(), anyBoolean())).thenAnswer(a -> {
            List<GeoPoint> points = a.getArgument(0);
            if (points.stream().anyMatch(p -> p.lat() > START.lat() + 0.0045)) {
                throw new IllegalStateException("길 없음");
            }
            return path(points, 1.3 * straight(points));
        });
        when(routing.roundTrip(any(), anyInt(), anyLong())).thenAnswer(a -> path(List.of(START, START), 0));

        List<RoutedPath> paths = generator(fixed()).generate(Shape.LOOP, START, null, 5_000, FAR);

        assertThat(paths).isNotEmpty().hasSizeLessThan(12).allSatisfy(p -> assertThat(p.distanceMeters()).isPositive());
    }

    @Test
    void stopsAtDeadline() {
        roadsAreLongerThanStraight();

        assertThat(generator(fixed()).generate(Shape.LOOP, START, null, 5_000, NOW)).isEmpty();
        verifyNoInteractions(routing);
    }

    @Test
    void returnsWhatItHasWhenDeadlinePassesMidway() {
        roadsAreLongerThanStraight();
        // 시계를 볼 때마다 1초 지난다. 기한 10초면 길찾기 몇 번 만에 끝난다
        Clock ticking = new Clock() {
            private Instant now = NOW;

            @Override
            public ZoneId getZone() {
                return ZoneOffset.UTC;
            }

            @Override
            public Clock withZone(ZoneId zone) {
                return this;
            }

            @Override
            public Instant instant() {
                now = now.plusSeconds(1);
                return now;
            }
        };

        List<RoutedPath> paths = generator(ticking).generate(Shape.LOOP, START, null, 5_000, NOW.plusSeconds(10));

        assertThat(paths).isNotEmpty().hasSizeLessThan(12);
    }

    @Test
    void outAndBackTurnsAtSixHeadings() {
        roadsAreLongerThanStraight();

        List<RoutedPath> paths = generator(fixed()).generate(Shape.OUT_AND_BACK, START, null, 5_000, FAR);

        assertThat(paths).hasSize(6).allSatisfy(p -> {
            assertThat(p.points()).hasSize(3);
            assertThat(p.points().getFirst()).isEqualTo(p.points().getLast());
            // 반환점은 목표/2/1.25 = 2km
            assertThat(START.distanceMeters(p.points().get(1))).isCloseTo(2_000, within(1.0));
        });
    }

    @Test
    void pointToPointAndVia() {
        roadsAreLongerThanStraight();
        GeoPoint place = new GeoPoint(36.8050, 127.0800);

        assertThat(generator(fixed()).generate(Shape.POINT_TO_POINT, START, place, null, FAR))
                .singleElement().satisfies(p -> assertThat(p.points()).containsExactly(START, place));

        List<RoutedPath> via = generator(fixed()).generate(Shape.VIA, START, place, null, FAR);
        assertThat(via).hasSize(3);
        // 경유지 옆으로 400 · 800 · 1200m 비켜 돌아온다
        assertThat(via).extracting(p -> (int) Math.round(place.distanceMeters(p.points().get(2)))).containsExactly(400, 800, 1200);
        assertThat(via).allSatisfy(p -> assertThat(p.points()).first().isEqualTo(START));
    }

    private void roadsAreLongerThanStraight() {
        when(routing.route(any(), anyBoolean())).thenAnswer(a -> {
            List<GeoPoint> points = a.getArgument(0);
            return path(points, 1.3 * straight(points));
        });
    }

    private CandidateGenerator generator(Clock clock) {
        return new CandidateGenerator(routing, clock);
    }

    private static Clock fixed() {
        return Clock.fixed(NOW, ZoneOffset.UTC);
    }

    private static RoutedPath path(List<GeoPoint> points, double meters) {
        return new RoutedPath(points, meters, List.of());
    }

    private static double straight(List<GeoPoint> points) {
        double meters = 0;
        for (int i = 0; i + 1 < points.size(); i++) {
            meters += points.get(i).distanceMeters(points.get(i + 1));
        }
        return meters;
    }
}
