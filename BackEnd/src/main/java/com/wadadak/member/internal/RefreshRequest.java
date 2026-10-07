package com.wadadak.member.internal;

import jakarta.validation.constraints.NotBlank;

record RefreshRequest(@NotBlank String refreshToken) {
}
