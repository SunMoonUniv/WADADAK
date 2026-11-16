package com.wadadak.run.internal.recording;

import com.wadadak.common.entity.BaseEntity;
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
@Table(schema = "run", name = "sessions")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class RunSession extends BaseEntity<UUID> {
    @Id
    private UUID id;
    private UUID memberId;
    private Instant startedAt;
    private Long finalSeq;
    private String processing;
    private String failure;

    RunSession(UUID id, UUID memberId, Instant startedAt) {
        this.id = id;
        this.memberId = memberId;
        this.startedAt = startedAt;
        this.processing = "PREPARED";
    }

    boolean acceptsInputs() {
        return "PREPARED".equals(processing) || "NEEDS_DATA".equals(processing);
    }

    void accept(long finalSeq, long storedCount) {
        this.finalSeq = finalSeq;
        this.processing = storedCount == finalSeq + 1 ? "PROCESSING" : "NEEDS_DATA";
    }

    void fail(String failure) {
        this.processing = "FAILED";
        this.failure = failure;
    }

    void complete() {
        this.processing = "DONE";
    }
}
