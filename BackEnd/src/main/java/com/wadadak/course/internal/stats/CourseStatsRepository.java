package com.wadadak.course.internal.stats;

import com.wadadak.common.entity.UuidV7;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.Optional;
import java.util.UUID;

/**
 * 코스 누적 · 일별 통계와 이벤트 처리 기록(개발 정책 5.4 · 5.6). 증감은 원자적 UPSERT라 동시에 와도 값이 사라지지 않는다.
 * 행이 없으면 첫 증감 때 만든다. 증감 전에 {@link #lockIfActive}로 공개 중인지 보고 코스 행을 잠근다.
 */
@Repository
@RequiredArgsConstructor
class CourseStatsRepository {

    private final JdbcClient jdbc;

    /** 처음 받은 이벤트면 처리 기록을 남기고 true, 이미 처리했으면 false. 트랜잭션 첫 단계에서 부른다(개발 정책 5.4). */
    boolean markProcessed(UUID eventId, String listener) {
        return jdbc.sql("""
                        INSERT INTO course.processed_events (event_id, listener, processed_at)
                        VALUES (:eventId, :listener, now())
                        ON CONFLICT DO NOTHING""")
                .param("eventId", eventId)
                .param("listener", listener)
                .update() == 1;
    }

    /**
     * 공개 중인 코스면 true. 코스 행을 공유 잠금해, 트랜잭션이 끝날 때까지 비공개 · 삭제로 바뀌지 않는다.
     * 그래서 삭제할 때 지운 통계 행이 늦게 온 증감으로 다시 생기지 않는다. 없는 코스는 false.
     */
    boolean lockIfActive(UUID courseId) {
        return jdbc.sql("SELECT status FROM course.courses WHERE id = :courseId FOR SHARE")
                .param("courseId", courseId)
                .query(String.class)
                .optional()
                .filter("ACTIVE"::equals)
                .isPresent();
    }

    /** 완주 수와 코스 총 소요시간 합. 기록을 지우면 음수로 뺀다 */
    void addCompletions(UUID courseId, int count, long seconds) {
        jdbc.sql("""
                        INSERT INTO course.course_stats AS s (course_id, completion_count, completion_seconds, created_at, updated_at)
                        VALUES (:courseId, :count, :seconds, now(), now())
                        ON CONFLICT (course_id) DO UPDATE
                            SET completion_count = s.completion_count + EXCLUDED.completion_count,
                                completion_seconds = s.completion_seconds + EXCLUDED.completion_seconds,
                                updated_at = now()""")
                .param("courseId", courseId)
                .param("count", count)
                .param("seconds", seconds)
                .update();
    }

    /** 평점 합과 리뷰 수. 누적과 [day](리뷰 작성일) 행에 같이 더한다 */
    void addReviews(UUID courseId, LocalDate day, int ratingSum, int reviewCount) {
        jdbc.sql("""
                        INSERT INTO course.course_stats AS s (course_id, rating_sum, review_count, created_at, updated_at)
                        VALUES (:courseId, :ratingSum, :reviewCount, now(), now())
                        ON CONFLICT (course_id) DO UPDATE
                            SET rating_sum = s.rating_sum + EXCLUDED.rating_sum,
                                review_count = s.review_count + EXCLUDED.review_count,
                                updated_at = now()""")
                .param("courseId", courseId)
                .param("ratingSum", ratingSum)
                .param("reviewCount", reviewCount)
                .update();
        jdbc.sql("""
                        INSERT INTO course.course_daily_stats AS d (id, course_id, stat_date, rating_sum, review_count, created_at, updated_at)
                        VALUES (:id, :courseId, :day, :ratingSum, :reviewCount, now(), now())
                        ON CONFLICT (course_id, stat_date) DO UPDATE
                            SET rating_sum = d.rating_sum + EXCLUDED.rating_sum,
                                review_count = d.review_count + EXCLUDED.review_count,
                                updated_at = now()""")
                .param("id", UuidV7.create())
                .param("courseId", courseId)
                .param("day", day)
                .param("ratingSum", ratingSum)
                .param("reviewCount", reviewCount)
                .update();
    }

    /** 조회 수 1. 누적과 [day] 행에 같이 더한다 */
    void addView(UUID courseId, LocalDate day) {
        jdbc.sql("""
                        INSERT INTO course.course_stats AS s (course_id, view_count, created_at, updated_at)
                        VALUES (:courseId, 1, now(), now())
                        ON CONFLICT (course_id) DO UPDATE SET view_count = s.view_count + 1, updated_at = now()""")
                .param("courseId", courseId)
                .update();
        jdbc.sql("""
                        INSERT INTO course.course_daily_stats AS d (id, course_id, stat_date, view_count, created_at, updated_at)
                        VALUES (:id, :courseId, :day, 1, now(), now())
                        ON CONFLICT (course_id, stat_date) DO UPDATE SET view_count = d.view_count + 1, updated_at = now()""")
                .param("id", UuidV7.create())
                .param("courseId", courseId)
                .param("day", day)
                .update();
    }

    /** 완주 수와 코스 총 소요시간 합. 행이 없으면 비어 있다 */
    Optional<Completions> completions(UUID courseId) {
        return jdbc.sql("SELECT completion_count, completion_seconds FROM course.course_stats WHERE course_id = :courseId")
                .param("courseId", courseId)
                .query((rs, rowNum) -> new Completions(rs.getInt("completion_count"), rs.getLong("completion_seconds")))
                .optional();
    }

    /** 누적 · 일별 통계 행을 지운다 */
    void delete(UUID courseId) {
        jdbc.sql("DELETE FROM course.course_daily_stats WHERE course_id = :courseId").param("courseId", courseId).update();
        jdbc.sql("DELETE FROM course.course_stats WHERE course_id = :courseId").param("courseId", courseId).update();
    }

    record Completions(int count, long seconds) {
    }
}
