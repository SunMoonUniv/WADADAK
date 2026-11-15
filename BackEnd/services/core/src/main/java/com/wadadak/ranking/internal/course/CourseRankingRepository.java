package com.wadadak.ranking.internal.course;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * 코스 랭킹 조회 SQL. 대표 기록 고르기와 공동순위(RANK)를 DB에서 한 번에 계산한다.
 * 같은 순위 안에서는 먼저 등록된 기록이 앞이다. 페이지를 넘겨도 순서가 바뀌지 않는다.
 */
@Repository
@RequiredArgsConstructor
class CourseRankingRepository {

    private static final RowMapper<RankedRecord> RECORD = (rs, rowNum) -> new RankedRecord(rs.getInt("rank"),
            rs.getObject("run_record_id", UUID.class), rs.getObject("member_id", UUID.class),
            rs.getInt("course_elapsed_seconds"), rs.getInt("course_distance_meters"),
            rs.getObject("completed_at", OffsetDateTime.class).toInstant());

    private final JdbcClient jdbc;

    /** 숨김·삭제된 코스면 {@code true}. 복사본에 행이 없으면 ACTIVE다(개발 정책 5.4). */
    boolean isHidden(UUID courseId) {
        return jdbc.sql("SELECT EXISTS (SELECT 1 FROM ranking.course_status_copies WHERE course_id = :courseId)")
                .param("courseId", courseId)
                .query(Boolean.class)
                .single();
    }

    /** 복사본에 행이 없으면 공개다. */
    boolean isVisible(UUID memberId) {
        return jdbc.sql("SELECT COALESCE((SELECT visible FROM ranking.member_visibility_copies WHERE member_id = :memberId), TRUE)")
                .param("memberId", memberId)
                .query(Boolean.class)
                .single();
    }

    /** {@code from} 이후 등록된 기록 중 공개 회원의 대표 기록을 순위순으로. */
    List<RankedRecord> ranking(UUID courseId, Instant from) {
        return jdbc.sql("""
                        SELECT RANK() OVER (ORDER BY best.course_elapsed_seconds) AS rank, best.*
                        FROM (SELECT DISTINCT ON (e.member_id)
                                     e.run_record_id, e.member_id, e.course_elapsed_seconds, e.course_distance_meters,
                                     e.completed_at, e.registered_at
                              FROM ranking.course_ranking_entries e
                              WHERE e.course_id = :courseId
                                AND NOT e.deleted
                                AND e.registered_at >= :from
                                AND NOT EXISTS (SELECT 1
                                                FROM ranking.member_visibility_copies v
                                                WHERE v.member_id = e.member_id AND NOT v.visible)
                              ORDER BY e.member_id, e.course_elapsed_seconds, e.registered_at, e.run_record_id) best
                        ORDER BY best.course_elapsed_seconds, best.registered_at, best.run_record_id""")
                .param("courseId", courseId)
                .param("from", OffsetDateTime.ofInstant(from, ZoneOffset.UTC))
                .query(RECORD)
                .list();
    }

    /** 공개 여부와 관계없이 그 회원의 대표 기록. 비공개 회원에게 자기 기록을 보여줄 때 쓴다. 순위는 0이다. */
    Optional<RankedRecord> best(UUID courseId, UUID memberId, Instant from) {
        return jdbc.sql("""
                        SELECT 0 AS rank, run_record_id, member_id, course_elapsed_seconds, course_distance_meters, completed_at
                        FROM ranking.course_ranking_entries
                        WHERE course_id = :courseId AND member_id = :memberId AND NOT deleted AND registered_at >= :from
                        ORDER BY course_elapsed_seconds, registered_at, run_record_id
                        LIMIT 1""")
                .param("courseId", courseId)
                .param("memberId", memberId)
                .param("from", OffsetDateTime.ofInstant(from, ZoneOffset.UTC))
                .query(RECORD)
                .optional();
    }
}
