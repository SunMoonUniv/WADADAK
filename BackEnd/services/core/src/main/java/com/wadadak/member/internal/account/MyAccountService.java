package com.wadadak.member.internal.account;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.common.storage.PhotoUploads;
import com.wadadak.common.storage.UploadForm;
import com.wadadak.event.member.MemberRegionChangedEvent;
import com.wadadak.event.member.MemberVisibilityChangedEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import com.wadadak.member.MemberErrorCode;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;

/**
 * 내 정보 조회와 MY 설정(F13). 앱만 부르는 기능이라 다른 모듈용 {@link com.wadadak.member.MemberApi}와 따로 둔다.
 *
 * <p>[흐름] 컨트롤러(HTTP 요청) → 이 서비스(회원 확인·규칙 확인·변경·이벤트) → 저장소(DB).
 * 규칙에 어긋나면 {@link AppException}을 던지고, GlobalExceptionHandler가 에러 코드(MEMBER-010 등)로 응답한다.
 */
@Service
@RequiredArgsConstructor
class MyAccountService {

    private final MemberRepository memberRepository;
    private final AgreementRepository agreementRepository;
    private final RegionDirectory regions;
    private final ObjectStorage storage;
    private final PhotoUploads uploads;
    private final ApplicationEventPublisher events; // 스프링 이벤트 발행기. 다른 모듈에 "공개 설정·활동 지역이 바뀌었다"를 알린다
    private final Clock clock; // 지금 시각. 테스트에서 시각을 고정할 수 있게 직접 now()를 부르지 않는다

    @Transactional(readOnly = true)
    MyProfile me(UUID memberId) {
        return view(active(memberRepository.findById(memberId)));
    }

    /*
     * @Transactional: 설정 변경과 이벤트 발행 기록을 한 트랜잭션으로 묶는다. 저장이 성공했을 때만 ranking에 전달된다
     * (Modulith 아웃박스, 개발 정책 5.1·5.3).
     */
    @Transactional
    MyProfile changeSettings(UUID memberId, MySettingsRequest request) {
        Member member = active(memberRepository.findLockedById(memberId));
        if (member.changeSettings(request.infoPublic(), request.profileSearchable())) {
            // flush: UPDATE를 지금 보내 @Version을 올린다. 이벤트에 올라간 버전을 실어야
            // 받는 쪽이 늦게 도착한 옛 이벤트(작은 버전)를 버릴 수 있다(상태형 이벤트, 개발 정책 5.6)
            memberRepository.flush();
            events.publishEvent(new MemberVisibilityChangedEvent(UuidV7.create(), clock.instant(), member.getId(),
                    member.isInfoPublic(), member.getVersion()));
        }
        // 프로필 검색 허용은 다른 모듈이 복사해 두지 않아(러너 검색이 member를 직접 본다) 이벤트가 없다
        return view(member);
    }

    /** F6에서 새 프로필 사진을 올릴 폼. 너무 많이 받으면 COMMON-008. 올린 키는 프로필 편집 저장의 profileImageKey로 보낸다. */
    UploadForm photoUploadForm(UUID memberId) {
        return uploads.form(Member.PHOTO_MODULE, memberId.toString());
    }

