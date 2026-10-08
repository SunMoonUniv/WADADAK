package com.wadadak.course.internal.registration;

import com.wadadak.common.entity.BaseEntity;
import com.wadadak.common.entity.UuidV7;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.util.UUID;

/**
 * 등록 멱등성(STA-05). 회원이 같은 키로 다시 요청하면 새로 만들지 않고 {@code courseId}를 돌려준다.
 * 키 내용이 달라도 처음 결과를 돌려준다. 24시간 뒤 지운다.
 */
@Getter
@Entity
@Table(schema = "course", name = "registration_requests")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class RegistrationRequest extends BaseEntity<UUID> {

    @Id
    private UUID id;

    private UUID memberId;

    /** 앱이 등록 시도마다 만드는 UUID({@code Idempotency-Key} 헤더). 같은 등록을 재시도할 때는 같은 값을 보낸다. */
    private UUID idempotencyKey;

    private UUID courseId;

    RegistrationRequest(UUID memberId, UUID idempotencyKey, UUID courseId) {
        this.id = UuidV7.create();
        this.memberId = memberId;
        this.idempotencyKey = idempotencyKey;
        this.courseId = courseId;
    }
}
