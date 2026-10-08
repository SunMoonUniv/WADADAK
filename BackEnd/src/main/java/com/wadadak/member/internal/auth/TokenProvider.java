package com.wadadak.member.internal.auth;

import com.wadadak.common.exception.AppException;
import com.wadadak.member.MemberErrorCode;
import com.wadadak.member.internal.social.SocialAccount;
import com.wadadak.member.internal.social.SocialProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.security.converter.RsaKeyConverters;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtAudienceValidator;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.security.interfaces.RSAPrivateCrtKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;

/**
 * member만 개인키로 토큰을 발급한다. 다른 모듈은 공개키로 검증만 한다(개발 정책 7장).
 * <ul>
 *   <li>액세스: JWT, {@code sub = memberId}, {@code aud = wadadak}</li>
 *   <li>가입: JWT, {@code aud = wadadak-signup}. 액세스 토큰으로는 거부된다(aud 불일치).</li>
 *   <li>리프레시: 임의 문자열. DB에는 해시만 둔다.</li>
 * </ul>
 */
@Component
class TokenProvider {

    /** 짧게 둬서 로그아웃 후 남은 토큰의 위험을 줄인다. 만료되면 앱이 리프레시 토큰으로 자동 갱신한다. */
    static final Duration ACCESS_TTL = Duration.ofHours(1);
    static final Duration REFRESH_TTL = Duration.ofDays(7);
    static final Duration SIGNUP_TTL = Duration.ofHours(1);

    static final String ACCESS_AUDIENCE = "wadadak";
    private static final String SIGNUP_AUDIENCE = "wadadak-signup";

    private final JwtEncoder encoder;
    private final NimbusJwtDecoder signupDecoder;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    TokenProvider(@Value("${app.member.jwt.private-key-location}") Resource privateKeyLocation, Clock clock)
            throws IOException, GeneralSecurityException {
        RSAPrivateCrtKey privateKey;
        try (InputStream in = privateKeyLocation.getInputStream()) {
            privateKey = (RSAPrivateCrtKey) RsaKeyConverters.pkcs8().convert(in);
        }
        RSAPublicKey publicKey = (RSAPublicKey) KeyFactory.getInstance("RSA")
                .generatePublic(new RSAPublicKeySpec(privateKey.getModulus(), privateKey.getPublicExponent()));
        this.encoder = NimbusJwtEncoder.withKeyPair(publicKey, privateKey).build();
        this.signupDecoder = NimbusJwtDecoder.withPublicKey(publicKey).build();
        this.signupDecoder.setJwtValidator(JwtValidators.createDefaultWithValidators(List.of(new JwtAudienceValidator(SIGNUP_AUDIENCE))));
        this.clock = clock;
    }

    String accessToken(UUID memberId, Instant now) {
        return encode(JwtClaimsSet.builder()
                .subject(memberId.toString())
                .audience(List.of(ACCESS_AUDIENCE))
                .issuedAt(now)
                .expiresAt(now.plus(ACCESS_TTL))
                .build());
    }

    String signupToken(SocialAccount account) {
        Instant now = clock.instant();
        JwtClaimsSet.Builder claims = JwtClaimsSet.builder()
                .subject(account.socialId())
                .audience(List.of(SIGNUP_AUDIENCE))
                .claim("provider", account.provider().name())
                .issuedAt(now)
                .expiresAt(now.plus(SIGNUP_TTL));
        if (account.email() != null) {
            claims.claim("email", account.email());
        }
        return encode(claims.build());
    }

    SocialAccount parseSignupToken(String token) {
        try {
            Jwt jwt = signupDecoder.decode(token);
            return new SocialAccount(SocialProvider.valueOf(jwt.getClaimAsString("provider")), jwt.getSubject(),
                    jwt.getClaimAsString("email"));
        } catch (JwtException | IllegalArgumentException e) {
            throw new AppException(MemberErrorCode.INVALID_SIGNUP_TOKEN);
        }
    }

    String newRefreshToken() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    static String hash(String refreshToken) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(refreshToken.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private String encode(JwtClaimsSet claims) {
        JwsHeader header = JwsHeader.with(SignatureAlgorithm.RS256).build();
        return encoder.encode(JwtEncoderParameters.from(header, claims)).getTokenValue();
    }
}
