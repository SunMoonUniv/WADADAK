package com.wadadak.review.internal;

import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

/**
 * 다른 모듈 이벤트를 review 복사본에 반영한다. 같은 이벤트가 두 번 오거나 순서가 바뀌어 와도 결과가 같다(개발 정책 5.4).
 * 메서드 이름은 이벤트 처리 기록의 키라서 바꾸지 않는다.
 *
 * <p>[읽는 법] {@code @ApplicationModuleListener}가 붙은 메서드는 이벤트를 발행한 쪽 트랜잭션이 커밋된 뒤,
 * 따로 떨어진 스레드와 트랜잭션에서 실행된다. 처리하다 실패하면 아웃박스({@code common.event_publication})에 남아
 * 다시 시도된다. 그래서 여러 번 실행돼도 결과가 같게 짜야 한다.
 */
@Component
@RequiredArgsConstructor
class ReviewEventHandler {

    private final JdbcClient jdbc;
    private final ReviewPhotos photos;

    /**
     * 상태 복사형. 숨김이면 상태만 남기고(리뷰 조회·작성이 이 표를 본다), 삭제면 그 코스의 리뷰(사진 포함)와 주행 기록 복사본도 지운다.
     * 삭제할 때 {@code ReviewDeletedEvent}는 발행하지 않는다. course가 그 코스 통계를 직접 지운다(개발 정책 5.6).
     * 복사본 행은 남겨 늦게 온 주행 기록을 받지 않는다.
     */
    @ApplicationModuleListener
    public void on(CourseStatusChangedEvent event) {
        // ON CONFLICT … WHERE: 이미 있으면 더 새 버전일 때만 바꾼다. 늦게 온 옛 이벤트(HIDDEN)가 DELETED를 덮지 못한다
        jdbc.sql("""
                        INSERT INTO review.course_status_copies AS c (course_id, status, source_version, created_at, updated_at)
                        VALUES (:courseId, :status, :version, now(), now())
                        ON CONFLICT (course_id) DO UPDATE
                            SET status = EXCLUDED.status, source_version = EXCLUDED.source_version, updated_at = now()
                            WHERE c.source_version < EXCLUDED.source_version""")
                .param("courseId", event.courseId())
                .param("status", event.status().name())
                .param("version", event.version())
                .update();
        if (event.status() == CourseStatus.DELETED) {
            // 사진 키는 리뷰가 지워지면 함께 사라지므로 먼저 읽어 둔다. 파일은 이 트랜잭션이 커밋된 뒤 지운다
            photos.deleteFilesOfCourse(event.courseId());
            jdbc.sql("DELETE FROM review.reviews WHERE course_id = :courseId")
                    .param("courseId", event.courseId())
                    .update();
            jdbc.sql("DELETE FROM review.course_run_records WHERE course_id = :courseId")
                    .param("courseId", event.courseId())
                    .update();
        }
    }
}
