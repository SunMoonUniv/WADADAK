package com.wadadak.review.internal;

import com.wadadak.common.paging.NumberedPage;
import com.wadadak.common.response.ApiResult;
import com.wadadak.review.internal.AdminReviewViews.AdminReportGroupRow;
import com.wadadak.review.internal.AdminReviewViews.AdminReviewDetail;
import com.wadadak.review.internal.AdminReviewViews.AdminReviewRow;
import com.wadadak.review.internal.AdminReviewViews.AdminReviewStats;
import com.wadadak.review.internal.AdminReviewViews.HandleReviewRequest;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * 운영자 리뷰 관리 API(운영자 웹 ADM-2). 회원 JWT가 아니라 운영자 계정(HTTP Basic)으로만 부른다(SecurityConfig).
 *
 * <p>URL은 {@code /api/v1/admin/…} 아래에 둔다. 운영자 로그인 체인 하나가 이 prefix 전체를 막고,
 * 나중에 review를 떼어내면 게이트웨이가 {@code /api/v1/admin/reviews} · {@code /api/v1/admin/review-reports}를 review로 보낸다.
 * 페이지는 0부터, 한 페이지 1~100개(기본 20). 범위 밖이면 COMMON-001.
 */
@RestController
@RequestMapping("/api/v1/admin")
@RequiredArgsConstructor
class AdminReviewController {

    private final AdminReviewService service;

    @Operation(summary = "[운영자] 리뷰 관리 숫자 카드 (ADM-2 · ADM-2-1)",
            description = "전체 리뷰 · 이번 주 작성 · 평균 별점(리뷰가 없으면 null) · 처리 대기(대기 신고가 있는 리뷰 수) · "
                    + "오늘 접수(신고 수) · 이번 주 처리(처리한 리뷰 수) · 누적 신고. 오늘 · 이번 주는 Asia/Seoul, 주는 월요일부터.")
    @GetMapping("/reviews/stats")
    ApiResult<AdminReviewStats> stats() {
        return ApiResult.success(service.stats());
    }

    @Operation(summary = "[운영자] 전체 리뷰 (ADM-2)",
            description = "최신순. 숨김 · 비공개 코스의 리뷰도 나온다. rating은 별점(1~5), days는 최근 며칠(오늘 포함, 1~365). "
                    + "pendingReportCount는 처리 대기 신고 수. 코스 이름 · 닉네임을 못 받으면 null.")
    @GetMapping("/reviews")
    ApiResult<NumberedPage<AdminReviewRow>> reviews(
            @RequestParam(required = false) @Min(1) @Max(5) Integer rating,
            @RequestParam(required = false) @Min(1) @Max(365) Integer days,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {
        return ApiResult.success(service.reviews(rating, days, page, size));
    }

    @Operation(summary = "[운영자] 신고 접수 (ADM-2-1)",
            description = "리뷰 하나에 한 줄, 최근 신고 순. status는 묶은 상태(PENDING 대기 · DELETED 삭제함 · DISMISSED 문제 없음): "
                    + "대기 신고가 하나라도 있으면 PENDING, 아니면 마지막 처리 결과. reason은 그 사유가 하나라도 들어온 리뷰만. "
                    + "리뷰가 지워졌으면 reviewDeleted=true이고 content는 마지막 신고 때의 내용.")
    @GetMapping("/review-reports")
    ApiResult<NumberedPage<AdminReportGroupRow>> reports(
            @RequestParam(required = false) ReviewReportStatus status,
            @RequestParam(required = false) ReviewReportReason reason,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {
        return ApiResult.success(service.reportGroups(status, reason, page, size));
    }

    @Operation(summary = "[운영자] 리뷰 상세 · 신고 처리 패널 (ADM-2-2)",
            description = "리뷰와 신고 내역(최근 순, 99건까지). 항목 평가 4개(safety · road · lighting · amenityRating)도 준다. "
                    + "리뷰가 지워졌으면 신고 때 저장한 내용(전체 별점 · 후기)을 보이고 항목 평가는 null, 태그 · 사진은 빈 목록. "
                    + "신고가 없으면 status · memo · handledAt은 null. 리뷰도 신고 기록도 없으면 REVIEW-003.")
    @GetMapping("/reviews/{reviewId}")
    ApiResult<AdminReviewDetail> detail(@PathVariable UUID reviewId) {
        return ApiResult.success(service.detail(reviewId));
    }

    @Operation(summary = "[운영자] 리뷰 삭제 · 문제 없음 처리 (ADM-2-2 · ADM-2 삭제)",
            description = "이 리뷰의 대기 신고를 한꺼번에 처리한다. result=DELETED면 리뷰를 사진과 함께 지우고(작성자 삭제와 같게 코스 평점 반영, "
                    + "되돌릴 수 없음) 대기 신고를 '삭제함'으로, DISMISSED면 리뷰는 두고 대기 신고를 '문제 없음'으로 닫는다. "
                    + "memo는 선택(200자). 신고 없는 리뷰도 DELETED로 지울 수 있다. "
                    + "이미 지워진 리뷰 REVIEW-003, 문제 없음인데 대기 신고 없음 REVIEW-010, PENDING · 형식 오류 COMMON-001.")
    @PostMapping("/reviews/{reviewId}/handle")
    ApiResult<Void> handle(@PathVariable UUID reviewId, @Valid @RequestBody HandleReviewRequest request) {
        service.handle(reviewId, request.result(), request.memo());
        return ApiResult.success();
    }
}
