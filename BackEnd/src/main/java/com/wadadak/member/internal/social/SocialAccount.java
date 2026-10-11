package com.wadadak.member.internal.social;

/** 소셜 토큰 검증 결과. 이메일 등 다른 계정 정보는 받지 않는다. */
public record SocialAccount(SocialProvider provider, String socialId) {
}
