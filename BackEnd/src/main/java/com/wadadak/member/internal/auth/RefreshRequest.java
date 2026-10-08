package com.wadadak.member.internal.auth;

import jakarta.validation.constraints.NotBlank;

record RefreshRequest(@NotBlank String refreshToken) {
}
