package com.wadadak.ranking.internal.course;

import com.wadadak.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 스텁 데이터로 응답 형식을 확인한다. 스텁 기록은 {@link RankingApiStub} 참고. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
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
