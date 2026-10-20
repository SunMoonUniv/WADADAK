package com.wadadak.member.internal.account;

import com.wadadak.common.region.Region;
import com.wadadak.member.internal.social.SocialProvider;

import java.util.UUID;

/**
 * 내 정보(E3 마이페이지 · F6 프로필 편집 · F4 설정). 본인만 보는 값이라 신체 정보도 담는다(정책 공통 9).
 *
 * @param region          활동 지역(시·군·구). 코드가 지역 목록에서 사라졌으면 {@code null}
 * @param profileImageUrl 프로필 사진이 없으면 {@code null}
 * @param bodyInfo        신체 정보. 입력하지 않았으면 {@code null}
 * @param socialProvider  F4 "연결된 소셜 계정". 이메일은 받지 않는다
 * @param infoPublic      내 정보 공개. 끄면 랭킹·고스트 후보·다른 러너 프로필에서 내 기록이 빠진다(정책 공통 6)
 */
record MyProfile(
        UUID memberId,
        String nickname,
        String bio,
        Region region,
        String affiliation,
        RunningExperience runningExperience,
        String profileImageUrl,
        BodyInfo bodyInfo,
        SocialProvider socialProvider,
        boolean infoPublic,
        boolean profileSearchable) {
}
