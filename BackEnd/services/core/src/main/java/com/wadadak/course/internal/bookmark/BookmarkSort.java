package com.wadadak.course.internal.bookmark;

/**
 * 저장한 코스 정렬(Figma G5). 정렬 값이 같으면 최근 저장순이다. 어느 정렬이든 삭제 예정 코스는 공개 중인 코스 뒤에 최근 저장순으로 온다.
 */
enum BookmarkSort {
    /** 최근 저장순(처음) */
    RECENT,
    /** 가까운순: 현재 위치에서 출발점까지 가까운 코스부터 */
    NEAREST,
    /** 평점순: 전체 기간 평점이 높은 코스부터, 같으면 리뷰 수가 많은 코스. 리뷰가 없는 코스는 맨 뒤다 */
    RATING,
    /** 만료 임박: 만료가 가까운 코스부터 */
    EXPIRING
}
