package com.wadadak.review.internal;

import com.wadadak.review.internal.ReviewSummary.ItemAverages;
import com.wadadak.review.internal.ReviewSummary.RatingCounts;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.sql.Array;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * 리뷰 화면 조회 SQL(B8·G2·지도 평점). 평점 요약은 저장하지 않고 조회할 때 리뷰에서 계산한다(DB 구조 3.4).
 *
 * <p>쓰기는 JPA({@link ReviewRepository})로 하고, 화면용 조회는 SQL을 직접 쓰는 {@link JdbcClient}로 나눴다.
 * 리뷰 카드에는 완주 횟수처럼 다른 표의 값도 모아야 해서 SQL로 쓰는 편이 읽기 쉽다(ranking 모듈과 같은 방식).
 * 숨김·삭제된 코스인지는 서비스가 먼저 확인한다.
 */
@Repository // 스프링이 관리하는 DB 접근 객체. DB 예외를 스프링 예외로 바꿔 준다
@RequiredArgsConstructor
class ReviewQueries {

    /*
     * 카드 한 장에 필요한 값. 완주 횟수는 저장하지 않고 주행 기록 복사본에서 센다(정책 제4부 4.1 D-09).
     * :requesterId와 같은 회원이면 mine = true다.
     */
    private static final String CARD = """
            SELECT r.id, r.member_id, r.member_id = :requesterId AS mine,
                   r.rating, r.safety_rating, r.road_rating, r.lighting_rating, r.amenity_rating,
                   r.content, r.tags, r.best_progress_percent, r.created_at,
                   (SELECT count(*)
                    FROM review.course_run_records c
                    WHERE c.member_id = r.member_id AND c.course_id = r.course_id
                      AND c.completed AND NOT c.deleted) AS completed_count
            FROM review.reviews r
            WHERE r.course_id = :courseId""";

    // RowMapper: SQL 결과 한 행을 자바 객체 하나로 바꾸는 규칙.
    // 닉네임·프로필 사진(member 모듈)과 리뷰 사진(ReviewPhotos)은 서비스가 여러 카드를 모아 한 번에 채운다
    private static final RowMapper<ReviewCard> CARD_MAPPER = (rs, rowNum) -> new ReviewCard(
            rs.getObject("id", UUID.class), rs.getObject("member_id", UUID.class), null, null, rs.getBoolean("mine"),
            rs.getInt("rating"), rs.getInt("safety_rating"), rs.getInt("road_rating"),
            rs.getInt("lighting_rating"), rs.getInt("amenity_rating"),
            rs.getString("content"), tags(rs.getArray("tags")), List.of(), rs.getInt("best_progress_percent"),
            rs.getInt("completed_count"), rs.getObject("created_at", OffsetDateTime.class).toInstant());

    private final JdbcClient jdbc;

    /** 리뷰가 없으면 리뷰 수 0, 평균은 {@code null}이다(집계 함수는 행이 없어도 한 줄을 돌려준다). */
    ReviewSummary summary(UUID courseId) {
        return jdbc.sql("""
                        SELECT count(*) AS review_count,
                               round(avg(rating), 1) AS rating,
                               count(*) FILTER (WHERE rating = 5) AS five,
                               count(*) FILTER (WHERE rating = 4) AS four,
                               count(*) FILTER (WHERE rating = 3) AS three,
                               count(*) FILTER (WHERE rating = 2) AS two,
                               count(*) FILTER (WHERE rating = 1) AS one,
                               round(avg(safety_rating), 1) AS safety,
                               round(avg(road_rating), 1) AS road,
                               round(avg(lighting_rating), 1) AS lighting,
                               round(avg(amenity_rating), 1) AS amenity
                        FROM review.reviews
                        WHERE course_id = :courseId""")
                .param("courseId", courseId)
                .query((rs, rowNum) -> new ReviewSummary(rs.getInt("review_count"), decimal(rs, "rating"),
                        new RatingCounts(rs.getInt("five"), rs.getInt("four"), rs.getInt("three"),
                                rs.getInt("two"), rs.getInt("one")),
                        new ItemAverages(decimal(rs, "safety"), decimal(rs, "road"),
                                decimal(rs, "lighting"), decimal(rs, "amenity"))))
                .single();
    }

