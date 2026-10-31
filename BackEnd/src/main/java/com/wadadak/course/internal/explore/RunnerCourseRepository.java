package com.wadadak.course.internal.explore;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.internal.course.CourseGeometry;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.UUID;

/** 다른 러너가 등록한 공개 코스(I3). 코스와 코스 통계(평점 · 완주 수)를 읽는다. 삭제 예정 코스는 목록에서 막힌다(정책 공통 4). */
@Repository
@RequiredArgsConstructor
class RunnerCourseRepository {

    private final JdbcClient jdbc;

    /** 최근 등록순, 같으면 ID순. 한 회원의 코스라 G4처럼 오프셋 커서로 넘긴다 */
    CursorSlice<RunnerCourseItem> list(UUID memberId, Cursorable page) {
        int offset = page.offset();
        List<RunnerCourseItem> rows = jdbc.sql("""
                        SELECT c.id, c.name, c.distance_meters, %s AS average_rating,
                               coalesce(s.completion_count, 0) AS completion_count, ST_AsBinary(c.route) AS route
                        FROM course.courses c
                        LEFT JOIN course.course_stats s ON s.course_id = c.id
                        WHERE c.creator_id = :memberId AND c.status = 'ACTIVE'
                        ORDER BY c.created_at DESC, c.id
                        LIMIT :limit OFFSET :offset""".formatted(CourseMapRepository.RATING))
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

    /** 공개 중인 코스만 센다 */
    RunnerCourseSummary summary(UUID memberId) {
        return new RunnerCourseSummary(jdbc.sql("SELECT count(*) FROM course.courses WHERE creator_id = :memberId AND status = 'ACTIVE'")
                .param("memberId", memberId)
                .query(Integer.class)
                .single());
    }

    private static RunnerCourseItem item(ResultSet rs) throws SQLException {
        BigDecimal rating = rs.getBigDecimal("average_rating");
        return new RunnerCourseItem(rs.getObject("id", UUID.class), rs.getString("name"), rs.getInt("distance_meters"),
                rating == null ? null : rating.doubleValue(), rs.getInt("completion_count"),
                CourseGeometry.points(rs.getBytes("route")));
    }
}
