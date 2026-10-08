package com.wadadak.member.internal.social;

import com.wadadak.common.stub.StubImplementation;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * 키·계정 없이 로컬에서 로그인한다. 토큰 문자열을 그대로 소셜 ID로 쓴다.
 * {@link StubImplementation}이라 prod 프로필에서는 기동이 실패한다.
 */
@Component
@ConditionalOnProperty(name = "app.member.social.fake", havingValue = "true")
class FakeSocialTokenVerifier implements SocialTokenVerifier, StubImplementation {

    @Override
    public SocialAccount verify(SocialProvider provider, String token) {
        return new SocialAccount(provider, token, null);
    }
}
