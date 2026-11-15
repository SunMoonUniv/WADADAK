package com.wadadak.review.internal;

/**
 * 리뷰 태그(B2). 정해진 4개 중 여러 개를 고를 수 있다(정책 제4부 4.1 B2).
 * DB에는 이 이름 그대로(예: {@code NIGHT_VIEW}) 저장되고, DB CHECK도 같은 4개만 허용한다. 태그를 늘리려면 둘 다 바꿔야 한다.
 */
enum ReviewTag {
    /** 야경 좋음 */
    NIGHT_VIEW,
    /** 신호 적음 */
    FEW_SIGNALS,
    /** 노면 좋음 */
    GOOD_SURFACE,
    /** 붐빔 */
    CROWDED
}
