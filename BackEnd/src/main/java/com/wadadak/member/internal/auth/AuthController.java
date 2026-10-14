package com.wadadak.member.internal.auth;

import com.wadadak.common.response.ApiResult;
import com.wadadak.common.storage.UploadForm;
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

    @Operation(summary = "가입", description = "소셜 정보 동의 + 프로필 초기 설정을 한 번에 보낸다. "
            + "활동 지역(regionCode)은 지역 검색(GET /api/v1/regions)으로 고른 시·군·구 코드다. 시·도·읍·면·동이나 없는 코드는 MEMBER-007. "
            + "프로필 사진은 선택이다. photo-uploads로 올린 키를 profileImageKey에 담는다. 올라오지 않았거나 이미 쓰는 키면 MEMBER-008.")
    @PostMapping("/signup")
    ApiResult<TokenResponse> signup(@Valid @RequestBody SignupRequest request) {
        return ApiResult.success(authService.signup(request));
    }

    @Operation(summary = "가입 프로필 사진 업로드 폼 (F2)",
            description = "로그인 전이라 가입 토큰으로 받는다(만료 MEMBER-003). 앱은 사진을 JPEG로 바꾸고 위치 등 EXIF를 지운 뒤, "
                    + "url에 multipart/form-data로 fields를 모두 넣고 파일을 마지막 file 필드로 붙여 POST한다(10분 안에, 50MB 이하, image/jpeg만). "
                    + "올린 뒤 key를 가입 요청의 profileImageKey에 담는다.")
    @PostMapping("/photo-uploads")
    ApiResult<UploadForm> photoUpload(@Valid @RequestBody PhotoUploadRequest request) {
        return ApiResult.success(authService.photoUploadForm(request));
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
