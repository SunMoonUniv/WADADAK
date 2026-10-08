package com.wadadak.course.internal.registration;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/courses")
@RequiredArgsConstructor
class RegistrationController {

    private final RegistrationService registrationService;

    @Operation(summary = "사용자 지정 코스 등록 (B4-07)",
            description = "입력점으로 경로를 다시 만들어 검증하고 바로 공개한다. 같은 Idempotency-Key로 재요청하면 처음 결과를 돌려준다. "
                    + "이름 길이 COMMON-001, 입력점·거리 COURSE-003~005, 이름 중복 006, 85% 유사 007, 일일 한도 008(429), 출발점 지역 없음 009.")
    @PostMapping
    ApiResult<RegisteredCourse> register(
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(description = "등록 시도마다 앱이 만드는 UUID. 같은 등록을 재시도할 때는 같은 값") @RequestHeader("Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody RegisterCourseRequest request) {
        return ApiResult.success(registrationService.registerCustom(UUID.fromString(jwt.getSubject()), idempotencyKey, request));
    }
}
