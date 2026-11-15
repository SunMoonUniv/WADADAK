package com.wadadak.ranking.internal.distance;

import com.wadadak.common.region.Region;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/**
 * 지역 주간 랭킹(E1 지역 탭, I5). 회원 활동 지역(시·군·구)이 같은 회원끼리, 이번 주 거리로 순위를 매긴다(정책 공통 6).
 * 매일 자정에 계산하고 매주 월요일 00:00에 새로 시작한다. 활동 지역을 바꾼 회원은 다음 주부터 새 지역에 들어간다.
 *
 * @param region     보고 있는 시·군·구
 * @param weekStart  이번 주 월요일(Asia/Seoul). 앱이 "9월 2주차"처럼 표시한다
 * @param calculatedAt 계산 시각(매일 00:00, Asia/Seoul)
 * @param participantCount 참여 러너 수. 1위 거리는 {@code top}의 첫 줄이다(I5)
 * @param top        상위 5줄
 * @param nextCursor 6위부터 이어 받을 커서. 더 없으면 {@code null}
 */
record RegionWeeklyRanking(Region region, LocalDate weekStart, Instant calculatedAt, int participantCount,
                           MyDistanceRanking me, List<DistanceRankingEntry> top, String nextCursor) {
}
