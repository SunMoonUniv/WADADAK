package com.wadadak.common.region;

import com.wadadak.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 시드 마이그레이션이 적용된 DB에서 확인한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RegionControllerTest {

    @Autowired
    MockMvcTester mvc;

    @Test
    void searchesSigunguWithoutLogin() {
        MvcTestResult result = mvc.get().uri("/api/v1/regions").param("query", "성북").exchange();

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data[0].code").isEqualTo("1129000000");
        assertThat(result).bodyJson().extractingPath("$.data[0].name").isEqualTo("성북구");
        assertThat(result).bodyJson().extractingPath("$.data[0].fullName").isEqualTo("서울특별시 성북구");
    }

    @Test
    void doesNotCheckTokens() {
        assertThat(mvc.get().uri("/api/v1/regions").param("query", "아산")
                .header(HttpHeaders.AUTHORIZATION, "Bearer expired-or-broken"))
                .hasStatusOk()
                .bodyJson().extractingPath("$.data[0].code").isEqualTo("4420000000");
    }

    @Test
    void rejectsBlankOrLongQuery() {
        for (String query : new String[]{" ", "가".repeat(21)}) {
            assertThat(mvc.get().uri("/api/v1/regions").param("query", query))
                    .hasStatus(HttpStatus.BAD_REQUEST)
                    .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
        }
    }

    @Test
    void servesSwaggerGroup() {
        assertThat(mvc.get().uri("/v3/api-docs/region")).hasStatusOk().bodyText().contains("/api/v1/regions");
    }
}
