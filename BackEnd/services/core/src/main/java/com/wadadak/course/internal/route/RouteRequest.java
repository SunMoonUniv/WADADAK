package com.wadadak.course.internal.route;

import com.wadadak.common.geo.GeoPoint;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * @param anchorPoints 사용자가 지도에 찍은 순서대로. 2개 미만이면 COURSE-003
 */
record RouteRequest(@NotNull @Size(max = RouteService.MAX_ANCHOR_POINTS) List<@NotNull GeoPoint> anchorPoints) {
}
