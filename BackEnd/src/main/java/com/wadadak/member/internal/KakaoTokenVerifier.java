package com.wadadak.member.internal;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.wadadak.common.exception.AppException;
import com.wadadak.member.MemberErrorCode;
import org.springframework.http.HttpHeaders;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

/**
 * 카카오 액세스 토큰 검증. 다른 앱에서 발급된 토큰으로 로그인하지 못하게 {@code app_id}를 대조한다.
 */
class KakaoTokenVerifier {

    private final RestClient restClient;
    private final long appId;

    KakaoTokenVerifier(RestClient.Builder builder, long appId) {
        this.restClient = builder.baseUrl("https://kapi.kakao.com").build();
        this.appId = appId;
    }

    SocialAccount verify(String accessToken) {
        try {
            TokenInfo info = get("/v1/user/access_token_info", accessToken, TokenInfo.class);
            if (info == null || info.appId() != appId) {
                throw new AppException(MemberErrorCode.INVALID_SOCIAL_TOKEN);
            }
            UserMe me = get("/v2/user/me", accessToken, UserMe.class);
            String email = me == null || me.kakaoAccount() == null ? null : me.kakaoAccount().email();
            return new SocialAccount(SocialProvider.KAKAO, String.valueOf(info.id()), email);
        } catch (HttpClientErrorException e) {
            throw new AppException(MemberErrorCode.INVALID_SOCIAL_TOKEN);
        }
    }

    private <T> T get(String uri, String accessToken, Class<T> type) {
        return restClient.get().uri(uri)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                .retrieve()
                .body(type);
    }

    record TokenInfo(long id, @JsonProperty("app_id") long appId) {
    }

    record UserMe(@JsonProperty("kakao_account") KakaoAccount kakaoAccount) {
    }

    record KakaoAccount(String email) {
    }
}
