package com.wadadak.member.internal.account;

import com.wadadak.member.internal.social.SocialProvider;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface MemberRepository extends JpaRepository<Member, UUID> {

    Optional<Member> findBySocialProviderAndSocialId(SocialProvider socialProvider, String socialId);

    boolean existsByNicknameIgnoreCase(String nickname);
}
