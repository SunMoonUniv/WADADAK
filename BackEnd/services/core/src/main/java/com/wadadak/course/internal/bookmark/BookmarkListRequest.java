package com.wadadak.course.internal.bookmark;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.geo.GeoPoint;

/**
 * 저장한 코스 목록의 정렬과 현재 위치.
 *
 * @param sort 비우면 최근 저장순
 * @param lat  현재 위치 위도. 가까운순이면 필요하다
 * @param lng  현재 위치 경도. 가까운순이면 필요하다
 */
record BookmarkListRequest(BookmarkSort sort, Double lat, Double lng) {

    BookmarkSort sortOrDefault() {
        return sort == null ? BookmarkSort.RECENT : sort;
    }

    /**
     * 가까운순의 현재 위치. 다른 정렬이면 null.
     *
     * @throws AppException COMMON-001 — 위도 · 경도 중 하나만 보냈거나, 좌표 범위를 벗어났거나, 가까운순인데 위치가 없을 때
     */
    GeoPoint origin() {
        if ((lat == null) != (lng == null)) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "현재 위치는 위도(lat)와 경도(lng)를 함께 보냅니다.");
        }
        if (sortOrDefault() != BookmarkSort.NEAREST) {
            return null;
        }
        if (lat == null) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "가까운순은 현재 위치(lat · lng)가 필요합니다.");
        }
        return new GeoPoint(lat, lng);
    }
}