    /** 리뷰가 있는 활성 코스만 돌려준다. 빠진 코스는 서비스가 평점 없음으로 채운다. */
    List<CourseRating> ratings(Set<UUID> courseIds) {
        return jdbc.sql("""
                        SELECT r.course_id, round(avg(r.rating), 1) AS rating
                        FROM review.reviews r
                        WHERE r.course_id IN (:courseIds)
                          AND NOT EXISTS (SELECT 1 FROM review.course_status_copies s WHERE s.course_id = r.course_id)
                        GROUP BY r.course_id""")
                .param("courseIds", courseIds) // 컬렉션을 넣으면 IN (?, ?, …)으로 펼쳐진다
                .query((rs, rowNum) -> new CourseRating(rs.getObject("course_id", UUID.class), decimal(rs, "rating")))
                .list();
    }

    /**
     * 목록 한 페이지.
     *
     * @param photoOnly   사진이 있는 리뷰만
     * @param excludeMine 요청자 리뷰를 뺀다(G2 "다른 러너 리뷰")
     * @param limit       읽을 개수. 다음 페이지가 있는지 알려고 서비스는 한 개 더 달라고 한다
     */
    List<ReviewCard> page(UUID courseId, ReviewSort sort, boolean photoOnly, boolean excludeMine, UUID requesterId,
                          int offset, int limit) {
        // ponytail: 오프셋 페이징이라 넘기는 사이 새 리뷰가 생기면 한 장 겹칠 수 있다. 문제 되면 (정렬 값, 작성 시각, ID) 키셋 커서로
        String sql = CARD
                + (photoOnly ? " AND EXISTS (SELECT 1 FROM review.review_photos p WHERE p.review_id = r.id)" : "")
                + (excludeMine ? " AND r.member_id <> :requesterId" : "")
                + " ORDER BY " + sort.orderBy
                + " LIMIT :limit OFFSET :offset";
        return jdbc.sql(sql)
                .param("courseId", courseId)
                .param("requesterId", requesterId)
                .param("limit", limit)
                .param("offset", offset)
                .query(CARD_MAPPER)
                .list();
    }

    /** 이 회원이 이 코스에 쓴 리뷰. 회원당 코스별 1개라 많아야 하나다. */
    Optional<ReviewCard> mine(UUID memberId, UUID courseId) {
        return jdbc.sql(CARD + " AND r.member_id = :requesterId")
                .param("courseId", courseId)
                .param("requesterId", memberId)
                .query(CARD_MAPPER)
                .optional();
    }

    /** 이 회원의 이 코스 리뷰가 있고, 그 근거 기록이 삭제됐다(B10-1). */
    boolean isSourceRecordDeleted(UUID memberId, UUID courseId) {
        return jdbc.sql("""
                        SELECT EXISTS (SELECT 1
                                       FROM review.reviews r
                                       JOIN review.course_run_records c ON c.run_record_id = r.source_run_record_id
                                       WHERE r.member_id = :memberId AND r.course_id = :courseId AND c.deleted)""")
                .param("memberId", memberId)
                .param("courseId", courseId)
                .query(Boolean.class)
                .single();
    }

    /** DB 배열(VARCHAR[])을 태그 집합으로. 태그 순서는 enum 선언 순서다. */
    private static Set<ReviewTag> tags(Array array) throws SQLException {
        return Arrays.stream((String[]) array.getArray())
                .map(ReviewTag::valueOf)
                .collect(Collectors.toCollection(() -> EnumSet.noneOf(ReviewTag.class)));
    }

    /** round()는 NUMERIC이라 BigDecimal로 온다. 리뷰가 없으면 avg가 NULL이다. */
    private static Double decimal(ResultSet rs, String column) throws SQLException {
        BigDecimal value = rs.getBigDecimal(column);
        return value == null ? null : value.doubleValue();
    }
}
