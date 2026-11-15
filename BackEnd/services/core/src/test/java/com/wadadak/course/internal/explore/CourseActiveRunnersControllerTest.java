package com.wadadak.course.internal.explore;

import com.wadadak.TestcontainersConfiguration;
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

import java.sql.Timestamp;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 홈 현재 러너 1분 갱신(공통 7 · HCR-05). 지도 · 목록 · 상세 테스트와 겹치지 않게 위도 33.90에 코스를 둔다. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseActiveRunnersControllerTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    private static final Instant NOW = Instant.parse("2026-10-01T00:00:00Z");

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    @Test
    void returnsTheRunnersOfActiveCoursesOnly() throws Exception {
        UUID running = insert(33.901);
        UUID nobody = insert(33.902);
        UUID hidden = insert(33.903);
        runners(running, 3);
        runners(hidden, 2);
        jdbcTemplate.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'EXPIRED', hidden_at = now() WHERE id = ?",
                hidden);
        UUID unknown = UUID.randomUUID();

        MvcTestResult result = find("courseIds=%s&courseIds=%s&courseIds=%s&courseIds=%s&courseIds=%s"
                .formatted(running, nobody, hidden, unknown, running));

        assertThat(result).hasStatusOk();
        // 받은 적이 없으면 0, 비공개 · 없는 코스는 빠진다. 같은 ID는 한 번
        assertThat(runnersById(data(result))).containsExactlyInAnyOrderEntriesOf(Map.of(running, 3, nobody, 0));
    }

    @Test
    void rejectsBadRequests() {
        assertBadRequest(find(""));
        assertBadRequest(find("courseIds=not-a-uuid"));
        String tooMany = IntStream.rangeClosed(0, CourseMapRepository.MAX_RUNNER_COURSES)
                .mapToObj(i -> "courseIds=" + UUID.randomUUID())
                .collect(Collectors.joining("&"));
        assertBadRequest(find(tooMany));
        String atMost = IntStream.range(0, CourseMapRepository.MAX_RUNNER_COURSES)
                .mapToObj(i -> "courseIds=" + UUID.randomUUID())
                .collect(Collectors.joining("&"));
        assertThat(find(atMost)).hasStatusOk();
    }

    @Test
    void needsLogin() {
        assertThat(mvc.get().uri("/api/v1/courses/active-runners?courseIds=" + UUID.randomUUID()).exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private MvcTestResult find(String query) {
        return mvc.get().uri("/api/v1/courses/active-runners?" + query).with(jwt()).exchange();
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private static Map<UUID, Integer> runnersById(JsonNode data) {
        Map<UUID, Integer> runners = new LinkedHashMap<>();
        data.forEach(course -> runners.put(UUID.fromString(course.get("courseId").asString()), course.get("activeRunners").asInt()));
        return runners;
    }

    private static void assertBadRequest(MvcTestResult result) {
        assertThat(result).hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    /** 현재 러너 수 복사본을 바로 넣는다 */
    private void runners(UUID course, int count) {
        jdbcTemplate.update("INSERT INTO course.course_active_runners (course_id, active_count, source_version, created_at, "
                + "updated_at) VALUES (?, ?, 1, now(), now())", course, count);
    }

    /** 출발점에서 북쪽으로 약 1.1km 가는 공개 코스를 바로 넣는다. */
    private UUID insert(double lat) {
        double lng = 126.301;
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    expires_at, version, created_at, updated_at)
                        VALUES (?, ?, 'CUSTOM', ?, ?, 'EASY', '{}'::varchar[], ST_GeomFromText(?, 4326), 1000, ST_GeogFromText(?),
                                '5011010100', '5011000000', '5000000000', 'ACTIVE', ?, 0, ?, ?)""",
                id, UUID.randomUUID(), "러너 코스 " + id, "러너코스" + id,
                "LINESTRING(%s %s, %s %s)".formatted(lng, lat, lng, lat + 0.01),
                "SRID=4326;POINT(%s %s)".formatted(lng, lat),
                Timestamp.from(NOW.plusSeconds(30 * 24 * 3600)), Timestamp.from(NOW), Timestamp.from(NOW));
        return id;
    }
}
