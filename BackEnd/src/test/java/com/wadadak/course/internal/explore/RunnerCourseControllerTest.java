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

import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 다른 러너가 등록한 코스(I3). 보는 사람은 그 러너가 아닌 다른 회원이다. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RunnerCourseControllerTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void listsRunnersPublicCoursesLatestFirst() {
        UUID runner = UUID.randomUUID();
        UUID older = course(runner, "ACTIVE", "2026-10-10T09:00:00Z");
        UUID latest = course(runner, "ACTIVE", "2026-10-29T09:00:00Z");
        course(runner, "HIDDEN", "2026-10-30T09:00:00Z");
        course(runner, "DELETED", "2026-10-30T10:00:00Z");
        course(UUID.randomUUID(), "ACTIVE", "2026-10-30T11:00:00Z");
        stats(latest, 61, 13, 3);

        MvcTestResult result = get("/api/v1/courses/members/" + runner);

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.content[*].courseId").asArray()
                .containsExactly(latest.toString(), older.toString());
        assertThat(result).bodyJson().extractingPath("$.data.content[0].name").isEqualTo("러너 코스 " + latest);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].distanceMeters").isEqualTo(1112);
        // 13 ÷ 3 = 4.33
        assertThat(result).bodyJson().extractingPath("$.data.content[0].averageRating").isEqualTo(4.3);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].completionCount").isEqualTo(61);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].route").asArray().hasSize(2);
        // 리뷰 · 완주가 없는 코스
        assertThat(result).bodyJson().extractingPath("$.data.content[1].averageRating").isNull();
        assertThat(result).bodyJson().extractingPath("$.data.content[1].completionCount").isEqualTo(0);
        assertThat(result).bodyJson().extractingPath("$.data.nextCursor").isNull();
    }

    @Test
    void pagesWithCursor() {
        UUID runner = UUID.randomUUID();
        UUID first = course(runner, "ACTIVE", "2026-10-29T09:00:00Z");
        UUID second = course(runner, "ACTIVE", "2026-10-28T09:00:00Z");
        UUID third = course(runner, "ACTIVE", "2026-10-27T09:00:00Z");

        MvcTestResult page1 = get("/api/v1/courses/members/" + runner + "?size=2");
        MvcTestResult page2 = get("/api/v1/courses/members/" + runner + "?size=2&cursor=2");

        assertThat(page1).bodyJson().extractingPath("$.data.content[*].courseId").asArray()
                .containsExactly(first.toString(), second.toString());
        assertThat(page1).bodyJson().extractingPath("$.data.nextCursor").isEqualTo("2");
        assertThat(page2).bodyJson().extractingPath("$.data.content[*].courseId").asArray().containsExactly(third.toString());
        assertThat(page2).bodyJson().extractingPath("$.data.nextCursor").isNull();
        assertThat(get("/api/v1/courses/members/" + UUID.randomUUID())).as("없는 회원")
                .bodyJson().extractingPath("$.data.content").asArray().isEmpty();
    }

    @Test
    void summaryCountsOnlyPublicCourses() {
        UUID runner = UUID.randomUUID();
        course(runner, "ACTIVE", "2026-10-29T09:00:00Z");
        course(runner, "ACTIVE", "2026-10-28T09:00:00Z");
        course(runner, "HIDDEN", "2026-10-27T09:00:00Z");
        course(runner, "DELETED", "2026-10-26T09:00:00Z");
        course(UUID.randomUUID(), "ACTIVE", "2026-10-25T09:00:00Z");

        assertThat(get("/api/v1/courses/members/" + runner + "/summary")).hasStatusOk()
                .bodyJson().extractingPath("$.data.courseCount").isEqualTo(2);
        assertThat(get("/api/v1/courses/members/" + UUID.randomUUID() + "/summary")).as("없는 회원")
                .bodyJson().extractingPath("$.data.courseCount").isEqualTo(0);
        assertThat(get("/api/v1/courses/members/abc/summary")).hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    private MvcTestResult get(String uri) {
        return mvc.get().uri(uri).with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString()))).exchange();
    }

    /** 비공개 · 삭제된 코스는 등록자가 지웠다 */
    private UUID course(UUID creatorId, String status, String createdAt) {
        UUID id = UUID.randomUUID();
        boolean active = status.equals("ACTIVE");
        Timestamp created = Timestamp.from(Instant.parse(createdAt));
        jdbc.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    status_reason, hidden_at, expires_at, version, created_at, updated_at)
                        VALUES (?, ?, 'CUSTOM', ?, ?, 'EASY', '{FLAT}'::varchar[],
                                ST_GeomFromText('LINESTRING(127.30 37.30, 127.30 37.31)', 4326), 1112,
                                ST_GeogFromText('SRID=4326;POINT(127.30 37.30)'), '1171010100', '1171000000', '1100000000',
                                ?, ?, ?, now() + interval '30 days', 0, ?, ?)""",
                id, creatorId, "러너 코스 " + id, "러너코스" + id, status, active ? null : "USER_DELETED",
                active ? null : created, created, created);
        return id;
    }

    private void stats(UUID courseId, int completions, int ratingSum, int reviews) {
        jdbc.update("""
                        INSERT INTO course.course_stats (course_id, completion_count, rating_sum, review_count, created_at, updated_at)
                        VALUES (?, ?, ?, ?, now(), now())""", courseId, completions, ratingSum, reviews);
    }
}
