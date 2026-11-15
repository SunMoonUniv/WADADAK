package com.wadadak.review.internal;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.paging.NumberedPage;
import com.wadadak.course.CourseApi;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import com.wadadak.review.ReviewErrorCode;
import com.wadadak.review.internal.AdminReviewQueries.ReportRow;
import com.wadadak.review.internal.AdminReviewViews.AdminReport;
import com.wadadak.review.internal.AdminReviewViews.AdminReportGroupRow;
import com.wadadak.review.internal.AdminReviewViews.AdminReviewDetail;
import com.wadadak.review.internal.AdminReviewViews.AdminReviewRow;
import com.wadadak.review.internal.AdminReviewViews.AdminReviewStats;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 운영자 리뷰 관리(ADM-2 전체 리뷰 · ADM-2-1 신고 접수 · ADM-2-2 신고 처리). 로그인은 SecurityConfig의 운영자 체인이 맡는다.
 *
 * <p>조회는 트랜잭션 없이 한다. 중간에 course · member 모듈을 불러 이름을 받는데, 나중에 서비스를 나누면 네트워크 호출이라
 * 그동안 DB 커넥션을 쥐고 있지 않게 한다(개발 정책 4.4, {@link ReviewQueryService}와 같다).
 */
@Slf4j
@Service
@RequiredArgsConstructor
class AdminReviewService {

    /** 오늘 · 이번 주 · 최근 n일은 한국 날짜로 센다 */
    static final ZoneId KST = ZoneId.of("Asia/Seoul");
    /**
     * 처리 패널에 보이는 신고 수. 닉네임 일괄 조회가 한 번에 100명이라 작성자 한 명을 빼고 99명이다.
     * ponytail: 한 리뷰에 신고가 99건을 넘으면 오래된 신고는 안 보인다. 그만큼 쌓이면 신고 내역에 페이지를 붙인다
     */
    static final int MAX_DETAIL_REPORTS = 99;

    private final AdminReviewQueries queries;
    private final ReviewRepository reviews;
    private final ReviewPhotos photos;
    private final ReviewService reviewService;
    private final MemberApi memberApi;
    private final CourseApi courseApi;
    private final Clock clock;

    AdminReviewStats stats() {
        LocalDate today = LocalDate.now(clock.withZone(KST));
        return queries.stats(startOf(today), startOf(today.with(DayOfWeek.MONDAY)));
    }

    /** @param days 최근 며칠(오늘 포함). {@code null}이면 전체 기간 */
    NumberedPage<AdminReviewRow> reviews(Integer rating, Integer days, int page, int size) {
        Instant since = days == null ? null : startOf(LocalDate.now(clock.withZone(KST)).minusDays(days - 1L));
        NumberedPage<AdminReviewRow> rows = queries.reviews(rating, since, page * size, size);
        Map<UUID, String> courseNames = courseNames(rows.content().stream().map(AdminReviewRow::courseId).collect(Collectors.toSet()));
        Map<UUID, MemberProfile> profiles = profiles(rows.content().stream().map(AdminReviewRow::authorId).collect(Collectors.toSet()));
        return new NumberedPage<>(rows.content().stream().map(row -> row.with(courseNames, profiles)).toList(), rows.totalCount());
    }

    NumberedPage<AdminReportGroupRow> reportGroups(ReviewReportStatus status, ReviewReportReason reason, int page, int size) {
        NumberedPage<AdminReportGroupRow> rows = queries.reportGroups(status, reason, page * size, size);
        Map<UUID, String> courseNames = courseNames(rows.content().stream().map(AdminReportGroupRow::courseId).collect(Collectors.toSet()));
        Map<UUID, MemberProfile> profiles = profiles(rows.content().stream().map(AdminReportGroupRow::authorId).collect(Collectors.toSet()));
        return new NumberedPage<>(rows.content().stream().map(row -> row.with(courseNames, profiles)).toList(), rows.totalCount());
    }

