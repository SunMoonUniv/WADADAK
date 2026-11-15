package com.wadadak.member.internal.admin;

import com.wadadak.common.paging.NumberedPage;
import com.wadadak.common.response.ApiResult;
import com.wadadak.member.internal.account.RunningExperience;
import com.wadadak.member.internal.admin.AdminMemberViews.AdminMemberDetail;
import com.wadadak.member.internal.admin.AdminMemberViews.AdminMemberRow;
import com.wadadak.member.internal.admin.AdminMemberViews.AdminMemberStats;
import com.wadadak.member.internal.social.SocialProvider;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * 운영자 회원 관리 API(운영자 웹 ADM-1). 회원 JWT가 아니라 운영자 계정(HTTP Basic)으로만 부른다(SecurityConfig).
 * 조회만 한다. 페이지는 0부터, 한 페이지 1~100개(기본 20). 범위 밖이면 COMMON-001.
 */
@RestController
@RequestMapping("/api/v1/admin/members")
@RequiredArgsConstructor
class AdminMemberController {

    private final AdminMemberService service;

    @Operation(summary = "[운영자] 회원 관리 숫자 카드 (ADM-1)",
            description = "전체 회원 · 이번 주 가입 · 이번 달 가입. 탈퇴 회원은 세지 않는다. 이번 주 · 이번 달은 Asia/Seoul, 주는 월요일부터.")
    @GetMapping("/stats")
    ApiResult<AdminMemberStats> stats() {
        return ApiResult.success(service.stats());
    }

    @Operation(summary = "[운영자] 회원 목록 (ADM-1)",
            description = "최근 가입 순. 탈퇴 회원은 빠진다. socialProvider(KAKAO · GOOGLE · APPLE) · "
                    + "runningExperience(BEGINNER · MONTHS_6 · YEAR_1 · YEAR_3)로 거른다. "
                    + "region은 활동 지역(코드가 지역 목록에서 사라졌으면 null).")
    @GetMapping
    ApiResult<NumberedPage<AdminMemberRow>> list(
            @RequestParam(required = false) SocialProvider socialProvider,
            @RequestParam(required = false) RunningExperience runningExperience,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {
        return ApiResult.success(service.list(socialProvider, runningExperience, page, size));
    }

    @Operation(summary = "[운영자] 회원 상세 (ADM-1-1)",
            description = "회원 정보 전부(소셜 ID · 신체 정보 포함)와 항목마다 가장 최근 약관 동의. "
                    + "신체 정보는 입력하지 않았거나 동의를 껐으면 null. 없거나 탈퇴한 회원 MEMBER-011.")
    @GetMapping("/{memberId}")
    ApiResult<AdminMemberDetail> detail(@PathVariable UUID memberId) {
        return ApiResult.success(service.detail(memberId));
    }
}
