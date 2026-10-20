package com.wadadak.member.internal.account;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * 내 정보 REST API(MY · F13). 로그인(JWT)한 본인 것만 다룬다. 토큰의 sub가 회원 ID다.
 *
 * <p>URL은 member 모듈 prefix {@code /api/v1/members} 아래 {@code /me}에 둔다(개발 정책 7장).
 */
@RestController // 메서드가 돌려준 값을 JSON 응답 본문으로 바꾼다
@RequestMapping("/api/v1/members/me")
@RequiredArgsConstructor
class MyAccountController {

    private final MyAccountService service;

    @Operation(summary = "내 정보 (E3 · F6 · F4)",
            description = "닉네임 · 한 줄 소개 · 활동 지역(region: code · name · fullName) · 소속 · 러닝 경력 · 프로필 사진 · "
                    + "신체 정보(입력하지 않았으면 null) · 연결된 소셜 계정 · 내 정보 공개 · 프로필 검색 허용. "
                    + "탈퇴했거나 없는 회원이면 COMMON-002.")
    @GetMapping
    ApiResult<MyProfile> me(@AuthenticationPrincipal Jwt jwt) {
        return ApiResult.success(service.me(memberId(jwt)));
    }

    @Operation(summary = "공개 설정 변경 (F4 공개 여부)",
            description = "infoPublic(내 정보 공개) · profileSearchable(프로필 검색 허용)을 둘 다 보낸다. 바뀐 내 정보를 돌려준다. "
                    + "내 정보 공개를 끄면 랭킹 목록 · 순위 계산 · 고스트 후보에서 빠지고, 다시 켜면 기존 기록이 그대로 보인다(정책 공통 6). "
                    + "프로필 검색 허용을 끄면 러너 검색(G7)에 나오지 않는다. 값이 빠지면 COMMON-001.")
    @PutMapping("/settings")
    ApiResult<MyProfile> changeSettings(@AuthenticationPrincipal Jwt jwt,
                                        @Valid @RequestBody MySettingsRequest request) { // @Valid: @NotNull 검사
        return ApiResult.success(service.changeSettings(memberId(jwt), request));
    }

    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
