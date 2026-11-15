package com.wadadak.member.internal.profile;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/** 다른 러너 프로필 REST API(I3). 규칙은 {@link RunnerProfileService}. */
@RestController
@RequestMapping("/api/v1/members/{memberId}")
@RequiredArgsConstructor
class RunnerProfileController {

    private final RunnerProfileService service;

    @Operation(summary = "다른 러너 프로필 (I3)",
            description = "I3 위쪽의 사진 · 닉네임 · `지역 · 러닝 경력`. 내 정보 공개 · 프로필 검색 허용과 관계없이 보인다(정책 공통 6). "
                    + "region은 활동 지역(시·군·구, 코드가 지역 목록에 없으면 null), runningExperience는 4단계"
                    + "(BEGINNER · MONTHS_6 · YEAR_1 · YEAR_3). 총 거리 · 러닝은 ranking GET /api/v1/rankings/distance/members/{memberId}, "
                    + "이 코스에서의 기록은 ranking GET /api/v1/rankings/courses/{courseId}/members/{memberId}로 받는다. "
                    + "탈퇴했거나 없는 회원은 MEMBER-011(404). 잘못된 ID는 COMMON-001.")
    @GetMapping
    ApiResult<RunnerProfile> profile(@PathVariable UUID memberId) {
        return ApiResult.success(service.profile(memberId));
    }
}
