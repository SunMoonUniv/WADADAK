package com.wadadak.review.internal;

import com.wadadak.common.paging.NumberedPage;
import com.wadadak.review.internal.AdminReviewViews.AdminReport;
import com.wadadak.review.internal.AdminReviewViews.AdminReportGroupRow;
import com.wadadak.review.internal.AdminReviewViews.AdminReviewRow;
import com.wadadak.review.internal.AdminReviewViews.AdminReviewStats;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

/**
 * 운영자 리뷰 관리 SQL(ADM-2 · ADM-2-1 · ADM-2-2). 화면 조회는 {@link ReviewQueries}처럼 {@link JdbcClient}로 직접 쓴다.
 *
 * <p>[번호 페이징] 표 아래 페이지 번호를 그리려면 전체 개수가 필요하다. {@code count(*) OVER ()}는 LIMIT으로 자르기 전의
 * 전체 행 수를 행마다 붙여 준다. 쿼리를 두 번(개수 · 목록) 보내지 않아도 된다.
 */
@Repository
@RequiredArgsConstructor
class AdminReviewQueries {

    /** 신고 처리 상태: 대기 신고가 하나라도 있으면 대기, 아니면 가장 최근에 처리한 결과 */
    private static final String GROUP_STATUS = """
            CASE WHEN bool_or(rr.status = 'PENDING') THEN 'PENDING'
                 ELSE (array_agg(rr.status ORDER BY rr.handled_at DESC))[1] END""";

    private final JdbcClient jdbc;

    /** @param todayStart 오늘 0시(Asia/Seoul), weekStart 이번 주 월요일 0시 */
    AdminReviewStats stats(Instant todayStart, Instant weekStart) {
        return jdbc.sql("""
                        SELECT (SELECT count(*) FROM review.reviews) AS total_reviews,
                               (SELECT count(*) FROM review.reviews WHERE created_at >= :weekStart) AS week_reviews,
                               (SELECT round(avg(rating), 1) FROM review.reviews) AS average_rating,
                               (SELECT count(DISTINCT review_id) FROM review.review_reports WHERE status = 'PENDING') AS pending_reviews,
                               (SELECT count(*) FROM review.review_reports WHERE created_at >= :todayStart) AS today_reports,
                               (SELECT count(DISTINCT review_id) FROM review.review_reports WHERE handled_at >= :weekStart) AS week_handled,
                               (SELECT count(*) FROM review.review_reports) AS total_reports""")
                .param("todayStart", timestamp(todayStart))
                .param("weekStart", timestamp(weekStart))
                .query((rs, rowNum) -> new AdminReviewStats(rs.getLong("total_reviews"), rs.getLong("week_reviews"),
                        ReviewQueries.decimal(rs, "average_rating"), rs.getLong("pending_reviews"),
                        rs.getLong("today_reports"), rs.getLong("week_handled"), rs.getLong("total_reports")))
                .single();
    }

    /**
     * ADM-2 전체 리뷰. 숨김 · 비공개 코스의 리뷰도 보인다(운영자가 지울 수 있게). 최신순.
     *
     * @param rating 이 별점만. {@code null}이면 전체
     * @param since  이 시각 이후 작성만. {@code null}이면 전체 기간
     */
    NumberedPage<AdminReviewRow> reviews(Integer rating, Instant since, int offset, int limit) {
        // 조건이 있을 때만 WHERE에 붙인다. "? IS NULL OR …"로 쓰면 PostgreSQL이 null 파라미터의 타입을 몰라 실패한다
        String sql = """
                SELECT r.id, r.course_id, r.member_id, r.rating, r.content, r.tags, r.created_at,
                       (SELECT count(*) FROM review.review_reports rr
                        WHERE rr.review_id = r.id AND rr.status = 'PENDING') AS pending_reports,
                       count(*) OVER () AS total
                FROM review.reviews r
                WHERE TRUE"""
                + (rating == null ? "" : " AND r.rating = :rating")
                + (since == null ? "" : " AND r.created_at >= :since")
                + " ORDER BY r.created_at DESC, r.id DESC LIMIT :limit OFFSET :offset";
        JdbcClient.StatementSpec query = jdbc.sql(sql).param("limit", limit).param("offset", offset);
        if (rating != null) {
            query = query.param("rating", rating);
        }
        if (since != null) {
            query = query.param("since", timestamp(since));
        }
        long[] total = {0};
        List<AdminReviewRow> rows = query.query((rs, rowNum) -> {
            total[0] = rs.getLong("total");
            return new AdminReviewRow(rs.getObject("id", UUID.class), rs.getObject("course_id", UUID.class), null,
                    rs.getObject("member_id", UUID.class), null, rs.getInt("rating"), rs.getString("content"),
                    ReviewQueries.tags(rs.getArray("tags")), rs.getInt("pending_reports"), instant(rs, "created_at"));
        }).list();
        return new NumberedPage<>(rows, total[0]);
    }

