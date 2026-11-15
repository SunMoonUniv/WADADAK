package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.RoadLayers.CellSet;
import com.wadadak.course.internal.planner.RoadLayers.Layer;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.IntStream;

import static com.wadadak.course.internal.planner.CandidateGenerator.destination;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.atMost;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
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
        when(routing.roundTrip(any(), anyInt(), anyLong(), any())).thenAnswer(a -> path(List.of(START, START), 4_900));

        List<RoutedPath> paths = generator(fixed()).generate(Shape.LOOP, START, null, 5_000, Set.of(), FAR);

        // 30°마다 원 12개 + round_trip 12개(씨앗 0~11), 그다음 15° 비킨 원 12개 + round_trip 12개(씨앗 12~23)
        assertThat(paths).hasSize(48);
        assertThat(paths.subList(0, 12)).allSatisfy(p -> assertThat(p.distanceMeters()).isCloseTo(5_000, within(250.0)));
        assertThat(paths.subList(24, 36)).allSatisfy(p -> assertThat(p.distanceMeters()).isCloseTo(5_000, within(250.0)));
        verify(routing).roundTrip(START, 5_000, 23, null);
        verify(routing, atMost(24 * CandidateGenerator.MAX_TRIES)).route(any(), anyBoolean(), any());
    }

    @Test
    void dropsFailedAndZeroLengthDirections() {
        // 출발점보다 북쪽 500m 넘는 경유점이 있으면 길이 없다(바다), round_trip은 길이 0(고립된 길)
        when(routing.route(any(), anyBoolean(), any())).thenAnswer(a -> {
            List<GeoPoint> points = a.getArgument(0);
            if (points.stream().anyMatch(p -> p.lat() > START.lat() + 0.0045)) {
                throw new IllegalStateException("길 없음");
            }
            return path(points, 1.3 * straight(points));
        });
        when(routing.roundTrip(any(), anyInt(), anyLong(), any())).thenAnswer(a -> path(List.of(START, START), 0));

        List<RoutedPath> paths = generator(fixed()).generate(Shape.LOOP, START, null, 5_000, Set.of(), FAR);

        assertThat(paths).isNotEmpty().hasSizeLessThan(24).allSatisfy(p -> assertThat(p.distanceMeters()).isPositive());
    }

    @Test
    void stopsAtDeadline() {
        roadsAreLongerThanStraight();

        assertThat(generator(fixed()).generate(Shape.LOOP, START, null, 5_000, Set.of(), NOW)).isEmpty();
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

        List<RoutedPath> paths = generator(ticking).generate(Shape.LOOP, START, null, 5_000, Set.of(), NOW.plusSeconds(10));

        assertThat(paths).isNotEmpty().hasSizeLessThan(12);
    }

    @Test
    void outAndBackTurnsAtTwelveHeadings() {
        roadsAreLongerThanStraight();

        List<RoutedPath> paths = generator(fixed()).generate(Shape.OUT_AND_BACK, START, null, 5_000, Set.of(), FAR);

        assertThat(paths).hasSize(12).allSatisfy(p -> {
            assertThat(p.points()).hasSize(3);
            assertThat(p.points().getFirst()).isEqualTo(p.points().getLast());
            // 반환점은 목표/2/1.25 = 2km
            assertThat(START.distanceMeters(p.points().get(1))).isCloseTo(2_000, within(1.0));
        });
        // 60°마다 6개 뒤에 30° 비킨 6개. 7번째 반환점은 출발점에서 북동(30°)
        GeoPoint turn = paths.get(6).points().get(1);
        assertThat(turn.lat()).isGreaterThan(START.lat());
        assertThat(turn.lng()).isGreaterThan(START.lng());
    }

    @Test
    void outAndBackFixesTurnDistance() {
        // 길이 직선의 1.6배면 첫 반환점(2km)으로는 6.4km(+28%)다. 반환점을 줄여 ±10% 안에 넣는다
        when(routing.route(any(), anyBoolean(), any())).thenAnswer(a -> {
            List<GeoPoint> points = a.getArgument(0);
            return path(points, 1.6 * straight(points));
        });

        List<RoutedPath> paths = generator(fixed()).generate(Shape.OUT_AND_BACK, START, null, 5_000, Set.of(), FAR);

        assertThat(paths).hasSize(12).allSatisfy(p -> assertThat(p.distanceMeters()).isCloseTo(5_000, within(500.0)));
        verify(routing, atMost(12 * CandidateGenerator.MAX_TRIES)).route(any(), anyBoolean(), any());
    }

    @Test
    void avoidArterialGoesIntoRoutingCost() {
        roadsAreLongerThanStraight();
        when(routing.roundTrip(any(), anyInt(), anyLong(), any())).thenAnswer(a -> path(List.of(START, START), 4_900));

        generator(fixed()).generate(Shape.LOOP, START, null, 5_000, Set.of(Pref.AVOID_ARTERIAL), FAR);

        verify(routing, never()).route(any(), anyBoolean(), isNull());
        verify(routing).roundTrip(eq(START), eq(5_000), eq(0L), argThat(m -> m.get("priority").toString().contains("road_class == TRUNK")
                && !m.containsKey("areas")));
    }

    @Test
    void layerPreferencesGoIntoRoutingCostAsAreas() {
        roadsAreLongerThanStraight();
        when(routing.roundTrip(any(), anyInt(), anyLong(), any())).thenAnswer(a -> path(List.of(START, START), 4_900));
        RoadLayers layers = new RoadLayers(Map.of(Layer.RIVER, CellSet.of(25, riverNorthOfStart())));

        // 강변은 구역으로 간다. 인도는 점수만 쓴다(비용에 넣지 않는다)
        new CandidateGenerator(routing, layers, fixed()).generate(Shape.LOOP, START, null, 5_000, Set.of(Pref.RIVER, Pref.SIDEWALK), FAR);

        verify(routing).roundTrip(eq(START), eq(5_000), eq(0L), argThat(m -> m.get("priority").toString().contains("!in_river")
                && !m.get("priority").toString().contains("in_sidewalk") && m.get("areas").toString().contains("id=river")));
    }

    @Test
    void riverMovesTurnPointToTheRiver() {
        roadsAreLongerThanStraight();
        RoadLayers layers = new RoadLayers(Map.of(Layer.RIVER, CellSet.of(25, riverNorthOfStart())));

        List<RoutedPath> paths = new CandidateGenerator(routing, layers, fixed())
                .generate(Shape.OUT_AND_BACK, START, null, 5_000, Set.of(Pref.RIVER), FAR);

        // 북동(30°) 반환점은 북쪽 1.73km라 하천(북쪽 2km)이 반경 1km 안이다. 하천으로 옮겨진다
        GeoPoint northEast = paths.get(6).points().get(1);
        assertThat(layers.ratio(Layer.RIVER, List.of(northEast, destination(northEast, 1, 90)))).isEqualTo(1.0);
        // 남쪽(180°) 반환점은 반경 안에 하천이 없어 그대로다
        assertThat(paths.get(3).points().get(1)).isEqualTo(destination(START, 2_000, 180));
    }

    @Test
    void pointToPointAndVia() {
        roadsAreLongerThanStraight();
        GeoPoint place = new GeoPoint(36.8050, 127.0800);

        assertThat(generator(fixed()).generate(Shape.POINT_TO_POINT, START, place, null, Set.of(), FAR))
                .singleElement().satisfies(p -> assertThat(p.points()).containsExactly(START, place));

        List<RoutedPath> via = generator(fixed()).generate(Shape.VIA, START, place, null, Set.of(), FAR);
        assertThat(via).hasSize(3);
        // 경유지 옆으로 400 · 800 · 1200m 비켜 돌아온다
        assertThat(via).extracting(p -> (int) Math.round(place.distanceMeters(p.points().get(2)))).containsExactly(400, 800, 1200);
        assertThat(via).allSatisfy(p -> assertThat(p.points()).first().isEqualTo(START));
    }

    /** 출발점 북쪽 2km를 지나 동서로 흐르는 하천(25m 칸, 좌우 1km) */
    private static long[] riverNorthOfStart() {
        GeoPoint riverMid = destination(START, 2_000, 0);
        return IntStream.rangeClosed(-40, 40)
                .mapToObj(i -> SpotHeights.tm5179(destination(riverMid, 25.0 * Math.abs(i), i < 0 ? 270 : 90)))
                .mapToLong(xy -> CellSet.key((long) Math.floor(xy[0] / 25), (long) Math.floor(xy[1] / 25))).distinct().sorted().toArray();
    }

    private void roadsAreLongerThanStraight() {
        when(routing.route(any(), anyBoolean(), any())).thenAnswer(a -> {
            List<GeoPoint> points = a.getArgument(0);
            return path(points, 1.3 * straight(points));
        });
    }

    private CandidateGenerator generator(Clock clock) {
        return new CandidateGenerator(routing, new RoadLayers(Map.of()), clock);
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
