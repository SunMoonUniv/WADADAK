package com.wadadak.course.internal.registration;

import jakarta.persistence.Embeddable;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.util.UUID;

@Getter
@Embeddable
@EqualsAndHashCode
@AllArgsConstructor
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class RegistrationRequestKey implements Serializable {

    private UUID memberId;

    /** 앱이 등록 시도마다 만드는 UUID. 같은 등록을 재시도할 때는 같은 값을 보낸다. */
    private UUID idempotencyKey;
}
