package com.wadadak.course.internal.route;

import com.wadadak.common.geo.GeoPoint;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * @param anchorPoints 사용자가 지도에 찍은 순서대로. 2개 미만이면 COURSE-003
 */
record RouteRequest(@NotNull @Size(max = RouteRequest.MAX_ANCHOR_POINTS) List<@NotNull GeoPoint> anchorPoints) {

    // ponytail: 입력점 최대 수는 정책 미정(정책 문서 미정 목록). 지도에서 손으로 찍는 수로는 넉넉한 값
    static final int MAX_ANCHOR_POINTS = 500;
}
