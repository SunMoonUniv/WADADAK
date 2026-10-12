package com.wadadak.ranking;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * ranking 단독 기동(다른 도메인 모듈 없이). 분리 가능성의 직접 증거다(개발 정책 10.6).
 * 실제 구현 전이라 {@code app.stub.ranking: true}로 스텁이 뜬다.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RankingModuleTests {

    private static final UUID COURSE_ID = UUID.randomUUID();

    @Autowired
    RankingApi rankingApi;

    @Test
    void returnsCandidatesInRankOrderWithoutRequester() {
        UUID firstPlace = UUID.fromString("00000000-0000-0000-0002-000000000001");

        assertThat(rankingApi.getPublicGhostCandidates(COURSE_ID, RankingPeriod.ALL, firstPlace, RankingApi.MAX_LIMIT))
                .extracting(GhostCandidate::rank)
                .containsExactly(2, 2, 4);
        assertThat(rankingApi.getPublicGhostCandidates(COURSE_ID, RankingPeriod.WEEK, UUID.randomUUID(), 1))
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
