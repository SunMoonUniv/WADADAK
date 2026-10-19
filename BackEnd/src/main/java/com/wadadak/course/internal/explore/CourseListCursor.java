package com.wadadak.course.internal.explore;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.UUID;

/**
 * 코스 목록 커서. 마지막으로 보낸 코스의 정렬 값과 ID다. 위치(몇 번째)가 아니라서 쪽을 넘기는 사이
 * 코스가 새로 등록되거나 숨겨져도 같은 코스가 두 번 나오거나 빠지지 않는다. 앱에는 Base64 문자열로 보내고 앱은 그대로 돌려보낸다.
 *
 * @param key 최신순은 등록 시각(1970년부터 마이크로초), 가까운순은 출발점까지 거리(m),
 *            평점순은 `평점_리뷰 수_등록 시각`(평점이 없으면 -1)
 */
record CourseListCursor(CourseListSort sort, String key, UUID id) {

    static CourseListCursor latest(Instant createdAt, UUID id) {
        return new CourseListCursor(CourseListSort.LATEST, String.valueOf(ChronoUnit.MICROS.between(Instant.EPOCH, createdAt)), id);
    }

    static CourseListCursor nearest(double distanceMeters, UUID id) {
        return new CourseListCursor(CourseListSort.NEAREST, String.valueOf(distanceMeters), id);
    }

    /** @param rating 정렬에 쓴 평점. 리뷰가 없으면 -1 */
    static CourseListCursor rating(BigDecimal rating, int reviewCount, Instant createdAt, UUID id) {
        return new CourseListCursor(CourseListSort.RATING,
                rating.toPlainString() + "_" + reviewCount + "_" + ChronoUnit.MICROS.between(Instant.EPOCH, createdAt), id);
    }

    /**
     * 비어 있으면 첫 쪽(null).
     *
     * @throws AppException COMMON-001 — 읽을 수 없거나 [sort]가 아닌 다른 정렬의 커서
     */
    static CourseListCursor decode(String value, CourseListSort sort) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            String[] parts = new String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8).split(":");
            CourseListCursor cursor = new CourseListCursor(CourseListSort.valueOf(parts[0]), parts[1], UUID.fromString(parts[2]));
            if (parts.length == 3 && cursor.sort() == sort) {
                // 정렬 값도 읽어 본다.
                switch (sort) {
                    case LATEST -> cursor.createdAt();
                    case NEAREST -> cursor.distanceMeters();
                    case RATING -> cursor.ratingKey();
                }
                return cursor;
            }
        } catch (RuntimeException ignored) {
            // 아래에서 잘못된 커서로 거절한다
        }
        throw new AppException(CommonErrorCode.INVALID_REQUEST, "cursor: 잘못된 값입니다.");
    }

    String encode() {
        return Base64.getUrlEncoder().withoutPadding()
                .encodeToString((sort + ":" + key + ":" + id).getBytes(StandardCharsets.UTF_8));
    }

    Instant createdAt() {
        return Instant.EPOCH.plus(Long.parseLong(key), ChronoUnit.MICROS);
    }

    double distanceMeters() {
        double distance = Double.parseDouble(key);
        if (!Double.isFinite(distance)) {
            throw new NumberFormatException(key);
        }
        return distance;
    }

    RatingKey ratingKey() {
        String[] parts = key.split("_");
        if (parts.length != 3) {
            throw new IllegalArgumentException(key);
        }
        return new RatingKey(new BigDecimal(parts[0]), Integer.parseInt(parts[1]),
                Instant.EPOCH.plus(Long.parseLong(parts[2]), ChronoUnit.MICROS));
    }

    /** 평점순 정렬 값. 평점(없으면 -1) · 리뷰 수 · 등록 시각 순으로 비교한다 */
    record RatingKey(BigDecimal rating, int reviewCount, Instant createdAt) {
    }
}
