package com.wadadak.member.internal.account;

import com.wadadak.common.response.ApiResult;
import com.wadadak.common.storage.UploadForm;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
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
            description = "닉네임 · 한 줄 소개 · 활동 지역(region: code · name · fullName) · 소속 · 러닝 경력 · 프로필 사진(key · url) · "
                    + "신체 정보(입력하지 않았으면 null) · 연결된 소셜 계정 · 내 정보 공개 · 프로필 검색 허용. "
                    + "nicknameChangeableAt은 닉네임을 다시 바꿀 수 있는 시각(F6 \"다음 변경 가능\")이고 지금 바꿀 수 있으면 null. "
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

    @Operation(summary = "프로필 편집 저장 (F6)",
            description = "화면의 값을 통째로 보낸다. 칸 규칙은 가입(F2)과 같다. 바뀐 내 정보를 돌려준다. "
                    + "닉네임은 바꾼 날(Asia/Seoul)부터 30일 뒤 00:00에 다시 바꿀 수 있다(MEMBER-010). 가입 뒤 첫 변경은 바로 된다. "
                    + "대소문자만 다른 남의 닉네임은 MEMBER-006. 활동 지역이 시·군·구가 아니면 MEMBER-007. "
                    + "profileImageKey: 그대로 두려면 내 정보의 profileImageKey, 새 사진이면 업로드 폼으로 올린 키(아니면 MEMBER-008), "
                    + "지우면 null. 바꾸거나 지운 예전 사진 파일은 지운다. "
                    + "bodyInfo: 동의를 끄면 null이고 저장된 신체 정보가 지워진다. 출생연도가 범위 밖이면 MEMBER-009. "
                    + "활동 지역을 바꾸면 다음 주(월요일 00:00)부터 지역 주간 랭킹에 반영된다.")
    @PutMapping
    ApiResult<MyProfile> editProfile(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody EditProfileRequest request) {
        return ApiResult.success(service.editProfile(memberId(jwt), request));
    }

    @Operation(summary = "프로필 사진 업로드 폼 (F6 사진 변경)",
            description = "가입 때 사진 폼과 같은 방식이다. 앱은 사진을 JPEG로 바꾸고 위치 등 EXIF를 지운 뒤, "
                    + "url에 multipart/form-data로 fields를 모두 넣고 파일을 마지막 file 필드로 붙여 POST한다(10분 안에, 50MB 이하, image/jpeg만). "
                    + "올린 뒤 key를 프로필 편집 저장의 profileImageKey에 담는다. 1시간 안에 저장하지 않으면 파일이 지워진다. "
                    + "받고 저장하지 않은 폼이 최근 1시간에 20개면 COMMON-008(429).")
    @PostMapping("/photo-uploads")
    ApiResult<UploadForm> photoUpload(@AuthenticationPrincipal Jwt jwt) {
        return ApiResult.success(service.photoUploadForm(memberId(jwt)));
    }

    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
