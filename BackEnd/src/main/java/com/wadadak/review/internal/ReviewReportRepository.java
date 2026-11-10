package com.wadadak.review.internal;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

/** 리뷰 신고 저장소. 메서드 이름을 읽고 Spring Data JPA가 쿼리를 만든다. */
interface ReviewReportRepository extends JpaRepository<ReviewReport, UUID> {

    /** "review_id = ? AND reporter_member_id = ?인 행이 있는가". 이미 신고했는지 먼저 확인할 때 쓴다. */
    boolean existsByReviewIdAndReporterMemberId(UUID reviewId, UUID reporterMemberId);
}
