package com.wadadak.member.internal.auth;

import com.wadadak.member.internal.account.RunningExperience;
import jakarta.validation.Valid;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 소셜 정보 동의 + F2 프로필 초기 설정.
 *
 * @param regionCode      활동 지역(시·군·구) 법정동 코드
 * @param profileImageKey 가입 사진 업로드 폼으로 올린 키. 선택
 */
record SignupRequest(
        @NotBlank String signupToken,
        @NotNull @Valid Agreements agreements,
        @NotBlank @Size(min = 2, max = 10) @Pattern(regexp = "^[가-힣a-zA-Z0-9]+$", message = "한글·영문·숫자만 쓸 수 있습니다")
        String nickname,
        @Size(max = 50) String bio,
        @NotBlank @Pattern(regexp = "^\\d{10}$", message = "법정동 코드 10자리여야 합니다") String regionCode,
        @Size(max = 30) String affiliation,
        @NotNull RunningExperience runningExperience,
        @Size(max = 100) String profileImageKey) {

    /** 모두 필수라 true여야 한다. */
    record Agreements(
            @AssertTrue boolean over14,
            @AssertTrue boolean serviceTerms,
            @AssertTrue boolean privacyPolicy,
            @AssertTrue boolean locationTerms,
            @AssertTrue boolean profileInfo) {
    }
}
