package com.wadadak.course.internal.registration;

import com.wadadak.common.geo.GeoPoint;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

class GpsGapRuleTest {

    /** 빈칸 앞 조각의 끝 점 */
    private static final GeoPoint GAP_START = new GeoPoint(37.5, 127.0);

    private static final double M_PER_DEG_LAT = Math.PI * GeoPoint.EARTH_RADIUS_M / 180;

    @Test
    void oneSegmentPasses() {
        assertThat(GpsGapRule.passes(List.of(leaving(GAP_START, 0, 50)))).isTrue();
    }

    @Test
    void noRouteFails() {
        assertThat(GpsGapRule.passes(List.of())).isFalse();
        assertThat(GpsGapRule.passes(List.of(List.of(), List.of(GAP_START)))).isFalse();
    }

    @Test
    void joinsGapUpTo20mWithoutLookingAtDirection() {
        // 앞은 북쪽, 빈칸은 동쪽, 뒤는 남쪽으로 꺾여도 20m 이하면 잇는다
        List<GeoPoint> before = arriving(GAP_START, 0, 50);
        GeoPoint next = move(GAP_START, 90, 19.9);
        assertThat(GpsGapRule.passes(List.of(before, leaving(next, 180, 50)))).isTrue();

        GeoPoint far = move(GAP_START, 90, 20.1);
        assertThat(GpsGapRule.passes(List.of(before, leaving(far, 180, 50)))).isFalse();
    }

    @Test
    void joinsLongGapWhenBothSidesHeadAlongIt() {
        GeoPoint next = move(GAP_START, 0, 500);
        assertThat(GpsGapRule.passes(List.of(arriving(GAP_START, 0, 50), leaving(next, 0, 50)))).isTrue();
        // 양쪽이 10°씩 어긋나도 15° 안
        assertThat(GpsGapRule.passes(List.of(arriving(GAP_START, 10, 50), leaving(next, -10, 50)))).isTrue();
    }

    @Test
    void longGapFailsWhenEitherSideTurnsMoreThan15Degrees() {
        GeoPoint next = move(GAP_START, 0, 100);
        assertThat(GpsGapRule.passes(List.of(arriving(GAP_START, 20, 50), leaving(next, 0, 50)))).isFalse();
        assertThat(GpsGapRule.passes(List.of(arriving(GAP_START, 0, 50), leaving(next, 20, 50)))).isFalse();
    }

    @Test
    void longGapFailsWhenSideIsTooShortToMeasureDirection() {
        GeoPoint next = move(GAP_START, 0, 100);
        assertThat(GpsGapRule.passes(List.of(arriving(GAP_START, 0, 15), leaving(next, 0, 50)))).isFalse();
        assertThat(GpsGapRule.passes(List.of(arriving(GAP_START, 0, 50), leaving(next, 0, 15)))).isFalse();
    }

    @Test
    void directionUsesOnlyTheLast20mBeforeTheGap() {
        // 동쪽으로 100m 달리다 북쪽으로 꺾어 30m 뒤 끊김, 빈칸도 북쪽
        List<GeoPoint> before = new ArrayList<>(arriving(move(GAP_START, 180, 30), 90, 100));
        before.addAll(leaving(move(GAP_START, 180, 30), 0, 30));
        GeoPoint next = move(GAP_START, 0, 100);
        assertThat(GpsGapRule.passes(List.of(before, leaving(next, 0, 50)))).isTrue();
    }

    @Test
    void directionIgnoresJitterNearTheGap() {
        // 끊기기 직전 제자리에서 흔들려도 직선 20m 떨어진 점까지의 방향을 본다
        List<GeoPoint> before = new ArrayList<>(arriving(GAP_START, 0, 50));
        for (int i = 0; i < 6; i++) {
            before.add(move(GAP_START, i * 60, 4));
        }
        before.add(GAP_START);
        GeoPoint next = move(GAP_START, 0, 100);
        assertThat(GpsGapRule.passes(List.of(before, leaving(next, 0, 50)))).isTrue();
    }

    @Test
    void everyGapMustPassAndEmptySegmentsAreSkipped() {
        GeoPoint second = move(GAP_START, 0, 10);
        GeoPoint third = move(second, 0, 50 + 100);
        List<GeoPoint> a = arriving(GAP_START, 0, 50);
        List<GeoPoint> b = leaving(second, 0, 50);
        assertThat(GpsGapRule.passes(List.of(a, List.of(), b, leaving(third, 0, 50)))).isTrue();
        assertThat(GpsGapRule.passes(List.of(a, List.of(), b, leaving(third, 30, 50)))).isFalse();
    }

    @Test
    void bearingAndAngleWrapAroundNorth() {
        assertThat(GpsGapRule.bearing(GAP_START, move(GAP_START, 90, 100))).isCloseTo(90, within(0.01));
        assertThat(GpsGapRule.bearing(GAP_START, move(GAP_START, -5, 100))).isCloseTo(355, within(0.01));
        assertThat(GpsGapRule.angleBetween(355, 5)).isCloseTo(10, within(1e-9));
        assertThat(GpsGapRule.angleBetween(90, 270)).isCloseTo(180, within(1e-9));
    }

    /** p에서 heading(°) 방향으로 meters 간 점. 100m 안에서는 평면 근사로 충분하다 */
    private static GeoPoint move(GeoPoint p, double heading, double meters) {
        double h = Math.toRadians(heading);
        double north = meters * Math.cos(h);
        double east = meters * Math.sin(h);
        return new GeoPoint(p.lat() + north / M_PER_DEG_LAT,
                p.lng() + east / (M_PER_DEG_LAT * Math.cos(Math.toRadians(p.lat()))));
    }

    /** from에서 heading 방향으로 length m를 5m 간격으로 달린 조각 */
    private static List<GeoPoint> leaving(GeoPoint from, double heading, double length) {
        List<GeoPoint> points = new ArrayList<>();
        for (double d = 0; d <= length + 1e-9; d += 5) {
            points.add(move(from, heading, d));
        }
        return points;
    }

    /** heading 방향으로 length m를 달려 to에서 끝나는 조각 */
    private static List<GeoPoint> arriving(GeoPoint to, double heading, double length) {
        List<GeoPoint> points = new ArrayList<>(leaving(move(to, heading + 180, length), heading, length));
        points.set(points.size() - 1, to);
        return points;
    }
}
