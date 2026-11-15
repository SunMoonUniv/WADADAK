package com.wadadak.member.internal.auth;

import jakarta.validation.constraints.NotBlank;

/** 가입 전 프로필 사진 업로드 폼 요청. 로그인 전이라 가입 토큰으로 누구인지 확인한다. */
record PhotoUploadRequest(@NotBlank String signupToken) {
}
