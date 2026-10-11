package com.wadadak.member.internal.account;

import com.wadadak.common.entity.BaseEntity;
import com.wadadak.common.entity.UuidV7;
import com.wadadak.member.internal.social.SocialAccount;
import com.wadadak.member.internal.social.SocialProvider;
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
public class Member extends BaseEntity<UUID> {

    enum Status { ACTIVE, WITHDRAWN }

    @Id
    private UUID id;

    @Enumerated(EnumType.STRING)
    private Status status;

    @Enumerated(EnumType.STRING)
    private SocialProvider socialProvider;

    private String socialId;
    private String nickname;
    private String bio;
    private String regionCode;
    private String affiliation;

    @Enumerated(EnumType.STRING)
    private RunningExperience runningExperience;

    private boolean infoPublic;
    private boolean profileSearchable;
    private Instant withdrawnAt;

    @Version
    private Long version;

    /** 가입. 약관 동의는 {@link Agreement}에 따로 남긴다. */
    public static Member join(SocialAccount account, String nickname, String bio, String regionCode,
                              String affiliation, RunningExperience runningExperience) {
        Member member = new Member();
        member.id = UuidV7.create();
        member.status = Status.ACTIVE;
        member.socialProvider = account.provider();
        member.socialId = account.socialId();
        member.nickname = nickname.strip();
        member.bio = blankToNull(bio);
        member.regionCode = regionCode;
        member.affiliation = blankToNull(affiliation);
        member.runningExperience = runningExperience;
        member.infoPublic = true;
        member.profileSearchable = true;
        return member;
    }

    public boolean isWithdrawn() {
        return status == Status.WITHDRAWN;
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }
}
