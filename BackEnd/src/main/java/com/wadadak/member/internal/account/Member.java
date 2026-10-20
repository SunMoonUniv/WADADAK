package com.wadadak.member.internal.account;

import com.wadadak.common.entity.BaseEntity;
import com.wadadak.common.entity.UuidV7;
import com.wadadak.member.internal.social.SocialAccount;
import com.wadadak.member.internal.social.SocialProvider;
import jakarta.persistence.Embedded;
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
    /** 사진 저장소 키({@code member/...}). 사진이 없으면 {@code null} */
    private String profileImageKey;

    @Enumerated(EnumType.STRING)
    private RunningExperience runningExperience;

    /** 신체 정보. 입력하지 않았으면 {@code null} */
    @Embedded
    private BodyInfo bodyInfo;

    private boolean infoPublic;
    private boolean profileSearchable;
    private Instant withdrawnAt;

    @Version
    private Long version;

    /** 가입. 약관 동의는 {@link Agreement}에 따로 남긴다. */
    public static Member join(SocialAccount account, String nickname, String bio, String regionCode,
                              String affiliation, RunningExperience runningExperience, String profileImageKey,
                              BodyInfo bodyInfo) {
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
        member.profileImageKey = profileImageKey;
        member.bodyInfo = bodyInfo;
        member.infoPublic = true;
        member.profileSearchable = true;
        return member;
    }

    /**
     * MY 설정(F4)의 내 정보 공개·프로필 검색 허용을 바꾼다.
     *
     * @return 내 정보 공개가 바뀌었으면 {@code true}. 그때만 다른 모듈(ranking 등)에 알린다
     */
    public boolean changeSettings(boolean infoPublic, boolean profileSearchable) {
        boolean visibilityChanged = this.infoPublic != infoPublic;
        this.infoPublic = infoPublic;
        this.profileSearchable = profileSearchable;
        return visibilityChanged;
    }

    public boolean isWithdrawn() {
        return status == Status.WITHDRAWN;
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }
}
