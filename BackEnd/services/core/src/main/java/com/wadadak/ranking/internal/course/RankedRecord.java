package com.wadadak.ranking.internal.course;

import java.time.Instant;
import java.util.UUID;

/**
 * 회원의 대표 기록과 순위.
 *
 * @param rank 코스 총 소요시간이 같으면 같은 순위(1·2·2·4). 순위를 매기지 않은 기록이면 0
 */
record RankedRecord(int rank, UUID runRecordId, UUID memberId, int courseElapsedSeconds, int courseDistanceMeters,
                    Instant completedAt) {
}
