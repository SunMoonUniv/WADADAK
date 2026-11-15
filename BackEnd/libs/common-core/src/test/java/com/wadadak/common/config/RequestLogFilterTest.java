package com.wadadak.common.config;

import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@ExtendWith(OutputCaptureExtension.class)
class RequestLogFilterTest {

    private final RequestLogFilter filter = new RequestLogFilter();

    @Test
    void logsMethodPathQueryStatusAndIp(CapturedOutput output) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/v1/regions");
        request.setQueryString("query=%EC%95%84%EC%82%B0");
        request.setRemoteAddr("203.0.113.7");

        filter.doFilter(request, new MockHttpServletResponse(),
                (req, res) -> ((HttpServletResponse) res).setStatus(401));

        assertThat(output).containsPattern("GET /api/v1/regions\\?query=%EC%95%84%EC%82%B0 401 \\d+ms 203\\.0\\.113\\.7");
    }

    @Test
    void logs500WhenChainThrows(CapturedOutput output) {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/v1/courses");

        assertThatThrownBy(() -> filter.doFilter(request, new MockHttpServletResponse(), (req, res) -> {
            throw new IllegalStateException("boom");
        })).isInstanceOf(IllegalStateException.class);

        assertThat(output).containsPattern("POST /api/v1/courses 500 \\d+ms");
    }

    @Test
    void skipsActuator(CapturedOutput output) throws Exception {
        filter.doFilter(new MockHttpServletRequest("GET", "/actuator/health"), new MockHttpServletResponse(),
                (req, res) -> {
                });

        assertThat(output).doesNotContain("/actuator/health");
    }
}
