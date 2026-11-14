package com.wadadak.course.internal.planner;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.paging.NumberedPage;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;

/**
 * 운영자 웹 "코스 생성 로그"(분석 로그 {@link PlannerLogRepository}를 읽기만 한다). 조회는 {@link JdbcClient}로 직접 쓴다.
 *
 * <p>[폼 수정] 채운 폼(parse)과 사용자가 보낸 폼(plan)이 다르면 수정한 것으로 본다. 안내 문구(message)는 비교하지 않고,
 * 원하는 길(prefer)은 순서가 달라도 같은 것으로 본다(서버는 정해진 순서로, 앱은 고른 순서로 보낼 수 있다).
 */
@Repository
@RequiredArgsConstructor
class AdminPlannerLogQueries {

    /** 목록의 코스 찾기 결과 필터 */
    enum Result {
        /** 후보가 1개 이상 */
        FOUND,
        /** 코스 찾기를 했지만 후보가 없음(장소 못 찾음 · 너무 멂 · 길 없음 · 비슷한 코스) */
        NONE,
        /** 문장만 채우고 10분 안에 코스 찾기를 안 함 */
        NOT_PLANNED
    }

    /** CSV 시각: 한국 시각 */
    private static final DateTimeFormatter CSV_TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(TimeConfig.SEOUL);

    private final JdbcClient jdbc;
    private final JsonMapper json;

    /** p(채우기)와 g(코스 찾기)의 폼이 다른지. SQL 조각이다 */
    static String edited(String p, String g) {
        return "((%1$s.form - 'message' - 'prefer') IS DISTINCT FROM (%2$s.form - 'message' - 'prefer') OR %3$s IS DISTINCT FROM %4$s)"
                .formatted(p, g, prefer(p), prefer(g));
    }

    /** 원하는 길을 정렬한 배열로. null · 빈 배열은 같다 */
    private static String prefer(String alias) {
        return "ARRAY(SELECT x FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(%s.form -> 'prefer') = 'array' THEN %s.form -> 'prefer' ELSE '[]' END) x ORDER BY x)"
                .formatted(alias, alias);
    }

    /** @param since 이 시각 이후만. {@code null}이면 전체 기간 */
    Stats stats(Instant since) {
        String parseWhere = since == null ? "" : " WHERE created_at >= :since";
        String planWhere = since == null ? "" : " WHERE g.created_at >= :since";
        JdbcClient.StatementSpec query = jdbc.sql("""
                SELECT (SELECT count(*) FROM course.planner_parse_logs%1$s) AS parses,
                       (SELECT count(*) FROM course.planner_plan_logs g%2$s) AS plans,
                       (SELECT avg((jev_answers IS NOT NULL)::int) FROM course.planner_parse_logs%1$s) AS jev_rate,
                       (SELECT avg((%3$s)::int) FROM course.planner_plan_logs g
                        JOIN course.planner_parse_logs p ON p.id = g.parse_log_id%2$s) AS edited_rate,
                       (SELECT avg((candidate_count = 0)::int) FROM course.planner_plan_logs g%2$s) AS no_candidate_rate,
                       (SELECT avg(place_ms + coalesce(route_ms, 0) + coalesce(select_ms, 0)) FROM course.planner_plan_logs g%2$s) AS plan_ms"""
                .formatted(parseWhere, planWhere, edited("p", "g")));
        if (since != null) {
            query = query.param("since", timestamp(since));
        }
        return query.query((rs, rowNum) -> new Stats(rs.getLong("parses"), rs.getLong("plans"), ratio(rs, "jev_rate"),
                ratio(rs, "edited_rate"), ratio(rs, "no_candidate_rate"), ratio(rs, "plan_ms"))).single();
    }

