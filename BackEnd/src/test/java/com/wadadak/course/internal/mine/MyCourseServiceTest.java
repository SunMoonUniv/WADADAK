package com.wadadak.course.internal.mine;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.config.TimeConfig;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.convention.TestBean;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 실제 구현({@code app.stub.course-mine: false})의 G4 목록 · 합계. 지금은 2026-10-30(금) 12:00 Asia/Seoul로 고정한다.
 * 스텁 응답은 {@link MyCourseControllerTest}.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class MyCourseServiceTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbc;

    @TestBean
    Clock clock;

    static Clock clock() {
        return Clock.fixed(Instant.parse("2026-10-30T03:00:00Z"), TimeConfig.SEOUL);
    }

    @Test
    void listsMyCoursesExpiringSoonFirstThenLatest() {
        UUID me = UUID.randomUUID();
        UUID dMinus1 = course(me, "ACTIVE", "2026-10-31T23:59:59", "2026-10-02T09:00:00");
        UUID dMinus7 = course(me, "ACTIVE", "2026-11-06T23:59:59", "2026-10-20T09:00:00");
        UUID dMinus8 = course(me, "ACTIVE", "2026-11-07T23:59:59", "2026-10-25T09:00:00");
        UUID deleting = course(me, "HIDDEN", "2026-11-20T23:59:59", "2026-10-28T09:00:00");
        UUID older = course(me, "ACTIVE", "2026-11-19T23:59:59", "2026-10-10T09:00:00");
        course(me, "DELETED", "2026-11-25T23:59:59", "2026-10-29T09:00:00");
        course(UUID.randomUUID(), "ACTIVE", "2026-10-31T23:59:59", "2026-10-29T09:00:00");
        completions(dMinus1, 214);
        // 00:30(Asia/Seoul)에 완주해 날짜는 10/30이다. 그 뒤 완주는 기록을 지웠다
        completion(dMinus1, "2026-10-01T10:00:00", null);
        completion(dMinus1, "2026-10-30T00:30:00", null);
        completion(dMinus1, "2026-10-30T09:00:00", "2026-10-30T10:00:00");
        completion(dMinus1, null, "2026-10-30T10:00:00"); // 삭제를 먼저 받은 기록
        completions(deleting, 3);

        MvcTestResult result = mine("/api/v1/courses/mine", me);

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.content[*].courseId").asArray()
                .containsExactly(dMinus1.toString(), dMinus7.toString(), deleting.toString(), dMinus8.toString(), older.toString());
        assertThat(result).bodyJson().extractingPath("$.data.content[0].completionCount").isEqualTo(214);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].lastCompletedOn").isEqualTo("2026-10-30");
        assertThat(result).bodyJson().extractingPath("$.data.content[0].expiresAt").isEqualTo("2026-10-31T14:59:59Z");
        assertThat(result).bodyJson().extractingPath("$.data.content[0].tags").asArray().containsExactly("FLAT", "SHADE");
        assertThat(result).bodyJson().extractingPath("$.data.content[0].route").asArray().hasSize(2);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].statusReason").isNull();
        assertThat(result).bodyJson().extractingPath("$.data.content[0].deleteAt").isNull();
        // 완주가 없는 코스
        assertThat(result).bodyJson().extractingPath("$.data.content[1].completionCount").isEqualTo(0);
        assertThat(result).bodyJson().extractingPath("$.data.content[1].lastCompletedOn").isNull();
        // 오늘 10:00에 지워 내일 10:00에 삭제된다
        assertThat(result).bodyJson().extractingPath("$.data.content[2].status").isEqualTo("HIDDEN");
        assertThat(result).bodyJson().extractingPath("$.data.content[2].statusReason").isEqualTo("USER_DELETED");
        assertThat(result).bodyJson().extractingPath("$.data.content[2].deleteAt").isEqualTo("2026-10-31T01:00:00Z");
        assertThat(result).bodyJson().extractingPath("$.data.nextCursor").isNull();
    }

    @Test
    void pagesWithCursor() {
        UUID me = UUID.randomUUID();
        UUID first = course(me, "ACTIVE", "2026-11-20T23:59:59", "2026-10-29T09:00:00");
        UUID second = course(me, "ACTIVE", "2026-11-20T23:59:59", "2026-10-28T09:00:00");
        UUID third = course(me, "ACTIVE", "2026-11-20T23:59:59", "2026-10-27T09:00:00");

        MvcTestResult page1 = mine("/api/v1/courses/mine?size=2", me);
        MvcTestResult page2 = mine("/api/v1/courses/mine?size=2&cursor=2", me);

        assertThat(page1).bodyJson().extractingPath("$.data.content[*].courseId").asArray()
                .containsExactly(first.toString(), second.toString());
        assertThat(page1).bodyJson().extractingPath("$.data.nextCursor").isEqualTo("2");
        assertThat(page2).bodyJson().extractingPath("$.data.content[*].courseId").asArray().containsExactly(third.toString());
        assertThat(page2).bodyJson().extractingPath("$.data.nextCursor").isNull();
    }

    @Test
    void summaryCountsOnlyMyPublicCourses() {
        UUID me = UUID.randomUUID();
        completions(course(me, "ACTIVE", "2026-10-30T23:59:59", "2026-10-01T09:00:00"), 214); // D-0
        completions(course(me, "ACTIVE", "2026-11-06T23:59:59", "2026-10-08T09:00:00"), 9);   // D-7
        completions(course(me, "ACTIVE", "2026-11-07T23:59:59", "2026-10-09T09:00:00"), 12);  // D-8
        course(me, "ACTIVE", "2026-11-20T23:59:59", "2026-10-22T09:00:00");                    // 완주 없음
        completions(course(me, "HIDDEN", "2026-10-31T23:59:59", "2026-10-02T09:00:00"), 3);
        completions(course(UUID.randomUUID(), "ACTIVE", "2026-10-31T23:59:59", "2026-10-02T09:00:00"), 50);

        MvcTestResult result = mine("/api/v1/courses/mine/summary", me);

        assertThat(result).bodyJson().extractingPath("$.data.courseCount").isEqualTo(4);
        assertThat(result).bodyJson().extractingPath("$.data.completionCount").isEqualTo(235);
        assertThat(result).bodyJson().extractingPath("$.data.expiringSoonCount").isEqualTo(2);
    }

    @Test
    void summaryIsZeroWithoutCourses() {
        MvcTestResult result = mine("/api/v1/courses/mine/summary", UUID.randomUUID());

        assertThat(result).bodyJson().extractingPath("$.data.courseCount").isEqualTo(0);
        assertThat(result).bodyJson().extractingPath("$.data.completionCount").isEqualTo(0);
    }

    private MvcTestResult mine(String uri, UUID memberId) {
        return mvc.get().uri(uri).with(jwt().jwt(j -> j.subject(memberId.toString()))).exchange();
    }

    /** 시각은 Asia/Seoul. 비공개 · 삭제된 코스는 등록자가 오늘 10:00에 지웠다 */
    private UUID course(UUID creatorId, String status, String expiresAt, String createdAt) {
        UUID id = UUID.randomUUID();
        boolean active = status.equals("ACTIVE");
        jdbc.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    status_reason, hidden_at, expires_at, version, created_at, updated_at)
                        VALUES (?, ?, 'CUSTOM', ?, ?, 'EASY', '{SHADE,FLAT}'::varchar[],
                                ST_GeomFromText('LINESTRING(127.30 37.30, 127.30 37.31)', 4326), 1112,
                                ST_GeogFromText('SRID=4326;POINT(127.30 37.30)'), '1171010100', '1171000000', '1100000000',
                                ?, ?, ?, ?, 0, ?, ?)""",
                id, creatorId, "내 코스 " + id, "내코스" + id, status, active ? null : "USER_DELETED",
                active ? null : seoul("2026-10-30T10:00:00"), seoul(expiresAt), seoul(createdAt), seoul(createdAt));
        return id;
    }

    private void completions(UUID courseId, int count) {
        jdbc.update("""
                        INSERT INTO course.course_stats (course_id, completion_count, created_at, updated_at)
                        VALUES (?, ?, now(), now())""", courseId, count);
    }

    private void completion(UUID courseId, String completedAt, String deletedAt) {
        jdbc.update("""
                        INSERT INTO course.course_completions (run_record_id, course_id, completed_at, deleted_at, created_at, updated_at)
                        VALUES (?, ?, ?, ?, now(), now())""",
                UUID.randomUUID(), courseId, completedAt == null ? null : seoul(completedAt), deletedAt == null ? null : seoul(deletedAt));
    }

    private static Timestamp seoul(String localDateTime) {
        return Timestamp.from(Instant.parse(localDateTime + "+09:00"));
    }
}