    /**
     * 리뷰가 남아 있으면 지금 내용(태그 · 사진 포함), 지워졌으면 마지막 신고 때 저장한 내용을 보인다.
     *
     * @throws AppException REVIEW-003 리뷰도 없고 신고 기록도 없음
     */
    AdminReviewDetail detail(UUID reviewId) {
        List<ReportRow> reports = queries.reportsOf(reviewId, MAX_DETAIL_REPORTS);
        Review review = reviews.findById(reviewId).orElse(null);
        if (review == null && reports.isEmpty()) {
            throw new AppException(ReviewErrorCode.REVIEW_NOT_FOUND);
        }
        ReportRow latest = reports.isEmpty() ? null : reports.getFirst();
        UUID courseId = review != null ? review.getCourseId() : latest.courseId();
        UUID authorId = review != null ? review.getMemberId() : latest.reviewMemberId();

        Set<UUID> memberIds = new HashSet<>();
        memberIds.add(authorId);
        reports.forEach(row -> memberIds.add(row.report().reporterId()));
        Map<UUID, MemberProfile> profiles = profiles(memberIds);
        MemberProfile author = profiles.get(authorId);

        // 묶은 상태는 목록과 같다: 대기가 하나라도 있으면 대기, 아니면 마지막 처리 결과
        ReportRow lastHandled = reports.stream()
                .filter(row -> row.handledAt() != null)
                .max(Comparator.comparing(ReportRow::handledAt))
                .orElse(null);
        ReviewReportStatus status = reports.isEmpty() ? null
                : reports.stream().anyMatch(row -> row.report().status() == ReviewReportStatus.PENDING)
                ? ReviewReportStatus.PENDING
                : lastHandled.report().status();

        return new AdminReviewDetail(reviewId, courseId, courseNames(Set.of(courseId)).get(courseId), authorId,
                author == null ? null : author.nickname(),
                review != null ? review.getRating() : latest.reviewRating(),
                review != null ? review.getSafetyRating() : null,
                review != null ? review.getRoadRating() : null,
                review != null ? review.getLightingRating() : null,
                review != null ? review.getAmenityRating() : null,
                review != null ? review.getContent() : latest.reviewContent(),
                review != null ? Set.copyOf(review.getTags()) : Set.of(),
                review != null ? photos.photosOf(List.of(reviewId)).getOrDefault(reviewId, List.of()) : List.of(),
                review != null ? review.getCreatedAt() : latest.reviewCreatedAt(),
                review == null, status,
                lastHandled == null ? null : lastHandled.memo(),
                lastHandled == null ? null : lastHandled.handledAt(),
                reports.stream().map(row -> row.report().with(profiles)).toList());
    }

    /**
     * 신고 처리(ADM-2-2) · 전체 리뷰 삭제(ADM-2). 이 리뷰의 대기 신고를 한꺼번에 처리한다.
     * <ul>
     *     <li>DELETED: 작성자가 지울 때와 같은 길로 리뷰를 지운다(사진 · 코스 평점 반영). 신고가 없어도 지울 수 있다</li>
     *     <li>DISMISSED: 리뷰는 그대로 두고 대기 신고만 "문제 없음"으로 닫는다</li>
     * </ul>
     *
     * @throws AppException COMMON-001 PENDING을 보냄, REVIEW-003 이미 지워진 리뷰(삭제), REVIEW-010 대기 신고가 없음(문제 없음)
     */
    @Transactional
    void handle(UUID reviewId, ReviewReportStatus result, String memo) {
        String note = memo == null || memo.isBlank() ? null : memo.strip();
        Instant now = clock.instant();
        switch (result) {
            case PENDING -> throw new AppException(CommonErrorCode.INVALID_REQUEST, "result: DELETED 또는 DISMISSED만 보낼 수 있습니다.");
            case DELETED -> {
                reviewService.deleteByAdmin(reviewId);
                queries.handlePending(reviewId, ReviewReportStatus.DELETED, note, now);
            }
            case DISMISSED -> {
                if (queries.handlePending(reviewId, ReviewReportStatus.DISMISSED, note, now) == 0) {
                    throw new AppException(ReviewErrorCode.NO_PENDING_REPORT);
                }
            }
        }
    }

    private static Instant startOf(LocalDate date) {
        return date.atStartOfDay(KST).toInstant();
    }

    /** 표시용이라 못 받아도 표는 보인다. 코스 칸만 비운다(개발 정책 4.4). */
    private Map<UUID, String> courseNames(Set<UUID> courseIds) {
        if (courseIds.isEmpty()) {
            return Map.of();
        }
        try {
            return courseApi.getNames(courseIds);
        } catch (RuntimeException e) {
            log.warn("코스 이름 조회 실패. 이름 없이 운영자 목록을 돌려준다", e);
            return Map.of();
        }
    }

    /** 표시용이라 못 받아도 표는 보인다. 닉네임만 비운다(개발 정책 4.4). */
    private Map<UUID, MemberProfile> profiles(Set<UUID> memberIds) {
        if (memberIds.isEmpty()) {
            return Map.of();
        }
        try {
            return memberApi.getProfiles(memberIds).stream()
                    .collect(Collectors.toMap(MemberProfile::memberId, Function.identity()));
        } catch (RuntimeException e) {
            log.warn("회원 프로필 조회 실패. 닉네임 없이 운영자 목록을 돌려준다", e);
            return Map.of();
        }
    }
}
