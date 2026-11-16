package com.wadadak.common.geo;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;

class GeoPointTest {

    @Test
    void acceptsBoundaryValues() {
        assertThat(new GeoPoint(37.5665, 126.9780).lat()).isEqualTo(37.5665);
        new GeoPoint(-90, -180);
        new GeoPoint(90, 180);
    }

    @Test
    void rejectsSwappedKoreanCoordinate() {
        assertThatThrownBy(() -> new GeoPoint(126.9780, 37.5665))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CommonErrorCode.INVALID_REQUEST));
    }

    @Test
    void rejectsNaN() {
        assertThatThrownBy(() -> new GeoPoint(Double.NaN, 127)).isInstanceOf(AppException.class);
    }

    @Test
    void distanceMetersIsHaversine() {
        // 위도 1° = R × π / 180 ≈ 111,195m
        assertThat(new GeoPoint(37, 127).distanceMeters(new GeoPoint(38, 127))).isCloseTo(111_195, within(1.0));
        assertThat(new GeoPoint(37, 127).distanceMeters(new GeoPoint(37, 127))).isZero();
        // 정반대 점: h가 1을 넘어도 NaN이 아니라 지구 반 바퀴
        assertThat(new GeoPoint(0, 0).distanceMeters(new GeoPoint(0, 180))).isCloseTo(Math.PI * GeoPoint.EARTH_RADIUS_M, within(1.0));
    }
}
