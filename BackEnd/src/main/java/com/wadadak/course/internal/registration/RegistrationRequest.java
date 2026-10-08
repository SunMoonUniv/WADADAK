package com.wadadak.course.internal.registration;

import com.wadadak.common.entity.BaseEntity;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.util.UUID;

/**
 * 등록 멱등성(STA-05). 회원이 같은 키로 다시 요청하면 새로 만들지 않고 {@code courseId}를 돌려준다.
 */
@Getter
@Entity
@Table(schema = "course", name = "registration_requests")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class RegistrationRequest extends BaseEntity<RegistrationRequestKey> {

    @EmbeddedId
    private RegistrationRequestKey id;

    private UUID courseId;

    RegistrationRequest(RegistrationRequestKey id, UUID courseId) {
        this.id = id;
        this.courseId = courseId;
    }
}
