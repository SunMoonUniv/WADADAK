package com.wadadak;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.micrometer.metrics.test.autoconfigure.AutoConfigureMetrics;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 앱 지표(/actuator/prometheus). 운영 PC Prometheus가 토큰 없이 Tailscale로 읽는다. 밖에서는 게이트웨이가 막는다(deploy/Caddyfile).
 * 테스트는 기본으로 지표 내보내기를 끄므로 {@link AutoConfigureMetrics}로 운영과 같게 켠다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureMetrics
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class MetricsEndpointTests {

    @Autowired
    MockMvcTester mvc;

    @Test
    void servesPrometheusMetricsWithoutToken() {
        // 요청 지표(http_server_requests)는 요청이 한 번 있어야 생긴다
        assertThat(mvc.get().uri("/v3/api-docs")).hasStatusOk();

        assertThat(mvc.get().uri("/actuator/prometheus"))
                .hasStatusOk()
                .bodyText().contains("jvm_memory_used_bytes", "hikaricp_connections_active", "http_server_requests_seconds_bucket");
    }

    @Test
    void keepsOtherActuatorEndpointsClosed() {
        assertThat(mvc.get().uri("/actuator/env")).hasStatus4xxClientError();
    }
}
