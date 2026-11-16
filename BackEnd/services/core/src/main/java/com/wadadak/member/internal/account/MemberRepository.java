package com.wadadak.member.internal.account;

import com.wadadak.member.internal.social.SocialProvider;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface MemberRepository extends JpaRepository<Member, UUID> {

    /** 러너 검색(G7) 대상: 활동 중이고 프로필 검색을 허용했고 닉네임에 :key가 들어간 회원 */
    String RUNNER_MATCH = "status = 'ACTIVE' AND profile_searchable AND strpos(lower(nickname), :key) > 0";

    Optional<Member> findBySocialProviderAndSocialId(SocialProvider socialProvider, String socialId);

    /**
     * 러너 검색(G7) 한 쪽. 인기순(G7-04)은 더미 프로필 방문자 수 많은 순이고, 더미 값은 회원 ID로 만든 0~1023 고정값이다.
     * ponytail: 실제 방문자 집계(커뮤니티 고도화)가 생기면 그 컬럼으로 정렬한다
     *
     * @param key 공백을 빼고 소문자로 바꾼 검색어
     */
    @Query(value = "SELECT * FROM member.members WHERE " + RUNNER_MATCH
            + " ORDER BY (hashtext(id::text) & 1023) DESC, id LIMIT :limit OFFSET :offset", nativeQuery = true)
    List<Member> searchRunners(String key, int offset, int limit);

    @Query(value = "SELECT count(*) FROM member.members WHERE " + RUNNER_MATCH, nativeQuery = true)
    int countRunners(String key);

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
