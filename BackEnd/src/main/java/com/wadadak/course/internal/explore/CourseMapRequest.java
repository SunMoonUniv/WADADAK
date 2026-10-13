package com.wadadak.course.internal.explore;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Difficulty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;

import java.util.Set;

/**
 * 지도 범위(남서쪽·북동쪽 끝)와 필터. 필터 값이 없으면 그 조건은 걸지 않는다.
 *
 * @param minDistanceMeters FIL-02 거리 하한(포함)
 * @param maxDistanceMeters FIL-02 거리 상한(포함). {@code 20km+}를 고르면 보내지 않는다
 * @param difficulties      FIL-03. 그중 하나면 된다. 없으면 전체
 * @param tags              FIL-04. 모두 가진 코스만(AND)
 * @param courseType        FIL-05. 없으면 전체
 */
record CourseMapRequest(
        @NotNull Double swLat,
        @NotNull Double swLng,
        @NotNull Double neLat,
        @NotNull Double neLng,
        @PositiveOrZero Integer minDistanceMeters,
        @PositiveOrZero Integer maxDistanceMeters,
        Set<Difficulty> difficulties,
        Set<CourseTag> tags,
        CourseType courseType) {

    /** 좌표 범위를 벗어났거나, 남서쪽 끝이 북동쪽 끝보다 크거나, 거리 하한이 상한보다 크면 COMMON-001. */
    CourseMapRequest requireValid() {
        GeoPoint southWest = new GeoPoint(swLat, swLng);
        GeoPoint northEast = new GeoPoint(neLat, neLng);
        if (southWest.lat() > northEast.lat() || southWest.lng() > northEast.lng()) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "지도 범위의 남서쪽 끝이 북동쪽 끝보다 큽니다.");
        }
        if (minDistanceMeters != null && maxDistanceMeters != null && minDistanceMeters > maxDistanceMeters) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "거리 하한이 상한보다 큽니다.");
        }
        return this;
    }
}
