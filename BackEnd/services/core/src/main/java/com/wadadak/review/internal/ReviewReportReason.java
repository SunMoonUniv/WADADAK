package com.wadadak.review.internal;

/**
 * 리뷰 신고 사유(G2-2). 정해진 5개 중 하나를 고른다(2026-11-10 확정).
 * DB에는 이 이름 그대로(예: {@code ADVERTISING}) 저장되고, DB CHECK도 같은 5개만 허용한다. 사유를 늘리려면 둘 다 바꿔야 한다.
 */
enum ReviewReportReason {
    /** 광고·홍보: 상품·가게 홍보나 링크로 끌어들이는 글 */
    ADVERTISING,
    /** 욕설·비하: 다른 사람을 깎아내리거나 불쾌하게 하는 말 */
    ABUSE,
    /** 개인정보 노출: 전화번호·주소처럼 누군지 알 수 있는 정보 */
    PRIVACY,
    /** 관계없는 내용: 이 코스와 상관없는 글 */
    IRRELEVANT,
    /** 기타: 위에 없는 다른 문제 */
    OTHER
}
