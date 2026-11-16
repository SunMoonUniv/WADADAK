package com.wadadak.notification.internal.push;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * FCM HTTP v1 요청 모양과 오류 처리. 실제 FCM 대신 가짜 서버({@link MockRestServiceServer})가 답한다.
 * 오류 본문은 FCM 문서의 모양 그대로다.
 */
class FcmPushSenderTest {

    private static final String SEND_URL = "https://fcm.googleapis.com/v1/projects/wadadak-test/messages:send";
    private static final PushMessage MESSAGE = new PushMessage("내 코스 만료 임박", "‘한강’ 코스가 내일 만료돼요.",
            Map.of("type", "COURSE_EXPIRING_SOON", "courseId", "c-1"));

    private MockRestServiceServer fcm;
    private FcmPushSender sender;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder();
        fcm = MockRestServiceServer.bindTo(builder).build();
        sender = new FcmPushSender(builder, "wadadak-test", () -> "access-1", JsonMapper.builder().build());
    }

    @Test
    void sendsTheMessageWithTheAccessToken() {
        fcm.expect(requestTo(SEND_URL))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer access-1"))
                .andExpect(jsonPath("$.message.token").value("device-1"))
                .andExpect(jsonPath("$.message.notification.title").value("내 코스 만료 임박"))
                .andExpect(jsonPath("$.message.notification.body").value("‘한강’ 코스가 내일 만료돼요."))
                .andExpect(jsonPath("$.message.data.type").value("COURSE_EXPIRING_SOON"))
                .andExpect(jsonPath("$.message.data.courseId").value("c-1"))
                .andRespond(withSuccess("{\"name\": \"projects/wadadak-test/messages/1\"}", MediaType.APPLICATION_JSON));

        assertThat(sender.send("device-1", MESSAGE)).isEqualTo(PushResult.sent());
        fcm.verify();
    }

    @Test
    void anUnregisteredTokenIsForgotten() {
        respond(HttpStatus.NOT_FOUND, error(404, "NOT_FOUND", "UNREGISTERED"));

        assertThat(sender.send("device-1", MESSAGE).outcome()).isEqualTo(PushResult.Outcome.INVALID_TOKEN);
    }

    @Test
    void aTokenOfAnotherFirebaseProjectIsForgotten() {
        respond(HttpStatus.FORBIDDEN, error(403, "PERMISSION_DENIED", "SENDER_ID_MISMATCH"));

        assertThat(sender.send("device-1", MESSAGE).outcome()).isEqualTo(PushResult.Outcome.INVALID_TOKEN);
    }

    @Test
    void aBadMessageIsNotRetriedAndKeepsTheToken() {
        respond(HttpStatus.BAD_REQUEST, error(400, "INVALID_ARGUMENT", "INVALID_ARGUMENT"));

        PushResult result = sender.send("device-1", MESSAGE);

        assertThat(result.outcome()).isEqualTo(PushResult.Outcome.REJECTED);
        assertThat(result.reason()).isEqualTo("400 INVALID_ARGUMENT");
    }

    @Test
    void temporaryProblemsAreRetried() {
        assertRetried(HttpStatus.SERVICE_UNAVAILABLE, error(503, "UNAVAILABLE", "UNAVAILABLE"));
        assertRetried(HttpStatus.TOO_MANY_REQUESTS, error(429, "RESOURCE_EXHAUSTED", "QUOTA_EXCEEDED"));
        assertRetried(HttpStatus.INTERNAL_SERVER_ERROR, "");
    }

    @Test
    void aSetupProblemDoesNotDeleteTokens() {
        // 서비스 계정에 권한이 없다(FcmError 없음). 토큰 잘못이 아니라 설정 잘못이라 지우지 않고 나중에 다시
        assertRetried(HttpStatus.FORBIDDEN, "{\"error\": {\"code\": 403, \"status\": \"PERMISSION_DENIED\"}}");
        // 주소(프로젝트 ID)가 틀렸다. FcmError 없이 404만 온다. 역시 토큰을 지우지 않는다
        setUp();
        respond(HttpStatus.NOT_FOUND, "{\"error\": {\"code\": 404, \"status\": \"NOT_FOUND\"}}");
        assertThat(sender.send("device-1", MESSAGE).outcome()).isEqualTo(PushResult.Outcome.REJECTED);
    }

    @Test
    void noAccessTokenMeansTryAgainLater() {
        FcmPushSender noToken = new FcmPushSender(RestClient.builder(), "wadadak-test", () -> {
            throw new IOException("oauth2.googleapis.com에 연결하지 못함");
        }, JsonMapper.builder().build());

        PushResult result = noToken.send("device-1", MESSAGE);

        assertThat(result.outcome()).isEqualTo(PushResult.Outcome.RETRY_LATER);
        assertThat(result.reason()).contains("액세스 토큰");
    }

    private void assertRetried(HttpStatus status, String body) {
        setUp();
        respond(status, body);
        assertThat(sender.send("device-1", MESSAGE).outcome()).as(status + " " + body).isEqualTo(PushResult.Outcome.RETRY_LATER);
    }

    private void respond(HttpStatus status, String body) {
        fcm.expect(requestTo(SEND_URL)).andRespond(withStatus(status).contentType(MediaType.APPLICATION_JSON).body(body));
    }

    /** FCM 오류 본문. details에 FcmError가 있다 */
    private static String error(int code, String status, String errorCode) {
        return """
                {"error": {"code": %d, "message": "...", "status": "%s",
                  "details": [{"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode": "%s"}]}}"""
                .formatted(code, status, errorCode);
    }
}
