package com.wadadak.course.internal.explore;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.geo.GeoPoint;
import jakarta.validation.constraints.NotNull;

/**
 * 코스 목록의 정렬과 현재 위치. 범위 · 필터는 {@link CourseMapRequest}로 따로 받는다(지도와 같은 조건, MAP-07).
 *
 * @param lat 현재 위치 위도. 가까운순이면 필요하다
 * @param lng 현재 위치 경도. 가까운순이면 필요하다
 */
record CourseListRequest(@NotNull CourseListSort sort, Double lat, Double lng) {

    /**
     * 현재 위치. 보내지 않았으면 null.
     *
     * @throws AppException COMMON-001 — 위도 · 경도 중 하나만 보냈거나, 좌표 범위를 벗어났거나, 가까운순인데 위치가 없을 때
     */
    GeoPoint origin() {
        if ((lat == null) != (lng == null)) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "현재 위치는 위도(lat)와 경도(lng)를 함께 보냅니다.");
        }
        if (lat == null) {
            if (sort == CourseListSort.NEAREST) {
                throw new AppException(CommonErrorCode.INVALID_REQUEST, "가까운순은 현재 위치(lat · lng)가 필요합니다.");
            }
            return null;
        }
        return new GeoPoint(lat, lng);
    }
}
