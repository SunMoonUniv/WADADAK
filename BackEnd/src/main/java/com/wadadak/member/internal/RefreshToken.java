package com.wadadak.member.internal;

import com.wadadak.common.entity.BaseEntity;
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
class RefreshToken extends BaseEntity<String> {

    @Id
    private String tokenHash;

    private UUID memberId;
    private Instant expiresAt;

    RefreshToken(String tokenHash, UUID memberId, Instant expiresAt) {
        this.tokenHash = tokenHash;
        this.memberId = memberId;
        this.expiresAt = expiresAt;
    }

    @Override
    public String getId() {
        return tokenHash;
    }
}
