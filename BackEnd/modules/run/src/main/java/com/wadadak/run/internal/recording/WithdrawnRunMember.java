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
@Table(schema = "run", name = "withdrawn_members")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class WithdrawnRunMember extends BaseEntity<UUID> {
    @Id
    private UUID memberId;
    private Instant withdrawnAt;

    WithdrawnRunMember(UUID memberId, Instant withdrawnAt) {
        this.memberId = memberId;
        this.withdrawnAt = withdrawnAt;
    }

    @Override
    public UUID getId() {
        return memberId;
    }
}
