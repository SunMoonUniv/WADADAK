package com.wadadak.review.internal;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.storage.UploadForm;
import com.wadadak.event.review.ReviewCreatedEvent;
import com.wadadak.event.review.ReviewDeletedEvent;
import com.wadadak.event.review.ReviewUpdatedEvent;
import com.wadadak.review.ReviewErrorCode;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.List;
import java.util.UUID;

/**
 * 리뷰 작성(B2)·수정(B10)·삭제. 바뀔 때마다 리뷰 이벤트를 발행해 course가 평점 합계·리뷰 수를 맞춘다(개발 정책 5.6).
 *
 * <p>[흐름] 컨트롤러(HTTP 요청) → 이 서비스(규칙 확인·저장·이벤트) → 저장소(DB).
 * 규칙에 어긋나면 {@link AppException}을 던지고, GlobalExceptionHandler가 에러 코드(REVIEW-001 등)로 응답한다.
 */
@Service
@RequiredArgsConstructor
class ReviewService {

    private final ReviewRepository reviewRepository;
    private final CourseRunRecords runRecords;
    private final ReviewPhotos photos;
    private final ApplicationEventPublisher events; // 스프링 이벤트 발행기. 다른 모듈에 "리뷰가 바뀌었다"를 알린다
    private final Clock clock; // 지금 시각. 테스트에서 시각을 고정할 수 있게 직접 now()를 부르지 않는다

    /*
     * @Transactional: 이 메서드 안의 DB 작업을 하나로 묶는다. 중간에 예외가 나면 저장한 것까지 모두 취소(롤백)된다.
     * 이벤트도 이 안에서 발행해야 한다. 발행 기록이 리뷰 저장과 같은 트랜잭션에 묶여서, 저장이 성공했을 때만 course에 전달된다
     * (Modulith 아웃박스, 개발 정책 5.1·5.3). 트랜잭션 밖에서 발행하면 조용히 사라진다.
     */
    @Transactional
    ReviewView write(UUID memberId, WriteReviewRequest request) {
        UUID courseId = request.courseId();
        // 확인 순서: 코스가 열려 있나 → 이미 썼나(수정하라고 안내) → 이 기록으로 쓸 자격이 있나
        requireActiveCourse(courseId);
        if (reviewRepository.existsByMemberIdAndCourseId(memberId, courseId)) {
            throw new AppException(ReviewErrorCode.ALREADY_REVIEWED);
        }
        if (!runRecords.isEligibleSource(memberId, courseId, request.sourceRunRecordId())) {
            throw new AppException(ReviewErrorCode.NOT_ELIGIBLE);
        }

        Review review;
        try {
            // saveAndFlush: 바로 INSERT까지 보낸다. 그래야 유니크 제약 위반을 여기서 잡을 수 있고 createdAt도 채워진다
            review = reviewRepository.saveAndFlush(Review.write(courseId, memberId, request.sourceRunRecordId(),
                    request.toContent(), runRecords.bestProgressPercent(memberId, courseId)));
        } catch (DataIntegrityViolationException e) {
            // 같은 회원이 같은 코스에 동시에 두 번 작성하면(버튼 연타 등) 위 확인을 둘 다 통과할 수 있다.
            // 그때는 DB 유니크 제약 (member_id, course_id)이 하나만 남기고, 나머지는 이미 작성으로 돌려준다
            throw new AppException(ReviewErrorCode.ALREADY_REVIEWED);
        }
        // 사진 행은 리뷰 행을 FK로 가리키므로 리뷰를 저장한 다음에 넣는다. 사진이 잘못되면 리뷰 저장까지 함께 취소된다
        List<ReviewView.Photo> savedPhotos = photos.replace(memberId, review.getId(), request.toContent().photoKeys());
        // eventId는 수신 측이 같은 이벤트를 두 번 처리하지 않게 하는 키, occurredAt은 발행 시각(개발 정책 5.3 공통 필드)
        events.publishEvent(new ReviewCreatedEvent(UuidV7.create(), clock.instant(), review.getId(), courseId,
                review.getRating(), review.getCreatedAt()));
        return ReviewView.from(review, savedPhotos);
    }

    /** 근거 기록이 삭제돼도 수정할 수 있다(B10-1). 최고 진행도는 지금 남은 기록이 더 높을 때만 올린다. */
    @Transactional
    ReviewView edit(UUID memberId, UUID reviewId, ReviewContent content) {
        Review review = ownReview(memberId, reviewId);
        requireActiveCourse(review.getCourseId());

        int oldRating = review.getRating(); // 바꾸기 전 별점. course가 평점 합계에 (새 별점 − 이전 별점)을 더한다
        review.edit(content, runRecords.bestProgressPercent(memberId, review.getCourseId()));
        reviewRepository.flush(); // 바뀐 값을 지금 UPDATE해서 응답의 updatedAt이 새 값이 되게 한다
        List<ReviewView.Photo> savedPhotos = photos.replace(memberId, review.getId(), content.photoKeys());
        // 별점이 그대로여도 발행한다. "리뷰가 수정됐다"는 사실을 알리고, 반영할지는 받는 쪽이 정한다(개발 정책 5.1)
        events.publishEvent(new ReviewUpdatedEvent(UuidV7.create(), clock.instant(), review.getId(), review.getCourseId(),
                oldRating, review.getRating(), review.getCreatedAt()));
        return ReviewView.from(review, savedPhotos);
    }

    /** 숨김 코스의 리뷰도 지울 수 있다. 사진 행은 함께 지워지고(DB의 ON DELETE CASCADE), 사진 파일은 커밋한 뒤 지운다. */
    @Transactional
    void delete(UUID memberId, UUID reviewId) {
        Review review = ownReview(memberId, reviewId);
        photos.deleteFiles(reviewId);
        reviewRepository.delete(review);
        // createdAt을 실어 보내야 course가 작성일 칸의 일별 평점에서 뺄 수 있다
        events.publishEvent(new ReviewDeletedEvent(UuidV7.create(), clock.instant(), review.getId(), review.getCourseId(),
                review.getRating(), review.getCreatedAt()));
    }

    /** 리뷰를 찾고, 요청한 회원이 쓴 리뷰인지 확인한다. 없으면 REVIEW-003, 남의 리뷰면 REVIEW-004. */
    private Review ownReview(UUID memberId, UUID reviewId) {
        Review review = reviewRepository.findById(reviewId)
                .orElseThrow(() -> new AppException(ReviewErrorCode.REVIEW_NOT_FOUND));
        if (!review.isWrittenBy(memberId)) {
            throw new AppException(ReviewErrorCode.NOT_REVIEW_OWNER);
        }
        return review;
    }

    /** 사진 한 장을 올릴 폼. 리뷰를 쓰기 전에 받는다. */
    UploadForm photoUploadForm(UUID memberId) {
        return photos.uploadForm(memberId);
    }

    /** 숨김·삭제된 코스에는 쓰거나 고칠 수 없다(정책 공통 5, REVIEW-005). */
    private void requireActiveCourse(UUID courseId) {
        if (!runRecords.isCourseActive(courseId)) {
            throw new AppException(ReviewErrorCode.COURSE_NOT_REVIEWABLE);
        }
    }
}
