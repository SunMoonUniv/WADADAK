package com.wadadak.run.internal.recording;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.UUID;

/** 코스별 현재 러너 수 이벤트의 version. 행 잠금으로 같은 코스의 증감을 트랜잭션 끝까지 한 줄로 세운다 */
@Repository
class CourseRunnerCounts {

    private final JdbcTemplate db;

    CourseRunnerCounts(JdbcTemplate db) {
        this.db = db;
    }

    long nextVersion(UUID courseId) {
        return db.queryForObject("""
                INSERT INTO run.course_runner_counts(course_id, version) VALUES (?, 1)
                ON CONFLICT (course_id) DO UPDATE SET version = run.course_runner_counts.version + 1, updated_at = now()
                RETURNING version""", Long.class, courseId);
    }
}
