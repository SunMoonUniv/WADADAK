package com.wadadak.course;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;
import java.util.UUID;

/**
 * @param route   기준 경로. 첫 점이 출발, 마지막 점이 도착이며 이 순서가 코스 방향이다(개발 정책 6.4).
 * @param version 코스 엔티티의 {@code @Version}. 어느 시점의 코스로 달렸는지 구분한다.
 */
public record CourseRouteSnapshot(UUID courseId, String name, List<GeoPoint> route, int totalDistanceMeters, long version) {
}
