package com.wadadak.member.internal.auth;

import com.wadadak.common.exception.AppException;
import com.wadadak.member.MemberErrorCode;
import com.wadadak.member.internal.account.Member;
import com.wadadak.member.internal.account.MemberRepository;
import com.wadadak.member.internal.social.SocialAccount;
import com.wadadak.member.internal.social.SocialTokenVerifier;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

@Service
@RequiredArgsConstructor
class AuthService {

    private final MemberRepository memberRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final TokenProvider tokenProvider;
    private final SocialTokenVerifier socialTokenVerifier;
    private final Clock clock;

    /** 소셜 검증(외부 호출)은 트랜잭션 밖에서 한다. */
    LoginResponse login(LoginRequest request) {
        SocialAccount account = socialTokenVerifier.verify(request.provider(), request.token());
        return memberRepository.findBySocialProviderAndSocialId(account.provider(), account.socialId())
                .map(member -> LoginResponse.signedIn(issueTokens(member.getId())))
                .orElseGet(() -> LoginResponse.signupRequired(tokenProvider.signupToken(account)));
    }

    @Transactional
    TokenResponse signup(SignupRequest request) {
        SocialAccount account = tokenProvider.parseSignupToken(request.signupToken());
        if (memberRepository.findBySocialProviderAndSocialId(account.provider(), account.socialId()).isPresent()) {
            throw new AppException(MemberErrorCode.ALREADY_REGISTERED);
        }
        if (memberRepository.existsByNicknameIgnoreCase(request.nickname())) {
            throw new AppException(MemberErrorCode.NICKNAME_TAKEN);
        }
        String email = request.agreements().email() ? account.email() : null;
        Member member = memberRepository.save(Member.join(account, email, request.nickname(), request.bio(),
                request.regionCode(), request.affiliation(), request.runningExperience(), clock.instant()));
        return issueTokens(member.getId());
    }

    /** 리프레시 토큰은 한 번만 쓸 수 있다. 쓸 때마다 새 토큰으로 바꾼다. */
    @Transactional
    TokenResponse refresh(RefreshRequest request) {
        String hash = TokenProvider.hash(request.refreshToken());
        RefreshToken token = refreshTokenRepository.findById(hash)
                .filter(t -> t.getExpiresAt().isAfter(clock.instant()))
                .orElseThrow(() -> new AppException(MemberErrorCode.INVALID_REFRESH_TOKEN));
        if (refreshTokenRepository.deleteByTokenHash(hash) == 0) {
            throw new AppException(MemberErrorCode.INVALID_REFRESH_TOKEN);
        }
        Member member = memberRepository.findById(token.getMemberId())
                .filter(m -> !m.isWithdrawn())
                .orElseThrow(() -> new AppException(MemberErrorCode.INVALID_REFRESH_TOKEN));
        return issueTokens(member.getId());
    }

    /** 액세스 토큰은 만료(1시간)까지 유효하다. 기기의 토큰을 지우는 것은 앱이 한다. */
    @Transactional
    void logout(RefreshRequest request) {
        refreshTokenRepository.deleteByTokenHash(TokenProvider.hash(request.refreshToken()));
    }

    private TokenResponse issueTokens(UUID memberId) {
        Instant now = clock.instant();
        String refreshToken = tokenProvider.newRefreshToken();
        Instant refreshExpiresAt = now.plus(TokenProvider.REFRESH_TTL);
        refreshTokenRepository.save(new RefreshToken(TokenProvider.hash(refreshToken), memberId, refreshExpiresAt));
        return new TokenResponse(tokenProvider.accessToken(memberId, now), now.plus(TokenProvider.ACCESS_TTL),
                refreshToken, refreshExpiresAt);
    }
}
