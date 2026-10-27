package com.wadadak.course.internal.registration;

import com.wadadak.common.entity.BaseEntity;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.util.UUID;

/**
 * GPS 주행 등록 코스의 출처. 같은 러닝 기록은 한 번만 코스로 만든다({@code run_record_id} 유니크).
 * 코스가 지워지거나 만료돼도 이 행은 남아 그 기록은 다시 쓰지 않는다.
 * 원본 경로 JSON이 커서 {@code Course}와 따로 둔다(코스를 읽을 때마다 함께 읽지 않게).
 */
@Getter
@Entity
@Table(schema = "course", name = "gps_course_sources")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class GpsCourseSource extends BaseEntity<UUID> {

    @Id
    private UUID courseId;

    private UUID runRecordId;

    private UUID memberId;

    /** 앱이 보낸 원본 경로 조각 그대로(점마다 고도 포함). 고도 프로필(보류)을 나중에 만들 때 쓰고 화면에는 쓰지 않는다. */
    private String sourceSegmentsJson;

    GpsCourseSource(UUID courseId, UUID runRecordId, UUID memberId, String sourceSegmentsJson) {
        this.courseId = courseId;
        this.runRecordId = runRecordId;
        this.memberId = memberId;
        this.sourceSegmentsJson = sourceSegmentsJson;
    }

    @Override
    public UUID getId() {
        return courseId;
    }
}
