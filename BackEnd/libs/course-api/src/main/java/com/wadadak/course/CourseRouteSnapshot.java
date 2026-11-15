package com.wadadak.course;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;
import java.util.UUID;

/**
 * @param route   기준 경로. 첫 점이 출발, 마지막 점이 도착이며 이 순서가 코스 방향이다(개발 정책 6.4).
 * @param version 코스 엔티티의 {@code @Version}. 어느 시점의 코스로 달렸는지 구분한다.
 * @param hasElevationProfile 고도 프로필이 이미 있다. true면 run은 완주해도 {@code CourseRunTrackEvent}를 보내지 않는다.
 *                            course가 채운다(5개 인자 생성자는 false — 프로필 없음으로 보고 보낸다)
 */
public record CourseRouteSnapshot(UUID courseId, String name, List<GeoPoint> route, int totalDistanceMeters, long version,
                                  boolean hasElevationProfile) {

    public CourseRouteSnapshot(UUID courseId, String name, List<GeoPoint> route, int totalDistanceMeters, long version) {
        this(courseId, name, route, totalDistanceMeters, version, false);
    }
}
