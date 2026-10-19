package com.wadadak.course.internal.explore;

/** 코스 목록 정렬(FIL-01). 인기순 · 실시간순은 run이 도전 수 · 현재 러너 수 이벤트를 발행하면 붙인다. */
enum CourseListSort {
    /** 최신순: 등록 시각이 늦은 코스부터 */
    LATEST,
    /** 가까운순: 현재 위치에서 출발점까지 가까운 코스부터 */
    NEAREST,
    /**
     * 평점순: 전체 기간 평점(소수 첫째 자리 반올림, 카드에 보이는 값)이 높은 코스부터. 같으면 리뷰 수가 많은 코스, 그다음 최신순.
     * 리뷰가 없는 코스는 맨 뒤다.
     */
    RATING
}
