package com.wadadak.ranking.internal.course;

import java.time.Instant;
import java.util.UUID;

/**
 * 다른 러너의 이 코스 기록(I3 "이 코스에서의 기록"). 코스 랭킹에 보이는 그 기간 대표 기록 1건이다.
 *
 * @param runRecordId            `이 기록과 대결하기`에서 run 공개 고스트 재생에 넘기는 기록 ID
 * @param rank                   코스 랭킹 순위. 같은 시간이면 같은 순위(1·2·2·4)
 * @param paceSecondsPerKm       코스 완주 페이스. 코스 총 소요시간 ÷ 코스 전체 거리(km)를 반올림한 정수 초
 * @param myCourseElapsedSeconds 요청자의 같은 기간 대표 기록 시간("내 최고 기록은 27:14예요"). 없으면 {@code null}
 */
record RunnerCourseRecord(UUID runRecordId, int rank, int courseElapsedSeconds, int paceSecondsPerKm, Instant completedAt,
                          Integer myCourseElapsedSeconds) {
}
