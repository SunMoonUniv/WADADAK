package com.wadadak.course.internal.bookmark;

/**
 * G5 탭의 `저장한 코스 N`과 위 칸. 공개 중인 코스만 센다(G4와 같다). 삭제 예정 코스는 목록에만 보인다.
 *
 * @param courseCount       저장한 공개 중인 코스 수(`저장한 코스`)
 * @param expiringSoonCount 그중 만료일까지 7일 이내(D-7 ~ D-0, Asia/Seoul)인 코스 수(`만료 임박`)
 */
record BookmarkSummary(int courseCount, int expiringSoonCount) {
}
