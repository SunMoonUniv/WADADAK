package com.wadadak.ranking;

import java.util.List;
import java.util.UUID;

/**
 * 코스 랭킹 기반 공개 고스트 후보 조회. 호출 허용: run (개발 정책 4.3).
 * <p>
 * 코스 랭킹은 서버가 완주로 확정한 기록만 반영하고, 회원마다 그 기간 가장 짧은 코스 총 소요시간 기록 1건을 대표로 쓴다(정책 공통 6).
 * 내 정보 공개를 끈 회원은 순위 계산과 후보에서 모두 빠진다.
 * <p>
 * 스텁({@code app.stub.ranking: true})은 어떤 코스든 고정 기록에 요청자를 끼워 순위를 매긴다.
 * {@code ALL}이면 12명 중 요청자가 5위이고, 후보는 요청자를 뺀 1·2·2·4·6…위다. 확인용 ID:
 * <ul>
 *     <li>{@code 00000000-0000-0000-0000-000000000001} → 빈 목록(공개 고스트 없음)</li>
 * </ul>
 */
public interface RankingApi {

    int MAX_LIMIT = 10;

    /**
     * 다른 러너 고스트 후보. 순위가 높은 순서로, 요청자 본인 기록을 뺀 뒤 최대 {@code limit}개를 돌려준다.
     * 같은 순위끼리의 순서는 구현에서 정한다(정책 D-11). 시작 직전 재확인에도 쓴다.
     *
     * @param limit 1~{@value #MAX_LIMIT}
     * @return 후보가 없으면 빈 목록. 숨김·삭제된 코스도 빈 목록이다.
     * @throws com.wadadak.common.exception.AppException {@link RankingErrorCode#INVALID_GHOST_LIMIT} — {@code limit} 범위 밖
     */
    List<GhostCandidate> getPublicGhostCandidates(UUID courseId, RankingPeriod period, UUID requesterId, int limit);
}
