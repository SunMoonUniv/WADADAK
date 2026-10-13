package com.wadadak.common.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * 요청마다 한 줄: 메서드 · 경로(쿼리는 받은 그대로) · 상태 · 처리 시간 · 클라이언트 IP.
 * 공용 서버에서 앱이 어떤 요청에 어떤 응답을 받았는지 보려고 둔다({@code app.common.request-log.enabled}).
 * 인증 실패(401)도 남기게 보안 필터보다 먼저 돈다. {@code /actuator}는 상태 확인이 10초마다 와서 뺀다.
 */
@Slf4j
@Component
@ConditionalOnProperty(name = "app.common.request-log.enabled", havingValue = "true")
@Order(Ordered.HIGHEST_PRECEDENCE)
class RequestLogFilter extends OncePerRequestFilter {

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return request.getRequestURI().startsWith("/actuator");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        long start = System.nanoTime();
        boolean failed = true;
        try {
            chain.doFilter(request, response);
            failed = false;
        } finally {
            String query = request.getQueryString();
            log.info("{} {}{} {} {}ms {}", request.getMethod(), request.getRequestURI(), query == null ? "" : "?" + query,
                    failed ? 500 : response.getStatus(), (System.nanoTime() - start) / 1_000_000, request.getRemoteAddr());
        }
    }
}
