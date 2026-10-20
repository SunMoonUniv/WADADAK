package com.wadadak.member.internal.account;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.event.member.MemberVisibilityChangedEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.Optional;
import java.util.UUID;

/**
 * 내 정보 조회와 MY 설정(F13). 앱만 부르는 기능이라 다른 모듈용 {@link com.wadadak.member.MemberApi}와 따로 둔다.
 *
 * <p>[흐름] 컨트롤러(HTTP 요청) → 이 서비스(회원 확인·변경·이벤트) → 저장소(DB).
 */
@Service
@RequiredArgsConstructor
class MyAccountService {

    private final MemberRepository memberRepository;
    private final RegionDirectory regions;
    private final ObjectStorage storage;
    private final ApplicationEventPublisher events; // 스프링 이벤트 발행기. 다른 모듈에 "공개 설정이 바뀌었다"를 알린다
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

    /** 토큰은 아직 살아 있지만 탈퇴했거나 없는 회원이면 다시 로그인하게 한다(COMMON-002). */
    private static Member active(Optional<Member> member) {
        return member.filter(m -> !m.isWithdrawn())
                .orElseThrow(() -> new AppException(CommonErrorCode.UNAUTHORIZED));
    }

    private MyProfile view(Member m) {
        return new MyProfile(m.getId(), m.getNickname(), m.getBio(),
                regions.findSigungu(m.getRegionCode()).orElse(null),
                m.getAffiliation(), m.getRunningExperience(),
                m.getProfileImageKey() == null ? null : storage.url(m.getProfileImageKey()),
                m.getBodyInfo(), m.getSocialProvider(), m.isInfoPublic(), m.isProfileSearchable());
    }
}
