package com.wadadak.course.internal.registration;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.event.course.CourseCreatedEvent;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.modulith.test.AssertablePublishedEvents;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.convention.TestBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import tools.jackson.databind.json.JsonMapper;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RegistrationControllerTest {

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    /** 2026-10-01 10:00 Asia/Seoul. 만료는 10/30 23:59:59 Asia/Seoul */
    @TestBean
    Clock clock;

    static Clock clock() {
        return Clock.fixed(Instant.parse("2026-10-01T01:00:00Z"), ZoneId.of("Asia/Seoul"));
    }

    @Test
    void registersCustomCourse(AssertablePublishedEvents events) throws Exception {
        UUID memberId = UUID.randomUUID();

        MvcTestResult result = register(memberId, UUID.randomUUID(), body("종로 북쪽 코스", northLine(126.9700)));

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.name").isEqualTo("종로 북쪽 코스");
        assertThat(result).bodyJson().extractingPath("$.data.startPoint.lat").isEqualTo(37.5700);
        assertThat(result).bodyJson().extractingPath("$.data.expiresAt").isEqualTo("2026-10-30T14:59:59Z");
        UUID courseId = UUID.fromString(jsonMapper.readTree(result.getResponse().getContentAsString()).get("data").get("courseId").asString());

        assertThat(jdbcTemplate.queryForMap("SELECT course_type, status, sido_code, creator_id FROM course.courses WHERE id = ?", courseId))
                .containsEntry("course_type", "CUSTOM")
                .containsEntry("status", "ACTIVE")
                .containsEntry("sido_code", "1100000000")
                .containsEntry("creator_id", memberId);
        assertThat(registeredCount(memberId)).isEqualTo(1);
        assertThat(events).contains(CourseCreatedEvent.class)
                .matching(e -> e.courseId().equals(courseId) && e.creatorId().equals(memberId) && e.sourceRunRecordId() == null);
    }

    @Test
    void sameIdempotencyKeyReturnsFirstResult() throws Exception {
        UUID memberId = UUID.randomUUID();
        UUID key = UUID.randomUUID();

        String first = register(memberId, key, body("멱등 확인 코스", northLine(126.9800))).getResponse().getContentAsString();
        // 같은 키면 내용이 달라도 처음 결과
        MvcTestResult again = register(memberId, key, body("다른 이름 코스", northLine(126.9900)));

        assertThat(again).hasStatusOk();
        assertThat(again.getResponse().getContentAsString()).isEqualTo(first);
        assertThat(registeredCount(memberId)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM course.courses WHERE creator_id = ?", Integer.class, memberId))
                .isEqualTo(1);
    }

    @Test
    void secondCustomCourseOnSameDayExceedsLimit() {
        UUID memberId = UUID.randomUUID();
        assertThat(register(memberId, UUID.randomUUID(), body("하루 첫 코스", northLine(127.0000)))).hasStatusOk();

        assertError(register(memberId, UUID.randomUUID(), body("하루 두번째 코스", northLine(127.0100))),
                HttpStatus.TOO_MANY_REQUESTS, "COURSE-008");
    }

    @Test
    void failedRegistrationDoesNotConsumeLimit() {
        UUID memberId = UUID.randomUUID();
        assertThat(register(UUID.randomUUID(), UUID.randomUUID(), body("선점된 이름 코스", northLine(127.0200)))).hasStatusOk();

        assertError(register(memberId, UUID.randomUUID(), body("선점된이름코스", northLine(127.0300))),
                HttpStatus.CONFLICT, "COURSE-006");
        assertThat(registeredCount(memberId)).isZero();
        assertThat(register(memberId, UUID.randomUUID(), body("실패 뒤 첫 코스", northLine(127.0300)))).hasStatusOk();
    }

    @Test
    void rejectsCourseOverlappingExistingOne() {
        assertThat(register(UUID.randomUUID(), UUID.randomUUID(), body("원래 있던 코스", northLine(127.0400)))).hasStatusOk();

        // 같은 길(10m 옆) → 거의 100% 겹침
        assertError(register(UUID.randomUUID(), UUID.randomUUID(), body("따라 만든 코스", northLine(127.04011))),
                HttpStatus.CONFLICT, "COURSE-007");
        // 50m 옆 평행한 길 → 겹치지 않음
        assertThat(register(UUID.randomUUID(), UUID.randomUUID(), body("옆길 코스", northLine(127.04057)))).hasStatusOk();
    }

    @Test
    void outAndBackOnExistingCourseIsFullOverlap() {
        assertThat(register(UUID.randomUUID(), UUID.randomUUID(), body("편도 원래 코스", northLine(127.0450)))).hasStatusOk();

        // 기존 편도 길을 그대로 왕복: 새 코스 전 구간이 기존 길 위라 100%
        assertError(register(UUID.randomUUID(), UUID.randomUUID(), body("왕복 코스", """
                        [{"lat": 37.5700, "lng": 127.0450}, {"lat": 37.5810, "lng": 127.0450}, {"lat": 37.5700, "lng": 127.0450}]""")),
                HttpStatus.CONFLICT, "COURSE-007");
    }

    @Test
    void halfOverlapIsAllowed() {
        assertThat(register(UUID.randomUUID(), UUID.randomUUID(), body("반 겹침 원래 코스", northLine(127.0480)))).hasStatusOk();

        // 앞 절반만 같은 길, 뒤는 동쪽으로 꺾음 → 85% 미만
        assertThat(register(UUID.randomUUID(), UUID.randomUUID(), body("반 겹침 새 코스", """
                [{"lat": 37.5700, "lng": 127.0480}, {"lat": 37.5755, "lng": 127.0480}, {"lat": 37.5755, "lng": 127.0560}]"""))).hasStatusOk();
    }

    @Test
    void rejectsStartAtSea() {
        assertError(register(UUID.randomUUID(), UUID.randomUUID(), body("바다 코스", """
                        [{"lat": 36.0000, "lng": 125.0000}, {"lat": 36.0110, "lng": 125.0000}]""")),
                HttpStatus.BAD_REQUEST, "COURSE-009");
    }

    @Test
    void requiresIdempotencyKey() {
        assertThat(mvc.post().uri("/api/v1/courses").with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString())))
                .contentType(MediaType.APPLICATION_JSON).content(body("키 없는 코스", northLine(127.0500))))
                .hasStatus(HttpStatus.BAD_REQUEST);
    }

    /** 서울 도심 위도 37.570에서 북쪽으로 약 1.2km */
    private static String northLine(double lng) {
        return """
                [{"lat": 37.5700, "lng": %s}, {"lat": 37.5810, "lng": %s}]""".formatted(lng, lng);
    }

    private static String body(String name, String anchorPoints) {
        return """
                {"anchorPoints": %s, "name": "%s", "difficulty": "EASY", "tags": ["FLAT", "RIVERSIDE"]}"""
                .formatted(anchorPoints, name);
    }

    private MvcTestResult register(UUID memberId, UUID key, String body) {
        return mvc.post().uri("/api/v1/courses").with(jwt().jwt(j -> j.subject(memberId.toString())))
                .header("Idempotency-Key", key.toString())
                .contentType(MediaType.APPLICATION_JSON).content(body).exchange();
    }

    private Integer registeredCount(UUID memberId) {
        return jdbcTemplate.query("SELECT registered_count FROM course.daily_registration_counts WHERE member_id = ?",
                (rs, rowNum) -> rs.getInt(1), memberId).stream().findFirst().orElse(0);
    }

    private static void assertError(MvcTestResult result, HttpStatus status, String code) {
        assertThat(result).hasStatus(status).bodyJson().extractingPath("$.code").isEqualTo(code);
    }
}
