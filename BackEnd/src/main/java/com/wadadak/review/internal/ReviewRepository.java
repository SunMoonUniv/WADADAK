package com.wadadak.review.internal;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
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
}
