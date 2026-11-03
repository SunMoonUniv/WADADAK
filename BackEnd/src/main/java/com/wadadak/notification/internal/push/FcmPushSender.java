package com.wadadak.notification.internal.push;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.ServiceAccountCredentials;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.InputStream;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.List;
import java.util.Map;

/**
 * FCM HTTP v1 API로 보낸다(개발 정책 1.2). 기기 하나에 요청 하나다.
 *
 * <p>[인증] Firebase 콘솔에서 받은 서비스 계정 키(JSON)로 Google에서 액세스 토큰(1시간짜리)을 받아
 * {@code Authorization: Bearer …}로 붙인다. 토큰 받기 · 갱신은 Google 인증 라이브러리가 한다.
 * 키는 공개 저장소라 커밋하지 않는다. 배포 비밀값으로 넣는다({@code app.notification.fcm.credentials-location}).
 *
 * <p>[오류] FCM은 실패 이유를 {@code error.details[].errorCode}로 준다. 없는 토큰(UNREGISTERED)만 토큰을 지우고,
 * 잠깐의 문제(점검 · 한도 · 연결)는 나중에 다시 보낸다. 설정 오류(권한 · 주소)로 토큰을 지우지 않게 조심한다.
 */
class FcmPushSender implements PushSender {

    /** FCM 보내기 권한. 서비스 계정 키로 이 권한의 액세스 토큰을 받는다 */
    static final String SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

    /** 지금 쓸 액세스 토큰을 준다. 시험에서는 고정 문자열을 주는 람다로 바꾼다 */
    @FunctionalInterface
    interface AccessTokens {
        String current() throws IOException;
    }

    private final RestClient rest;
    private final String sendPath;
    private final AccessTokens accessTokens;
    private final JsonMapper json;

    FcmPushSender(RestClient.Builder builder, String projectId, AccessTokens accessTokens, JsonMapper json) {
        this.rest = builder.baseUrl("https://fcm.googleapis.com").build();
        this.sendPath = "/v1/projects/" + projectId + "/messages:send";
        this.accessTokens = accessTokens;
        this.json = json;
    }

    /** 서비스 계정 키로 만든다. 키에 프로젝트 ID가 들어 있다. 키가 잘못됐으면 서버가 뜨지 않는다(조용히 못 보내는 것보다 낫다) */
    static FcmPushSender fromServiceAccount(Resource key, JsonMapper json) throws IOException {
        ServiceAccountCredentials account;
        try (InputStream in = key.getInputStream()) {
            account = ServiceAccountCredentials.fromStream(in);
        }
        if (account.getProjectId() == null) {
            throw new IllegalStateException("FCM 서비스 계정 키에 project_id가 없다");
        }
        GoogleCredentials scoped = account.createScoped(List.of(SCOPE));
        // 카카오 토큰 확인(member)과 같은 시간 제한. FCM이 멈춰도 발송 작업이 오래 붙잡히지 않는다
        JdkClientHttpRequestFactory timeouts = new JdkClientHttpRequestFactory(
                HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build());
        timeouts.setReadTimeout(Duration.ofSeconds(5));
        return new FcmPushSender(RestClient.builder().requestFactory(timeouts), account.getProjectId(), () -> {
            scoped.refreshIfExpired(); // 곧 만료되면 새로 받고, 아니면 갖고 있던 토큰을 그대로 쓴다
            return scoped.getAccessToken().getTokenValue();
        }, json);
    }

    @Override
    public PushResult send(String token, PushMessage message) {
        String accessToken;
        try {
            accessToken = accessTokens.current();
        } catch (IOException e) {
            return PushResult.retryLater("액세스 토큰을 받지 못함: " + e.getMessage());
        }
        try {
            rest.post().uri(sendPath)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(new SendRequest(new Message(token, new Notification(message.title(), message.body()), message.data())))
                    .retrieve()
                    .toBodilessEntity();
            return PushResult.sent();
        } catch (RestClientResponseException e) { // FCM이 오류로 답했다(4xx · 5xx)
            return classify(e.getStatusCode().value(), e.getResponseBodyAsString());
        } catch (ResourceAccessException e) { // 연결 실패 · 시간 초과
            return PushResult.retryLater("연결 실패: " + e.getMessage());
        }
    }

    /**
     * FCM 오류를 결과로 바꾼다(FCM 문서의 오류 코드 표).
     * errorCode가 없으면 HTTP 상태로 판단한다: 인증 · 권한 · 한도 · 서버 오류는 나중에 다시, 나머지는 포기.
     */
    PushResult classify(int status, String body) {
        String code = errorCode(body);
        String reason = status + " " + code;
        return switch (code) {
            case "UNREGISTERED", "SENDER_ID_MISMATCH" -> PushResult.invalidToken(reason);
            case "INVALID_ARGUMENT" -> PushResult.rejected(reason);
            case "QUOTA_EXCEEDED", "UNAVAILABLE", "INTERNAL", "THIRD_PARTY_AUTH_ERROR" -> PushResult.retryLater(reason);
            default -> status == 401 || status == 403 || status == 429 || status >= 500
                    ? PushResult.retryLater(reason)
                    : PushResult.rejected(reason);
        };
    }

    /** 오류 본문에서 FCM 오류 코드를 꺼낸다. {@code details}에 없으면 {@code error.status}, 그것도 없으면 빈 문자열 */
    private String errorCode(String body) {
        try {
            ErrorBody parsed = json.readValue(body, ErrorBody.class);
            if (parsed == null || parsed.error() == null) {
                return "";
            }
            if (parsed.error().details() != null) {
                for (ErrorDetail detail : parsed.error().details()) {
                    if (detail != null && detail.errorCode() != null) {
                        return detail.errorCode();
                    }
                }
            }
            return parsed.error().status() == null ? "" : parsed.error().status();
        } catch (JacksonException e) { // 본문이 비었거나 JSON이 아니다
            return "";
        }
    }

    /** 보내는 본문 {@code {"message": {"token": …, "notification": {…}, "data": {…}}}} */
    record SendRequest(Message message) {
    }

    record Message(String token, Notification notification, Map<String, String> data) {
    }

    record Notification(String title, String body) {
    }

    /** 오류 본문 {@code {"error": {"code": 404, "status": "NOT_FOUND", "details": [{"errorCode": "UNREGISTERED"}]}}} */
    @JsonIgnoreProperties(ignoreUnknown = true)
    record ErrorBody(ErrorInfo error) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record ErrorInfo(String status, List<ErrorDetail> details) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record ErrorDetail(String errorCode) {
    }
}
