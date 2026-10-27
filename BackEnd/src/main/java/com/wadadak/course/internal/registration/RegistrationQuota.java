package com.wadadak.course.internal.registration;

import java.util.List;
import java.util.UUID;

/**
 * 오늘(Asia/Seoul) 유형별 등록 한도와 남은 수. 유형마다 따로 센다.
 *
 * @param custom           사용자 지정(B3 지도에 점 찍기). 하루 1개
 * @param gps              GPS 주행 등록(B5·B6 합산). 하루 3개
 * @param usedRunRecordIds 이 회원이 GPS 코스 등록에 쓴 러닝 기록 ID(등록한 순서). 그 코스가 지워지거나 만료돼도 남는다.
 *                         B6 · 결과 화면의 `이미 등록됨`(B6-04)
 */
record RegistrationQuota(TypeQuota custom, TypeQuota gps, List<UUID> usedRunRecordIds) {

    record TypeQuota(int limit, int remaining) {
    }
}
