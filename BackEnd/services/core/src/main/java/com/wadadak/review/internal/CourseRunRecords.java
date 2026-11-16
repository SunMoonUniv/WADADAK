package com.wadadak.review.internal;

import com.wadadak.review.internal.MyReview.CourseRun;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

/**
 * run·course 이벤트로 받아 둔 복사본 조회. 다른 모듈을 호출하지 않는다(개발 정책 4.2).
 *
 * <p>리뷰를 쓰려면 "이 코스를 충분히 달렸는지", "코스가 숨김·삭제되지 않았는지"를 알아야 한다. 그 원본은 run·course 모듈에 있지만,
 * 모듈 사이에서는 남의 테이블을 읽지 않기로 했으므로(MSA 대비) 이벤트로 받아 review 스키마에 복사해 둔 표를 읽는다.
 * 엔티티가 따로 없는 단순 조회라 SQL을 직접 쓰는 {@link JdbcClient}를 썼다(ranking 모듈과 같은 방식).
 */
@Component // 스프링이 이 객체를 하나 만들어 두고 필요한 곳(ReviewService)에 넣어 준다
@RequiredArgsConstructor // Lombok: final 필드를 받는 생성자를 만든다. 스프링은 이 생성자로 JdbcClient를 넣어 준다(생성자 주입)
class CourseRunRecords {

    // B2·B10 상단에 보이는 기록 한 건. 아래 두 조회가 같이 쓴다
    private static final RowMapper<CourseRun> COURSE_RUN = (rs, rowNum) -> new CourseRun(
            rs.getObject("run_record_id", UUID.class), rs.getInt("course_distance_meters"),
            rs.getInt("course_elapsed_seconds"), rs.getInt("progress_percent"), rs.getBoolean("completed"),
            rs.getObject("ended_at", OffsetDateTime.class).toInstant());

    private final JdbcClient jdbc;

    /** 숨김·삭제된 코스면 {@code false}. 복사본 행이 없으면 활성이다(숨김·삭제될 때만 행이 생긴다). */
    boolean isCourseActive(UUID courseId) {
        return jdbc.sql("SELECT count(*) FROM review.course_status_copies WHERE course_id = :courseId")
                .param("courseId", courseId) // :courseId 자리에 값을 안전하게 넣는다(SQL 인젝션 방지)
                .query(Integer.class)
                .single() == 0;
    }

    /** 이 회원이 이 코스에서 이 기록으로 리뷰 자격을 얻었고 그 기록이 남아 있다(정책 5.1·제4부 4.1 D-09). */
    boolean isEligibleSource(UUID memberId, UUID courseId, UUID runRecordId) {
        return jdbc.sql("""
                        SELECT count(*) FROM review.course_run_records
                        WHERE run_record_id = :runRecordId AND member_id = :memberId AND course_id = :courseId
                          AND review_eligible AND NOT deleted""")
                .param("runRecordId", runRecordId)
                .param("memberId", memberId)
                .param("courseId", courseId)
                .query(Integer.class)
                .single() > 0;
    }

    /** 리뷰를 쓸 수 있는 이 회원의 이 코스 기록 중 가장 최근에 끝난 것(B2 진입). 삭제된 기록은 빼고, 없으면 비어 있다. */
    Optional<CourseRun> latestEligibleRecord(UUID memberId, UUID courseId) {
        return jdbc.sql("""
                        SELECT run_record_id, course_distance_meters, course_elapsed_seconds, progress_percent, completed, ended_at
                        FROM review.course_run_records
                        WHERE member_id = :memberId AND course_id = :courseId AND review_eligible AND NOT deleted
                        ORDER BY ended_at DESC, run_record_id DESC
                        LIMIT 1""")
                .param("memberId", memberId)
                .param("courseId", courseId)
                .query(COURSE_RUN)
                .optional(); // 결과가 없으면 Optional.empty()
    }

    /** 이 회원의 이 코스 리뷰가 근거로 삼은 기록(B10 상단). 리뷰가 없거나 그 기록이 삭제됐으면 비어 있다. */
    Optional<CourseRun> sourceRecordOfReview(UUID memberId, UUID courseId) {
        return jdbc.sql("""
                        SELECT c.run_record_id, c.course_distance_meters, c.course_elapsed_seconds, c.progress_percent,
                               c.completed, c.ended_at
                        FROM review.reviews r
                        JOIN review.course_run_records c ON c.run_record_id = r.source_run_record_id
                        WHERE r.member_id = :memberId AND r.course_id = :courseId AND NOT c.deleted""")
                .param("memberId", memberId)
                .param("courseId", courseId)
                .query(COURSE_RUN)
                .optional();
    }

    /** 이 회원의 이 코스 최고 진행도(%). 남아 있는 기록만 보고, 없으면 0이다. 자격이 없는 기록도 진행도에는 들어간다. */
    int bestProgressPercent(UUID memberId, UUID courseId) {
        return jdbc.sql("""
                        SELECT coalesce(max(progress_percent), 0) FROM review.course_run_records
                        WHERE member_id = :memberId AND course_id = :courseId AND NOT deleted""")
                .param("memberId", memberId)
                .param("courseId", courseId)
                .query(Integer.class)
                .single();
    }
}
