package com.wadadak.common.config;

import org.springframework.http.client.JdkClientHttpRequestFactory;

import java.net.http.HttpClient;
import java.time.Duration;

/** 외부 HTTP 호출의 시간 제한. 상대가 멈춰도 요청이 오래 붙잡히지 않게 {@code RestClient.builder().requestFactory(...)}에 건다. */
public final class HttpTimeouts {

    private HttpTimeouts() {
    }

    /** 연결 · 응답 각각 timeout까지 기다린다 */
    public static JdkClientHttpRequestFactory requestFactory(Duration timeout) {
        return requestFactory(timeout, timeout);
    }

    public static JdkClientHttpRequestFactory requestFactory(Duration connect, Duration read) {
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(connect).build());
        factory.setReadTimeout(read);
        return factory;
    }
}
