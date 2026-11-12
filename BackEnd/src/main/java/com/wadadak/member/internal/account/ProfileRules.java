package com.wadadak.member.internal.account;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.member.MemberErrorCode;

import java.time.Clock;
import java.time.Year;

/** 가입(F2)과 프로필 편집(F6)이 같이 쓰는 프로필 칸 확인. 칸의 길이 · 문자는 요청 record의 검증이 본다. */
public final class ProfileRules {

    private ProfileRules() {
    }

    /**
     * 활동 지역이 시·군·구 코드가 아니면 MEMBER-007, 출생연도가 받는 범위 밖이면 MEMBER-009.
     *
     * @param body 신체 정보. 입력하지 않았으면 {@code null}
     */
    public static void check(RegionDirectory regions, Clock clock, String regionCode, BodyInfo body) {
        // FK가 없으니 시·도·읍·면·동이나 없는 코드를 여기서 막는다. 지역 주간 랭킹이 이 코드로 회원을 묶는다
        if (regions.findSigungu(regionCode).isEmpty()) {
            throw new AppException(MemberErrorCode.REGION_NOT_FOUND);
        }
        if (body != null && !BodyInfo.allowsBirthYear(body.birthYear(), Year.now(clock))) {
            throw new AppException(MemberErrorCode.INVALID_BIRTH_YEAR);
        }
    }
}
