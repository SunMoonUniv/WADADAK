package com.wadadak.ranking.internal.distance;

import com.wadadak.member.MemberProfile;

/**
 * 내 순위(E1 내 행). {@code status}가 {@code RANKED}가 아니면 {@code rank}·{@code topPercent}·{@code lastWeekRank}는 {@code null}이다.
 *
 * @param nickname               내 닉네임(`나 (닉네임)` 표시용). 상태와 관계없이 채운다. 프로필 조회에 실패하면 {@code null}
 * @param profileImageUrl        내 프로필 사진. 없거나 조회에 실패하면 {@code null}
 * @param distanceMeters         그 기간 내 거리(m). 기록이 없으면 {@code null}
 * @param thisWeekDistanceMeters 이번 주 내 거리(m, 전체 랭킹 탭의 "이번 주 +48.2km"). 지역 탭에서는 {@code null}
 * @param runCount               그 기간 내 기록 수
 * @param topPercent             상위 비율(%, 전체 랭킹 탭). 순위 ÷ 참여 러너 수 × 100 올림. 지역 탭에서는 {@code null}
 * @param lastWeekRank           지난주 마지막 순위(지역 탭의 "지난주 19위 ▲7"). 지난주에 순위가 없었으면 {@code null}
 */
record MyDistanceRanking(Status status, Integer rank, String nickname, String profileImageUrl, Integer distanceMeters,
                         Integer thisWeekDistanceMeters, Integer runCount, Integer topPercent, Integer lastWeekRank) {

    /** 기록 값만. 닉네임·사진은 {@link #withProfile}로 붙인다 */
    MyDistanceRanking(Status status, Integer rank, Integer distanceMeters, Integer thisWeekDistanceMeters,
                      Integer runCount, Integer topPercent, Integer lastWeekRank) {
        this(status, rank, null, null, distanceMeters, thisWeekDistanceMeters, runCount, topPercent, lastWeekRank);
    }

    MyDistanceRanking withProfile(MemberProfile profile) {
        return profile == null ? this : new MyDistanceRanking(status, rank, profile.nickname(), profile.profileImageUrl(),
                distanceMeters, thisWeekDistanceMeters, runCount, topPercent, lastWeekRank);
    }

    enum Status {
        /** 순위가 있다 */
        RANKED,
        /** 그 기간 기록이 없다 */
        NO_RECORD,
        /** 내 정보 공개를 꺼서 순위에서 빠졌다. 앱은 순위 대신 `비공개 중`을 표시한다. 거리 값은 채운다 */
        PRIVATE,
        /** 지역 탭에서 이번 주 내 활동 지역이 아닌 지역을 보고 있다 */
        OTHER_REGION
    }
}
