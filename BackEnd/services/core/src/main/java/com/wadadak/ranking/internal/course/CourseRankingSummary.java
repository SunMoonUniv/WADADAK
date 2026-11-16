package com.wadadak.ranking.internal.course;

import com.wadadak.ranking.GhostCandidate;

import java.util.List;

/**
 * 코스 랭킹 요약(B9). G3 상단의 통계·내 순위와 B1·B8·B9·G3 고스트 대결 버튼에도 쓴다.
 * 내 정보 공개를 끈 회원은 참여 수·평균·순위·목록에서 모두 빠진다(정책 공통 6).
 *
 * @param participantCount            참여 러너 수
 * @param averageCourseElapsedSeconds 랭킹 평균 총 소요시간. 회원별 대표 기록의 평균을 반올림한 정수 초. 참여 0명이면 {@code null}
 * @param top                         상위 5줄(B9-04). 첫 줄이 1위다(B9-03)
 * @param ghost                       고스트 대결 버튼에 넘길 첫 공개 고스트(요청자 본인 제외, {@code RankingApi}와 같은 규칙).
 *                                    없으면 {@code null}이고 앱은 버튼을 끈다
 */
record CourseRankingSummary(int participantCount, Integer averageCourseElapsedSeconds, MyCourseRanking me,
                            List<CourseRankingEntry> top, GhostCandidate ghost) {
}
