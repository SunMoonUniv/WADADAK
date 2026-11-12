package com.wadadak.review.internal;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.util.UUID;

/** 리뷰 신고 저장소. 메서드 이름을 읽고 Spring Data JPA가 쿼리를 만든다. */
interface ReviewReportRepository extends JpaRepository<ReviewReport, UUID> {

    /** "review_id = ? AND reporter_member_id = ?인 행이 있는가". 이미 신고했는지 먼저 확인할 때 쓴다. */
    boolean existsByReviewIdAndReporterMemberId(UUID reviewId, UUID reporterMemberId);

    /**
     * 작성자가 리뷰를 직접 지울 때 그 리뷰의 대기 신고를 지운다(2026-11-12 결정: 운영자가 볼 필요 없음).
     * 이미 처리한 신고는 기록으로 남긴다. 처리 상태는 엔티티에 없어서 SQL을 직접 쓴다.
     */
    @Modifying // SELECT가 아니라 DELETE라고 알린다
    @Query(value = "DELETE FROM review.review_reports WHERE review_id = :reviewId AND status = 'PENDING'", nativeQuery = true)
    void deletePending(UUID reviewId);
}
