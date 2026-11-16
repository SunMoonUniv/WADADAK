package com.wadadak.member.internal.admin;

import com.wadadak.common.region.Region;
import com.wadadak.member.internal.account.AgreementType;
import com.wadadak.member.internal.account.BodyInfo;
import com.wadadak.member.internal.account.RunningExperience;
import com.wadadak.member.internal.social.SocialProvider;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 운영자 회원 관리(ADM-1 · ADM-1-1)의 응답 모양. 탈퇴 회원은 개인정보를 지워서(Member.withdraw) 보이지 않는다.
 */
final class AdminMemberViews {

    private AdminMemberViews() {
    }

    /** ADM-1 위 숫자 카드. 이번 주 · 이번 달은 Asia/Seoul 기준이고 주는 월요일부터다. 탈퇴 회원은 세지 않는다. */
    record AdminMemberStats(long totalMembers, long weekJoined, long monthJoined) {
    }

    /**
     * ADM-1 회원 표 한 줄.
     *
     * @param region 활동 지역. 코드가 지역 목록에서 사라졌으면 {@code null}
     */
    record AdminMemberRow(UUID memberId, String nickname, String profileImageUrl, SocialProvider socialProvider,
                          Region region, String affiliation, RunningExperience runningExperience, Instant joinedAt) {
    }

    /**
     * ADM-1-1 회원 상세. members 컬럼 전부와 항목별 최신 약관 동의(정보만 보고 고치지 않는다).
     *
     * @param profileImageKey   사진 저장소 키. 없으면 {@code null}
     * @param updatedAt         회원 정보를 마지막으로 바꾼 시각
     * @param nicknameChangedAt 닉네임을 마지막으로 바꾼 시각. 바꾼 적 없으면 {@code null}
     * @param bodyInfo          신체 정보. 입력하지 않았거나 동의를 껐으면 {@code null}
     * @param agreements        항목 순서대로, 항목마다 가장 최근 동의
     */
    record AdminMemberDetail(UUID memberId, String nickname, String bio, Region region, String regionCode,
                             String affiliation, RunningExperience runningExperience,
                             String profileImageKey, String profileImageUrl,
                             SocialProvider socialProvider, String socialId, Instant joinedAt, Instant updatedAt,
                             Instant nicknameChangedAt, BodyInfo bodyInfo, boolean infoPublic, boolean profileSearchable,
                             List<AdminAgreement> agreements) {
    }

    /** @param agreedAt 이 동의(또는 철회)를 남긴 시각 */
    record AdminAgreement(AgreementType type, boolean agreed, String version, Instant agreedAt) {
    }
}
