package com.wadadak.review.internal;

/**
 * 리뷰 목록 정렬(B8-03·G2). 같은 별점이면 최신순이다.
 *
 * <p>{@code orderBy}는 SQL에 그대로 붙는다. 사용자가 보낸 문자열이 아니라 여기 정해 둔 값만 쓰므로 SQL 인젝션 걱정이 없다.
 * 앱이 목록에 없는 값을 보내면 스프링이 enum으로 바꾸지 못해 COMMON-001이 된다.
 */
enum ReviewSort {
    /** 최신순(기본) */
    LATEST("r.created_at DESC, r.id DESC"),
    /** 높은 평점 */
    HIGHEST("r.rating DESC, r.created_at DESC, r.id DESC"),
    /** 낮은 평점 */
    LOWEST("r.rating, r.created_at DESC, r.id DESC");

    // 마지막 r.id는 같은 시각에 쓴 리뷰끼리도 순서를 고정해서, 페이지를 넘길 때 겹치거나 빠지지 않게 한다
    final String orderBy;

    ReviewSort(String orderBy) {
        this.orderBy = orderBy;
    }
}
