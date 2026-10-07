package com.wadadak.member.internal;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

interface MemberRepository extends JpaRepository<Member, UUID> {

    Optional<Member> findBySocialProviderAndSocialId(SocialProvider socialProvider, String socialId);

    boolean existsByNicknameIgnoreCase(String nickname);
}
