package com.wadadak.member.internal;

import java.time.Instant;

record TokenResponse(String accessToken, Instant accessTokenExpiresAt, String refreshToken, Instant refreshTokenExpiresAt) {
}
