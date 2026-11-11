package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;

/**
 * 길찾기 결과 경로 하나.
 *
 * @param distanceMeters 길찾기 엔진이 잰 길이(m)
 * @param roadClasses    도로 종류 구간. 큰길 비율에 쓴다
 */
record RoutedPath(List<GeoPoint> points, double distanceMeters, List<RoadClassSpan> roadClasses) {

    /** points[from..to] 사이 선분의 도로 종류(GraphHopper {@code road_class}, 예: primary · residential · footway) */
    record RoadClassSpan(int from, int to, String roadClass) {
    }
}
