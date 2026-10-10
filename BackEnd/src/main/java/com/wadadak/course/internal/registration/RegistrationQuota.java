package com.wadadak.course.internal.registration;

/**
 * 오늘(Asia/Seoul) 유형별 등록 한도와 남은 수. 유형마다 따로 센다.
 *
 * @param custom 사용자 지정(B3 지도에 점 찍기). 하루 1개
 * @param gps    GPS 주행 등록(B5·B6 합산). 하루 3개
 */
record RegistrationQuota(TypeQuota custom, TypeQuota gps) {

    record TypeQuota(int limit, int remaining) {
    }
}
