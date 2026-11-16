package com.wadadak.run.internal.recording;

import com.wadadak.common.entity.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@Entity
@Table(schema = "run", name = "records")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class RunRecord extends BaseEntity<UUID> {
    @Id
    private UUID id;
    private Instant registeredAt;
    @Column(columnDefinition = "text")
    private String resultJson;
    @Column(columnDefinition = "text")
    private String summaryJson;
    private boolean registrationPublished;

    RunRecord(UUID id, Instant registeredAt, String resultJson, String summaryJson) {
        this.id = id;
        this.registeredAt = registeredAt;
        this.resultJson = resultJson;
        this.summaryJson = summaryJson;
    }

    /** 저장 뒤 더한 값(GPS 코스 등록 기준 등)을 채운다 */
    void replaceJson(String resultJson, String summaryJson) {
        this.resultJson = resultJson;
        this.summaryJson = summaryJson;
    }

    void markRegistrationPublished() {
        this.registrationPublished = true;
    }
}
