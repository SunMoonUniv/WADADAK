package com.wadadak.review.internal;

import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.run.RunRecordDeletedEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.UUID;

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
    private final CourseRunRecords runRecords;

    /**
     * 삽입형. 코스 주행 기록 1건을 복사해 두고 리뷰 자격·최고 진행도·완주 횟수에 쓴다(정책 5.1·제4부 4.1 D-09).
     * 자유 러닝(courseId 없음), 숨김·삭제된 코스, 탈퇴한 회원의 기록은 받지 않는다.
     * 이미 쓴 리뷰의 최고 진행도는 여기서 올리지 않는다. 리뷰를 수정할 때 올린다(D-09).
     */
    @ApplicationModuleListener
    public void on(RunSessionEndedEvent event) {
        if (event.courseId() == null || !runRecords.isCourseActive(event.courseId()) || isWithdrawn(event.memberId())) {
            return;
        }
        /*
         * run 기록 ID가 PK라 같은 이벤트가 다시 와도 한 행이다(ON CONFLICT).
         * 이미 있는 행이 삭제가 먼저 와서 만든 삭제 표시 행이면(진행도가 비어 있음) 빈 값만 채우고 삭제 표시는 그대로 둔다.
         */
        jdbc.sql("""
                        INSERT INTO review.course_run_records AS c (run_record_id, course_id, member_id, review_eligible, completed,
                            progress_percent, course_distance_meters, course_elapsed_seconds, ended_at, created_at, updated_at)
                        VALUES (:runRecordId, :courseId, :memberId, :reviewEligible, :completed,
                            :progressPercent, :courseDistanceMeters, :courseElapsedSeconds, :endedAt, now(), now())
                        ON CONFLICT (run_record_id) DO UPDATE
                            SET review_eligible = EXCLUDED.review_eligible, progress_percent = EXCLUDED.progress_percent,
                                course_distance_meters = EXCLUDED.course_distance_meters, updated_at = now()
                            WHERE c.progress_percent IS NULL""")
                .param("runRecordId", event.runRecordId())
                .param("courseId", event.courseId())
                .param("memberId", event.memberId())
                .param("reviewEligible", event.reviewEligible()) // 판정은 run이 한다. 여기서 다시 계산하지 않는다
                .param("completed", event.completed())
                .param("progressPercent", progressPercent(event.progress()))
                .param("courseDistanceMeters", event.courseDistanceMeters())
                .param("courseElapsedSeconds", event.courseElapsedSeconds())
                .param("endedAt", timestamp(event.endedAt()))
                .update();
    }

    /**
     * 기록 삭제. 행은 지우지 않고 삭제 표시만 한다. 그 기록으로 얻은 리뷰 자격이 사라지고 최고 진행도·완주 횟수에서도 빠진다.
     * 이미 쓴 리뷰와 저장된 최고 진행도는 그대로다(정책 공통 5, 제4부 4.1 D-09). 근거 기록이면 B10-1 안내가 나온다.
     * 주행 기록보다 먼저 오면 삭제 표시 행을 먼저 만들어, 늦게 온 주행 기록이 되살리지 못하게 한다.
     */
    @ApplicationModuleListener
    public void on(RunRecordDeletedEvent event) {
        if (event.courseId() == null || isWithdrawn(event.memberId())) {
            return;
        }
        jdbc.sql("""
                        INSERT INTO review.course_run_records (run_record_id, course_id, member_id, completed,
                            course_elapsed_seconds, ended_at, deleted, created_at, updated_at)
                        VALUES (:runRecordId, :courseId, :memberId, :completed, :courseElapsedSeconds, :endedAt, TRUE, now(), now())
                        ON CONFLICT (run_record_id) DO UPDATE SET deleted = TRUE, updated_at = now()""")
                .param("runRecordId", event.runRecordId())
                .param("courseId", event.courseId())
                .param("memberId", event.memberId())
                .param("completed", event.completed())
                .param("courseElapsedSeconds", event.courseElapsedSeconds())
                .param("endedAt", timestamp(event.endedAt()))
                .update();
    }

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

    /** 탈퇴한 회원. 탈퇴 처리가 리뷰·기록을 지운 뒤에 늦게 온 기록을 받지 않는다. */
    private boolean isWithdrawn(UUID memberId) {
        return jdbc.sql("SELECT EXISTS (SELECT 1 FROM review.withdrawn_members WHERE member_id = :memberId)")
                .param("memberId", memberId)
                .query(Boolean.class)
                .single();
    }

    /**
     * 이벤트의 진행도(인정 거리 ÷ 코스 전체 거리 × 100, run 판정 기대값 문서)를 정수 %로.
     * 내림한다. 99.6%를 반올림하면 완주하지 않았는데 "완주 100%"처럼 보인다.
     */
    private static int progressPercent(double progress) {
        return (int) Math.max(0, Math.min(100, Math.floor(progress)));
    }

    /** PostgreSQL 드라이버는 Instant를 바로 받지 못해서 UTC 시각으로 바꿔 넘긴다. */
    private static OffsetDateTime timestamp(Instant instant) {
        return OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
