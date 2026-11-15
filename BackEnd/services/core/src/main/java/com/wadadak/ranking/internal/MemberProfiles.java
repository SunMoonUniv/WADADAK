package com.wadadak.ranking.internal;

import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/** 랭킹 줄의 닉네임·사진. 코스 랭킹과 누적 거리 랭킹이 같이 쓴다. */
@Slf4j
public final class MemberProfiles {

    private MemberProfiles() {
    }

    /** 표시용이라 실패해도 랭킹은 보여준다. 닉네임·사진만 비운다(개발 정책 4.4). */
    public static Map<UUID, MemberProfile> find(MemberApi memberApi, Set<UUID> memberIds) {
        if (memberIds.isEmpty()) {
            return Map.of();
        }
        try {
            return memberApi.getProfiles(memberIds).stream()
                    .collect(Collectors.toMap(MemberProfile::memberId, Function.identity()));
        } catch (RuntimeException e) {
            log.warn("회원 프로필 조회 실패. 닉네임 없이 랭킹을 돌려준다", e);
            return Map.of();
        }
    }
}
