package com.wadadak.course.internal.explore;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;
import java.util.UUID;

/**
 * 다른 러너가 등록한 코스 카드(I3 `등록한 코스`). 카드의 `8.1km · ★ 4.4 · 주행 61회`와 썸네일이다.
 *
 * @param averageRating   전체 기간 평점(소수 첫째 자리 반올림). 리뷰가 없으면 {@code null}
 * @param completionCount 완주 수(카드의 `주행 N회`, G4 `누적 주행`과 같다)
 * @param route           카드 썸네일
 */
record RunnerCourseItem(UUID courseId, String name, int distanceMeters, Double averageRating, int completionCount,
                        List<GeoPoint> route) {
}
