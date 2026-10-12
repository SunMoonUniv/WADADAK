package com.wadadak.ranking.internal.course;

import java.time.Instant;
import java.util.UUID;

/**
 * 코스 랭킹 한 줄. 회원마다 그 기간 가장 짧은 코스 총 소요시간의 완주 기록 1건이다(정책 공통 6).
 *
 * @param rank                 코스 총 소요시간이 같으면 같은 순위이고 다음 순위는 그 인원만큼 건너뛴다(1·2·2·4)
 * @param nickname             표시용. 탈퇴 회원은 {@code 탈퇴한 사용자}
 * @param courseElapsedSeconds 코스 총 소요시간(정수 초)
 * @param paceSecondsPerKm     코스 완주 페이스. 코스 총 소요시간 ÷ 코스 전체 거리(km)를 반올림한 정수 초
 * @param completedAt          완주 시각. 기간은 이 값이 아니라 기록 등록 시각으로 나눈다
 * @param mine                 요청자 본인 기록이면 {@code true}. 앱은 이 행을 눌러도 프로필로 이동하지 않는다(G3-03)
 */
record CourseRankingEntry(int rank, UUID memberId, String nickname, String profileImageUrl,
                          int courseElapsedSeconds, int paceSecondsPerKm, Instant completedAt, boolean mine) {
}
