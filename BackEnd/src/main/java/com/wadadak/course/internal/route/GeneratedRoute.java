package com.wadadak.course.internal.route;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;

/**
 * 입력점을 직선으로 이은 최종 경로.
 *
 * @param route           첫 점 출발, 마지막 점 도착. 연속으로 같은 입력점은 하나로 합친다
 * @param distanceMeters  WGS84 타원체 기준 경로 길이(m, 반올림)
 * @param distanceMarkers 출발점부터 1km마다의 지점(B4-01 거리 표지)
 */
public record GeneratedRoute(List<GeoPoint> route, int distanceMeters, List<DistanceMarker> distanceMarkers) {

    /** @param km 출발점부터의 거리(km) */
    public record DistanceMarker(int km, GeoPoint point) {
    }
}