    /**
     * MY 프로필 편집(F6) 저장.
     *
     * <p>확인 순서: 닉네임(30일 · 중복) → 활동 지역 → 출생연도 → 새 사진. 모두 통과하면 저장하고,
     * 바뀐 것에 따라 동의 이력 · 사진 파일 · 활동 지역 이벤트를 처리한다.
     */
    @Transactional
    MyProfile editProfile(UUID memberId, EditProfileRequest request) {
        Member member = active(memberRepository.findLockedById(memberId));
        Instant now = clock.instant();

        String nickname = request.nickname().strip();
        if (!nickname.equals(member.getNickname())) {
            Instant changeableAt = member.nicknameChangeableAt();
            if (changeableAt != null && now.isBefore(changeableAt)) {
                throw new AppException(MemberErrorCode.NICKNAME_CHANGE_TOO_SOON);
            }
            if (memberRepository.existsByNicknameIgnoreCaseAndIdNot(nickname, memberId)) {
                throw new AppException(MemberErrorCode.NICKNAME_TAKEN);
            }
        }
        BodyInfo body = request.bodyInfo();
        ProfileRules.check(regions, clock, request.regionCode(), body);
        String oldPhoto = member.getProfileImageKey();
        String photo = request.profileImageKey();
        // 새 사진은 내가 받은 폼으로 올린 키만, 한 번만 받는다(가입과 같은 규칙. DB 유니크가 마지막 방어)
        if (photo != null && !photo.equals(oldPhoto)
                && !uploads.claim(Member.PHOTO_MODULE, memberId.toString(), List.of(photo))) {
            throw new AppException(MemberErrorCode.PROFILE_PHOTO_NOT_FOUND);
        }

        // 바뀌기 전 값을 기억해 둔다. 저장한 뒤 무엇이 바뀌었는지 비교한다
        String oldRegion = member.getRegionCode();
        boolean hadBodyInfo = member.getBodyInfo() != null;

        member.editProfile(nickname, request.bio(), request.regionCode(), request.affiliation(),
                request.runningExperience(), photo, body, now);
        memberRepository.flush(); // UPDATE를 지금 보내 @Version을 올린다(아래 지역 이벤트에 싣는다)

        // 신체 정보 동의를 켜거나 껐으면 동의 이력을 한 줄 더 쌓는다(DB 구조 member.agreements)
        if (hadBodyInfo != (body != null)) {
            agreementRepository.save(Agreement.bodyInfo(memberId, body != null));
        }
        // 사진을 바꾸거나 지웠으면 예전 파일을 지운다. 커밋된 뒤에 지워서, 저장이 실패하면 예전 사진이 남는다
        if (oldPhoto != null && !oldPhoto.equals(photo)) {
            storage.deleteAfterCommit(List.of(oldPhoto));
        }
        // 활동 지역이 바뀌면 ranking이 다음 주부터 새 지역 주간 랭킹에 넣는다(정책 공통 6, 개발 정책 5.6)
        if (!Objects.equals(oldRegion, member.getRegionCode())) {
            events.publishEvent(new MemberRegionChangedEvent(UuidV7.create(), now, memberId,
                    member.getRegionCode(), oldRegion, member.getVersion()));
        }
        return view(member);
    }

    /**
     * 회원 탈퇴(F4 회원 탈퇴, 개발 정책 6.2).
     *
     * <p>순서: 회원 행을 잠그고 → 개인정보를 비우고 {@code WITHDRAWN}으로 → 동의 이력 삭제 → 사진 파일 삭제(커밋 뒤) →
     * {@link MemberWithdrawnEvent} 발행. 이벤트를 받으면 리프레시 토큰(같은 트랜잭션), 러닝 기록 · 랭킹 · 리뷰 · 저장한 코스(커밋 뒤
     * 각 모듈)가 지워진다. 등록한 코스는 남는다(정책 공통 4).
     *
     * <p>이미 탈퇴했으면 COMMON-002다. 액세스 토큰은 만료(1시간)까지 남지만 내 정보 API는 탈퇴 회원을 받지 않는다.
     */
    @Transactional
    void withdraw(UUID memberId) {
        Member member = active(memberRepository.findLockedById(memberId));
        Instant now = clock.instant();
        String photo = member.withdraw(now);
        agreementRepository.deleteByMemberId(memberId);
        if (photo != null) {
            storage.deleteAfterCommit(List.of(photo));
        }
        events.publishEvent(new MemberWithdrawnEvent(UuidV7.create(), now, memberId, now));
    }

    /** 토큰은 아직 살아 있지만 탈퇴했거나 없는 회원이면 다시 로그인하게 한다(COMMON-002). */
    private static Member active(Optional<Member> member) {
        return member.filter(m -> !m.isWithdrawn())
                .orElseThrow(() -> new AppException(CommonErrorCode.UNAUTHORIZED));
    }

    private MyProfile view(Member m) {
        Instant changeableAt = m.nicknameChangeableAt();
        return new MyProfile(m.getId(), m.getNickname(),
                changeableAt != null && clock.instant().isBefore(changeableAt) ? changeableAt : null,
                m.getBio(), regions.findSigungu(m.getRegionCode()).orElse(null),
                m.getAffiliation(), m.getRunningExperience(), m.getProfileImageKey(),
                m.getProfileImageKey() == null ? null : storage.url(m.getProfileImageKey()),
                m.getBodyInfo(), m.getSocialProvider(), m.isInfoPublic(), m.isProfileSearchable());
    }
}
