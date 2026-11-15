package com.wadadak.ranking.internal.course;

import com.wadadak.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 스텁({@code app.stub.ranking=true}) 데이터로 응답 형식을 확인한다. 스텁 기록은 {@link RankingApiStub} 참고. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
@TestPropertySource(properties = "app.stub.ranking=true")
class CourseRankingControllerTest {

    private static final UUID ME = UUID.randomUUID();
    private static final String COURSE = "/api/v1/rankings/courses/" + UUID.randomUUID();

    @Autowired
    MockMvcTester mvc;

    @Test
    void summarizesWithMyRankTopAndGhost() {
        MvcTestResult result = get(COURSE);

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.participantCount").isEqualTo(12);
        assertThat(result).bodyJson().extractingPath("$.data.averageCourseElapsedSeconds").isEqualTo(332);
        assertThat(result).bodyJson().extractingPath("$.data.me.status").isEqualTo("RANKED");
        assertThat(result).bodyJson().extractingPath("$.data.me.rank").isEqualTo(5);
        assertThat(result).bodyJson().extractingPath("$.data.me.topPercent").isEqualTo(42);
        assertThat(result).bodyJson().extractingPath("$.data.top[*].rank").asArray().containsExactly(1, 2, 2, 4, 5);
        assertThat(result).bodyJson().extractingPath("$.data.top[4].mine").isEqualTo(true);
        assertThat(result).bodyJson().extractingPath("$.data.ghost.rank").isEqualTo(1);
    }

    @Test
    void periodChangesRankingAndMyRecord() {
        MvcTestResult week = get(COURSE, "period", "WEEK");

        assertThat(week).bodyJson().extractingPath("$.data.participantCount").isEqualTo(3);
        assertThat(week).bodyJson().extractingPath("$.data.top[*].rank").asArray().containsExactly(1, 1, 3);
        assertThat(week).bodyJson().extractingPath("$.data.me.status").isEqualTo("NO_RECORD");
        assertThat(week).bodyJson().extractingPath("$.data.me.rank").isNull();
        assertThat(week).bodyJson().extractingPath("$.data.me.nickname").asString().startsWith("러너-");
    }

    @Test
    void emptyCourseHasNoParticipantsOrGhost() {
        MvcTestResult result = get("/api/v1/rankings/courses/00000000-0000-0000-0000-000000000001");

        assertThat(result).bodyJson().extractingPath("$.data.participantCount").isEqualTo(0);
        assertThat(result).bodyJson().extractingPath("$.data.averageCourseElapsedSeconds").isNull();
        assertThat(result).bodyJson().extractingPath("$.data.top").asArray().isEmpty();
        assertThat(result).bodyJson().extractingPath("$.data.ghost").isNull();
    }

    @Test
    void privateRequesterIsLeftOutOfRanking() {
        MvcTestResult result = get("/api/v1/rankings/courses/00000000-0000-0000-0000-000000000002");

        assertThat(result).bodyJson().extractingPath("$.data.participantCount").isEqualTo(11);
        assertThat(result).bodyJson().extractingPath("$.data.me.status").isEqualTo("PRIVATE");
        assertThat(result).bodyJson().extractingPath("$.data.me.rank").isNull();
        assertThat(result).bodyJson().extractingPath("$.data.me.courseElapsedSeconds").isEqualTo(318);
        assertThat(result).bodyJson().extractingPath("$.data.me.nickname").asString().startsWith("러너-");
        assertThat(result).bodyJson().extractingPath("$.data.top[*].mine").asArray().containsOnly(false);
    }

    @Test
    void pagesEntriesWithCursor() {
        MvcTestResult first = get(COURSE + "/entries", "size", "5");
        assertThat(first).bodyJson().extractingPath("$.data.content[*].rank").asArray().containsExactly(1, 2, 2, 4, 5);
        assertThat(first).bodyJson().extractingPath("$.data.content[4].mine").isEqualTo(true);
        assertThat(first).bodyJson().extractingPath("$.data.nextCursor").isEqualTo("5");

        MvcTestResult second = get(COURSE + "/entries", "size", "5", "cursor", "5");
        assertThat(second).bodyJson().extractingPath("$.data.content[*].rank").asArray().containsExactly(6, 7, 8, 9, 9);

        MvcTestResult last = get(COURSE + "/entries", "size", "5", "cursor", "10");
        assertThat(last).bodyJson().extractingPath("$.data.content[*].rank").asArray().containsExactly(11, 12);
        assertThat(last).bodyJson().extractingPath("$.data.nextCursor").isNull();
    }

