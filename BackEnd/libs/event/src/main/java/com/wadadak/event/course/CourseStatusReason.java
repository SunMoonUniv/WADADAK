package com.wadadak.event.course;

/**
 * 코스가 {@link CourseStatus#HIDDEN}이 된 사유. {@link CourseStatus#DELETED}로 바뀔 때도 같은 사유를 유지한다(정책 공통 4).
 */
public enum CourseStatusReason {
    /** 유지 기간 만료 */
    EXPIRED,
    /** 등록자가 삭제 */
    USER_DELETED
}
