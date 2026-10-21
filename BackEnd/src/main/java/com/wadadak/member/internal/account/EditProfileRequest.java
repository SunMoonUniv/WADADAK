package com.wadadak.member.internal.account;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * MY 프로필 편집(F6) 저장. 화면의 값을 통째로 보낸다. 칸마다 규칙은 가입(F2)과 같다.
 *
 * @param regionCode      활동 지역(시·군·구) 법정동 코드. 바꾸면 다음 주부터 지역 주간 랭킹에 반영된다(정책 공통 6)
 * @param profileImageKey 사진을 그대로 두려면 내 정보의 {@code profileImageKey}, 새 사진이면 업로드 폼으로 올린 키,
 *                        사진을 지우면 {@code null}
 * @param bodyInfo        신체 정보. 동의를 끄면 {@code null}이고 저장된 값이 지워진다(정책 공통 9)
 */
record EditProfileRequest(
        @NotBlank @Size(min = 2, max = 10) @Pattern(regexp = "^[가-힣a-zA-Z0-9]+$", message = "한글·영문·숫자만 쓸 수 있습니다")
        String nickname,
        @Size(max = 50) String bio,
        @NotBlank @Pattern(regexp = "^\\d{10}$", message = "법정동 코드 10자리여야 합니다") String regionCode,
        @Size(max = 30) String affiliation,
        @NotNull RunningExperience runningExperience,
        @Size(max = 100) String profileImageKey,
        @Valid BodyInfo bodyInfo) { // @Valid: BodyInfo 안의 범위 검사(키 100~250 등)까지 한다
}
