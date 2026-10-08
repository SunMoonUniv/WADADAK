package com.wadadak.course;

import java.util.UUID;

/**
 * 러닝 준비·시작용 코스 경로 조회. 호출 허용: run (개발 정책 4.3).
 * 시작 시 받은 스냅샷으로 러닝을 끝까지 진행한다. 이후 코스가 비공개·삭제돼도 다시 조회하지 않는다(6.2).
 */
public interface CourseApi {

    /**
     * @throws com.wadadak.common.exception.AppException {@link CourseErrorCode#COURSE_NOT_FOUND} — 없는 코스,
     *         {@link CourseErrorCode#COURSE_NOT_AVAILABLE} — {@code ACTIVE}가 아닌 코스(비공개·삭제)
     */
    CourseRouteSnapshot getRouteForRun(UUID courseId);
}
