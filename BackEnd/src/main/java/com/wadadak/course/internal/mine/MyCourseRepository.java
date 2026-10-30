package com.wadadak.course.internal.mine;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.course.internal.course.Retention;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusReason;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

/** 내가 등록한 코스(G4). 코스 · 코스 통계(완주 수) · 완주 줄(마지막 완주)을 읽는다. */
@Repository
@RequiredArgsConstructor
class MyCourseRepository {

    /** 만료 임박 공개 코스. {@code :soonBefore}는 {@link Retention#expiringSoonBefore} */
    private static final String EXPIRING_SOON = "c.status = 'ACTIVE' AND c.expires_at < :soonBefore";

    /** 카드 값({@link #item}). 뒤에 WHERE를 붙인다 */
    private static final String CARDS = """
            SELECT c.id, c.name, c.course_type, c.difficulty, c.tags, ST_AsBinary(c.route) AS route, c.status,
                   c.status_reason, c.expires_at, c.hidden_at, coalesce(s.completion_count, 0) AS completion_count,
                   k.last_completed_at
            FROM course.courses c
            LEFT JOIN course.course_stats s ON s.course_id = c.id
            LEFT JOIN LATERAL (SELECT max(cc.completed_at) AS last_completed_at
                               FROM course.course_completions cc
                               WHERE cc.course_id = c.id AND cc.deleted_at IS NULL) k ON true
            """;

    private final JdbcClient jdbc;

    /** 만료 임박 먼저(만료가 가까운 순), 나머지는 최근 등록순, 같으면 ID순. 한 회원의 코스라 오프셋 커서로 넘긴다 */
    CursorSlice<MyCourseItem> list(UUID memberId, Instant soonBefore, Cursorable page) {
        int offset = page.offset();
        List<MyCourseItem> rows = jdbc.sql(CARDS + """
                        WHERE c.creator_id = :memberId AND c.status IN ('ACTIVE', 'HIDDEN')
                        ORDER BY (%1$s) DESC, CASE WHEN %1$s THEN c.expires_at END, c.created_at DESC, c.id
                        LIMIT :limit OFFSET :offset""".formatted(EXPIRING_SOON))
                .param("memberId", memberId)
                .param("soonBefore", OffsetDateTime.ofInstant(soonBefore, ZoneOffset.UTC))
                .param("limit", page.size() + 1)
                .param("offset", offset)
                .query((rs, rowNum) -> item(rs))
                .list();
        if (rows.size() <= page.size()) {
            return new CursorSlice<>(rows, null);
        }
        return new CursorSlice<>(rows.subList(0, page.size()), String.valueOf(offset + page.size()));
    }

    /** 코스 한 장(B7 수정 응답) */
    MyCourseItem find(UUID courseId) {
        return jdbc.sql(CARDS + "WHERE c.id = :courseId")
                .param("courseId", courseId)
                .query((rs, rowNum) -> item(rs))
                .single();
    }

    /** 공개 중인 코스만 센다 */
    MyCourseSummary summary(UUID memberId, Instant soonBefore) {
        return jdbc.sql("""
                        SELECT count(*) AS course_count, coalesce(sum(s.completion_count), 0) AS completion_count,
                               count(*) FILTER (WHERE c.expires_at < :soonBefore) AS expiring_soon_count
                        FROM course.courses c
                        LEFT JOIN course.course_stats s ON s.course_id = c.id
                        WHERE c.creator_id = :memberId AND c.status = 'ACTIVE'""")
                .param("memberId", memberId)
                .param("soonBefore", OffsetDateTime.ofInstant(soonBefore, ZoneOffset.UTC))
                .query((rs, rowNum) -> new MyCourseSummary(rs.getInt("course_count"), rs.getInt("completion_count"),
                        rs.getInt("expiring_soon_count")))
                .single();
    }

    /** 특징은 FIL-04 순서. 삭제 예정 시각은 비공개 시각 + 24시간, 마지막 완주는 Asia/Seoul 날짜다 */
    private static MyCourseItem item(ResultSet rs) throws SQLException {
        List<CourseTag> tags = Arrays.stream((String[]) rs.getArray("tags").getArray())
                .map(CourseTag::valueOf)
                .sorted()
                .toList();
        CourseStatus status = CourseStatus.valueOf(rs.getString("status"));
        String reason = rs.getString("status_reason");
        OffsetDateTime hiddenAt = rs.getObject("hidden_at", OffsetDateTime.class);
        OffsetDateTime lastCompletedAt = rs.getObject("last_completed_at", OffsetDateTime.class);
        return new MyCourseItem(rs.getObject("id", UUID.class), rs.getString("name"), CourseType.valueOf(rs.getString("course_type")),
                Difficulty.valueOf(rs.getString("difficulty")), tags, CourseGeometry.points(rs.getBytes("route")), status,
                reason == null ? null : CourseStatusReason.valueOf(reason),
                rs.getObject("expires_at", OffsetDateTime.class).toInstant(),
                status == CourseStatus.HIDDEN ? hiddenAt.toInstant().plus(Retention.DELETE_AFTER) : null,
                rs.getInt("completion_count"),
                lastCompletedAt == null ? null : LocalDate.ofInstant(lastCompletedAt.toInstant(), TimeConfig.SEOUL));
    }
}
