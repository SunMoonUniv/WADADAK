package com.wadadak.member.internal;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.wadadak.common.exception.AppException;
import com.wadadak.member.MemberErrorCode;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.security.converter.RsaKeyConverters;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class IdTokenVerifierTest {

    private static final String ISSUER = "https://appleid.apple.com";
    private static final String CLIENT_ID = "com.wadadak.app";

    private final IdTokenVerifier verifier;

    IdTokenVerifierTest() throws Exception {
        RSAPublicKey publicKey = RsaKeyConverters.x509().convert(new ClassPathResource("jwt/test-public.pem").getInputStream());
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withPublicKey(publicKey).build();
        decoder.setJwtValidator(IdTokenVerifier.validator(Set.of(ISSUER), List.of(CLIENT_ID)));
        verifier = new IdTokenVerifier(SocialProvider.APPLE, decoder);
    }

    @Test
    void acceptsTokenForOurApp() throws Exception {
        SocialAccount account = verifier.verify(idToken(ISSUER, CLIENT_ID));

        assertThat(account).isEqualTo(new SocialAccount(SocialProvider.APPLE, "apple-user", "runner@example.com"));
    }

    @Test
    void rejectsTokenIssuedToAnotherApp() {
        assertThatThrownBy(() -> verifier.verify(idToken(ISSUER, "com.other.app")))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(MemberErrorCode.INVALID_SOCIAL_TOKEN));
    }

    @Test
    void rejectsTokenFromAnotherIssuer() {
        assertThatThrownBy(() -> verifier.verify(idToken("https://evil.example.com", CLIENT_ID)))
                .isInstanceOf(AppException.class);
    }

    private static String idToken(String issuer, String audience) throws Exception {
        RSAPrivateKey key = RsaKeyConverters.pkcs8().convert(new ClassPathResource("jwt/test-private.pem").getInputStream());
        SignedJWT jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.RS256), new JWTClaimsSet.Builder()
                .issuer(issuer)
                .audience(audience)
                .subject("apple-user")
                .claim("email", "runner@example.com")
                .expirationTime(Date.from(Instant.now().plusSeconds(60)))
                .build());
        jwt.sign(new RSASSASigner(key));
        return jwt.serialize();
    }
}
