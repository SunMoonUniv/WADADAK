package com.wadadak.review.internal;

/**
 * 신고 처리 상태(ADM-2-1 상태 칸). 리뷰 하나에 달린 대기 신고를 운영자가 한꺼번에 처리한다.
 * DB CHECK도 같은 3개만 허용한다.
 */
enum ReviewReportStatus {
    /** 대기: 아직 처리하지 않음 */
    PENDING,
    /** 삭제함: 운영자가 리뷰를 지움 */
    DELETED,
    /** 문제 없음: 리뷰를 그대로 둠 */
    DISMISSED
}
