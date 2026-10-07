package com.wadadak.member.internal;

/** 소셜 토큰 검증 결과. {@code email}은 제공되지 않으면 {@code null}. */
record SocialAccount(SocialProvider provider, String socialId, String email) {
}
