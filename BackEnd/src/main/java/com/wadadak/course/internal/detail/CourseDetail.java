package com.wadadak.course.internal.detail;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.course.internal.route.GeneratedRoute.DistanceMarker;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 코스 상세(B1 공통 헤더 · 정보 탭). 평점 · 리뷰 수 · 항목 평가는 리뷰 API가 준다.
 * 평균 페이스 · 현재 러너는 코스 통계(F11)를 만든 뒤 붙인다.
 *
 * @param tags            FIL-04 순서
 * @param route           첫 점이 출발점이다(코스 방향)
 * @param distanceMarkers 출발점부터 1km마다의 지점(B1-02 거리 표지). 표시용이며 주행 판정에 쓰지 않는다
 * @param expiresAt       공개 만료 시각(만료일 23:59:59 Asia/Seoul). 완주로 연장되면 바뀐다(B1-04)
 * @param creatorNickname 등록자 닉네임. 탈퇴했으면 `탈퇴한 사용자`(정책 공통 4). 회원 정보를 받지 못하면 {@code null}
 */
record CourseDetail(
        UUID courseId,
        String name,
        CourseType courseType,
        Difficulty difficulty,
        List<CourseTag> tags,
        int distanceMeters,
        List<GeoPoint> route,
        List<DistanceMarker> distanceMarkers,
        Instant expiresAt,
        String creatorNickname) {
}
