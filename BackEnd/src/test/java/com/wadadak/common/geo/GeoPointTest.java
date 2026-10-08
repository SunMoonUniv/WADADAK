package com.wadadak.common.geo;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

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
}
