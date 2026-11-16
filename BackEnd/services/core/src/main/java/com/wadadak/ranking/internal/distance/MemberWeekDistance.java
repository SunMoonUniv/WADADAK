package com.wadadak.ranking.internal.distance;

import java.util.UUID;

/**
 * 회원 한 명의 이번 주 거리(G7 러너 검색 "주 32 km").
 *
 * @param thisWeekDistanceMeters 전체 랭킹의 {@code me.thisWeekDistanceMeters}와 같은 값(m). 기록이 없으면 0,
 *                               내 정보 비공개 회원이면 {@code null}(요청자 본인은 비공개여도 값이 있다)
 */
record MemberWeekDistance(UUID memberId, Integer thisWeekDistanceMeters) {
}
