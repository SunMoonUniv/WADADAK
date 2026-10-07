package com.wadadak.common.entity;

import jakarta.persistence.Column;
import jakarta.persistence.MappedSuperclass;
import jakarta.persistence.Transient;
import lombok.Getter;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;
import org.springframework.data.domain.Persistable;

import java.time.Instant;

/**
 * 모든 엔티티의 생성일·수정일. ID는 애플리케이션이 미리 만들기 때문에({@link UuidV7})
 * 새 엔티티 판단을 ID가 아닌 생성일로 한다. 그래야 {@code save()}가 merge(SELECT) 대신 persist한다.
 */
@Getter
@MappedSuperclass
public abstract class BaseEntity<ID> implements Persistable<ID> {

    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(nullable = false)
    private Instant updatedAt;

    @Transient
    @Override
    public boolean isNew() {
        return createdAt == null;
    }
}
