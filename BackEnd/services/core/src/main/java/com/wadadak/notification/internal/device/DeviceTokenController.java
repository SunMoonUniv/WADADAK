package com.wadadak.notification.internal.device;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/** 기기 푸시 토큰 REST API(F14). 토큰의 sub가 회원 ID다 */
@RestController
@RequestMapping("/api/v1/notifications/tokens")
@RequiredArgsConstructor
class DeviceTokenController {

    private final DeviceTokenService service;

    @Operation(summary = "기기 토큰 등록 (F14)",
            description = "이 기기의 FCM 토큰을 내 기기로 등록한다. 로그인할 때 · 앱을 열 때 · 토큰이 바뀔 때 보낸다. "
                    + "같은 토큰을 다시 보내도 한 기기다(등록 시각만 새로 한다). 다른 계정이 쓰던 토큰이면 내 기기로 옮긴다. "
                    + "한 회원에 기기 10개까지 두고 넘으면 오래 등록하지 않은 기기부터 지운다. "
                    + "token이 비었거나 1024자를 넘음 · platform이 ANDROID · IOS가 아님 COMMON-001, 탈퇴한 회원 COMMON-002.")
    @PutMapping
    ApiResult<Void> register(@AuthenticationPrincipal Jwt jwt, @RequestBody @Valid RegisterTokenRequest request) {
        service.register(memberId(jwt), request);
        return ApiResult.success();
    }

    @Operation(summary = "기기 토큰 삭제 (F14 · F4 로그아웃)",
            description = "로그아웃하기 전에 보낸다. 이 기기에는 더 알림을 보내지 않는다. "
                    + "토큰은 주소에 남지 않게 본문으로 보낸다. 내 토큰이 아니거나 없으면 그냥 넘어간다. token이 비었으면 COMMON-001.")
    @DeleteMapping
    ApiResult<Void> remove(@AuthenticationPrincipal Jwt jwt, @RequestBody @Valid RemoveTokenRequest request) {
        service.remove(memberId(jwt), request);
        return ApiResult.success();
    }

    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
