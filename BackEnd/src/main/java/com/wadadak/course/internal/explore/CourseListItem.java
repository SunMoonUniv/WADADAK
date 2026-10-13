package com.wadadak.course.internal.explore;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Difficulty;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 코스 목록 카드(A2-05 · A6-03). 평점 · 리뷰 수 · 현재 러너는 코스 통계(F11)를 만든 뒤 붙인다.
 *
 * @param tags      FIL-04 순서
 * @param expiresAt 공개 만료 시각(만료일 23:59:59 Asia/Seoul). 카드의 `만료 D-1`을 여기서 센다
 * @param route     카드 썸네일. 첫 점이 출발점이라 현재 위치에서의 거리(`0.8 km 거리`)도 여기서 잰다
 */
record CourseListItem(
        UUID courseId,
        String name,
        int distanceMeters,
        Difficulty difficulty,
        List<CourseTag> tags,
        CourseType courseType,
        Instant expiresAt,
        List<GeoPoint> route) {
}
