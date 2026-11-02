package com.wadadak.course.internal.bookmark;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.course.internal.course.Retention;
import com.wadadak.event.course.CourseStatus;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/** 저장한 코스(B1-09 · G5 · C8). 저장 줄과 코스 · 코스 통계(평점 · 리뷰 수) · 현재 러너 수를 읽는다. */
@Repository
@RequiredArgsConstructor
class BookmarkRepository {

    /** 전체 기간 평점. 목록 카드(explore)와 같은 식이다: 소수 첫째 자리 반올림, 리뷰가 없으면 NULL */
    private static final String RATING = "CASE WHEN s.review_count > 0 THEN round(s.rating_sum::numeric / s.review_count, 1) END";

    private final JdbcClient jdbc;

    record CourseState(CourseStatus status, Instant expiresAt) {
    }

    /** 코스 상태와 만료 시각. 공유 잠금해 트랜잭션이 끝날 때까지 비공개 · 삭제로 바뀌지 않는다. 없는 코스면 empty */
    Optional<CourseState> lockCourse(UUID courseId) {
        return jdbc.sql("SELECT status, expires_at FROM course.courses WHERE id = :courseId FOR SHARE")
                .param("courseId", courseId)
                .query((rs, rowNum) -> new CourseState(CourseStatus.valueOf(rs.getString("status")),
                        rs.getObject("expires_at", OffsetDateTime.class).toInstant()))
                .optional();
    }

    boolean exists(UUID memberId, UUID courseId) {
        return jdbc.sql("SELECT EXISTS (SELECT 1 FROM course.course_bookmarks WHERE member_id = :memberId AND course_id = :courseId)")
                .param("memberId", memberId)
                .param("courseId", courseId)
                .query(Boolean.class)
                .single();
    }

    /** 이미 있으면 그대로 둔다(저장 시각을 바꾸지 않는다). 동시에 두 번 저장해도 한 줄이다 */
    void insert(UUID memberId, UUID courseId, Instant now) {
        jdbc.sql("""
                        INSERT INTO course.course_bookmarks (member_id, course_id, created_at, updated_at)
                        VALUES (:memberId, :courseId, :now, :now)
                        ON CONFLICT DO NOTHING""")
                .param("memberId", memberId)
                .param("courseId", courseId)
                .param("now", OffsetDateTime.ofInstant(now, ZoneOffset.UTC))
                .update();
    }

    /** 저장하지 않은 코스는 그냥 넘어간다 */
    void delete(UUID memberId, Set<UUID> courseIds) {
        jdbc.sql("DELETE FROM course.course_bookmarks WHERE member_id = :memberId AND course_id IN (:courseIds)")
                .param("memberId", memberId)
                .param("courseIds", courseIds)
                .update();
    }

    /** [courseIds] 중 저장한 코스. 코스 상태와 상관없다 */
    List<UUID> bookmarked(UUID memberId, Set<UUID> courseIds) {
        return jdbc.sql("SELECT course_id FROM course.course_bookmarks WHERE member_id = :memberId AND course_id IN (:courseIds)")
                .param("memberId", memberId)
                .param("courseIds", courseIds)
                .query(UUID.class)
                .list();
    }

