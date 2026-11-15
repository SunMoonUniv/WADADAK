package com.wadadak.course.internal.explore;

/**
 * 다른 러너 프로필(I3) 위 칸의 `등록 코스 N개`.
 *
 * @param courseCount 그 러너가 등록한 공개 중인 코스 수(MY `등록 코스`와 같은 기준)
 */
record RunnerCourseSummary(int courseCount) {
}
