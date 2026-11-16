package com.wadadak.course.internal.registration;

import com.wadadak.common.geo.GeoPoint;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.function.DoubleUnaryOperator;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * 고도 프로필 기준(정책 문서 제4부 4.1 `B1-03 고도 프로필`). 경로는 북쪽으로 3m마다 한 점(1초에 한 점쯤)이라
 * 점 사이 거리가 정확히 3m다. 높이는 출발점부터 거리(m)로 정한다.
 */
class ElevationProfileTest {

    private static final double START_LAT = 37.5560;
    private static final double M_PER_DEG_LAT = Math.PI * GeoPoint.EARTH_RADIUS_M / 180;

    @Test
    void flatCourseHasNoClimbAndEvenBars() {
        ElevationProfile profile = ElevationProfile.of(List.of(north(0, 1800, d -> 31.5)));

        assertThat(profile.gainMeters()).isZero();
        assertThat(profile.samplesMeters()).hasSize(18).containsOnly(31.5);
    }

    @Test
    void barsAreTheAverageHeightOfEachEighteenthOfTheCourse() {
        // 1.8km 동안 0m에서 90m까지 고르게 오른다: 칸마다 100m, 평균은 5k + 2.5m
        ElevationProfile profile = ElevationProfile.of(List.of(north(0, 1800, d -> d / 20)));

        assertThat(profile.samplesMeters().getFirst()).isCloseTo(2.5, within(0.1));
        assertThat(profile.samplesMeters().get(9)).isCloseTo(47.5, within(0.1));
        assertThat(profile.samplesMeters().getLast()).isCloseTo(87.5, within(0.1));
        // 끝까지 오른 오르막도 센다
        assertThat(profile.gainMeters()).isEqualTo(90);
    }

    @Test
    void countsOnlyClimbsOfTenMetersOrMore() {
        // 30m 평지에 15m 언덕 하나와 6m 둔덕 하나
        DoubleUnaryOperator height = d -> 30 + hill(d, 300, 300, 15) + hill(d, 1200, 150, 6);

        assertThat(ElevationProfile.of(List.of(north(0, 1800, height))).gainMeters()).isEqualTo(15);
    }

    @Test
    void gpsWobbleIsNotAClimb() {
        // 평지에서 점마다 ±4m 흔들리고, 가끔 한 점만 25m 튄다
        DoubleUnaryOperator height = d -> 30 + (Math.round(d / 3) % 2 == 0 ? 4 : -4) + (Math.round(d) % 300 == 0 ? 25 : 0);

        ElevationProfile profile = ElevationProfile.of(List.of(north(0, 1800, height)));

        assertThat(profile.gainMeters()).isZero();
        assertThat(profile.samplesMeters()).allSatisfy(m -> assertThat(m).isBetween(25.0, 35.0));
    }

    @Test
    void doesNotJoinHeightsAcrossGapsOrSteps() {
        // 끊긴 조각 사이에서 25m 높아진다(조각 사이 10m는 직선으로 잇는다)
        ElevationProfile gapped = ElevationProfile.of(List.of(north(0, 900, d -> 30), north(910, 1810, d -> 55)));
        assertThat(gapped.gainMeters()).isZero();
        assertThat(gapped.samplesMeters().getFirst()).isEqualTo(30.0);
        assertThat(gapped.samplesMeters().getLast()).isEqualTo(55.0);

        // 한 조각 안에서 이웃 점과 26m 차이로 계단처럼 바뀐다(GPS 고도 기준이 바뀐 것처럼)
        assertThat(ElevationProfile.of(List.of(north(0, 1800, d -> d < 900 ? 30 : 56))).gainMeters()).isZero();
    }

    @Test
    void needsAltitudeOnNinetyPercentOfTheCourse() {
        // 1.8km에서 처음 150m(8%)만 고도가 없으면 만든다. 200m(11%)면 만들지 않는다
        assertThat(ElevationProfile.of(List.of(withoutAltitudeUntil(150, null)))).isNotNull();
        assertThat(ElevationProfile.of(List.of(withoutAltitudeUntil(200, null)))).isNull();
        // 고도 정확도가 20m보다 나쁜 점도 쓰지 않는다
        assertThat(ElevationProfile.of(List.of(withoutAltitudeUntil(200, 25.0)))).isNull();

        assertThat(ElevationProfile.of(List.of())).isNull();
        assertThat(ElevationProfile.of(List.of(north(0, 1800, d -> Double.NaN)))).isNull();
    }

    /** [start]부터 [length]m 동안 [rise]m 올랐다가 같은 거리 동안 내려오는 언덕 */
    private static double hill(double d, double start, double length, double rise) {
        double x = d - start;
        if (x < 0 || x > 2 * length) {
            return 0;
        }
        return rise * (x <= length ? x / length : 2 - x / length);
    }

    /** 1.8km 평지에서 처음 [meters]m는 고도가 없다. [accuracy]를 주면 고도는 있고 정확도가 그 값이다 */
    private static List<GpsSourcePoint> withoutAltitudeUntil(double meters, Double accuracy) {
        List<GpsSourcePoint> points = new ArrayList<>();
        for (GpsSourcePoint p : north(0, 1800, d -> 30)) {
            boolean missing = (p.lat() - START_LAT) * M_PER_DEG_LAT < meters - 1e-6;
            points.add(!missing ? p : new GpsSourcePoint(p.lat(), p.lng(), p.accuracyM(),
                    accuracy == null ? null : p.altitudeM(), accuracy == null ? null : accuracy));
        }
        return Collections.unmodifiableList(points);
    }

    /** 출발점에서 [fromM]m부터 [toM]m까지 북쪽으로 3m마다 한 점. 고도 정확도 3m */
    private static List<GpsSourcePoint> north(double fromM, double toM, DoubleUnaryOperator height) {
        List<GpsSourcePoint> points = new ArrayList<>();
        for (double d = fromM; d <= toM + 1e-9; d += 3) {
            points.add(new GpsSourcePoint(START_LAT + d / M_PER_DEG_LAT, 126.9000, 5.0, height.applyAsDouble(d), 3.0));
        }
        return points;
    }
}
