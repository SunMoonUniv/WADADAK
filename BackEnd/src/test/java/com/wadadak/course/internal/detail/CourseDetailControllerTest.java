package com.wadadak.course.internal.detail;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
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
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseDetailControllerTest {

    private static final Instant EXPIRES_AT = Instant.parse("2026-11-13T14:59:59Z");

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    // course만 띄워서 member 모듈이 없다. 등록자 닉네임을 붙이려고 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Test
    void returnsTheCourseWithItsCreator() throws Exception {
        UUID creator = UUID.randomUUID();
        UUID course = insert(creator, "ACTIVE");
        given(memberApi.getProfiles(Set.of(creator))).willReturn(List.of(new MemberProfile(creator, "러닝왕김", null, false)));

        JsonNode detail = data(detail(course));

        assertThat(detail.get("courseId").asString()).isEqualTo(course.toString());
        assertThat(detail.get("name").asString()).isEqualTo("상세 코스 " + course);
        assertThat(detail.get("courseType").asString()).isEqualTo("GPS");
        assertThat(detail.get("difficulty").asString()).isEqualTo("MEDIUM");
        // FIL-04 순서
        List<String> tags = new ArrayList<>();
        detail.get("tags").forEach(tag -> tags.add(tag.asString()));
        assertThat(tags).containsExactly("FLAT", "RIVERSIDE", "NIGHT_LIGHT");
        assertThat(detail.get("distanceMeters").asInt()).isEqualTo(5_200);
        // 첫 점이 출발점(코스 방향)
        JsonNode route = detail.get("route");
        assertThat(route).hasSize(3);
        assertThat(route.get(0).get("lat").asDouble()).isEqualTo(33.70);
        assertThat(route.get(0).get("lng").asDouble()).isEqualTo(126.30);
        assertThat(route.get(2).get("lat").asDouble()).isEqualTo(33.71);
        assertThat(route.get(2).get("lng").asDouble()).isEqualTo(126.31);
        // 경로 길이 약 1.6km라 1km 표지 하나. 등록 때와 같은 계산(B1-02)
        JsonNode markers = detail.get("distanceMarkers");
        assertThat(markers).hasSize(1);
        assertThat(markers.get(0).get("km").asInt()).isEqualTo(1);
        assertThat(markers.get(0).get("point").get("lat").asDouble()).isBetween(33.705, 33.71);
        assertThat(Instant.parse(detail.get("expiresAt").asString())).isEqualTo(EXPIRES_AT);
        assertThat(detail.get("creatorNickname").asString()).isEqualTo("러닝왕김");
    }

    @Test
    void showsAWithdrawnCreatorAsWithdrawn() throws Exception {
        UUID creator = UUID.randomUUID();
        UUID course = insert(creator, "ACTIVE");
        given(memberApi.getProfiles(Set.of(creator)))
                .willReturn(List.of(new MemberProfile(creator, MemberProfile.WITHDRAWN_NICKNAME, null, true)));

        assertThat(data(detail(course)).get("creatorNickname").asString()).isEqualTo("탈퇴한 사용자");
    }

    @Test
    void stillReturnsTheCourseWhenTheCreatorCannotBeRead() throws Exception {
        UUID course = insert(UUID.randomUUID(), "ACTIVE");
        given(memberApi.getProfiles(any())).willThrow(new IllegalStateException("member down"));

        JsonNode detail = data(detail(course));

        assertThat(detail.get("name").asString()).isEqualTo("상세 코스 " + course);
        assertThat(detail.get("creatorNickname").isNull()).isTrue();
    }

    /** 현재 러너 수(B1-01). 받은 적이 없으면 0명이다 */
    @Test
    void showsTheActiveRunners() throws Exception {
        UUID course = insert(UUID.randomUUID(), "ACTIVE");
        assertThat(data(detail(course)).get("activeRunners").asInt()).isZero();

        jdbcTemplate.update("INSERT INTO course.course_active_runners (course_id, active_count, source_version, created_at, "
                + "updated_at) VALUES (?, 3, 1, now(), now())", course);
        assertThat(data(detail(course)).get("activeRunners").asInt()).isEqualTo(3);
    }

    /** 열 때마다 조회 수가 늘고(누적 · 오늘 날짜), 완주가 있으면 평균 페이스를 준다(F11) */
    @Test
    void countsViewsAndShowsTheAveragePace() throws Exception {
        UUID course = insert(UUID.randomUUID(), "ACTIVE");

        assertThat(data(detail(course)).get("averagePaceSecondsPerKm").isNull()).as("완주가 없다").isTrue();
        assertThat(views(course)).isEqualTo(1);

        // 5.2km 코스를 52분 · 56분 20초에 완주 → 평균 54분 10초 ÷ 5.2km = 625초/km(10′25″)
        jdbcTemplate.update("UPDATE course.course_stats SET completion_count = 2, completion_seconds = ? WHERE course_id = ?",
                3_120 + 3_380, course);
        assertThat(data(detail(course)).get("averagePaceSecondsPerKm").asInt()).isEqualTo(625);
        assertThat(views(course)).isEqualTo(2);
        assertThat(jdbcTemplate.queryForObject(
                "SELECT view_count FROM course.course_daily_stats WHERE course_id = ? AND stat_date = ?", Integer.class,
                course, LocalDate.now(ZoneId.of("Asia/Seoul")))).isEqualTo(2);
    }

    @Test
    void doesNotCountViewsOfHiddenCourses() {
        UUID hidden = insert(UUID.randomUUID(), "HIDDEN");

        assertThat(detail(hidden)).hasStatus(HttpStatus.CONFLICT);
        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM course.course_stats WHERE course_id = ?", Long.class, hidden))
                .isZero();
    }

    @Test
    void blocksHiddenOrDeletedCoursesAndUnknownOnes() {
        UUID hidden = insert(UUID.randomUUID(), "HIDDEN");
        UUID deleted = insert(UUID.randomUUID(), "DELETED");

        for (UUID course : List.of(hidden, deleted)) {
            assertThat(detail(course)).hasStatus(HttpStatus.CONFLICT).bodyJson().extractingPath("$.code").isEqualTo("COURSE-002");
        }
        assertThat(detail(UUID.randomUUID())).hasStatus(HttpStatus.NOT_FOUND).bodyJson().extractingPath("$.code")
                .isEqualTo("COURSE-001");
        assertThat(mvc.get().uri("/api/v1/courses/not-a-course").with(jwt()).exchange()).hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    @Test
    void needsLogin() {
        UUID course = insert(UUID.randomUUID(), "ACTIVE");

        assertThat(mvc.get().uri("/api/v1/courses/" + course).exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private long views(UUID course) {
        return jdbcTemplate.queryForObject("SELECT view_count FROM course.course_stats WHERE course_id = ?", Long.class, course);
    }

    private MvcTestResult detail(UUID course) {
        return mvc.get().uri("/api/v1/courses/" + course).with(jwt()).exchange();
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    /** 출발 → 북쪽 → 북동쪽으로 가는 GPS 코스를 바로 넣는다. 거리 값은 확인용이라 실제 경로 길이와 다르다. */
    private UUID insert(UUID creator, String status) {
        UUID id = UUID.randomUUID();
        boolean active = status.equals("ACTIVE");
        jdbcTemplate.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    status_reason, hidden_at, expires_at, version, created_at, updated_at)
                        VALUES (?, ?, 'GPS', ?, ?, 'MEDIUM', '{NIGHT_LIGHT,FLAT,RIVERSIDE}'::varchar[],
                                ST_GeomFromText('LINESTRING(126.30 33.70, 126.30 33.705, 126.31 33.71)', 4326), 5200,
                                ST_GeogFromText('SRID=4326;POINT(126.30 33.70)'), '5011010100', '5011000000', '5000000000',
                                ?, ?, ?, ?, 0, now(), now())""",
                id, creator, "상세 코스 " + id, "상세코스" + id, status, active ? null : "EXPIRED",
                active ? null : Timestamp.from(Instant.now()), Timestamp.from(EXPIRES_AT));
        return id;
    }
}
