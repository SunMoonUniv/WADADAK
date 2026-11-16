package com.wadadak.member.internal.profile;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.member.MemberErrorCode;
import com.wadadak.member.internal.account.Member;
import com.wadadak.member.internal.account.MemberRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/** 다른 러너 프로필(I3) 머리 부분. 기록 · 등록 코스는 앱이 ranking · course API로 따로 받는다(개발 정책 4.2). */
@Service
@RequiredArgsConstructor
class RunnerProfileService {

    private final MemberRepository memberRepository;
    private final RegionDirectory regions;
    private final ObjectStorage storage;

    /** @throws AppException MEMBER-011 — 탈퇴했거나 없는 회원 */
    @Transactional(readOnly = true)
    RunnerProfile profile(UUID memberId) {
        Member member = memberRepository.findById(memberId)
                .filter(m -> !m.isWithdrawn())
                .orElseThrow(() -> new AppException(MemberErrorCode.MEMBER_NOT_FOUND));
        String photoUrl = member.getProfileImageKey() == null ? null : storage.url(member.getProfileImageKey());
        return new RunnerProfile(member.getId(), member.getNickname(), photoUrl,
                regions.findSigungu(member.getRegionCode()).orElse(null), member.getRunningExperience());
    }
}
