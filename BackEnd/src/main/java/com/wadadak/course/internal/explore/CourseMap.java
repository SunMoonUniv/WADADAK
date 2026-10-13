package com.wadadak.course.internal.explore;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;
import java.util.UUID;

/**
 * 지도 범위 안 코스(A2·A5). 출발점이 범위 안에 있는 활성 코스다. 평점은 앱이 리뷰 API에서 받아 붙인다(개발 정책 4.2).
 *
 * @param totalCount 조건에 맞는 코스 전체 수(지도의 "코스 N개")
 * @param courses    그중 최대 100개, 최근 등록순. 인기순 우선 노출(MAP-03)은 코스 통계가 생기면 바꾼다
 */
record CourseMap(int totalCount, List<MapCourse> courses) {

    /** @param route 첫 점 출발, 마지막 점 도착(코스 방향) */
    record MapCourse(UUID courseId, String name, List<GeoPoint> route) {
    }
}
