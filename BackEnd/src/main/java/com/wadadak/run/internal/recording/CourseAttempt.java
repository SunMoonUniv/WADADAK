package com.wadadak.run.internal.recording;

import com.wadadak.common.entity.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

/**
 * 세션 하나의 코스 러닝 시도. 준비(C6)에서 만들고 시작 신호로 측정 시작을 남긴다.
 * 시작 때 받은 코스 스냅샷으로 끝까지 판정한다(코스가 나중에 비공개·삭제돼도 다시 조회하지 않음).
 */
@Getter
@Entity
@Table(schema = "run", name = "course_attempts")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class CourseAttempt extends BaseEntity<UUID> {

    @Id
    @Column(name = "session_id")
    private UUID id;
    private UUID memberId;
    private UUID courseId;
    private String courseName;
    private long courseVersion;
    /** 기준 경로 GeoPoint JSON 배열. 첫 점이 출발 */
    @Column(columnDefinition = "text")
    private String routeJson;
    private int totalDistanceMeters;
    /** 측정 시작. null이면 준비만 했다 */
    private Instant startedAt;
    /** CourseRunStartedEvent.occurredAt */
    private Instant startedEventAt;
    /** 현재 러너 수에서 뺀 시각 */
    private Instant releasedAt;
    private String releaseReason;

    CourseAttempt(UUID id, UUID memberId, UUID courseId, String courseName, long courseVersion, String routeJson,
                  int totalDistanceMeters) {
        this.id = id;
        this.memberId = memberId;
        this.courseId = courseId;
        this.courseName = courseName;
        this.courseVersion = courseVersion;
        this.routeJson = routeJson;
        this.totalDistanceMeters = totalDistanceMeters;
    }

    /** 현재 러너 수에 들어가 있다 */
    boolean active() {
        return startedAt != null && releasedAt == null;
    }

    void start(Instant startedAt, Instant eventAt) {
        this.startedAt = startedAt;
        this.startedEventAt = eventAt;
    }

    void release(Instant at, String reason) {
        this.releasedAt = at;
        this.releaseReason = reason;
    }
}