    /**
     * 문장 한 줄 = 한 행, 최신순. 같은 문장으로 코스 찾기를 여러 번 했으면 마지막 결과와 횟수를 붙인다.
     *
     * @param jev {@code null}이면 전체, true면 Jev를 쓴 것만, false면 규칙만 쓴 것만
     */
    NumberedPage<Row> rows(Instant since, Result result, Boolean jev, int offset, int limit) {
        // 조건이 있을 때만 WHERE에 붙인다. "? IS NULL OR …"로 쓰면 PostgreSQL이 null 파라미터의 타입을 몰라 실패한다
        String sql = """
                SELECT p.id, p.member_hash, p.sentence, p.jev_answers IS NOT NULL AS jev_used, p.form::text AS form,
                       p.elapsed_ms, p.created_at, g.candidate_count, g.reason, g.total_ms, g.edited, g.plan_count,
                       count(*) OVER () AS total
                FROM course.planner_parse_logs p
                LEFT JOIN LATERAL (
                    SELECT gl.candidate_count, gl.reason,
                           gl.place_ms + coalesce(gl.route_ms, 0) + coalesce(gl.select_ms, 0) AS total_ms,
                           %s AS edited, count(*) OVER () AS plan_count
                    FROM course.planner_plan_logs gl WHERE gl.parse_log_id = p.id
                    ORDER BY gl.created_at DESC LIMIT 1) g ON TRUE
                WHERE TRUE""".formatted(edited("p", "gl"))
                + (since == null ? "" : " AND p.created_at >= :since")
                + (jev == null ? "" : jev ? " AND p.jev_answers IS NOT NULL" : " AND p.jev_answers IS NULL")
                + (result == null ? "" : switch (result) {
                    case FOUND -> " AND g.candidate_count > 0";
                    case NONE -> " AND g.candidate_count = 0";
                    case NOT_PLANNED -> " AND g.candidate_count IS NULL";
                })
                + " ORDER BY p.created_at DESC, p.id DESC LIMIT :limit OFFSET :offset";
        JdbcClient.StatementSpec query = jdbc.sql(sql).param("limit", limit).param("offset", offset);
        if (since != null) {
            query = query.param("since", timestamp(since));
        }
        long[] total = {0};
        List<Row> rows = query.query((rs, rowNum) -> {
            total[0] = rs.getLong("total");
            Integer candidates = (Integer) rs.getObject("candidate_count");
            Plan plan = candidates == null ? null : new Plan(candidates, rs.getString("reason"), rs.getLong("total_ms"),
                    rs.getBoolean("edited"), rs.getInt("plan_count"));
            return new Row(rs.getObject("id", UUID.class), shortHash(rs.getString("member_hash")), rs.getString("sentence"),
                    rs.getBoolean("jev_used"), json.readTree(rs.getString("form")), rs.getLong("elapsed_ms"),
                    instant(rs, "created_at"), plan);
        }).list();
        return new NumberedPage<>(rows, total[0]);
    }

    /** 채우기 로그 하나와 거기 이어진 코스 찾기 전부(먼저 한 것부터). 없으면 null */
    Detail detail(UUID id) {
        Detail parse = jdbc.sql("""
                        SELECT member_hash, sentence, jev_answers::text AS jev_answers, form::text AS form, elapsed_ms, created_at
                        FROM course.planner_parse_logs WHERE id = :id""")
                .param("id", id)
                .query((rs, rowNum) -> new Detail(id, shortHash(rs.getString("member_hash")), rs.getString("sentence"),
                        tree(rs.getString("jev_answers")), json.readTree(rs.getString("form")), rs.getLong("elapsed_ms"),
                        instant(rs, "created_at"), List.of()))
                .optional().orElse(null);
        if (parse == null) {
            return null;
        }
        List<PlanDetail> plans = jdbc.sql("""
                        SELECT g.id, g.form::text AS form, g.target_meters, g.candidate_count, g.reason, g.candidates::text AS candidates,
                               g.place_ms, g.route_ms, g.select_ms, g.created_at, %s AS edited
                        FROM course.planner_plan_logs g JOIN course.planner_parse_logs p ON p.id = g.parse_log_id
                        WHERE g.parse_log_id = :id ORDER BY g.created_at""".formatted(edited("p", "g")))
                .param("id", id)
                .query((rs, rowNum) -> new PlanDetail(rs.getObject("id", UUID.class), json.readTree(rs.getString("form")),
                        rs.getBoolean("edited"), (Integer) rs.getObject("target_meters"), rs.getInt("candidate_count"),
                        rs.getString("reason"), json.readTree(rs.getString("candidates")), rs.getLong("place_ms"),
                        (Integer) rs.getObject("route_ms"), (Integer) rs.getObject("select_ms"), instant(rs, "created_at")))
                .list();
        return new Detail(parse.id(), parse.user(), parse.sentence(), parse.jevAnswers(), parse.form(), parse.elapsedMs(),
                parse.createdAt(), plans);
    }

