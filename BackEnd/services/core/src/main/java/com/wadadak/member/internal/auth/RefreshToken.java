package com.wadadak.member.internal.auth;

import com.wadadak.common.entity.BaseEntity;
import com.wadadak.common.entity.UuidV7;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

@Getter
@Entity
@Table(schema = "member", name = "refresh_tokens")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class RefreshToken extends BaseEntity<UUID> {

    @Id
    private UUID id;

    private String tokenHash;
    private UUID memberId;
    private Instant expiresAt;

    RefreshToken(String tokenHash, UUID memberId, Instant expiresAt) {
        this.id = UuidV7.create();
        this.tokenHash = tokenHash;
        this.memberId = memberId;
        this.expiresAt = expiresAt;
    }
}
