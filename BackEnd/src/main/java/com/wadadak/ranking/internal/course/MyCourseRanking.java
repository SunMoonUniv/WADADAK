package com.wadadak.ranking.internal.course;

import java.time.Instant;

/**
 * 내 순위(B9-02). {@code status}가 {@code RANKED}가 아니면 {@code rank}·{@code topPercent}는 {@code null}이다.
 *
 * @param courseElapsedSeconds 내 대표 기록의 코스 총 소요시간. 그 기간 완주 기록이 없으면 {@code null}
 * @param topPercent           상위 비율(%). 순위 ÷ 참여 러너 수 × 100을 올림한 정수(1~100)
 */
record MyCourseRanking(Status status, Integer rank, Integer courseElapsedSeconds, Integer paceSecondsPerKm,
                       Instant completedAt, Integer topPercent) {

    enum Status {
        /** 순위가 있다 */
        RANKED,
        /** 그 기간 완주 기록이 없다 */
        NO_RECORD,
        /** 내 정보 공개를 꺼서 순위 계산에서 빠졌다. 앱은 순위 대신 `비공개 중`을 표시한다. 기록 값은 있으면 채운다 */
        PRIVATE
    }
}
