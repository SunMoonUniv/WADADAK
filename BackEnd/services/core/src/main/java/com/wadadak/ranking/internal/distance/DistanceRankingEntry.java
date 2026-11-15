package com.wadadak.ranking.internal.distance;

import java.util.UUID;

/**
 * 누적 거리 랭킹 한 줄(E1·I5).
 *
 * @param rank                거리가 같으면 같은 순위이고 다음 순위는 그 인원만큼 건너뛴다(1·2·2·4)
 * @param nickname            표시용. 탈퇴 회원은 {@code 탈퇴한 사용자}
 * @param distanceMeters      그 기간에 달린 거리(m). 자유 러닝·미완주·코스 밖의 정상 측정 거리도 포함한다
 * @param runCount            그 기간에 등록된 기록 수(지역 탭의 "러닝 14회")
 * @param weeklyAverageMeters 주 평균(m, 전체 랭킹 누적 탭의 "주 평균 38km"). 누적 거리 ÷ 첫 기록이 등록된 주부터 이번 주까지의 주 수, 반올림
 * @param mine                요청자 본인이면 {@code true}
 */
record DistanceRankingEntry(int rank, UUID memberId, String nickname, String profileImageUrl, int distanceMeters,
                            int runCount, int weeklyAverageMeters, boolean mine) {
}
