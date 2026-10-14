package com.wadadak.review.internal;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 리뷰 조회(B8·G2·지도 평점·B2/B10 진입). 숨김·삭제된 코스의 리뷰는 보이지 않는다(DB 구조 3.4).
 * 다만 내 리뷰는 숨김 코스여도 돌려준다. 숨김 코스의 리뷰도 지울 수는 있어서다.
 *
 * <p>트랜잭션({@code @Transactional})을 걸지 않았다. 조회만 하고, 중간에 member 모듈을 부르기 때문이다.
 * 나중에 member가 다른 서버가 되면 그 호출이 네트워크를 기다리는데, 트랜잭션 안이면 그동안 DB 커넥션을 쥐고 있게 된다(개발 정책 4.4).
 */
@Slf4j // Lombok: 로그를 남기는 log 필드를 만든다
@Service
@RequiredArgsConstructor
class ReviewQueryService {

    /** 지도 평점 일괄 조회 한 번에 받는 코스 수. 다른 일괄 조회와 같은 100개다(개발 정책 4.2) */
    static final int MAX_COURSE_IDS = 100;

    private final ReviewQueries queries;
    private final CourseRunRecords runRecords;
    private final ReviewPhotos reviewPhotos;
    private final MemberApi memberApi; // 작성자 닉네임·프로필 사진. 표시용이라 실패해도 목록은 보여준다

    ReviewSummary summary(UUID courseId) {
        return runRecords.isCourseActive(courseId) ? queries.summary(courseId) : ReviewSummary.EMPTY;
    }

    /**
     * 요청한 코스마다 한 줄씩, 요청 순서대로 돌려준다. 리뷰가 없거나 숨김·삭제된 코스는 평점이 {@code null}이다.
     *
     * @throws AppException COMMON-001 — 코스가 {@value #MAX_COURSE_IDS}개를 넘을 때
     */
    List<CourseRating> ratings(Set<UUID> courseIds) {
        if (courseIds.size() > MAX_COURSE_IDS) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "courseIds: 한 번에 " + MAX_COURSE_IDS + "개까지 조회할 수 있습니다.");
        }
        if (courseIds.isEmpty()) {
            return List.of(); // 빈 IN ()은 SQL 문법 오류라 DB까지 가지 않는다
        }
        Map<UUID, CourseRating> found = queries.ratings(courseIds).stream()
                .collect(Collectors.toMap(CourseRating::courseId, Function.identity()));
        return courseIds.stream()
                .map(id -> found.getOrDefault(id, CourseRating.none(id)))
                .toList();
    }

    CursorSlice<ReviewCard> list(UUID courseId, ReviewSort sort, boolean photoOnly, boolean excludeMine, UUID requesterId,
                                 Cursorable page) {
        if (!runRecords.isCourseActive(courseId)) {
            return new CursorSlice<>(List.of(), null);
        }
        int offset = page.offset();
        // 한 장 더 읽어서, 남는 게 있으면 다음 페이지가 있다
        List<ReviewCard> cards = queries.page(courseId, sort, photoOnly, excludeMine, requesterId, offset, page.size() + 1);
        boolean hasNext = cards.size() > page.size();
        List<ReviewCard> content = hasNext ? cards.subList(0, page.size()) : cards;
        return new CursorSlice<>(complete(content), hasNext ? String.valueOf(offset + page.size()) : null);
    }

    MyReview mine(UUID memberId, UUID courseId) {
        ReviewCard review = queries.mine(memberId, courseId)
                .map(card -> complete(List.of(card)).getFirst())
                .orElse(null);
        boolean sourceRecordDeleted = review != null && queries.isSourceRecordDeleted(memberId, courseId);
        // 숨김·삭제된 코스에는 새로 쓸 수 없으니(REVIEW-005) 작성 근거 기록도 주지 않는다
        MyReview.EligibleRecord eligibleRecord = runRecords.isCourseActive(courseId)
                ? runRecords.latestEligibleRecord(memberId, courseId).orElse(null)
                : null;
        return new MyReview(review, sourceRecordDeleted, eligibleRecord);
    }

    /**
     * 카드에 닉네임·프로필 사진과 리뷰 사진을 붙인다.
     * 회원과 사진을 각각 한 번에 모아 조회한다(카드마다 부르면 N+1, 개발 정책 4.2).
     */
    private List<ReviewCard> complete(List<ReviewCard> cards) {
        Map<UUID, MemberProfile> profiles = profiles(cards.stream().map(ReviewCard::memberId).collect(Collectors.toSet()));
        Map<UUID, List<ReviewView.Photo>> photos = reviewPhotos.photosOf(cards.stream().map(ReviewCard::reviewId).toList());
        return cards.stream()
                .map(card -> card.with(profiles.get(card.memberId()), photos.getOrDefault(card.reviewId(), List.of())))
                .toList();
    }

    /** 표시용이라 실패해도 리뷰는 보여준다. 닉네임·사진만 비운다(개발 정책 4.4). */
    private Map<UUID, MemberProfile> profiles(Set<UUID> memberIds) {
        if (memberIds.isEmpty()) {
            return Map.of();
        }
        try {
            return memberApi.getProfiles(memberIds).stream()
                    .collect(Collectors.toMap(MemberProfile::memberId, Function.identity()));
        } catch (RuntimeException e) {
            log.warn("회원 프로필 조회 실패. 닉네임 없이 리뷰를 돌려준다", e);
            return Map.of();
        }
    }
}
