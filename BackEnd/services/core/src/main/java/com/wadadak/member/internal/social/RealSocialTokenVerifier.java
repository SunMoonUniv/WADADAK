package com.wadadak.member.internal.social;

import com.wadadak.common.config.HttpTimeouts;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.Duration;
import java.util.List;

@Component
@ConditionalOnProperty(name = "app.member.social.fake", havingValue = "false", matchIfMissing = true)
class RealSocialTokenVerifier implements SocialTokenVerifier {

    private final KakaoTokenVerifier kakao;
    private final IdTokenVerifier apple;
    private final IdTokenVerifier google;

    RealSocialTokenVerifier(@Value("${app.member.social.kakao-app-id}") long kakaoAppId,
                            @Value("${app.member.social.apple-client-ids}") List<String> appleClientIds,
                            @Value("${app.member.social.google-client-ids}") List<String> googleClientIds) {
        this.kakao = new KakaoTokenVerifier(RestClient.builder()
                .requestFactory(HttpTimeouts.requestFactory(Duration.ofSeconds(3), Duration.ofSeconds(5))), kakaoAppId);
        this.apple = IdTokenVerifier.apple(appleClientIds);
        this.google = IdTokenVerifier.google(googleClientIds);
    }

    @Override
    public SocialAccount verify(SocialProvider provider, String token) {
        return switch (provider) {
            case KAKAO -> kakao.verify(token);
            case APPLE -> apple.verify(token);
            case GOOGLE -> google.verify(token);
        };
    }
}
