package com.wadadak.member.internal.auth;

import com.wadadak.member.internal.social.SocialProvider;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/**
 * @param token 카카오는 액세스 토큰, Apple·Google은 ID 토큰
 */
record LoginRequest(@NotNull SocialProvider provider, @NotBlank String token) {
}
