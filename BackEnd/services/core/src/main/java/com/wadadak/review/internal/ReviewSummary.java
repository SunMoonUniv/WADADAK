package com.wadadak.review.internal;

/**
 * 코스 평점 요약(B8-02·G2 상단). 저장해 두지 않고 조회할 때 리뷰에서 바로 계산한다(DB 구조 3.4).
 * 평균은 모두 소수 첫째 자리에서 반올림한다(4.35 → 4.4).
 *
 * @param reviewCount   리뷰 수. "리뷰 128"·"리뷰 128개 모두 보기"
 * @param averageRating 전체 별점 평균. 리뷰가 없으면 {@code null}
 * @param ratingCounts  별점별 리뷰 수(분포 막대)
 * @param itemAverages  항목별 평균. 리뷰가 없으면 모두 {@code null}
 */
record ReviewSummary(int reviewCount, Double averageRating, RatingCounts ratingCounts, ItemAverages itemAverages) {

    /** 리뷰가 없거나 숨김·삭제된 코스 */
    static final ReviewSummary EMPTY = new ReviewSummary(0, null, new RatingCounts(0, 0, 0, 0, 0),
            new ItemAverages(null, null, null, null));

    /** 별 5개 ~ 1개를 준 리뷰 수 */
    record RatingCounts(int five, int four, int three, int two, int one) {
    }

    /** 안전성·도로 상태·야간 조명·편의시설 평균 */
    record ItemAverages(Double safety, Double road, Double lighting, Double amenity) {
    }
}
