package com.wadadak.member.internal.auth;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.storage.PhotoUploads;
import com.wadadak.common.storage.UploadForm;
import com.wadadak.event.member.MemberRegionChangedEvent;
import com.wadadak.member.MemberErrorCode;
import com.wadadak.member.internal.account.Agreement;
import com.wadadak.member.internal.account.AgreementRepository;
import com.wadadak.member.internal.account.Member;
import com.wadadak.member.internal.account.MemberRepository;
import com.wadadak.member.internal.social.SocialAccount;
import com.wadadak.member.internal.social.SocialTokenVerifier;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
class AuthService {

    /** 프로필 사진 키 앞부분(개발 정책 7장 사진 업로드) */
    static final String PHOTO_MODULE = "member";

    private final MemberRepository memberRepository;
    private final AgreementRepository agreementRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final TokenProvider tokenProvider;
    private final SocialTokenVerifier socialTokenVerifier;
    private final RegionDirectory regions;
    private final PhotoUploads uploads;
    private final ApplicationEventPublisher events;
    private final Clock clock;

    /** 소셜 검증(외부 호출)은 트랜잭션 밖에서 한다. */
    LoginResponse login(LoginRequest request) {
        SocialAccount account = socialTokenVerifier.verify(request.provider(), request.token());
        return memberRepository.findBySocialProviderAndSocialId(account.provider(), account.socialId())
                .map(member -> LoginResponse.signedIn(issueTokens(member.getId())))
                .orElseGet(() -> LoginResponse.signupRequired(tokenProvider.signupToken(account)));
    }

    /** 가입 화면에서 프로필 사진을 올릴 폼. 가입 토큰이 만료됐으면 MEMBER-003, 너무 많이 받으면 COMMON-008. */
    UploadForm photoUploadForm(PhotoUploadRequest request) {
        return uploads.form(PHOTO_MODULE, uploader(tokenProvider.parseSignupToken(request.signupToken())));
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
        // FK가 없으니 시·도·읍·면·동이나 없는 코드를 여기서 막는다. 지역 주간 랭킹이 이 코드로 회원을 묶는다.
        if (regions.findSigungu(request.regionCode()).isEmpty()) {
            throw new AppException(MemberErrorCode.REGION_NOT_FOUND);
        }
        String photo = request.profileImageKey();
        // 사진 주소에 키가 보여서 남의 사진 키를 가져다 쓸 수 있다. 이 계정이 받은 폼의 키만, 한 번만 받는다(DB 유니크가 마지막 방어)
        if (photo != null && !uploads.claim(PHOTO_MODULE, uploader(account), List.of(photo))) {
            throw new AppException(MemberErrorCode.PROFILE_PHOTO_NOT_FOUND);
        }
        Member member = memberRepository.save(Member.join(account, request.nickname(), request.bio(),
                request.regionCode(), request.affiliation(), request.runningExperience(), photo));
        agreementRepository.saveAll(Agreement.agreeAll(member.getId()));
        events.publishEvent(new MemberRegionChangedEvent(UuidV7.create(), clock.instant(), member.getId(),
                member.getRegionCode(), null, member.getVersion()));
        return issueTokens(member.getId());
    }

    /** 리프레시 토큰은 한 번만 쓸 수 있다. 쓸 때마다 새 토큰으로 바꾼다. */
    @Transactional
    TokenResponse refresh(RefreshRequest request) {
        String hash = TokenProvider.hash(request.refreshToken());
        RefreshToken token = refreshTokenRepository.findByTokenHash(hash)
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

    /** 가입 사진 폼을 받는 사람. 가입 전이라 회원 ID 대신 소셜 계정으로 센다. */
    private static String uploader(SocialAccount account) {
        return account.provider() + ":" + account.socialId();
    }
}
