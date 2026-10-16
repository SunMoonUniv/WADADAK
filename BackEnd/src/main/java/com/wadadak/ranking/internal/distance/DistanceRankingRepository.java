package com.wadadak.ranking.internal.distance;

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

/** 누적 거리 랭킹 SQL. 회원별 거리 합계만 세고 순위는 서비스가 매긴다. */
@Repository
@RequiredArgsConstructor
class DistanceRankingRepository {

    private static final String DISTANCES = """
            SELECT d.member_id,
                   NOT EXISTS (SELECT 1
                               FROM ranking.member_visibility_copies v
                               WHERE v.member_id = d.member_id AND NOT v.visible) AS visible,
                   COALESCE(sum(d.distance_meters) FILTER (WHERE d.registered_at >= :from), 0) AS period_meters,
                   count(*) FILTER (WHERE d.registered_at >= :from) AS period_runs,
                   COALESCE(sum(d.distance_meters) FILTER (WHERE d.registered_at >= :weekStart), 0) AS week_meters,
                   sum(d.distance_meters) AS total_meters,
                   min(d.registered_at) AS first_registered_at
            FROM ranking.distance_run_records d
            WHERE NOT d.deleted
              AND d.registered_at < :to
              %s
            GROUP BY d.member_id
            HAVING count(*) FILTER (WHERE d.registered_at >= :from) > 0""";

    /** 그 시각에 지역이 :regionCode인 회원. 이력 중 그 시각 이전에 들어간 가장 늦은 행이 그때 지역이다. */
    private static final String IN_REGION = """
            AND d.member_id IN (SELECT h.member_id
                                FROM (SELECT DISTINCT ON (member_id) member_id, region_code
                                      FROM ranking.member_region_history
                                      WHERE effective_from <= :regionAt
                                      ORDER BY member_id, effective_from DESC, source_version DESC) h
                                WHERE h.region_code = :regionCode)""";

    private static final RowMapper<MemberDistance> ROW = (rs, rowNum) -> new MemberDistance(
            rs.getObject("member_id", UUID.class), rs.getBoolean("visible"), rs.getDouble("period_meters"),
            rs.getInt("period_runs"), rs.getDouble("week_meters"), rs.getDouble("total_meters"),
            rs.getObject("first_registered_at", OffsetDateTime.class).toInstant());

    private final JdbcClient jdbc;

    /**
     * {@code [from, to)}에 등록된 기록이 있는 회원. 내 정보 비공개 회원도 넣는다(본인 행에 쓴다).
     * 이번 주 거리·누적 거리·첫 기록은 {@code to} 전에 등록된 기록 전체로 센다.
     *
     * @param regionCode 이 활동 지역 회원만. {@code null}이면 전체
     * @param regionAt   {@code regionCode}로 묶는 시각(그 주 월요일 00:00)
     */
    List<MemberDistance> distances(Instant from, Instant to, Instant weekStart, String regionCode, Instant regionAt) {
        JdbcClient.StatementSpec sql = jdbc.sql(DISTANCES.formatted(regionCode == null ? "" : IN_REGION))
                .param("from", utc(from))
                .param("to", utc(to))
                .param("weekStart", utc(weekStart));
        if (regionCode != null) {
            sql = sql.param("regionCode", regionCode).param("regionAt", utc(regionAt));
        }
        return sql.query(ROW).list();
    }

    /** 그 시각에 회원이 있던 활동 지역 */
    Optional<String> regionAt(UUID memberId, Instant at) {
        return jdbc.sql("""
                        SELECT region_code
                        FROM ranking.member_region_history
                        WHERE member_id = :memberId AND effective_from <= :at
                        ORDER BY effective_from DESC, source_version DESC
                        LIMIT 1""")
                .param("memberId", memberId)
                .param("at", utc(at))
                .query(String.class)
                .optional();
    }

    private static OffsetDateTime utc(Instant instant) {
        return OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }

    /**
     * 회원 한 명의 거리 합계(m).
     *
     * @param periodMeters      그 기간 거리
     * @param periodRuns        그 기간 기록 수
     * @param weekMeters        이번 주 거리
     * @param totalMeters       누적 거리(주 평균)
     * @param firstRegisteredAt 첫 기록 등록 시각(주 평균)
     */
    record MemberDistance(UUID memberId, boolean visible, double periodMeters, int periodRuns, double weekMeters,
                          double totalMeters, Instant firstRegisteredAt) {

        /** 표시하는 m 정수. 순위도 이 값으로 매긴다 */
        int meters() {
            return (int) Math.round(periodMeters);
        }
    }
}
