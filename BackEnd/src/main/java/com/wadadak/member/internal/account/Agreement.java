package com.wadadak.member.internal.account;

import com.wadadak.common.entity.BaseEntity;
import com.wadadak.common.entity.UuidV7;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.util.Arrays;
import java.util.List;
import java.util.UUID;

/** 약관 동의 이력. 쌓기만 하고 고치지 않는다. {@code createdAt}이 동의 시각이다. */
@Getter
@Entity
@Table(schema = "member", name = "agreements")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Agreement extends BaseEntity<UUID> {

    @Id
    private UUID id;

    private UUID memberId;

    @Enumerated(EnumType.STRING)
    private AgreementType type;

    private String version;
    private boolean agreed;

    /** 가입. 필수 항목은 모두 현재 버전에 동의했고, 신체 정보(선택)는 {@code bodyInfo}일 때만 동의했다. */
    public static List<Agreement> signup(UUID memberId, boolean bodyInfo) {
        return Arrays.stream(AgreementType.values()).map(type -> {
            Agreement agreement = new Agreement();
            agreement.id = UuidV7.create();
            agreement.memberId = memberId;
            agreement.type = type;
            agreement.version = type.version;
            agreement.agreed = type != AgreementType.BODY_INFO || bodyInfo;
            return agreement;
        }).toList();
    }
}
