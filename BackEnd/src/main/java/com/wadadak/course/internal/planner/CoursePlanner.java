package com.wadadak.course.internal.planner;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.UUID;

/**
 * 코스 자동 생성(정책 B3 `자동 생성`). 앱만 쓰는 API라 지금은 {@code app.stub.course-planner: true}일 때
 * {@link PlannerStub}만 뜬다(개발 정책 3.2).
 */
interface CoursePlanner {

    /** 문장으로 폼을 채운다. 하루 50회, 넘으면 COURSE-013 */
    PlanForm parse(UUID memberId, String text);

    /** 후보를 만든다. 하루 20회, 넘으면 COURSE-012 */
    PlanResult plan(UUID memberId, PlanRequest request);

    /** 오늘(Asia/Seoul) 남은 코스 자동 생성 횟수 */
    PlanQuota quota(UUID memberId);

    record PlanQuota(int limit, int remaining) {
    }

    /** @param text 1~200자 */
    record ParseRequest(@NotBlank @Size(max = 200) String text) {
    }
}
