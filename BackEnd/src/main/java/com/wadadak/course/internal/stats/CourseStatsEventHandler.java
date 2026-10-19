package com.wadadak.course.internal.stats;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.event.IntegrationEvent;
import com.wadadak.event.review.ReviewCreatedEvent;
import com.wadadak.event.review.ReviewDeletedEvent;
import com.wadadak.event.review.ReviewUpdatedEvent;
import com.wadadak.event.run.RunRecordDeletedEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/**
 * 완주 · 기록 삭제 · 리뷰 이벤트로 코스 통계를 늘리고 줄인다(개발 정책 5.6). 증감형이라 이벤트마다 처리 기록을 먼저 남겨
 * 같은 이벤트를 두 번 반영하지 않는다(개발 정책 5.4). 공개 중인 코스만 바꾸고, 비공개 · 삭제 뒤에 온 이벤트는 버린다(정책 D-15).
 * 처리 기록의 이름(아래 상수)은 바꾸지 않는다. 도전 수는 run이 {@code CourseRunStartedEvent}를 발행하면 붙인다.
 */
@Component
@RequiredArgsConstructor
class CourseStatsEventHandler {

    static final String COMPLETED = "course.stats.completed";
    static final String COMPLETION_DELETED = "course.stats.completion-deleted";
    static final String REVIEW_CREATED = "course.stats.review-created";
    static final String REVIEW_UPDATED = "course.stats.review-updated";
    static final String REVIEW_DELETED = "course.stats.review-deleted";

    private final CourseStatsRepository stats;

    /** 서버가 확정한 코스 완주. 완주 수 +1, 코스 총 소요시간 합 + */
    @ApplicationModuleListener
    public void on(RunSessionEndedEvent event) {
        if (event.courseId() == null || !event.completed()) {
            return;
        }
        apply(event, COMPLETED, event.courseId(),
                () -> stats.addCompletions(event.courseId(), 1, event.courseElapsedSeconds()));
    }

    /** 완주 기록 삭제(회원 탈퇴 포함). 완주로 이미 연장한 유지 기간은 되돌리지 않는다(정책 공통 4) */
    @ApplicationModuleListener
    public void on(RunRecordDeletedEvent event) {
        if (event.courseId() == null || !event.completed()) {
            return;
        }
        apply(event, COMPLETION_DELETED, event.courseId(),
                () -> stats.addCompletions(event.courseId(), -1, -event.courseElapsedSeconds()));
    }

    @ApplicationModuleListener
    public void on(ReviewCreatedEvent event) {
        apply(event, REVIEW_CREATED, event.courseId(),
                () -> stats.addReviews(event.courseId(), day(event.createdAt()), event.rating(), 1));
    }

    /** 별점이 그대로면(내용 · 사진 · 항목 평가만 수정) 바꿀 것이 없다 */
    @ApplicationModuleListener
    public void on(ReviewUpdatedEvent event) {
        int change = event.newRating() - event.oldRating();
        if (change == 0) {
            return;
        }
        apply(event, REVIEW_UPDATED, event.courseId(),
                () -> stats.addReviews(event.courseId(), day(event.createdAt()), change, 0));
    }

    @ApplicationModuleListener
    public void on(ReviewDeletedEvent event) {
        apply(event, REVIEW_DELETED, event.courseId(),
                () -> stats.addReviews(event.courseId(), day(event.createdAt()), -event.rating(), -1));
    }

    private void apply(IntegrationEvent event, String listener, UUID courseId, Runnable change) {
        if (stats.markProcessed(event.eventId(), listener) && stats.lockIfActive(courseId)) {
            change.run();
        }
    }

    /** 리뷰는 작성일(Asia/Seoul) 행에 반영한다. 수정 · 삭제한 날에 반영하면 그날의 평점 합과 리뷰 수가 어긋난다(개발 정책 5.6) */
    private static LocalDate day(Instant createdAt) {
        return LocalDate.ofInstant(createdAt, TimeConfig.SEOUL);
    }
}
