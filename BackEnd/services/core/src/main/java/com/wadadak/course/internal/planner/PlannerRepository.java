package com.wadadak.course.internal.planner;

import com.wadadak.common.entity.UuidV7;
import lombok.RequiredArgsConstructor;
import org.locationtech.jts.geom.LineString;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.UUID;

/**
 * 코스 자동 생성의 하루 한도(정책 B3-A05)와 후보 지표용 POI.
 * 날짜는 부르는 쪽이 {@code LocalDate.now(clock.withZone(TimeConfig.SEOUL))}로 구한다.
 */
@Repository
@RequiredArgsConstructor
class PlannerRepository {

    /** 코스 자동 생성(하루 20회) */
    static final String PLAN = "PLAN";
    /** 조건 자동 채우기(하루 50회) */
    static final String PARSE = "PARSE";

    private final JdbcTemplate jdbcTemplate;

    /**
     * 한도 안이면 1을 더하고 true, 이미 한도면 그대로 두고 false.
     * 한 문장의 조건부 upsert라 같은 회원이 동시에 보내도 한도를 넘지 않는다.
     */
    boolean reserve(UUID memberId, LocalDate date, String kind, int limit) {
        return !jdbcTemplate.queryForList("""
                        INSERT INTO course.daily_plan_counts (id, member_id, plan_date, kind, plan_count, created_at, updated_at)
                        VALUES (?, ?, ?, ?, 1, now(), now())
                        ON CONFLICT (member_id, plan_date, kind) DO UPDATE
                            SET plan_count = course.daily_plan_counts.plan_count + 1, updated_at = now()
                            WHERE course.daily_plan_counts.plan_count < ?
                        RETURNING plan_count""",
                Integer.class, UuidV7.create(), memberId, date, kind, limit).isEmpty();
    }

    /** 세지 않는 요청(길을 찾지 않고 끝남 · 서버 장애)이면 {@link #reserve}를 되돌린다. 0 아래로 내려가지 않는다 */
    void release(UUID memberId, LocalDate date, String kind) {
        jdbcTemplate.update("""
                UPDATE course.daily_plan_counts SET plan_count = plan_count - 1, updated_at = now()
                WHERE member_id = ? AND plan_date = ? AND kind = ? AND plan_count > 0""", memberId, date, kind);
    }

    int used(UUID memberId, LocalDate date, String kind) {
        return jdbcTemplate.queryForObject("""
                SELECT coalesce(max(plan_count), 0) FROM course.daily_plan_counts
                WHERE member_id = ? AND plan_date = ? AND kind = ?""", Integer.class, memberId, date, kind);
    }

    /** 경로에서 storeMeters 안 편의점 수와 toiletMeters 안 화장실 수 */
    PoiCounts poisNear(LineString route, int storeMeters, int toiletMeters) {
        return jdbcTemplate.queryForObject("""
                        SELECT count(*) FILTER (WHERE kind = 'CONVENIENCE' AND ST_DWithin(location, route.line, ?)) AS stores,
                               count(*) FILTER (WHERE kind = 'TOILET' AND ST_DWithin(location, route.line, ?)) AS toilets
                        FROM course.planner_pois, (SELECT ST_GeomFromText(?, 4326)::geography AS line) AS route
                        WHERE ST_DWithin(location, route.line, greatest(?, ?))""",
                (rs, i) -> new PoiCounts(rs.getInt("stores"), rs.getInt("toilets")),
                storeMeters, toiletMeters, route.toText(), storeMeters, toiletMeters);
    }

    record PoiCounts(int stores, int toilets) {
    }
}
