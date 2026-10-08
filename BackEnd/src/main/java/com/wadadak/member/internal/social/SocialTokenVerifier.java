package com.wadadak.member.internal.social;

/**
 * 앱이 소셜 SDK로 받은 토큰을 검증한다. 실패하면 {@code MemberErrorCode.INVALID_SOCIAL_TOKEN}.
 * 로컬은 {@link FakeSocialTokenVerifier}({@code app.member.social.fake: true}), 운영은 {@link RealSocialTokenVerifier}.
 */
public interface SocialTokenVerifier {

    SocialAccount verify(SocialProvider provider, String token);
}
