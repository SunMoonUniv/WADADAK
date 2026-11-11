package com.wadadak.review.internal;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 리뷰 신고(G2-2) 요청 본문. 사유가 없거나 내용이 100자를 넘으면 COMMON-001.
 *
 * @param reason 사유 5개 중 하나. 필수
 * @param detail 자세한 내용. 선택, {@value #MAX_DETAIL_LENGTH}자까지
 */
record ReportReviewRequest(
        @NotNull ReviewReportReason reason, // 목록에 없는 값이면 JSON을 읽을 때 실패해 COMMON-001이 된다
        @Size(max = ReportReviewRequest.MAX_DETAIL_LENGTH) String detail) {

    /** DB 컬럼 {@code detail VARCHAR(100)}과 같다 */
    static final int MAX_DETAIL_LENGTH = 100;
}
