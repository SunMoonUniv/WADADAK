package com.wadadak.review.internal;

import com.wadadak.common.exception.AppException;
import com.wadadak.review.ReviewErrorCode;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * 리뷰 신고(G2-1~G2-4). 다른 러너의 리뷰를 사유와 함께 신고한다.
 *
 * <p>[중복 신고를 막는 두 겹] 앱은 리뷰 목록의 {@code reportedByMe}로 이미 신고한 리뷰면 사유 화면을 열지 않는다(G2-4).
 * 그래도 다른 기기에서 거의 동시에 신고하면 둘 다 여기까지 올 수 있어서, 서버가 먼저 확인하고(exists)
 * 그 사이를 뚫고 들어온 요청은 DB 유니크 제약이 막는다. 어느 쪽이든 REVIEW-009로 돌려주고 앱은 같은 G2-4를 띄운다.
 */
@Service
@RequiredArgsConstructor
class ReviewReportService {

    private final ReviewRepository reviewRepository;
    private final ReviewReportRepository reportRepository;

    /**
     * @throws AppException REVIEW-003 리뷰가 없음, REVIEW-008 내 리뷰, REVIEW-009 이미 신고함
     */
    @Transactional
    void report(UUID reporterId, UUID reviewId, ReportReviewRequest request) {
        Review review = reviewRepository.findById(reviewId)
                .orElseThrow(() -> new AppException(ReviewErrorCode.REVIEW_NOT_FOUND));
        if (review.isWrittenBy(reporterId)) {
            throw new AppException(ReviewErrorCode.CANNOT_REPORT_OWN_REVIEW);
        }
        if (reportRepository.existsByReviewIdAndReporterMemberId(reviewId, reporterId)) {
            throw new AppException(ReviewErrorCode.ALREADY_REPORTED);
        }
        try {
            // saveAndFlush: 바로 INSERT까지 보내야 유니크 제약 위반을 여기서 잡을 수 있다(리뷰 작성과 같은 방식)
            reportRepository.saveAndFlush(ReviewReport.report(reviewId, reporterId, request.reason(), request.detail()));
        } catch (DataIntegrityViolationException e) {
            // 위 확인을 동시에 통과한 두 번째 요청. 유니크 제약 (review_id, reporter_member_id)이 하나만 남긴다
            throw new AppException(ReviewErrorCode.ALREADY_REPORTED);
        }
    }
}
