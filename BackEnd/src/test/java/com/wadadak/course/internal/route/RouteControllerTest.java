package com.wadadak.course.internal.route;

import com.wadadak.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RouteControllerTest {

    // 선문대 앞에서 북쪽으로 위도 0.0045도 ≈ 약 500m씩
    private static final String NORTH_1500M = """
            {"anchorPoints": [
              {"lat": 36.7990, "lng": 127.0750},
              {"lat": 36.8035, "lng": 127.0750},
              {"lat": 36.8035, "lng": 127.0750},
              {"lat": 36.8080, "lng": 127.0750},
              {"lat": 36.8125, "lng": 127.0750}
            ]}""";

    @Autowired
    MockMvcTester mvc;

    @Test
    void generatesStraightRouteWithKmMarkers() {
        MvcTestResult result = post(NORTH_1500M);

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.route.length()").isEqualTo(4);
        assertThat(result).bodyJson().extractingPath("$.data.route[0].lat").isEqualTo(36.7990);
        assertThat(result).bodyJson().extractingPath("$.data.distanceMeters").asNumber().satisfies(
                d -> assertThat(d.intValue()).isBetween(1490, 1510));
        assertThat(result).bodyJson().extractingPath("$.data.distanceMarkers.length()").isEqualTo(1);
        assertThat(result).bodyJson().extractingPath("$.data.distanceMarkers[0].km").isEqualTo(1);
        assertThat(result).bodyJson().extractingPath("$.data.distanceMarkers[0].point.lat").asNumber().satisfies(
                lat -> assertThat(lat.doubleValue()).isBetween(36.8075, 36.8085));
    }

    @Test
    void rejectsSinglePoint() {
        assertError(post("""
                {"anchorPoints": [{"lat": 36.7990, "lng": 127.0750}, {"lat": 36.7990, "lng": 127.0750}]}"""),
                HttpStatus.BAD_REQUEST, "COURSE-003");
    }

    @Test
    void rejectsShorterThan1km() {
        assertError(post("""
                {"anchorPoints": [{"lat": 36.7990, "lng": 127.0750}, {"lat": 36.8035, "lng": 127.0750}]}"""),
                HttpStatus.BAD_REQUEST, "COURSE-004");
    }

    @Test
    void rejectsLongerThan100km() {
        // 서울 시청 → 아산 약 90km → 다시 북쪽으로: 합계 100km 초과
        assertError(post("""
                {"anchorPoints": [{"lat": 37.5665, "lng": 126.9780}, {"lat": 36.7990, "lng": 127.0750},
                                  {"lat": 37.2000, "lng": 127.0750}]}"""),
                HttpStatus.BAD_REQUEST, "COURSE-005");
    }

    @Test
    void rejectsOutOfRangeCoordinate() {
        assertError(post("""
                {"anchorPoints": [{"lat": 127.0750, "lng": 36.7990}, {"lat": 36.8035, "lng": 127.0750}]}"""),
                HttpStatus.BAD_REQUEST, "COMMON-001");
    }

    @Test
    void requiresLogin() {
        assertThat(mvc.post().uri("/api/v1/courses/routes").contentType(MediaType.APPLICATION_JSON).content(NORTH_1500M))
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private MvcTestResult post(String body) {
        return mvc.post().uri("/api/v1/courses/routes").with(jwt())
                .contentType(MediaType.APPLICATION_JSON).content(body).exchange();
    }

    private static void assertError(MvcTestResult result, HttpStatus status, String code) {
        assertThat(result).hasStatus(status).bodyJson().extractingPath("$.code").isEqualTo(code);
    }
}
