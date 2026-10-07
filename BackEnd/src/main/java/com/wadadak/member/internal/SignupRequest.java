package com.wadadak.member.internal;

import jakarta.validation.Valid;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 소셜 정보 동의 + F2 프로필 초기 설정. 프로필 사진은 업로드 기능과 함께 추가한다.
 *
 * @param regionCode 활동 지역(시·군·구) 법정동 코드
 */
record SignupRequest(
        @NotBlank String signupToken,
        @NotNull @Valid Agreements agreements,
        @NotBlank @Size(min = 2, max = 10) @Pattern(regexp = "^[가-힣a-zA-Z0-9]+$", message = "한글·영문·숫자만 쓸 수 있습니다")
        String nickname,
        @Size(max = 50) String bio,
        @NotBlank @Pattern(regexp = "^\\d{10}$", message = "법정동 코드 10자리여야 합니다") String regionCode,
        @Size(max = 30) String affiliation,
        @NotNull RunningExperience runningExperience) {

    /** 필수 5개는 모두 true여야 한다. {@code email}만 선택. */
    record Agreements(
            @AssertTrue boolean over14,
            @AssertTrue boolean serviceTerms,
            @AssertTrue boolean privacyPolicy,
            @AssertTrue boolean locationTerms,
            @AssertTrue boolean profileInfo,
            boolean email) {
    }
}
