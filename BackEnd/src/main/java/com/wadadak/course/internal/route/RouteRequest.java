package com.wadadak.course.internal.route;

import com.wadadak.common.geo.GeoPoint;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * @param anchorPoints 사용자가 지도에 찍은 순서대로. 2개 미만이면 COURSE-003
 */
record RouteRequest(@NotNull @Size(max = RouteRequest.MAX_ANCHOR_POINTS) List<@NotNull GeoPoint> anchorPoints) {

    // 입력점 최대 500개(정책 B3-01). 넘으면 COMMON-001
    static final int MAX_ANCHOR_POINTS = 500;
}
