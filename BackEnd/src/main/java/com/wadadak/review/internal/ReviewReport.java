package com.wadadak.review.internal;

import com.wadadak.common.entity.BaseEntity;
import com.wadadak.common.entity.UuidV7;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.util.UUID;

/**
 * 리뷰 신고 한 건(G2-2). 한 회원은 한 리뷰를 한 번만 신고한다(DB 유니크 제약 {@code review_reports_review_reporter_uk}).
 * 신고는 쌓기만 하고 고치지 않는다. 처리 결과(삭제·문제 없음)는 운영자 화면을 만들 때 따로 남긴다.
 */
@Getter
@Entity
@Table(schema = "review", name = "review_reports") // review 스키마의 review_reports 테이블
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA가 DB에서 읽을 때 쓰는 빈 생성자. 밖에서는 report()로만 만든다
class ReviewReport extends BaseEntity<UUID> {

    @Id
    private UUID id;

    private UUID reviewId;

    private UUID reporterMemberId;

    @Enumerated(EnumType.STRING) // enum 이름(예: "ADVERTISING")을 그대로 문자열로 저장한다. 순서 번호로 저장하면 사유 순서를 바꿀 때 값이 꼬인다
    private ReviewReportReason reason;

    /** 자세한 내용. 없으면 {@code null} */
    private String detail;

    /** 새 신고를 만든다. 공백만 있는 내용은 없는 것으로 본다. 저장은 서비스가 repository로 한다. */
    static ReviewReport report(UUID reviewId, UUID reporterMemberId, ReviewReportReason reason, String detail) {
        ReviewReport report = new ReviewReport();
        report.id = UuidV7.create();
        report.reviewId = reviewId;
        report.reporterMemberId = reporterMemberId;
        report.reason = reason;
        report.detail = detail == null || detail.isBlank() ? null : detail.strip();
        return report;
    }
}
