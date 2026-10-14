package com.wadadak.review.internal;

import com.wadadak.member.MemberProfile;

import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * 리뷰 카드 한 장(B8-04·G2). 목록과 내 리뷰(G2 상단·B10 수정 화면 초기값)가 같은 모양을 쓴다.
 *
 * @param nickname            표시용. 회원 정보를 못 가져오면 {@code null}이고, 카드는 그대로 보여준다(개발 정책 4.4)
 * @param profileImageUrl     프로필 사진이 없거나 회원 정보를 못 가져오면 {@code null}
 * @param mine                요청자 본인 리뷰면 {@code true}
 * @param content             한줄 후기. 없으면 {@code null}
 * @param photos              보이는 순서대로. B10에서 수정할 때 남길 사진은 이 키를 다시 보낸다
 * @param bestProgressPercent 이 회원의 이 코스 최고 진행도(%). "완주 100%"·"62% 주행"으로 표시한다
 * @param completedCount      이 회원의 이 코스 완주 횟수(삭제된 기록 제외). 0이면 표시하지 않는다(정책 제4부 4.1 D-09)
 * @param createdAt           작성 시각. 수정해도 바뀌지 않는다
 */
record ReviewCard(UUID reviewId, UUID memberId, String nickname, String profileImageUrl, boolean mine,
                  int rating, int safetyRating, int roadRating, int lightingRating, int amenityRating,
                  String content, Set<ReviewTag> tags, List<ReviewView.Photo> photos,
                  int bestProgressPercent, int completedCount, Instant createdAt) {

    /**
     * 닉네임·프로필 사진과 리뷰 사진을 채운 카드. record는 값을 바꿀 수 없어서 새로 만든다.
     *
     * @param profile 못 가져왔으면 {@code null}. 그때는 닉네임·프로필 사진을 비워 둔다
     */
    ReviewCard with(MemberProfile profile, List<ReviewView.Photo> photos) {
        return new ReviewCard(reviewId, memberId, profile == null ? null : profile.nickname(),
                profile == null ? null : profile.profileImageUrl(), mine,
                rating, safetyRating, roadRating, lightingRating, amenityRating,
                content, tags, photos, bestProgressPercent, completedCount, createdAt);
    }
}
