package com.wadadak.notification.internal.setting;

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

/** 알림 설정 REST API(F4 `알림`). 토큰의 sub가 회원 ID다 */
@RestController
@RequestMapping("/api/v1/notifications/settings")
@RequiredArgsConstructor
class NotificationSettingController {

    private final NotificationSettingService service;

    @Operation(summary = "알림 설정 (F4)",
            description = "courseExpiringSoon: `내 코스 만료 임박`. 한 번도 바꾸지 않았으면 켜져 있다(true). 탈퇴한 회원 COMMON-002.")
    @GetMapping
    ApiResult<NotificationSettings> get(@AuthenticationPrincipal Jwt jwt) {
        return ApiResult.success(service.get(memberId(jwt)));
    }

    @Operation(summary = "알림 설정 변경 (F4)",
            description = "바꾸는 즉시 저장하고 바꾼 설정을 돌려준다. 끄면 그 뒤에 만드는 알림부터 보내지 않는다. "
                    + "courseExpiringSoon이 없으면 COMMON-001, 탈퇴한 회원 COMMON-002.")
    @PutMapping
    ApiResult<NotificationSettings> change(@AuthenticationPrincipal Jwt jwt,
                                           @RequestBody @Valid NotificationSettings request) {
        return ApiResult.success(service.change(memberId(jwt), request));
    }

    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
