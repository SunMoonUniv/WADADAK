package com.wadadak.notification.internal.device;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 기기 토큰 등록 요청 본문.
 *
 * @param token    FCM 등록 토큰(앱의 {@code FirebaseMessaging.getToken()}). 보통 150~200자다
 * @param platform 기기 종류
 */
record RegisterTokenRequest(@NotBlank @Size(max = 1024) String token, @NotNull DevicePlatform platform) {
}
