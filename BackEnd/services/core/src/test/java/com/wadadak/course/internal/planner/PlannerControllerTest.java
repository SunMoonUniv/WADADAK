package com.wadadak.course.internal.planner;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 스텁({@code app.stub.course-planner=true})으로 B3 자동 생성 API의 요청 검증과 응답 모양을 확인한다. 스텁 값은 {@link PlannerStub}. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
@TestPropertySource(properties = "app.stub.course-planner=true")
class PlannerControllerTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    MockMvcTester mvc;

    private static final String SUNMOON = "{\"lat\": 36.7983, \"lng\": 127.0746}";

    // --- parse

    @Test
    void parseFillsForm() {
        MvcTestResult result = parse("선문대에서 큰길 피해서 5km 한 바퀴");

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.start.kind").isEqualTo("PLACE");
        assertThat(result).bodyJson().extractingPath("$.data.start.query").isEqualTo("선문대");
        assertThat(result).bodyJson().extractingPath("$.data.shape").isEqualTo("LOOP");
        assertThat(result).bodyJson().extractingPath("$.data.distanceM").isEqualTo(5000);
        assertThat(result).bodyJson().extractingPath("$.data.prefer").asArray().containsExactly("AVOID_ARTERIAL");
        assertThat(result).bodyJson().extractingPath("$.data.message").isNull();
    }

    @Test
    void parseLeavesUnreadDistanceEmpty() {
        assertThat(parse("선문대에서 초보자가 뛸 만한 코스")).bodyJson().extractingPath("$.data.distanceM").isNull();
    }

    @Test
    void parseAnswersOffTopicWithMessageOnly() {
        MvcTestResult result = parse("주식 추천해 줘");

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.message").isNotNull();
        assertThat(result).bodyJson().extractingPath("$.data.start").isNull();
    }

    @Test
    void parseLimit() {
        assertError(parse("한도"), HttpStatus.TOO_MANY_REQUESTS, "COURSE-013");
    }

    @Test
    void parseRejectsBlankAndTooLong() {
        assertError(parse(" "), HttpStatus.BAD_REQUEST, "COMMON-001");
        assertError(parse("가".repeat(201)), HttpStatus.BAD_REQUEST, "COMMON-001");
    }

    // --- plans

    @Test
    void planReturnsThreeCandidates() {
        MvcTestResult result = plan(form("""
                "start": {"kind": "PLACE", "query": "선문대"}, "shape": "LOOP", "distanceM": 5000, "prefer": ["AVOID_ARTERIAL", "PARK"]"""));

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.reason").isNull();
        assertThat(result).bodyJson().extractingPath("$.data.startName").isEqualTo("선문대");
        assertThat(result).bodyJson().extractingPath("$.data.candidates.length()").isEqualTo(3);
        assertThat(result).bodyJson().extractingPath("$.data.candidates[0].distanceMeters").asNumber()
                .satisfies(d -> assertThat(d.intValue()).isBetween(4750, 5250));
        assertThat(result).bodyJson().extractingPath("$.data.candidates[0].anchorPoints.length()").asNumber()
                .satisfies(n -> assertThat(n.intValue()).isBetween(2, 500));
        assertThat(result).bodyJson().extractingPath("$.data.candidates[0].toiletCount").isEqualTo(1);
        assertThat(result).bodyJson().extractingPath("$.data.candidates[0].ascentMeters").isEqualTo(109);
        // 공원은 아직 반영하지 않고, 큰길 피하기는 반영한다
        assertThat(result).bodyJson().extractingPath("$.data.notApplied").asArray().containsExactly("PARK");
    }

    @Test
    void planFromCurrentLocationHasNoStartName() {
        MvcTestResult result = plan(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"OUT_AND_BACK\", \"durationMin\": 30"));

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.startName").isNull();
    }

    @Test
    void planReasons() {
        assertReason(form("\"start\": {\"kind\": \"PLACE\", \"query\": \"없는 장소\"}, \"shape\": \"LOOP\", \"distanceM\": 5000"),
                "PLACE_NOT_FOUND");
        assertReason(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"VIA\", \"viaQuery\": \"한강\", \"distanceM\": 5000"),
                "PLACE_TOO_FAR");
        assertReason(form("\"start\": {\"kind\": \"PLACE\", \"query\": \"섬\"}, \"shape\": \"LOOP\", \"distanceM\": 5000"),
                "NO_CANDIDATES");
        assertReason(form("\"start\": {\"kind\": \"PLACE\", \"query\": \"중복\"}, \"shape\": \"LOOP\", \"distanceM\": 5000"),
                "SIMILAR_EXISTS");
    }

    @Test
    void planLimit() {
        assertError(plan(form("\"start\": {\"kind\": \"PLACE\", \"query\": \"한도\"}, \"shape\": \"LOOP\", \"distanceM\": 5000")),
                HttpStatus.TOO_MANY_REQUESTS, "COURSE-012");
    }

    @Test
    void planRejectsInconsistentForm() {
        // 장소 출발인데 이름 없음
        assertInvalid(form("\"start\": {\"kind\": \"PLACE\"}, \"shape\": \"LOOP\", \"distanceM\": 5000"));
        // 편도인데 도착지 없음, 경유인데 경유지 없음
        assertInvalid(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"POINT_TO_POINT\""));
        assertInvalid(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"VIA\", \"viaQuery\": \" \""));
        // 한 바퀴인데 거리 · 시간 없음
        assertInvalid(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"LOOP\""));
        // 모양 없음
        assertInvalid(form("\"start\": {\"kind\": \"CURRENT\"}, \"distanceM\": 5000"));
    }

    @Test
    void planChecksTargetDistance() {
        // 한 바퀴는 22km까지, 왕복은 100km까지
        assertInvalid(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"LOOP\", \"distanceM\": 22001"));
        assertThat(plan(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"OUT_AND_BACK\", \"distanceM\": 22001"))).hasStatusOk();
        // 시간은 기본 페이스 390초/km로 환산한다: 150분 ≈ 23.1km(한 바퀴 초과), 5분 ≈ 0.77km(1km 미만)
        assertInvalid(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"LOOP\", \"durationMin\": 150"));
        assertInvalid(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"LOOP\", \"durationMin\": 5"));
        // 페이스 300초/km면 5분 = 1km
        assertThat(plan("{\"form\": {\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"LOOP\", \"durationMin\": 5}, "
                + "\"currentLocation\": " + SUNMOON + ", \"paceSecPerKm\": 300}")).hasStatusOk();
        // 칸 범위
        assertInvalid(form("\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"OUT_AND_BACK\", \"distanceM\": 999"));
        assertInvalid("{\"form\": {\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"LOOP\", \"distanceM\": 5000}, "
                + "\"currentLocation\": " + SUNMOON + ", \"paceSecPerKm\": 179}");
    }

    @Test
    void planRequiresCurrentLocation() {
        assertInvalid("{\"form\": {\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"LOOP\", \"distanceM\": 5000}}");
        assertInvalid("{\"form\": {\"start\": {\"kind\": \"CURRENT\"}, \"shape\": \"LOOP\", \"distanceM\": 5000}, "
                + "\"currentLocation\": {\"lat\": 127.0746, \"lng\": 36.7983}}");
    }

    // --- quota

    @Test
    void quota() {
        MvcTestResult result = mvc.get().uri("/api/v1/courses/plans/quota").with(member()).exchange();

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.limit").isEqualTo(20);
        assertThat(result).bodyJson().extractingPath("$.data.remaining").isEqualTo(19);
    }

    @Test
    void requiresLogin() {
        assertThat(mvc.get().uri("/api/v1/courses/plans/quota")).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private static RequestPostProcessor member() {
        return jwt().jwt(j -> j.subject(UUID.randomUUID().toString()));
    }

    private static String form(String fields) {
        return "{\"form\": {" + fields + "}, \"currentLocation\": " + SUNMOON + "}";
    }

    private MvcTestResult parse(String text) {
        return mvc.post().uri("/api/v1/courses/plans/parse").with(member())
                .contentType(MediaType.APPLICATION_JSON).content("{\"text\": \"" + text + "\"}").exchange();
    }

    private MvcTestResult plan(String body) {
        return mvc.post().uri("/api/v1/courses/plans").with(member())
                .contentType(MediaType.APPLICATION_JSON).content(body).exchange();
    }

    private void assertReason(String body, String reason) {
        MvcTestResult result = plan(body);
        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.reason").isEqualTo(reason);
        assertThat(result).bodyJson().extractingPath("$.data.message").isNotNull();
        assertThat(result).bodyJson().extractingPath("$.data.candidates.length()").isEqualTo(0);
    }

    private void assertInvalid(String body) {
        assertError(plan(body), HttpStatus.BAD_REQUEST, "COMMON-001");
    }

    private static void assertError(MvcTestResult result, HttpStatus status, String code) {
        assertThat(result).hasStatus(status).bodyJson().extractingPath("$.code").isEqualTo(code);
    }
}
