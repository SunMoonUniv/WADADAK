package com.wadadak.course.internal.course;

/** 코스 특징(FIL-04·B4-04). 값을 추가할 때는 DB 컬럼 길이(VARCHAR(20))를 넘지 않게 한다. */
public enum CourseTag {
    /** 평지 */
    FLAT,
    /** 오르막 */
    UPHILL,
    /** 그늘 */
    SHADE,
    /** 강변 */
    RIVERSIDE,
    /** 야간 조명 */
    NIGHT_LIGHT,
    /** 화장실 */
    RESTROOM,
    /** 편의점 */
    CONVENIENCE_STORE,
    /** 트랙 */
    TRACK
}
