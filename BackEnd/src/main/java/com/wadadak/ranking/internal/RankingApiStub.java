package com.wadadak.ranking.internal;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.stub.StubImplementation;
import com.wadadak.ranking.GhostCandidate;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingErrorCode;
import com.wadadak.ranking.RankingPeriod;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;

/**
 * 어떤 코스·기간이든 스텁 코스(약 1km)를 5분 안팎에 달린 후보 4명을 돌려준다. 공동순위(2위 2명)를 포함한다.
 * 확인용 ID는 {@link RankingApi} 참고.
 */
@Component
@ConditionalOnProperty(name = "app.stub.ranking", havingValue = "true")
class RankingApiStub implements RankingApi, StubImplementation {

    static final UUID NO_GHOST_COURSE_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");

    private static final List<GhostCandidate> CANDIDATES = List.of(
            candidate(1, 1, 290),
            candidate(2, 2, 305),
            candidate(3, 2, 305),
            candidate(4, 4, 331));

    @Override
    public List<GhostCandidate> getPublicGhostCandidates(UUID courseId, RankingPeriod period, UUID requesterId, int limit) {
        if (limit < 1 || limit > MAX_LIMIT) {
            throw new AppException(RankingErrorCode.INVALID_GHOST_LIMIT);
        }
        if (NO_GHOST_COURSE_ID.equals(courseId)) {
            return List.of();
        }
        return CANDIDATES.stream()
                .filter(candidate -> !candidate.memberId().equals(requesterId))
                .limit(limit)
                .toList();
    }

    private static GhostCandidate candidate(int n, int rank, int courseElapsedSeconds) {
        return new GhostCandidate(UUID.fromString("00000000-0000-0000-0001-00000000000" + n),
                UUID.fromString("00000000-0000-0000-0002-00000000000" + n), rank, courseElapsedSeconds);
    }
}
