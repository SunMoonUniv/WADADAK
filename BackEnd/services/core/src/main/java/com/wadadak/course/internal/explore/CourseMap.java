package com.wadadak.course.internal.explore;

import java.util.List;

/**
 * 지도 범위 안 코스(A2·A5). 출발점이 범위 안에 있는 활성 코스다. 평점 · 리뷰 수는 코스 통계(F11) 복사본에서 같이 싣는다(개발 정책 4.2).
 *
 * @param totalCount 조건에 맞는 코스 전체 수(목록 제목 `지금 달리기 좋은 코스 N`)
 * @param courses    그중 최대 100개, 인기순(전체 기간). 앱은 이름표가 겹치면 앞 코스를 보인다(MAP-03 인기순 우선 노출).
 *                   목록 카드와 같은 값이라 지도에서 코스를 고르면(A5) 바로 카드로 보인다
 */
record CourseMap(int totalCount, List<CourseListItem> courses) {
}
