package com.wadadak.member.internal;

import com.wadadak.common.entity.BaseEntity;
import com.wadadak.common.entity.UuidV7;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

@Getter
@Entity
@Table(schema = "member", name = "members")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class Member extends BaseEntity<UUID> {

    enum Status { ACTIVE, WITHDRAWN }

    @Id
    private UUID id;

    @Enumerated(EnumType.STRING)
    private Status status;

    @Enumerated(EnumType.STRING)
    private SocialProvider socialProvider;

    private String socialId;
    private String email;
    private String nickname;
    private String bio;
    private String regionCode;
    private String affiliation;

    @Enumerated(EnumType.STRING)
    private RunningExperience runningExperience;

    private boolean infoPublic;
    private boolean profileSearchable;
    private Instant termsAgreedAt;
    private Instant withdrawnAt;

    @Version
    private Long version;

    static Member join(SocialAccount account, SignupRequest request, Instant now) {
        Member member = new Member();
        member.id = UuidV7.create();
        member.status = Status.ACTIVE;
        member.socialProvider = account.provider();
        member.socialId = account.socialId();
        member.email = request.agreements().email() ? account.email() : null;
        member.nickname = request.nickname().strip();
        member.bio = blankToNull(request.bio());
        member.regionCode = request.regionCode();
        member.affiliation = blankToNull(request.affiliation());
        member.runningExperience = request.runningExperience();
        member.infoPublic = true;
        member.profileSearchable = true;
        member.termsAgreedAt = now;
        return member;
    }

    boolean isWithdrawn() {
        return status == Status.WITHDRAWN;
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }
}