    /**
     * 논문 분석용 CSV(UTF-8, 엑셀이 한글을 읽게 BOM을 붙인다). 채우기와 코스 찾기를 이어 한 줄씩:
     * 코스 찾기를 안 한 문장, 문장 없이 직접 조건으로 찾은 요청도 들어간다. 후보는 경로 점(anchorPoints)을 빼고 지표만 넣는다.
     *
     * <p>ponytail: 전체를 메모리에서 만든다. 내부 테스트 규모(수천 줄)면 충분하고, 커지면 스트리밍으로 바꾼다
     */
    String csv(Instant since) {
        String sql = """
                SELECT p.id AS parse_id, p.created_at AS parsed_at, coalesce(p.member_hash, g.member_hash) AS member_hash,
                       p.sentence, p.jev_answers::text AS jev_answers, p.form::text AS parsed_form, p.elapsed_ms AS parse_ms,
                       g.id AS plan_id, g.created_at AS planned_at, g.form::text AS sent_form,
                       CASE WHEN p.id IS NULL OR g.id IS NULL THEN NULL ELSE %s END AS edited,
                       g.target_meters, g.candidate_count, g.reason, g.place_ms, g.route_ms, g.select_ms,
                       (SELECT jsonb_agg(c - 'anchorPoints') FROM jsonb_array_elements(g.candidates) c)::text AS candidates
                FROM course.planner_parse_logs p
                FULL JOIN course.planner_plan_logs g ON g.parse_log_id = p.id""".formatted(edited("p", "g"))
                + (since == null ? "" : " WHERE coalesce(p.created_at, g.created_at) >= :since")
                + " ORDER BY coalesce(p.created_at, g.created_at), g.created_at";
        JdbcClient.StatementSpec query = jdbc.sql(sql);
        if (since != null) {
            query = query.param("since", timestamp(since));
        }
        String[] columns = {"parse_id", "parsed_at", "member_hash", "sentence", "jev_answers", "parsed_form", "parse_ms",
                "plan_id", "planned_at", "sent_form", "edited", "target_meters", "candidate_count", "reason",
                "place_ms", "route_ms", "select_ms", "candidates"};
        StringBuilder out = new StringBuilder("﻿").append(String.join(",", columns)).append("\r\n");
        query.query(rs -> {
            for (int i = 0; i < columns.length; i++) {
                Object value = rs.getObject(columns[i]);
                if (value instanceof OffsetDateTime time) {
                    value = CSV_TIME.format(time);
                } else if (value instanceof java.sql.Timestamp time) {
                    value = CSV_TIME.format(time.toInstant());
                }
                out.append(i == 0 ? "" : ",").append(cell(value));
            }
            out.append("\r\n");
        });
        return out.toString();
    }

    /** CSV 칸: 쉼표 · 따옴표 · 줄바꿈이 있으면 따옴표로 감싸고 안의 따옴표는 두 번 쓴다 */
    static String cell(Object value) {
        if (value == null) {
            return "";
        }
        String text = value.toString();
        return text.matches("(?s).*[\",\r\n].*") ? "\"" + text.replace("\"", "\"\"") + "\"" : text;
    }

    /** 표에서 같은 사람을 알아볼 만큼만(앞 8자리) */
    private static String shortHash(String hash) {
        return hash.substring(0, 8);
    }

    private JsonNode tree(String text) {
        return text == null ? null : json.readTree(text);
    }

    private static Double ratio(ResultSet rs, String column) throws SQLException {
        Number value = (Number) rs.getObject(column);
        return value == null ? null : value.doubleValue();
    }

    private static OffsetDateTime timestamp(Instant instant) {
        return instant.atOffset(ZoneOffset.UTC);
    }

    private static Instant instant(ResultSet rs, String column) throws SQLException {
        return rs.getObject(column, OffsetDateTime.class).toInstant();
    }

    /**
     * 위 숫자 카드. 비율은 0~1이고 셀 것이 없으면 {@code null}이다.
     *
     * @param jevRate         Jev를 쓴(실패하지 않은) 채우기 비율
     * @param editedRate      문장과 이어진 코스 찾기 중 사용자가 폼을 고쳐 보낸 비율
     * @param noCandidateRate 코스 찾기 중 후보가 없던 비율
     * @param planMs          코스 찾기 평균 시간(ms, 장소 + 길찾기 + 고르기)
     */
    record Stats(long parses, long plans, Double jevRate, Double editedRate, Double noCandidateRate, Double planMs) {
    }

    /**
     * 목록 한 줄(채우기 하나).
     *
     * @param user 회원 해시 앞 8자리. 같은 사람끼리 같다
     * @param form 채운 폼
     * @param plan 이어진 마지막 코스 찾기. 안 했으면 {@code null}
     */
    record Row(UUID id, String user, String sentence, boolean jevUsed, JsonNode form, long elapsedMs, Instant createdAt,
               Plan plan) {
    }

    /**
     * @param totalMs 장소 + 길찾기 + 고르기 시간
     * @param edited  채운 폼과 다르게 보냈는지
     * @param count   이 문장에 이어진 코스 찾기 횟수
     */
    record Plan(int candidateCount, String reason, long totalMs, boolean edited, int count) {
    }

    /** @param jevAnswers Jev를 못 썼으면 {@code null} */
    record Detail(UUID id, String user, String sentence, JsonNode jevAnswers, JsonNode form, long elapsedMs, Instant createdAt,
                  List<PlanDetail> plans) {
    }

    /** @param candidates 앱에 돌려준 후보 전부(경로 점 포함) */
    record PlanDetail(UUID id, JsonNode form, boolean edited, Integer targetMeters, int candidateCount, String reason,
                      JsonNode candidates, long placeMs, Integer routeMs, Integer selectMs, Instant createdAt) {
    }
}
