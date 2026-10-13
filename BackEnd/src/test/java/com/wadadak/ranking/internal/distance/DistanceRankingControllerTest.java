package com.wadadak.ranking.internal.distance;

import com.wadadak.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.convention.TestBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 스텁 데이터로 응답 형식을 확인한다. 스텁 기록은 {@link DistanceRankingStub} 참고.
 * 지금은 2026-10-14(수) 12:00 Asia/Seoul로 고정한다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class DistanceRankingControllerTest {

    private static final UUID ME = UUID.randomUUID();

    @Autowired
    MockMvcTester mvc;

    @TestBean
    Clock clock;

    static Clock clock() {
        return Clock.fixed(Instant.parse("2026-10-14T03:00:00Z"), ZoneId.of("Asia/Seoul"));
    }

    @Test
    void summarizesWholeRankingWithPodium() {
        MvcTestResult result = get("/api/v1/rankings/distance");

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.participantCount").isEqualTo(31);
        assertThat(result).bodyJson().extractingPath("$.data.calculatedAt").isEqualTo("2026-10-13T15:00:00Z");
        assertThat(result).bodyJson().extractingPath("$.data.top[*].nickname").asArray()
                .containsExactly("러너_하늘", "러너_민", "성북러너");
        assertThat(result).bodyJson().extractingPath("$.data.top[0].distanceMeters").isEqualTo(1_284_000);
        assertThat(result).bodyJson().extractingPath("$.data.nextCursor").isEqualTo("3");
        // 128km로 러너26과 공동 26위
        assertThat(result).bodyJson().extractingPath("$.data.me.status").isEqualTo("RANKED");
        assertThat(result).bodyJson().extractingPath("$.data.me.rank").isEqualTo(26);
        assertThat(result).bodyJson().extractingPath("$.data.me.thisWeekDistanceMeters").isEqualTo(48_200);
        assertThat(result).bodyJson().extractingPath("$.data.me.topPercent").isEqualTo(84);
    }

    @Test
    void continuesListAfterPodium() {
        MvcTestResult result = get("/api/v1/rankings/distance/entries", "cursor", "3", "size", "5");

        assertThat(result).bodyJson().extractingPath("$.data.content[*].rank").asArray().containsExactly(4, 5, 6, 7, 8);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].weeklyAverageMeters").isEqualTo(38_000);
        assertThat(result).bodyJson().extractingPath("$.data.nextCursor").isEqualTo("8");
    }

    @Test
    void weekRankingPutsMeTwelfth() {
        MvcTestResult result = get("/api/v1/rankings/distance", "period", "WEEK");

        assertThat(result).bodyJson().extractingPath("$.data.participantCount").isEqualTo(16);
        assertThat(result).bodyJson().extractingPath("$.data.me.rank").isEqualTo(12);
    }

    @Test
    void regionWeeklyDefaultsToMyActivityRegion() {
        MvcTestResult result = get("/api/v1/rankings/distance/regions/weekly");

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.region.code").isEqualTo("1129000000");
        assertThat(result).bodyJson().extractingPath("$.data.region.name").isEqualTo("성북구");
        assertThat(result).bodyJson().extractingPath("$.data.weekStart").isEqualTo("2026-10-12");
        assertThat(result).bodyJson().extractingPath("$.data.top[*].rank").asArray().containsExactly(1, 2, 3, 4, 5);
        assertThat(result).bodyJson().extractingPath("$.data.top[0].nickname").isEqualTo("러너_하늘");
        assertThat(result).bodyJson().extractingPath("$.data.me.rank").isEqualTo(12);
        assertThat(result).bodyJson().extractingPath("$.data.me.lastWeekRank").isEqualTo(19);
        assertThat(result).bodyJson().extractingPath("$.data.nextCursor").isEqualTo("5");
    }

    @Test
    void otherRegionHasNoRankForMe() {
        MvcTestResult result = get("/api/v1/rankings/distance/regions/weekly", "regionCode", "1111000000");

        assertThat(result).bodyJson().extractingPath("$.data.region.name").isEqualTo("종로구");
        assertThat(result).bodyJson().extractingPath("$.data.me.status").isEqualTo("OTHER_REGION");
        assertThat(get("/api/v1/rankings/distance/regions/weekly/entries", "regionCode", "1111000000", "size", "50"))
                .bodyJson().extractingPath("$.data.content[*].mine").asArray().containsOnly(false);
    }

    @Test
    void rejectsRegionThatIsNotSigungu() {
        for (String code : new String[]{"1100000000", "1129010100", "9999999999"}) {
            assertThat(get("/api/v1/rankings/distance/regions/weekly", "regionCode", code))
                    .hasStatus(HttpStatus.NOT_FOUND)
                    .bodyJson().extractingPath("$.code").isEqualTo("RANKING-002");
        }
    }

    @Test
    void requiresLogin() {
        assertThat(mvc.get().uri("/api/v1/rankings/distance")).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void servesSwaggerGroup() {
        assertThat(mvc.get().uri("/v3/api-docs/ranking")).hasStatusOk()
                .bodyText().contains("/api/v1/rankings/distance/regions/weekly");
    }

    private MvcTestResult get(String uri, String... params) {
        var request = mvc.get().uri(uri).with(jwt().jwt(token -> token.subject(ME.toString())));
        for (int i = 0; i < params.length; i += 2) {
            request = request.param(params[i], params[i + 1]);
        }
        return request.exchange();
    }
}
