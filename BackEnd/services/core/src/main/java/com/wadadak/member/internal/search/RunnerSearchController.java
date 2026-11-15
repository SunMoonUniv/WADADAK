package com.wadadak.member.internal.search;

import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/** 러너 검색 REST API(G7). 규칙은 {@link RunnerSearchService}. */
@RestController
@RequestMapping("/api/v1/members/search")
@RequiredArgsConstructor
class RunnerSearchController {

    private final RunnerSearchService service;

    @Operation(summary = "러너 검색 (G7)",
            description = "닉네임에 검색어(query)가 들어간 회원을 찾는다. 공백과 대소문자는 보지 않는다. "
                    + "프로필 검색 허용을 끈 회원 · 탈퇴 회원은 빠지고, 내 정보 비공개 회원은 나온다(프로필 표시는 그대로, 정책 공통 6). "
                    + "요청자 본인도 나오며 mine=true다. 앱은 내 행을 누르면 I3 대신 MY로 보낸다. "
                    + "정렬은 인기순(더미 프로필 방문자 수 많은 순, G7-04) 하나다. "
                    + "region은 활동 지역(시·군·구, 코드가 지역 목록에 없으면 null), runningExperience는 4단계(BEGINNER · MONTHS_6 · YEAR_1 · YEAR_3). "
                    + "주간 거리(\"주 32 km\")는 ranking의 GET /api/v1/rankings/distance/members에 이 쪽의 memberId를 모아 받는다. "
                    + "totalCount는 걸린 러너 수(`검색 결과 · N명`)다. "
                    + "검색어가 공백을 빼고 2글자 미만이거나 잘못된 cursor · size는 COMMON-001.")
    @GetMapping
    ApiResult<RunnerSearchResult> search(
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(description = "닉네임 검색어. 공백을 빼고 2글자 이상") @RequestParam String query,
            @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(service.search(query, UUID.fromString(jwt.getSubject()), page));
    }
}
