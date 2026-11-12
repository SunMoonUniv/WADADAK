package com.wadadak.review.internal;

import com.wadadak.member.MemberProfile;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * 운영자 리뷰 관리(ADM-2 · ADM-2-1 · ADM-2-2)의 요청 · 응답 모양을 한곳에 모았다.
 * 코스 이름 · 닉네임은 SQL이 아니라 서비스가 course · member 모듈에서 한 번에 받아 채운다({@code with}).
 * 표시용이라 못 받으면 {@code null}이고, 닉네임이 null이면 웹은 "알 수 없음"으로 보인다.
 */
final class AdminReviewViews {

    private AdminReviewViews() {
    }

    /**
     * ADM-2 위 숫자 카드(전체 리뷰 탭 4개 · 신고 접수 탭 4개). 오늘 · 이번 주는 Asia/Seoul 기준이고 주는 월요일부터다.
     *
     * @param averageRating     전체 리뷰 별점 평균(소수 첫째 자리). 리뷰가 없으면 {@code null}
     * @param pendingReviews    처리 대기: 대기 신고가 있는 리뷰 수(목록 한 줄 = 리뷰 하나)
     * @param todayReports      오늘 접수된 신고 수
     * @param weekHandledReviews 이번 주에 처리한 리뷰 수
     * @param totalReports      누적 신고 수
     */
    record AdminReviewStats(long totalReviews, long weekReviews, Double averageRating,
                            long pendingReviews, long todayReports, long weekHandledReviews, long totalReports) {
    }

    /** ADM-2 전체 리뷰 표 한 줄. {@code pendingReportCount}가 0이면 신고 칸은 "–"다. */
    record AdminReviewRow(UUID reviewId, UUID courseId, String courseName, UUID authorId, String authorNickname,
                          int rating, String content, Set<ReviewTag> tags, int pendingReportCount, Instant createdAt) {

        AdminReviewRow with(Map<UUID, String> courseNames, Map<UUID, MemberProfile> profiles) {
            return new AdminReviewRow(reviewId, courseId, courseNames.get(courseId), authorId, nickname(profiles, authorId),
                    rating, content, tags, pendingReportCount, createdAt);
        }
    }

    /**
     * ADM-2-1 신고 접수 표 한 줄. 리뷰 하나에 달린 신고를 묶는다.
     *
     * @param content       지금 리뷰 내용. 리뷰가 지워졌으면 마지막 신고 때의 내용
     * @param reviewDeleted 리뷰가 지워졌으면 {@code true}(운영자 삭제 · 코스 삭제)
     * @param reasons       이 리뷰에 들어온 신고 사유(겹치지 않게, 사유 선언 순서)
     * @param status        대기 신고가 하나라도 있으면 PENDING, 아니면 마지막 처리 결과
     */
    record AdminReportGroupRow(UUID reviewId, UUID courseId, String courseName, UUID authorId, String authorNickname,
                               String content, boolean reviewDeleted, List<ReviewReportReason> reasons, int reportCount,
                               Instant lastReportedAt, ReviewReportStatus status) {

        AdminReportGroupRow with(Map<UUID, String> courseNames, Map<UUID, MemberProfile> profiles) {
            return new AdminReportGroupRow(reviewId, courseId, courseNames.get(courseId), authorId,
                    nickname(profiles, authorId), content, reviewDeleted, reasons, reportCount, lastReportedAt, status);
        }
    }

    /**
     * ADM-2-2 처리 패널(전체 리뷰 탭의 상세도 같다). 리뷰가 지워졌으면 신고할 때 저장한 리뷰 내용을 보이고
     * 항목 평가는 {@code null}, 태그 · 사진은 빈 목록이다(신고 때는 전체 별점 · 후기만 저장한다).
     *
     * @param safetyRating 항목 평가(안전성 · 도로 상태 · 야간 조명 · 편의시설, 1~5). 리뷰가 지워졌으면 {@code null}
     * @param status   신고가 없으면 {@code null}
     * @param memo     마지막 처리 메모. 없으면 {@code null}
     * @param handledAt 마지막 처리 시각. 처리한 적 없으면 {@code null}
     * @param reports  최근 신고부터
     */
    record AdminReviewDetail(UUID reviewId, UUID courseId, String courseName, UUID authorId, String authorNickname,
                             int rating, Integer safetyRating, Integer roadRating, Integer lightingRating,
                             Integer amenityRating, String content, Set<ReviewTag> tags, List<ReviewView.Photo> photos,
                             Instant createdAt, boolean reviewDeleted, ReviewReportStatus status, String memo,
                             Instant handledAt, List<AdminReport> reports) {
    }

    /** ADM-2-2 신고 내역 한 줄 */
    record AdminReport(UUID reporterId, String reporterNickname, ReviewReportReason reason, String detail,
                       Instant reportedAt, ReviewReportStatus status) {

        AdminReport with(Map<UUID, MemberProfile> profiles) {
            return new AdminReport(reporterId, nickname(profiles, reporterId), reason, detail, reportedAt, status);
        }
    }

    /**
     * ADM-2-2 처리 버튼 · ADM-2 삭제 버튼.
     *
     * @param result DELETED(리뷰 삭제) 또는 DISMISSED(문제 없음). PENDING은 COMMON-001
     * @param memo   처리 메모. 선택, 200자까지(DB {@code memo VARCHAR(200)})
     */
    record HandleReviewRequest(@NotNull ReviewReportStatus result, @Size(max = 200) String memo) {
    }

    private static String nickname(Map<UUID, MemberProfile> profiles, UUID memberId) {
        MemberProfile profile = profiles.get(memberId);
        return profile == null ? null : profile.nickname();
    }
}
