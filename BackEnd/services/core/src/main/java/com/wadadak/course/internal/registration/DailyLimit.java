package com.wadadak.course.internal.registration;

import com.wadadak.course.internal.course.CourseType;

/**
 * 유형별 하루 등록 한도(정책 공통 3). 유형마다 따로 센다. GPS는 B5(달리며 등록)·B6(기록에서 등록)을 합산한다.
 * 날짜는 Asia/Seoul, 성공한 등록만 센다.
 */
final class DailyLimit {

    private DailyLimit() {
    }

    static int of(CourseType type) {
        return switch (type) {
            case CUSTOM -> 1;
            case GPS -> 3;
        };
    }
}
