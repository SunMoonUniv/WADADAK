package com.wadadak.ranking;

import java.util.UUID;

/**
 * @param runRecordId          고스트로 쓸 완주 기록(run 모듈 ID)
 * @param rank                 요청자와 관계없이 랭킹 화면에 보이는 순위. 코스 총 소요시간이 같으면 같은 순위이고
 *                             다음 순위는 그 인원만큼 건너뛴다(1·2·2·4). 요청자 본인 기록은 후보에서만 뺀다.
 * @param courseElapsedSeconds 코스 총 소요시간(정수 초)
 */
public record GhostCandidate(UUID runRecordId, UUID memberId, int rank, int courseElapsedSeconds) {
}
