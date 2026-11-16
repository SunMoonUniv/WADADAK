package com.wadadak;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.HttpStatus;
import org.springframework.security.converter.RsaKeyConverters;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

import java.security.interfaces.RSAPrivateKey;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class WadadakApplicationTests {

    @Autowired
    MockMvcTester mvc;

    @Test
    void rejectsRequestWithoutToken() {
        assertThat(mvc.get().uri("/api/v1/anything"))
                .hasStatus(HttpStatus.UNAUTHORIZED)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-002");
    }

    @Test
    void acceptsTokenSignedWithPrivateKey() throws Exception {
        // 인증을 통과하면 없는 경로라 404가 된다.
        assertThat(mvc.get().uri("/api/v1/anything").header("Authorization", "Bearer " + token()))
                .hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-004");
    }

    @Test
    void servesOpenApiWithoutToken() {
        assertThat(mvc.get().uri("/v3/api-docs")).hasStatusOk();
    }

    private static String token() throws Exception {
        RSAPrivateKey key = RsaKeyConverters.pkcs8()
                .convert(new ClassPathResource("jwt/test-private.pem").getInputStream());
        SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.RS256), new JWTClaimsSet.Builder()
                .subject(UUID.randomUUID().toString())
                .audience("wadadak")
                .expirationTime(Date.from(Instant.now().plusSeconds(60)))
                .build());
        jwt.sign(new RSASSASigner(key));
        return jwt.serialize();
    }
}
