package com.wadadak.course.internal.planner;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.course.internal.planner.JevClient.JevAnswers;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.json.JsonMapper;

import java.util.UUID;

/**
 * 코스 자동 생성 분석 로그(내부 테스트 · 논문용). 문장 → 폼과 폼 → 코스를 한 줄씩 남긴다.
 *
 * <p>회원 ID 대신 sha256 값(member_hash)을 남긴다. 해시는 PostgreSQL 내장 {@code sha256()}로 구한다.
 * 후보는 앱에 돌려준 그대로(경로 점 anchorPoints · 지표 전부) 남긴다. 사용자의 현재 위치는 남기지 않는다.
 * 코스 찾기 로그는 저장할 때 같은 사람이 10분 안에 보낸 마지막 채우기 로그와 잇는다({@code parse_log_id}).
 *
 * <p>로그 저장이 실패해도(DB · JSON 변환) 사용자 요청은 그대로 성공해야 하므로, 예외를 삼키고 종류만 경고로 남긴다.
 * 메시지에는 문장이 들어 있을 수 있어 남기지 않는다.
 */
@Slf4j
@Repository
@RequiredArgsConstructor
class PlannerLogRepository {

    /** 이 시간 안의 채우기만 코스 찾기와 잇는다 */
    static final String LINK_WINDOW = "10 minutes";

    private static final String MEMBER_HASH = "encode(sha256(convert_to(?::text, 'UTF8')), 'hex')";

    private final JdbcTemplate jdbcTemplate;
    private final JsonMapper json;

    /** @param jev Jev를 못 썼으면 null */
    void saveParse(UUID memberId, String sentence, JevAnswers jev, PlanForm form, long elapsedMs) {
        try {
            // ?::jsonb = 자바에서 만든 JSON 문자열을 PostgreSQL JSONB 칸에 넣도록 형을 바꾼다
            jdbcTemplate.update("""
                            INSERT INTO course.planner_parse_logs (id, member_hash, sentence, jev_answers, form, elapsed_ms, created_at)
                            VALUES (?, %s, ?, ?::jsonb, ?::jsonb, ?, now())""".formatted(MEMBER_HASH),
                    UuidV7.create(), memberId, sentence, jev == null ? null : json.writeValueAsString(jev),
                    json.writeValueAsString(form), elapsedMs);
        } catch (RuntimeException e) {
            log.warn("코스 자동 생성 채우기 로그를 남기지 못했다: {}", e.getClass().getSimpleName());
        }
    }

    /** @param routeMs · selectMs 길을 찾지 않고 끝났으면 null */
    void savePlan(UUID memberId, PlanRequest request, PlanResult result, long placeMs, Long routeMs, Long selectMs) {
        try {
            // 저장할 때 잇기: 맨 아래 h에서 해시를 한 번 구하고, 그 해시로 같은 사람의 마지막 채우기 로그 id를 찾아 같이 넣는다.
            // ?는 SQL에 적힌 순서대로 채워지므로 회원 ID(맨 아래 h의 ?)가 마지막 값이다.
            jdbcTemplate.update("""
                            INSERT INTO course.planner_plan_logs (id, member_hash, parse_log_id, form, target_meters, candidate_count,
                                                                  reason, candidates, place_ms, route_ms, select_ms, created_at)
                            SELECT ?, h.hash,
                                   (SELECT p.id FROM course.planner_parse_logs p
                                    WHERE p.member_hash = h.hash AND p.created_at >= now() - interval '%s'
                                    ORDER BY p.created_at DESC LIMIT 1),
                                   ?::jsonb, ?, ?, ?, ?::jsonb, ?, ?, ?, now()
                            FROM (SELECT %s AS hash) h""".formatted(LINK_WINDOW, MEMBER_HASH),
                    UuidV7.create(), json.writeValueAsString(request.form()), request.targetMeters(),
                    result.candidates().size(), result.reason() == null ? null : result.reason().name(),
                    json.writeValueAsString(result.candidates()), placeMs, routeMs, selectMs, memberId);
        } catch (RuntimeException e) {
            log.warn("코스 자동 생성 찾기 로그를 남기지 못했다: {}", e.getClass().getSimpleName());
        }
    }
}
