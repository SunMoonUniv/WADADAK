package com.wadadak.ranking.internal.distance;

import java.time.Instant;
import java.util.List;

/**
 * 전체 랭킹 탭(E1). 오늘 00:00(Asia/Seoul) 전에 등록된 기록으로 계산한 값이다(정책 공통 6). 내 정보 비공개 회원은 참여 수·순위·목록에서 빠진다.
 *
 * @param participantCount 참여 러너 수. 그 기간에 기록이 있는 내 정보 공개 회원
 * @param calculatedAt     계산 시각(매일 00:00, Asia/Seoul)
 * @param top              시상대 1~3위
 * @param nextCursor       4위부터 이어 받을 커서(목록 API의 {@code cursor}). 더 없으면 {@code null}
 */
record DistanceRankingSummary(int participantCount, Instant calculatedAt, MyDistanceRanking me,
                              List<DistanceRankingEntry> top, String nextCursor) {
}
