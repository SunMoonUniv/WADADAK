package com.wadadak.member;

import java.util.UUID;

/**
 * @param profileImageUrl 프로필 사진이 없으면 {@code null}
 */
public record MemberProfile(UUID memberId, String nickname, String profileImageUrl, boolean withdrawn) {

    public static final String WITHDRAWN_NICKNAME = "탈퇴한 사용자";
}