    /**
     * 공개 중인 코스를 [sort]로, 그 뒤에 삭제 예정 코스를 최근 저장순으로. 같으면 최근 저장순, 그다음 코스 ID순이다.
     * 한 회원의 저장이라 G4처럼 오프셋 커서로 넘긴다. 등록자 닉네임은 비워서 준다.
     *
     * @param origin 현재 위치. 가까운순이면 있어야 한다
     */
    CursorSlice<BookmarkItem> list(UUID memberId, BookmarkSort sort, GeoPoint origin, Cursorable page) {
        Map<String, Object> params = new HashMap<>();
        String keys = switch (sort) {
            case RECENT -> "";
            case NEAREST -> {
                params.put("originLat", origin.lat());
                params.put("originLng", origin.lng());
                yield active("ST_Distance(c.start_point, ST_SetSRID(ST_MakePoint(:originLng, :originLat), 4326)::geography)") + ", ";
            }
            case RATING -> active("coalesce(" + RATING + ", -1)") + " DESC, " + active("coalesce(s.review_count, 0)") + " DESC, ";
            case EXPIRING -> active("c.expires_at") + ", ";
        };
        int offset = page.offset();
        List<BookmarkItem> rows = jdbc.sql("""
                        SELECT c.id, c.name, c.distance_meters, c.difficulty, c.tags, c.course_type, %s AS average_rating,
                               GREATEST(coalesce(s.review_count, 0), 0) AS review_count,
                               CASE WHEN c.status = 'ACTIVE' THEN GREATEST(coalesce(r.active_count, 0), 0) ELSE 0 END AS active_runners,
                               c.creator_id, ST_AsBinary(c.route) AS route, c.status, c.expires_at, c.hidden_at
                        FROM course.course_bookmarks b
                        JOIN course.courses c ON c.id = b.course_id
                        LEFT JOIN course.course_stats s ON s.course_id = c.id
                        LEFT JOIN course.course_active_runners r ON r.course_id = c.id
                        WHERE b.member_id = :memberId AND c.status IN ('ACTIVE', 'HIDDEN')
                        ORDER BY c.status = 'HIDDEN', %sb.created_at DESC, c.id
                        LIMIT :limit OFFSET :offset""".formatted(RATING, keys))
                .params(params)
                .param("memberId", memberId)
                .param("limit", page.size() + 1)
                .param("offset", offset)
                .query((rs, rowNum) -> item(rs))
                .list();
        if (rows.size() <= page.size()) {
            return new CursorSlice<>(rows, null);
        }
        return new CursorSlice<>(rows.subList(0, page.size()), String.valueOf(offset + page.size()));
    }

    /** 공개 중인 코스만 센다. {@code soonBefore}는 {@link Retention#expiringSoonBefore} */
    BookmarkSummary summary(UUID memberId, Instant soonBefore) {
        return jdbc.sql("""
                        SELECT count(*) AS course_count, count(*) FILTER (WHERE c.expires_at < :soonBefore) AS expiring_soon_count
                        FROM course.course_bookmarks b
                        JOIN course.courses c ON c.id = b.course_id
                        WHERE b.member_id = :memberId AND c.status = 'ACTIVE'""")
                .param("memberId", memberId)
                .param("soonBefore", OffsetDateTime.ofInstant(soonBefore, ZoneOffset.UTC))
                .query((rs, rowNum) -> new BookmarkSummary(rs.getInt("course_count"), rs.getInt("expiring_soon_count")))
                .single();
    }

    void deleteForCourse(UUID courseId) {
        jdbc.sql("DELETE FROM course.course_bookmarks WHERE course_id = :courseId").param("courseId", courseId).update();
    }

    void deleteForMember(UUID memberId) {
        jdbc.sql("DELETE FROM course.course_bookmarks WHERE member_id = :memberId").param("memberId", memberId).update();
    }

    /** 공개 중인 코스만 정렬 값을 갖는다. 삭제 예정 코스는 NULL이라 뒤에서 최근 저장순으로 선다 */
    private static String active(String key) {
        return "CASE WHEN c.status = 'ACTIVE' THEN " + key + " END";
    }

    /** 특징은 FIL-04 순서. 삭제 예정 시각은 비공개 시각 + 24시간 */
    private static BookmarkItem item(ResultSet rs) throws SQLException {
        List<CourseTag> tags = Arrays.stream((String[]) rs.getArray("tags").getArray())
                .map(CourseTag::valueOf)
                .sorted()
                .toList();
        BigDecimal rating = rs.getBigDecimal("average_rating");
        CourseStatus status = CourseStatus.valueOf(rs.getString("status"));
        OffsetDateTime hiddenAt = rs.getObject("hidden_at", OffsetDateTime.class);
        return new BookmarkItem(rs.getObject("id", UUID.class), rs.getString("name"), rs.getInt("distance_meters"),
                Difficulty.valueOf(rs.getString("difficulty")), tags, CourseType.valueOf(rs.getString("course_type")),
                rating == null ? null : rating.doubleValue(), rs.getInt("review_count"), rs.getInt("active_runners"),
                rs.getObject("creator_id", UUID.class), null, CourseGeometry.points(rs.getBytes("route")), status,
                rs.getObject("expires_at", OffsetDateTime.class).toInstant(),
                status == CourseStatus.HIDDEN ? hiddenAt.toInstant().plus(Retention.DELETE_AFTER) : null);
    }
}
