package com.wadadak.course.internal.planner;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.JevClient.Answer;
import com.wadadak.course.internal.planner.JevClient.JevAnswers;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.Start;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import com.wadadak.course.internal.planner.PlanResult.PlanCandidate;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;
import java.util.EnumSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;

/**
 * 운영자 코스 생성 로그 API. 로그는 {@link PlannerLogRepository}로 넣는다(실제 저장 길과 같다).
 * 다른 테스트가 넣은 로그도 같은 DB에 있어서, 목록은 이 테스트가 넣은 문장만 골라 보고 숫자 카드는 늘어난 만큼만 본다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class AdminPlannerLogControllerTest {

    private static final GeoPoint HERE = new GeoPoint(36.7983, 127.0746);

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JsonMapper jsonMapper;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    PlannerLogRepository logs;

    @Test
    void onlyAdminAccountCanCall() {
        assertThat(mvc.get().uri("/api/v1/admin/planner-logs").exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(mvc.get().uri("/api/v1/admin/planner-logs/export").exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(admin("/api/v1/admin/planner-logs")).hasStatusOk();
    }

    @Test
    void listShowsLastPlanAndWhetherFormWasEdited() throws Exception {
        String edited = unique("5km 한 바퀴");
        String kept = unique("평지 밝은 길 4km");
        String parsedOnly = unique("오늘 점심 뭐 먹지");
        // 거리를 고쳐 보냈다
        UUID a = UUID.randomUUID();
        logs.saveParse(a, edited, jev(), loop(5_000, EnumSet.noneOf(Pref.class)), 300);
        logs.savePlan(a, request(loop(6_000, EnumSet.noneOf(Pref.class))), found(), 10, 3_000L, 50L);
        // 원하는 길 순서만 다르면 고친 것이 아니다
        UUID b = UUID.randomUUID();
        logs.saveParse(b, kept, null, loop(4_000, EnumSet.of(Pref.FLAT, Pref.LIT)), 20);
        logs.savePlan(b, request(loop(4_000, new LinkedHashSet<>(List.of(Pref.LIT, Pref.FLAT)))),
                PlanResult.noCandidates(true, null), 10, 1_000L, 5L);
        // 채우기만 했다
        logs.saveParse(UUID.randomUUID(), parsedOnly, jev(), PlanForm.offTopic(), 200);

        JsonNode all = data(admin("/api/v1/admin/planner-logs?days=1&size=100")).get("content");
        JsonNode editedRow = find(all, edited);
        assertThat(editedRow.get("jevUsed").asBoolean()).isTrue();
        assertThat(editedRow.get("user").asString()).hasSize(8);
        assertThat(editedRow.get("form").get("distanceM").asInt()).isEqualTo(5_000);
        assertThat(editedRow.get("plan").get("edited").asBoolean()).isTrue();
        assertThat(editedRow.get("plan").get("candidateCount").asInt()).isOne();
        assertThat(editedRow.get("plan").get("totalMs").asLong()).isEqualTo(3_060);
        assertThat(find(all, kept).get("plan").get("edited").asBoolean()).isFalse();
        assertThat(find(all, kept).get("plan").get("reason").asString()).isEqualTo("NO_CANDIDATES");
        assertThat(find(all, parsedOnly).get("plan").isNull()).isTrue();

        JsonNode found = data(admin("/api/v1/admin/planner-logs?result=FOUND&size=100")).get("content");
        assertThat(find(found, edited)).isNotNull();
        assertThat(find(found, kept)).isNull();
        JsonNode notPlanned = data(admin("/api/v1/admin/planner-logs?result=NOT_PLANNED&size=100")).get("content");
        assertThat(find(notPlanned, parsedOnly)).isNotNull();
        assertThat(find(notPlanned, edited)).isNull();
        JsonNode rulesOnly = data(admin("/api/v1/admin/planner-logs?jev=false&size=100")).get("content");
        assertThat(find(rulesOnly, kept)).isNotNull();
        assertThat(find(rulesOnly, edited)).isNull();
    }

    @Test
    void detailShowsJevAnswersAndEveryPlan() throws Exception {
        String sentence = unique("선문대에서 5km");
        UUID member = UUID.randomUUID();
        logs.saveParse(member, sentence, jev(), loop(5_000, EnumSet.noneOf(Pref.class)), 300);
        logs.savePlan(member, request(loop(5_000, EnumSet.noneOf(Pref.class))), found(), 10, 3_000L, 50L);
        logs.savePlan(member, request(loop(7_000, EnumSet.noneOf(Pref.class))), found(), 10, 2_000L, 40L);
        UUID id = jdbcTemplate.queryForObject("SELECT id FROM course.planner_parse_logs WHERE sentence = ?", UUID.class, sentence);

        JsonNode detail = data(admin("/api/v1/admin/planner-logs/" + id));

        assertThat(detail.get("sentence").asString()).isEqualTo(sentence);
        assertThat(detail.get("jevAnswers").get("answers").get("shape").get("choice").asString()).isEqualTo("loop");
        assertThat(detail.get("plans")).hasSize(2);
        assertThat(detail.get("plans").get(0).get("edited").asBoolean()).isFalse();
        assertThat(detail.get("plans").get(1).get("edited").asBoolean()).isTrue();
        // 상세는 경로 점까지 준다
        assertThat(detail.get("plans").get(0).get("candidates").get(0).get("anchorPoints")).hasSize(2);
        assertThat(admin("/api/v1/admin/planner-logs/" + UUID.randomUUID())).hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-004");
    }

    @Test
    void statsCountAndRates() throws Exception {
        JsonNode before = data(admin("/api/v1/admin/planner-logs/stats?days=1"));
        UUID member = UUID.randomUUID();
        logs.saveParse(member, unique("3km 한 바퀴"), jev(), loop(3_000, EnumSet.noneOf(Pref.class)), 300);
        logs.savePlan(member, request(loop(3_000, EnumSet.noneOf(Pref.class))), found(), 10, 3_000L, 50L);

        JsonNode after = data(admin("/api/v1/admin/planner-logs/stats?days=1"));

        assertThat(after.get("parses").asLong() - before.get("parses").asLong()).isOne();
        assertThat(after.get("plans").asLong() - before.get("plans").asLong()).isOne();
        assertThat(after.get("jevRate").asDouble()).isBetween(0.0, 1.0);
        assertThat(after.get("editedRate").asDouble()).isBetween(0.0, 1.0);
        assertThat(after.get("planMs").asDouble()).isPositive();
    }

    @Test
    void csvJoinsParseAndPlanWithoutRoutePoints() throws Exception {
        String sentence = unique("한강, \"평지\" 5km");
        UUID member = UUID.randomUUID();
        logs.saveParse(member, sentence, null, loop(5_000, EnumSet.noneOf(Pref.class)), 300);
        logs.savePlan(member, request(loop(6_000, EnumSet.noneOf(Pref.class))), found(), 10, 3_000L, 50L);
        // 문장 없이 직접 조건으로 찾은 요청도 들어간다
        logs.savePlan(UUID.randomUUID(), request(loop(8_123, EnumSet.noneOf(Pref.class))), found(), 10, 3_000L, 50L);

        MvcTestResult result = admin("/api/v1/admin/planner-logs/export?days=1");

        assertThat(result).hasStatusOk();
        assertThat(result.getResponse().getHeader("Content-Disposition")).startsWith("attachment").contains("planner-logs-");
        String csv = new String(result.getResponse().getContentAsByteArray(), StandardCharsets.UTF_8);
        assertThat(csv).startsWith("﻿parse_id,parsed_at,member_hash,sentence,");
        String line = csv.lines().filter(l -> l.contains(sentence.replace("\"", "\"\""))).findFirst().orElseThrow();
        // 쉼표 · 따옴표가 든 문장은 따옴표로 감싸고, 고쳐 보냈으니 edited는 true
        assertThat(line).contains("\"" + sentence.replace("\"", "\"\"") + "\"").contains(",true,6000,1,");
        assertThat(csv).contains("8123").doesNotContain("anchorPoints");
    }

    private MvcTestResult admin(String uri) {
        return mvc.get().uri(uri).with(httpBasic("test-admin", "test-admin-password")).exchange();
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    /** 목록에서 이 문장 줄. 없으면 {@code null} */
    private static JsonNode find(JsonNode rows, String sentence) {
        return rows.valueStream().filter(r -> r.get("sentence").asString().equals(sentence)).findFirst().orElse(null);
    }

    /** 같은 DB를 쓰는 다른 테스트와 겹치지 않는 문장 */
    private static String unique(String sentence) {
        return sentence + " #" + UUID.randomUUID().toString().substring(0, 8);
    }

    private static PlanForm loop(int meters, Set<Pref> prefer) {
        return new PlanForm(new Start(StartKind.CURRENT, null), Shape.LOOP, null, null, meters, null, prefer, null);
    }

    private static PlanRequest request(PlanForm form) {
        return new PlanRequest(form, HERE, null);
    }

    private static PlanResult found() {
        return PlanResult.found(List.of(new PlanCandidate(List.of(HERE, HERE), 5_100, 0, 0.1, 3, 0, null, null, null, null)),
                null, Set.of());
    }

    private static JevAnswers jev() {
        return new JevAnswers(Map.of("shape", new Answer(null, "loop", Map.of("loop", 0.93)), "on_topic", new Answer(0.98, null, null)));
    }
}
