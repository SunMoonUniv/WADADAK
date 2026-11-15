package com.wadadak.ranking.internal.distance;

import java.util.UUID;

/**
 * 회원 한 명의 누적 거리 · 러닝 수(I3 "총 거리 642km · 러닝 118회"). 전체 랭킹 누적(ALL)과 같은 기준이다.
 * 내 정보 비공개 회원이면 둘 다 {@code null}이다(요청자 본인은 비공개여도 값이 있다).
 *
 * @param totalDistanceMeters 오늘 00:00(Asia/Seoul) 전에 등록된 기록 거리 합(m). 기록이 없으면 0
 * @param runCount            그 기록 수. 자유 러닝 · 미완주도 센다
 */
record MemberDistanceTotal(UUID memberId, Integer totalDistanceMeters, Integer runCount) {
}
