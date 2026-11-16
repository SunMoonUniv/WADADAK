package com.wadadak.course.internal.course;

/** 코스 유형(정책 공통 3). 사용자가 바꿀 수 없다. */
public enum CourseType {
    /** 사용자 지정: 지도에 입력점을 찍어 만든 코스 */
    CUSTOM,
    /** GPS 주행 등록: 러닝 기록으로 만든 코스 */
    GPS
}
