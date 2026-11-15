package com.wadadak.member.internal.profile;

import com.wadadak.common.region.Region;
import com.wadadak.member.internal.account.RunningExperience;

import java.util.UUID;

/**
 * 다른 러너 프로필(I3) 머리 부분. 내 정보 공개와 관계없이 보인다(프로필 표시는 그대로, 정책 공통 6).
 *
 * @param profileImageUrl 프로필 사진이 없으면 {@code null}
 * @param region          활동 지역(시·군·구). 코드가 지역 목록에서 사라졌으면 {@code null}
 */
record RunnerProfile(UUID memberId, String nickname, String profileImageUrl, Region region,
                     RunningExperience runningExperience) {
}
