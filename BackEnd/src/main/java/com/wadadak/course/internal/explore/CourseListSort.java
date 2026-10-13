package com.wadadak.course.internal.explore;

/** 코스 목록 정렬(FIL-01). 인기순 · 평점순 · 실시간순은 코스 통계(F11)를 만든 뒤 붙인다. */
enum CourseListSort {
    /** 최신순: 등록 시각이 늦은 코스부터 */
    LATEST,
    /** 가까운순: 현재 위치에서 출발점까지 가까운 코스부터 */
    NEAREST
}
