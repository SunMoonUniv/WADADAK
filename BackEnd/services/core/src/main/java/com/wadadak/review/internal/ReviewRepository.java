package com.wadadak.review.internal;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * 리뷰 저장소. 인터페이스만 선언하면 Spring Data JPA가 구현체를 자동으로 만든다.
 *
 * <p>{@code JpaRepository<Review, UUID>}를 상속해서 save·findById·delete 같은 기본 메서드는 이미 있다.
 * 아래처럼 규칙에 맞는 이름으로 메서드를 선언하면 이름을 읽고 쿼리를 만들어 준다.
 */
interface ReviewRepository extends JpaRepository<Review, UUID> {

    /** "member_id = ? AND course_id = ?인 행이 있는가" 쿼리가 자동으로 만들어진다. 코스당 1개 확인에 쓴다. */
    boolean existsByMemberIdAndCourseId(UUID memberId, UUID courseId);

    /** 그 회원이 쓴 리뷰 전부. 회원 탈퇴 때 하나씩 지우며 리뷰마다 삭제 이벤트를 낸다. */
    List<Review> findByMemberId(UUID memberId);

    /**
     * 리뷰 한 행을 잠그고(SELECT ... FOR UPDATE) 읽는다. 수정·삭제가 동시에 들어오면 먼저 온 쪽이 끝날 때까지 다음 쪽이 기다린다.
     * 그래야 "이전 별점"을 항상 최신 값으로 읽어서, course가 평점 합계에 더하는 차이값이 어긋나지 않는다.
     * 잠금 없이 읽으면 두 요청이 모두 같은 이전 별점을 보고 차이값을 보내 합계가 틀어진다.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<Review> findLockedById(UUID id);
}
