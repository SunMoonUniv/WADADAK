package com.wadadak.course.internal.mine;

/**
 * G4 탭의 `등록한 코스 N`과 위 칸. 공개 중인 코스만 센다. 삭제 예정 코스는 목록에만 보인다.
 *
 * @param courseCount       공개 중인 내 코스 수(`등록 코스`)
 * @param completionCount   그 코스들의 완주 수 합(`누적 주행`)
 * @param expiringSoonCount 그중 만료일까지 7일 이내(D-7 ~ D-0, Asia/Seoul)인 코스 수(`만료 임박`)
 */
record MyCourseSummary(int courseCount, int completionCount, int expiringSoonCount) {
}
