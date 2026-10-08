package com.wadadak.member.internal.social;

import com.wadadak.common.exception.AppException;
import com.wadadak.member.MemberErrorCode;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class KakaoTokenVerifierTest {

    private static final long APP_ID = 1234L;

    private final RestClient.Builder builder = RestClient.builder();
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    private final KakaoTokenVerifier verifier = new KakaoTokenVerifier(builder, APP_ID);

    @Test
    void returnsKakaoIdAndEmail() {
        server.expect(requestTo("https://kapi.kakao.com/v1/user/access_token_info"))
                .andExpect(header("Authorization", "Bearer token"))
                .andRespond(withSuccess("""
                        {"id": 42, "expires_in": 3600, "app_id": 1234}""", MediaType.APPLICATION_JSON));
        server.expect(requestTo("https://kapi.kakao.com/v2/user/me"))
                .andRespond(withSuccess("""
                        {"id": 42, "kakao_account": {"email": "runner@kakao.com", "is_email_valid": true}}""",
                        MediaType.APPLICATION_JSON));

        assertThat(verifier.verify("token")).isEqualTo(new SocialAccount(SocialProvider.KAKAO, "42", "runner@kakao.com"));
    }

    @Test
    void rejectsTokenIssuedToAnotherApp() {
        server.expect(requestTo("https://kapi.kakao.com/v1/user/access_token_info"))
                .andRespond(withSuccess("""
                        {"id": 42, "app_id": 9999}""", MediaType.APPLICATION_JSON));

        assertInvalid();
    }

    @Test
    void rejectsExpiredToken() {
        server.expect(requestTo("https://kapi.kakao.com/v1/user/access_token_info"))
                .andRespond(withStatus(HttpStatus.UNAUTHORIZED));

        assertInvalid();
    }

    private void assertInvalid() {
        assertThatThrownBy(() -> verifier.verify("token"))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(MemberErrorCode.INVALID_SOCIAL_TOKEN));
    }
}
