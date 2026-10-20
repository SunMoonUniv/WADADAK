package com.wadadak.member.internal.account;

import com.wadadak.common.config.TimeConfig;
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

    /** 프로필 사진 키 앞부분(개발 정책 7장 사진 업로드). 가입(F2)과 프로필 편집(F6)이 같이 쓴다 */
    public static final String PHOTO_MODULE = "member";

    /** 닉네임을 바꾼 날부터 이만큼 지나야 다시 바꿀 수 있다(F6) */
    public static final int NICKNAME_CHANGE_DAYS = 30;

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
    /** 닉네임을 마지막으로 바꾼 시각. 가입 뒤 한 번도 안 바꿨으면 {@code null} */
    private Instant nicknameChangedAt;
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

    /**
     * 닉네임을 다시 바꿀 수 있는 시각. 바꾼 날(Asia/Seoul)로부터 {@value #NICKNAME_CHANGE_DAYS}일 뒤 00:00이다.
     * 시각이 아니라 날짜로 세서, 앱이 보여 주는 "다음 변경 가능 2026.10.08"의 그날 0시부터 바꿀 수 있다.
     *
     * @return 한 번도 안 바꿨으면 {@code null}(바로 바꿀 수 있다)
     */
    public Instant nicknameChangeableAt() {
        return nicknameChangedAt == null ? null : nicknameChangedAt.atZone(TimeConfig.SEOUL).toLocalDate()
                .plusDays(NICKNAME_CHANGE_DAYS).atStartOfDay(TimeConfig.SEOUL).toInstant();
    }

    /**
     * MY 프로필 편집(F6) 저장. 화면의 값을 통째로 바꾼다. 규칙 확인(30일 · 중복 · 지역 · 사진)은 서비스가 먼저 한다.
     *
     * @param profileImageKey 지금 사진을 그대로 두려면 지금 키, 새 사진이면 새 키, 사진을 지우면 {@code null}
     * @param bodyInfo        신체 정보 동의를 끄면 {@code null}이라 네 값이 모두 지워진다(정책 공통 9)
     * @param now             닉네임이 바뀌었으면 이 시각을 바꾼 시각으로 남긴다
     */
    public void editProfile(String nickname, String bio, String regionCode, String affiliation,
                            RunningExperience runningExperience, String profileImageKey, BodyInfo bodyInfo, Instant now) {
        String newNickname = nickname.strip();
        if (!newNickname.equals(this.nickname)) {
            this.nickname = newNickname;
            this.nicknameChangedAt = now;
        }
        this.bio = blankToNull(bio);
        this.regionCode = regionCode;
        this.affiliation = blankToNull(affiliation);
        this.runningExperience = runningExperience;
        this.profileImageKey = profileImageKey;
        this.bodyInfo = bodyInfo;
    }

    public boolean isWithdrawn() {
        return status == Status.WITHDRAWN;
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }
}
