package com.wadadak.member.internal;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/members/auth")
@RequiredArgsConstructor
class AuthController {

    private final AuthService authService;

    @Operation(summary = "소셜 로그인", description = "처음 로그인한 회원은 signupRequired와 signupToken(1시간)을 받는다.")
    @PostMapping("/login")
    ApiResult<LoginResponse> login(@Valid @RequestBody LoginRequest request) {
        return ApiResult.success(authService.login(request));
    }

    @Operation(summary = "가입", description = "소셜 정보 동의 + 프로필 초기 설정을 한 번에 보낸다.")
    @PostMapping("/signup")
    ApiResult<TokenResponse> signup(@Valid @RequestBody SignupRequest request) {
        return ApiResult.success(authService.signup(request));
    }

    @Operation(summary = "토큰 갱신", description = "보낸 리프레시 토큰은 폐기되고 새 토큰을 받는다.")
    @PostMapping("/refresh")
    ApiResult<TokenResponse> refresh(@Valid @RequestBody RefreshRequest request) {
        return ApiResult.success(authService.refresh(request));
    }

    @Operation(summary = "로그아웃", description = "리프레시 토큰을 폐기한다.")
    @PostMapping("/logout")
    ApiResult<Void> logout(@Valid @RequestBody RefreshRequest request) {
        authService.logout(request);
        return ApiResult.success();
    }
}
