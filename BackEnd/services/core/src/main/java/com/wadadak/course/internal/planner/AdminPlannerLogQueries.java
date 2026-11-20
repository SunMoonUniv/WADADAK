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
        NOT_PLANNED,
        /** 이 문장으로 찾은 후보로 코스를 실제로 등록함 */
        REGISTERED
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
                       (SELECT avg(place_ms + coalesce(route_ms, 0) + coalesce(select_ms, 0)) FROM course.planner_plan_logs g%2$s) AS plan_ms,
                       (SELECT avg((registered_course_id IS NOT NULL)::int) FROM course.planner_plan_logs g%4$s) AS registered_rate"""
                .formatted(parseWhere, planWhere, edited("p", "g"),
                        // 등록률은 후보를 받은 찾기 중에서
                        since == null ? " WHERE g.candidate_count > 0" : planWhere + " AND g.candidate_count > 0"));
        if (since != null) {
            query = query.param("since", timestamp(since));
        }
        return query.query((rs, rowNum) -> new Stats(rs.getLong("parses"), rs.getLong("plans"), ratio(rs, "jev_rate"),
                ratio(rs, "edited_rate"), ratio(rs, "no_candidate_rate"), ratio(rs, "plan_ms"), ratio(rs, "registered_rate"))).single();
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
                       -- 이 문장으로 한 찾기 중 하나라도 등록했으면 그 후보 순위(마지막 찾기가 아니어도)
                       (SELECT gr.registered_rank FROM course.planner_plan_logs gr
                        WHERE gr.parse_log_id = p.id AND gr.registered_course_id IS NOT NULL
                        ORDER BY gr.registered_at DESC LIMIT 1) AS registered_rank,
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
                    case REGISTERED -> " AND EXISTS (SELECT 1 FROM course.planner_plan_logs gr"
                            + " WHERE gr.parse_log_id = p.id AND gr.registered_course_id IS NOT NULL)";
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
                    instant(rs, "created_at"), plan, (Integer) rs.getObject("registered_rank"));
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
                               g.place_ms, g.route_ms, g.select_ms, g.created_at, %s AS edited,
                               g.generated_count, g.passed_count, g.paths::text AS paths, g.registered_rank, g.registered_at
                        FROM course.planner_plan_logs g JOIN course.planner_parse_logs p ON p.id = g.parse_log_id
                        WHERE g.parse_log_id = :id ORDER BY g.created_at""".formatted(edited("p", "g")))
                .param("id", id)
                .query((rs, rowNum) -> new PlanDetail(rs.getObject("id", UUID.class), json.readTree(rs.getString("form")),
                        rs.getBoolean("edited"), (Integer) rs.getObject("target_meters"), rs.getInt("candidate_count"),
                        rs.getString("reason"), json.readTree(rs.getString("candidates")), rs.getLong("place_ms"),
                        (Integer) rs.getObject("route_ms"), (Integer) rs.getObject("select_ms"), instant(rs, "created_at"),
                        (Integer) rs.getObject("generated_count"), (Integer) rs.getObject("passed_count"), tree(rs.getString("paths")),
                        (Integer) rs.getObject("registered_rank"),
                        rs.getObject("registered_at") == null ? null : instant(rs, "registered_at")))
                .list();
        return new Detail(parse.id(), parse.user(), parse.sentence(), parse.jevAnswers(), parse.form(), parse.elapsedMs(),
                parse.createdAt(), plans);
    }

    /**
     * 논문 분석용 CSV(UTF-8, 엑셀이 한글을 읽게 BOM을 붙인다). 채우기와 코스 찾기를 이어 한 줄씩:
     * 코스 찾기를 안 한 문장, 문장 없이 직접 조건으로 찾은 요청도 들어간다. 폼 · Jev 답 · 후보는 {@link PlannerLogCsv}가
     * 읽기 쉬운 칸으로 푼다(경로 점은 넣지 않는다).
     *
     * <p>ponytail: 전체를 메모리에서 만든다. 내부 테스트 규모(수천 줄)면 충분하고, 커지면 스트리밍으로 바꾼다
     */
    String csv(Instant since) {
        String sql = """
                SELECT p.created_at AS parsed_at, coalesce(p.member_hash, g.member_hash) AS member_hash, p.sentence,
                       p.jev_answers::text AS jev_answers, p.form::text AS parsed_form, p.elapsed_ms AS parse_ms,
                       g.created_at AS planned_at, g.form::text AS sent_form, g.target_meters, g.candidate_count, g.reason,
                       g.place_ms, g.route_ms, g.select_ms, g.candidates::text AS candidates, g.generated_count, g.passed_count,
                       g.id AS plan_id, g.registered_rank,
                       -- 만든 경로의 결과별 개수: {"PICKED": 3, "OUT_OF_RANGE": 28, ...}
                       (SELECT jsonb_object_agg(f.fate, f.n) FROM (SELECT x ->> 'fate' AS fate, count(*) AS n
                                                                  FROM jsonb_array_elements(g.paths) x GROUP BY 1) f)::text AS fates
                FROM course.planner_parse_logs p
                FULL JOIN course.planner_plan_logs g ON g.parse_log_id = p.id"""
                + (since == null ? "" : " WHERE coalesce(p.created_at, g.created_at) >= :since")
                + " ORDER BY coalesce(p.created_at, g.created_at), g.created_at";
        JdbcClient.StatementSpec query = jdbc.sql(sql);
        if (since != null) {
            query = query.param("since", timestamp(since));
        }
        StringBuilder out = new StringBuilder("﻿");
        line(out, PlannerLogCsv.header());
        query.query(rs -> {
            OffsetDateTime parsedAt = rs.getObject("parsed_at", OffsetDateTime.class);
            OffsetDateTime plannedAt = rs.getObject("planned_at", OffsetDateTime.class);
            line(out, PlannerLogCsv.row(searchId(rs.getObject("plan_id", UUID.class)),
                    parsedAt == null ? null : CSV_TIME.format(parsedAt), shortHash(rs.getString("member_hash")),
                    rs.getString("sentence"), tree(rs.getString("jev_answers")), tree(rs.getString("parsed_form")),
                    (Integer) rs.getObject("parse_ms"),
                    plannedAt == null ? null : CSV_TIME.format(plannedAt), tree(rs.getString("sent_form")),
                    (Integer) rs.getObject("target_meters"), (Integer) rs.getObject("candidate_count"), rs.getString("reason"),
                    (Integer) rs.getObject("place_ms"), (Integer) rs.getObject("route_ms"), (Integer) rs.getObject("select_ms"),
                    tree(rs.getString("candidates")), (Integer) rs.getObject("generated_count"), (Integer) rs.getObject("passed_count"),
                    tree(rs.getString("fates")), (Integer) rs.getObject("registered_rank")));
        });
        return out.toString();
    }

    /**
     * 논문 분석용 경로 CSV: 코스 찾기에서 만든 경로 하나 = 한 줄(뽑힌 것 · 걸러진 것 모두). 경로 점은 넣지 않는다(상세 API에 있다).
     * 2026-11-16 전 로그에는 경로 기록이 없어 빠진다.
     *
     * @param planId 코스 찾기 하나만. 이때는 그 찾기의 문장 · 모양 같은 칸이 줄마다 반복되지 않게 빼고 경로 칸만 넣는다.
     *               {@code null}이면 기간 안의 전부(찾기 ID 칸으로 메인 CSV와 잇는다)
     */
    String pathsCsv(Instant since, UUID planId) {
        String sql = """
                SELECT g.id AS plan_id, g.created_at, g.member_hash, p.sentence, g.form::text AS form, g.target_meters,
                       g.registered_rank, path.value::text AS path
                FROM course.planner_plan_logs g
                LEFT JOIN course.planner_parse_logs p ON p.id = g.parse_log_id
                CROSS JOIN LATERAL jsonb_array_elements(g.paths) AS path
                WHERE g.paths IS NOT NULL"""
                + (planId != null ? " AND g.id = :planId" : since == null ? "" : " AND g.created_at >= :since")
                + " ORDER BY g.created_at, (path.value ->> 'order')::int";
        JdbcClient.StatementSpec query = jdbc.sql(sql);
        if (planId != null) {
            query = query.param("planId", planId);
        } else if (since != null) {
            query = query.param("since", timestamp(since));
        }
        boolean one = planId != null;
        StringBuilder out = new StringBuilder("﻿");
        line(out, PlannerLogCsv.pathHeader(one));
        // 중괄호로 감싸야 "한 줄씩 처리(RowCallbackHandler)"로 읽힌다. 식 하나면 RowMapper와 헷갈려 컴파일이 안 된다
        query.query(rs -> {
            line(out, PlannerLogCsv.pathRow(one, searchId(rs.getObject("plan_id", UUID.class)),
                    CSV_TIME.format(rs.getObject("created_at", OffsetDateTime.class)),
                    shortHash(rs.getString("member_hash")), rs.getString("sentence"), tree(rs.getString("form")),
                    (Integer) rs.getObject("target_meters"), tree(rs.getString("path")), (Integer) rs.getObject("registered_rank")));
        });
        return out.toString();
    }

    /**
     * 메인 CSV와 경로 CSV를 잇는 "찾기 ID": 코스 찾기 로그 id의 끝 8자리.
     * id는 UUID v7이라 앞자리는 시각이라 가까운 시각끼리 같고, 끝자리는 무작위라 겹치지 않는다. 문장만 채운 줄은 null.
     * 앞에 S를 붙인다: "12345678"이나 "4e201234"는 엑셀이 숫자(지수)로 바꿔 버린다
     */
    static String searchId(UUID planId) {
        if (planId == null) {
            return null;
        }
        String id = planId.toString();
        return "S" + id.substring(id.length() - 8);
    }

    /** 칸들을 쉼표로 이어 한 줄. 엑셀이 읽는 줄바꿈(CRLF)으로 끝낸다 */
    private static void line(StringBuilder out, List<String> cells) {
        out.append(String.join(",", cells.stream().map(AdminPlannerLogQueries::cell).toList())).append("\r\n");
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
     * @param registeredRate  후보를 받은 코스 찾기 중 그 후보로 코스를 등록한 비율
     */
    record Stats(long parses, long plans, Double jevRate, Double editedRate, Double noCandidateRate, Double planMs,
                 Double registeredRate) {
    }

    /**
     * 목록 한 줄(채우기 하나).
     *
     * @param user 회원 해시 앞 8자리. 같은 사람끼리 같다
     * @param form 채운 폼
     * @param plan           이어진 마지막 코스 찾기. 안 했으면 {@code null}
     * @param registeredRank 이 문장으로 한 찾기의 후보로 코스를 등록했으면 그 후보 순위. 안 했으면 {@code null}
     */
    record Row(UUID id, String user, String sentence, boolean jevUsed, JsonNode form, long elapsedMs, Instant createdAt,
               Plan plan, Integer registeredRank) {
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

    /**
     * @param candidates     앱에 돌려준 후보 전부(경로 점 포함)
     * @param generatedCount 길찾기로 만든 경로 수. 2026-11-16 전 로그 · 길을 찾지 않은 요청은 {@code null}(아래 둘도 같다)
     * @param passedCount    거리 · 되돌아감 조건을 통과한 경로 수
     * @param paths          만든 경로 전부(만든 순서, {@link CandidateSelector.PathLog})
     * @param registeredRank 이 찾기의 후보로 코스를 등록했으면 그 후보 순위(1~3). 안 했으면 {@code null}(registeredAt도 같다)
     */
    record PlanDetail(UUID id, JsonNode form, boolean edited, Integer targetMeters, int candidateCount, String reason,
                      JsonNode candidates, long placeMs, Integer routeMs, Integer selectMs, Instant createdAt,
                      Integer generatedCount, Integer passedCount, JsonNode paths, Integer registeredRank, Instant registeredAt) {
    }
}
