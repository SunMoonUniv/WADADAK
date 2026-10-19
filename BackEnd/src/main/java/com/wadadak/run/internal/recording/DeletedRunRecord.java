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
@Table(schema = "run", name = "deleted_records")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class DeletedRunRecord extends BaseEntity<UUID> {
    @Id
    private UUID id;
    private UUID memberId;
    private Instant deletedAt;

    DeletedRunRecord(UUID id, UUID memberId, Instant deletedAt) {
        this.id = id;
        this.memberId = memberId;
        this.deletedAt = deletedAt;
    }
}
