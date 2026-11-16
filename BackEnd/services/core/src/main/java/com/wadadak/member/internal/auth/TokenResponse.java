package com.wadadak.member.internal.auth;

import java.time.Instant;

record TokenResponse(String accessToken, Instant accessTokenExpiresAt, String refreshToken, Instant refreshTokenExpiresAt) {
}
