package com.wadadak.member.internal.account;

import com.wadadak.member.internal.social.SocialProvider;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import java.util.Optional;
import java.util.UUID;

public interface MemberRepository extends JpaRepository<Member, UUID> {

    Optional<Member> findBySocialProviderAndSocialId(SocialProvider socialProvider, String socialId);

    boolean existsByNicknameIgnoreCase(String nickname);

    /** 프로필 편집에서 쓰는 닉네임 중복 확인. 내 닉네임의 대소문자만 바꾸는 것은 허용하려고 나는 뺀다. */
    boolean existsByNicknameIgnoreCaseAndIdNot(String nickname, UUID id);

    /**
     * 회원 행을 잠그고 읽는다(SELECT … FOR UPDATE). 내 정보를 바꾸는 요청이 동시에 와도 하나씩 차례로 처리돼,
     * 버전(@Version)이 바뀐 순서대로 이벤트가 나간다. 이름의 {@code Locked}는 쿼리에 영향이 없는 설명용 단어다.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<Member> findLockedById(UUID id);
}
