package com.wadadak.member.internal.social;

import com.wadadak.common.exception.AppException;
import com.wadadak.member.MemberErrorCode;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtClaimNames;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

import java.util.List;
import java.util.Set;

/**
 * Apple·Google ID 토큰(OIDC) 검증: 제공자 공개키 서명, 만료, 발급자, 우리 앱 client ID(aud).
 */
class IdTokenVerifier {

    private final SocialProvider provider;
    private final JwtDecoder decoder;

    IdTokenVerifier(SocialProvider provider, JwtDecoder decoder) {
        this.provider = provider;
        this.decoder = decoder;
    }

    static IdTokenVerifier apple(List<String> clientIds) {
        return new IdTokenVerifier(SocialProvider.APPLE, decoder("https://appleid.apple.com/auth/keys",
                Set.of("https://appleid.apple.com"), clientIds));
    }

    static IdTokenVerifier google(List<String> clientIds) {
        return new IdTokenVerifier(SocialProvider.GOOGLE, decoder("https://www.googleapis.com/oauth2/v3/certs",
                Set.of("https://accounts.google.com", "accounts.google.com"), clientIds));
    }

    static OAuth2TokenValidator<Jwt> validator(Set<String> issuers, List<String> clientIds) {
        return JwtValidators.createDefaultWithValidators(List.of(
                new JwtClaimValidator<Object>(JwtClaimNames.ISS, iss -> issuers.contains(String.valueOf(iss))),
                new JwtClaimValidator<List<String>>(JwtClaimNames.AUD,
                        aud -> aud != null && aud.stream().anyMatch(clientIds::contains))));
    }

    SocialAccount verify(String idToken) {
        try {
            Jwt jwt = decoder.decode(idToken);
            return new SocialAccount(provider, jwt.getSubject(), jwt.getClaimAsString("email"));
        } catch (JwtException e) {
            throw new AppException(MemberErrorCode.INVALID_SOCIAL_TOKEN);
        }
    }

    private static JwtDecoder decoder(String jwkSetUri, Set<String> issuers, List<String> clientIds) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();
        decoder.setJwtValidator(validator(issuers, clientIds));
        return decoder;
    }
}