    /**
     * ADM-2-1 신고 접수. 리뷰 하나에 한 줄이고 최근 신고 순이다.
     *
     * @param status 이 처리 상태(묶은 상태 기준)만. {@code null}이면 전체
     * @param reason 이 사유가 하나라도 들어온 리뷰만. {@code null}이면 전체
     */
    NumberedPage<AdminReportGroupRow> reportGroups(ReviewReportStatus status, ReviewReportReason reason, int offset, int limit) {
        // WITH g: 신고를 리뷰별로 먼저 묶고, 지금 리뷰가 남아 있는지는 묶은 뒤에 붙인다
        String sql = """
                WITH g AS (
                    SELECT rr.review_id,
                           (array_agg(rr.course_id))[1] AS course_id,
                           (array_agg(rr.review_member_id))[1] AS author_id,
                           (array_agg(rr.review_content ORDER BY rr.created_at DESC))[1] AS snapshot_content,
                           array_agg(DISTINCT rr.reason) AS reasons,
                           count(*) AS report_count,
                           max(rr.created_at) AS last_reported_at,
                           %s AS status
                    FROM review.review_reports rr
                    GROUP BY rr.review_id)
                SELECT g.*, r.id IS NULL AS review_deleted,
                       CASE WHEN r.id IS NULL THEN g.snapshot_content ELSE r.content END AS content,
                       count(*) OVER () AS total
                FROM g
                LEFT JOIN review.reviews r ON r.id = g.review_id
                WHERE TRUE""".formatted(GROUP_STATUS)
                + (status == null ? "" : " AND g.status = :status")
                + (reason == null ? "" : " AND :reason = ANY (g.reasons)")
                + " ORDER BY g.last_reported_at DESC, g.review_id LIMIT :limit OFFSET :offset";
        JdbcClient.StatementSpec query = jdbc.sql(sql).param("limit", limit).param("offset", offset);
        if (status != null) {
            query = query.param("status", status.name());
        }
        if (reason != null) {
            query = query.param("reason", reason.name());
        }
        long[] total = {0};
        List<AdminReportGroupRow> rows = query.query((rs, rowNum) -> {
            total[0] = rs.getLong("total");
            return new AdminReportGroupRow(rs.getObject("review_id", UUID.class), rs.getObject("course_id", UUID.class),
                    null, rs.getObject("author_id", UUID.class), null, rs.getString("content"),
                    rs.getBoolean("review_deleted"), reasons(rs), rs.getInt("report_count"),
                    instant(rs, "last_reported_at"), ReviewReportStatus.valueOf(rs.getString("status")));
        }).list();
        return new NumberedPage<>(rows, total[0]);
    }

    /**
     * ADM-2-2 신고 내역 한 줄과, 리뷰가 지워졌을 때 보일 신고 때의 리뷰 내용 · 처리 메모.
     *
     * @param memo      이 신고를 처리할 때 남긴 메모
     * @param handledAt 처리 시각. 대기면 {@code null}
     */
    record ReportRow(AdminReport report, String memo, Instant handledAt,
                     UUID courseId, UUID reviewMemberId, int reviewRating, String reviewContent, Instant reviewCreatedAt) {
    }

    /** 최근 신고부터 {@code limit}개 */
    List<ReportRow> reportsOf(UUID reviewId, int limit) {
        return jdbc.sql("""
                        SELECT reporter_member_id, reason, detail, created_at, status, memo, handled_at,
                               course_id, review_member_id, review_rating, review_content, review_created_at
                        FROM review.review_reports
                        WHERE review_id = :reviewId
                        ORDER BY created_at DESC, id DESC
                        LIMIT :limit""")
                .param("reviewId", reviewId)
                .param("limit", limit)
                .query((rs, rowNum) -> new ReportRow(
                        new AdminReport(rs.getObject("reporter_member_id", UUID.class), null,
                                ReviewReportReason.valueOf(rs.getString("reason")), rs.getString("detail"),
                                instant(rs, "created_at"), ReviewReportStatus.valueOf(rs.getString("status"))),
                        rs.getString("memo"), nullableInstant(rs, "handled_at"),
                        rs.getObject("course_id", UUID.class), rs.getObject("review_member_id", UUID.class),
                        rs.getInt("review_rating"), rs.getString("review_content"), instant(rs, "review_created_at")))
                .list();
    }

    /** 이 리뷰의 대기 신고를 모두 처리한다. 처리한 신고 수를 돌려준다(0이면 처리할 게 없었다). */
    int handlePending(UUID reviewId, ReviewReportStatus result, String memo, Instant now) {
        return jdbc.sql("""
                        UPDATE review.review_reports
                        SET status = :status, memo = :memo, handled_at = :now, updated_at = :now
                        WHERE review_id = :reviewId AND status = 'PENDING'""")
                .param("status", result.name())
                .param("memo", memo)
                .param("now", timestamp(now))
                .param("reviewId", reviewId)
                .update();
    }

    /** DB는 사유를 이름순으로 묶어 준다. 화면에는 사유 선언 순서(광고 → 욕설 → …)로 보인다. */
    private static List<ReviewReportReason> reasons(ResultSet rs) throws SQLException {
        return Arrays.stream((String[]) rs.getArray("reasons").getArray())
                .map(ReviewReportReason::valueOf)
                .sorted()
                .toList();
    }

    private static Instant instant(ResultSet rs, String column) throws SQLException {
        return rs.getObject(column, OffsetDateTime.class).toInstant();
    }

    private static Instant nullableInstant(ResultSet rs, String column) throws SQLException {
        OffsetDateTime value = rs.getObject(column, OffsetDateTime.class);
        return value == null ? null : value.toInstant();
    }

    /** PostgreSQL 드라이버는 Instant를 바로 받지 못해서 UTC 시각으로 바꿔 넘긴다. */
    private static OffsetDateTime timestamp(Instant instant) {
        return OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