    @Test
    void publicCandidatesPageBeyondTenAndCarryExactSourceIds() {
        var first = get(COURSE + "/ghost-candidates", "size", "10");
        assertThat(first).hasStatusOk();
        assertThat(first).bodyJson().extractingPath("$.data.content").asArray().hasSize(10);
        assertThat(first).bodyJson().extractingPath("$.data.content[*].memberId").asArray().doesNotContain(ME.toString());
        assertThat(first).bodyJson().extractingPath("$.data.content[0].runRecordId").asString().isNotBlank();
        assertThat(first).bodyJson().extractingPath("$.data.content[0].nickname").isEqualTo("러너1");
        assertThat(first).bodyJson().extractingPath("$.data.nextCursor").isEqualTo("10");
        var last = get(COURSE + "/ghost-candidates", "size", "10", "cursor", "10");
        assertThat(last).bodyJson().extractingPath("$.data.content").asArray().hasSize(1);
        assertThat(last).bodyJson().extractingPath("$.data.nextCursor").isNull();
        assertThat(get(COURSE + "/ghost-candidates", "sort", "SIMILAR"))
                .bodyJson().extractingPath("$.data.content[0].courseElapsedSeconds").isEqualTo(312);
        assertThat(get(COURSE + "/ghost-candidates", "sort", "WRONG")).hasStatus(HttpStatus.BAD_REQUEST);
        assertThat(get(COURSE + "/ghost-candidates", "cursor", "abc")).hasStatus(HttpStatus.BAD_REQUEST);
        assertThat(get(COURSE + "/ghost-candidates", "size", "51")).hasStatus(HttpStatus.BAD_REQUEST);
        assertThat(get(COURSE + "/ghost-candidates", "period", "YEAR")).hasStatus(HttpStatus.BAD_REQUEST);
        assertThat(mvc.get().uri(COURSE + "/ghost-candidates")).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void runnerRecordForProfile() {
        // 스텁의 1위 러너(러너1, 290초)
        MvcTestResult result = get(COURSE + "/members/00000000-0000-0000-0002-000000000001");

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.rank").isEqualTo(1);
        assertThat(result).bodyJson().extractingPath("$.data.courseElapsedSeconds").isEqualTo(290);
        assertThat(result).bodyJson().extractingPath("$.data.paceSecondsPerKm").isEqualTo(290);   // 1001m라 289.7 → 290
        assertThat(result).bodyJson().extractingPath("$.data.myCourseElapsedSeconds").isEqualTo(318);
        // 순위에 없는 러너는 data가 null이라 앱이 섹션을 숨긴다
        assertThat(get(COURSE + "/members/" + UUID.randomUUID())).bodyJson().extractingPath("$.data").isNull();
    }

    @Test
    void rejectsInvalidParameters() {
        assertThat(get(COURSE, "period", "YEAR")).hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
        assertThat(get(COURSE + "/entries", "size", "51")).hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
        assertThat(get(COURSE + "/entries", "cursor", "abc")).hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    @Test
    void requiresLogin() {
        assertThat(mvc.get().uri(COURSE)).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void servesSwaggerGroup() {
        assertThat(mvc.get().uri("/v3/api-docs/ranking")).hasStatusOk()
                .bodyText().contains("/api/v1/rankings/courses/{courseId}/entries");
    }

    private MvcTestResult get(String uri, String... params) {
        var request = mvc.get().uri(uri).with(jwt().jwt(token -> token.subject(ME.toString())));
        for (int i = 0; i < params.length; i += 2) {
            request = request.param(params[i], params[i + 1]);
        }
        return request.exchange();
    }
}
