package com.wadadak.ranking;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * ranking 단독 기동(다른 도메인 모듈 없이). 분리 가능성의 직접 증거다(개발 정책 10.6).
 * 스텁({@code app.stub.ranking=true})으로 띄운다. 실제 구현은 {@code CourseRankingServiceTest}·{@code DistanceRankingServiceTest}.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
@TestPropertySource(properties = "app.stub.ranking=true")
class RankingModuleTests {

    private static final UUID COURSE_ID = UUID.randomUUID();

    @Autowired
    RankingApi rankingApi;

    @Test
    void returnsOtherRunnersInRankOrder() {
        UUID requester = UUID.randomUUID();

        List<GhostCandidate> candidates = rankingApi.getPublicGhostCandidates(COURSE_ID, RankingPeriod.ALL, requester, RankingApi.MAX_LIMIT);

        // 요청자(5위)는 후보에서만 빠지고 다른 러너의 순위는 그대로다.
        assertThat(candidates).extracting(GhostCandidate::rank).containsExactly(1, 2, 2, 4, 6, 7, 8, 9, 9, 11);
        assertThat(candidates).extracting(GhostCandidate::memberId).doesNotContain(requester);
        assertThat(rankingApi.getPublicGhostCandidates(COURSE_ID, RankingPeriod.WEEK, requester, 1))
                .extracting(GhostCandidate::rank)
                .containsExactly(1);
    }

    @Test
    void returnsEmptyWhenNoPublicGhost() {
        assertThat(rankingApi.getPublicGhostCandidates(UUID.fromString("00000000-0000-0000-0000-000000000001"),
                RankingPeriod.ALL, UUID.randomUUID(), 1)).isEmpty();
    }

    @Test
    void rejectsLimitOutOfRange() {
        for (int limit : new int[]{0, RankingApi.MAX_LIMIT + 1}) {
            assertThatThrownBy(() -> rankingApi.getPublicGhostCandidates(COURSE_ID, RankingPeriod.ALL, UUID.randomUUID(), limit))
                    .isInstanceOfSatisfying(AppException.class,
                            e -> assertThat(e.getErrorCode()).isEqualTo(RankingErrorCode.INVALID_GHOST_LIMIT));
        }
    }
}
