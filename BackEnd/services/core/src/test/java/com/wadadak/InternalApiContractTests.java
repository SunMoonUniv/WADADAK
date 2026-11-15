package com.wadadak;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseApiHttpClient;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.ranking.GhostCandidate;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingApiHttpClient;
import com.wadadak.ranking.RankingPeriod;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Import;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.converter.RsaKeyConverters;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.io.InputStream;
import java.security.KeyFactory;
import java.security.interfaces.RSAPrivateCrtKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 내부 API 계약(MSA 분리 2단계, 개발 정책 11.3). HTTP 구현체로 자기 서버의 {@code /internal}을 불러
 * 직접 호출과 같은 값·같은 예외가 오는지 본다. 내부 API나 응답 DTO를 바꾸면 이 테스트가 그 PR에서 깨진다.
 * 서비스 로직이 아니라 HTTP 왕복을 보므로 스텁 구현({@code app.stub.course}·{@code app.stub.ranking})으로 띄운다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "app.common.internal-api.enabled=true", "app.stub.course=true", "app.stub.ranking=true"})
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class InternalApiContractTests {

    // CourseApiStub의 에러 확인용 ID
    private static final UUID COURSE_NOT_FOUND_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final UUID COURSE_NOT_AVAILABLE_ID = UUID.fromString("00000000-0000-0000-0000-000000000002");

    @LocalServerPort
    int port;

    @Autowired
    CourseApi courseApi;

    @Autowired
    RankingApi rankingApi;

    CourseApiHttpClient courseClient;
    RankingApiHttpClient rankingClient;
    UUID requesterId = UUID.randomUUID();

    @BeforeEach
    void setUp() throws Exception {
        String baseUrl = "http://localhost:" + port;
        courseClient = new CourseApiHttpClient(baseUrl, Duration.ofSeconds(5));
        rankingClient = new RankingApiHttpClient(baseUrl, Duration.ofSeconds(5));
        // 앱 요청을 처리하는 중인 것처럼: HTTP 구현체가 이 요청의 Authorization을 그대로 넘긴다
        MockHttpServletRequest appRequest = new MockHttpServletRequest();
        appRequest.addHeader(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken(requesterId));
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(appRequest));
    }

    @AfterEach
    void clearRequest() {
        RequestContextHolder.resetRequestAttributes();
    }

    @Test
    void courseRouteSameAsDirectCall() {
        UUID courseId = UUID.randomUUID();

        assertThat(courseClient.getRouteForRun(courseId)).isEqualTo(courseApi.getRouteForRun(courseId));
    }

    @Test
    void courseErrorsComeBackAsSameAppException() {
        assertThatThrownBy(() -> courseClient.getRouteForRun(COURSE_NOT_FOUND_ID))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CourseErrorCode.COURSE_NOT_FOUND));
        assertThatThrownBy(() -> courseClient.getRouteForRun(COURSE_NOT_AVAILABLE_ID))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CourseErrorCode.COURSE_NOT_AVAILABLE));
    }

    @Test
    void publicGhostCandidateSameAsDirectCallAndEmptyWhenNotCandidate() {
        UUID courseId = UUID.randomUUID();
        GhostCandidate first = rankingApi.getPublicGhostCandidates(courseId, RankingPeriod.ALL, requesterId, 1).getFirst();

        assertThat(rankingClient.findPublicGhostCandidate(courseId, RankingPeriod.ALL, requesterId, first.runRecordId()))
                .contains(first);
        assertThat(rankingClient.findPublicGhostCandidate(courseId, RankingPeriod.ALL, requesterId, UUID.randomUUID()))
                .isEmpty();
    }

    @Test
    void callOutsideAppRequestIsUnauthorized() {
        RequestContextHolder.resetRequestAttributes();

        assertThatThrownBy(() -> courseClient.getRouteForRun(UUID.randomUUID()))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CommonErrorCode.UNAUTHORIZED));
    }

    /** member의 TokenProvider와 같은 형식의 액세스 토큰(test 프로필 키) */
    private static String accessToken(UUID memberId) throws Exception {
        RSAPrivateCrtKey privateKey;
        try (InputStream in = new ClassPathResource("jwt/test-private.pem").getInputStream()) {
            privateKey = (RSAPrivateCrtKey) RsaKeyConverters.pkcs8().convert(in);
        }
        RSAPublicKey publicKey = (RSAPublicKey) KeyFactory.getInstance("RSA")
                .generatePublic(new RSAPublicKeySpec(privateKey.getModulus(), privateKey.getPublicExponent()));
        Instant now = Instant.now();
        JwtClaimsSet claims = JwtClaimsSet.builder().subject(memberId.toString()).audience(List.of("wadadak"))
                .issuedAt(now).expiresAt(now.plusSeconds(600)).build();
        return NimbusJwtEncoder.withKeyPair(publicKey, privateKey).build()
                .encode(JwtEncoderParameters.from(JwsHeader.with(SignatureAlgorithm.RS256).build(), claims)).getTokenValue();
    }
}
