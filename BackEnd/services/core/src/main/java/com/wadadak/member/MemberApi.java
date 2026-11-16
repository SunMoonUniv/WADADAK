package com.wadadak.member;

import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * 회원 표시용 프로필 조회. 호출 허용: ranking·review·course (개발 정책 4.3).
 * 표시용이므로 호출 쪽은 실패 시 기본값으로 대신하고 화면 전체를 실패시키지 않는다(4.4).
 */
public interface MemberApi {

    int MAX_IDS = 100;

    /**
     * @param memberIds 최대 {@value #MAX_IDS}개
     * @return 프로필 목록. 탈퇴 회원은 닉네임이 {@value MemberProfile#WITHDRAWN_NICKNAME}이고
     *         {@code withdrawn = true}다. 존재하지 않는 ID는 결과에서 빠질 수 있다.
     * @throws com.wadadak.common.exception.AppException {@link MemberErrorCode#TOO_MANY_MEMBER_IDS} — 개수 초과
     */
    List<MemberProfile> getProfiles(Set<UUID> memberIds);
}
