package com.wadadak.course.internal.registration;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.Course;

import java.time.Instant;
import java.util.UUID;

/**
 * 등록 결과. 앱은 성공 팝업 뒤 A2에서 {@code startPoint}로 새 코스 위치를 보여준다(B4-07).
 *
 * @param expiresAt 만료 시각(등록일 포함 30일째 23:59:59 Asia/Seoul)
 */
record RegisteredCourse(UUID courseId, String name, GeoPoint startPoint, int distanceMeters, Instant expiresAt) {

    static RegisteredCourse from(Course course) {
        return new RegisteredCourse(course.getId(), course.getName(),
                new GeoPoint(course.getStartPoint().getY(), course.getStartPoint().getX()),
                course.getDistanceMeters(), course.getExpiresAt());
    }
}
