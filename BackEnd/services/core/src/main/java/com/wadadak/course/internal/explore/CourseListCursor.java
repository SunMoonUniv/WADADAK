package com.wadadak.course.internal.explore;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.UUID;

/**
 * 코스 목록 커서. 마지막으로 보낸 코스의 정렬 값과 ID다. 위치(몇 번째)가 아니라서 쪽을 넘기는 사이
 * 코스가 새로 등록되거나 숨겨져도 같은 코스가 두 번 나오거나 빠지지 않는다. 앱에는 Base64 문자열로 보내고 앱은 그대로 돌려보낸다.
 *
 * @param key 최신순은 등록 시각(1970년부터 마이크로초), 가까운순은 출발점까지 거리(m),
 *            평점순은 `평점_리뷰 수_등록 시각`(평점이 없으면 -1),
 *            인기순은 `도전 수_조회 수_리뷰 수_등록 시각`(기간이 있으면 그 기간의 수), 실시간순은 `러너 수_도전 수_조회 수_리뷰 수_등록 시각`
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

    /** 인기순. [popularity]는 정렬에 쓴 도전 수 · 조회 수 · 리뷰 수다 */
    static CourseListCursor popular(Counts popularity, UUID id) {
        return new CourseListCursor(CourseListSort.POPULAR, popularity.key(), id);
    }

    /** 실시간순. [counts]는 정렬에 쓴 러너 수 · 도전 수 · 조회 수 · 리뷰 수다 */
    static CourseListCursor live(Counts counts, UUID id) {
        return new CourseListCursor(CourseListSort.LIVE, counts.key(), id);
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
                    case POPULAR -> cursor.counts(POPULAR_COUNTS);
                    case LIVE -> cursor.counts(LIVE_COUNTS);
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

    /** 인기순 커서의 수 개수(도전 수 · 조회 수 · 리뷰 수). */
    static final int POPULAR_COUNTS = 3;

    /** 실시간순 커서의 수 개수(러너 수 · 도전 수 · 조회 수 · 리뷰 수). */
    static final int LIVE_COUNTS = 4;

    /** 인기순 · 실시간순 정렬 값. 수가 [size]개가 아니거나 0보다 작으면 읽지 못한다 */
    Counts counts(int size) {
        String[] parts = key.split("_");
        if (parts.length != size + 1) {
            throw new IllegalArgumentException(key);
        }
        List<Long> counts = new ArrayList<>();
        for (int i = 0; i < size; i++) {
            long count = Long.parseLong(parts[i]);
            if (count < 0) {
                throw new IllegalArgumentException(key);
            }
            counts.add(count);
        }
        return new Counts(counts, Instant.EPOCH.plus(Long.parseLong(parts[size]), ChronoUnit.MICROS));
    }

    /** 평점순 정렬 값. 평점(없으면 -1) · 리뷰 수 · 등록 시각 순으로 비교한다 */
    record RatingKey(BigDecimal rating, int reviewCount, Instant createdAt) {
    }

    /** 인기순 · 실시간순 정렬 값. 앞의 수부터 차례로, 다 같으면 등록 시각으로 비교한다 */
    record Counts(List<Long> counts, Instant createdAt) {

        String key() {
            StringBuilder key = new StringBuilder();
            for (long count : counts) {
                key.append(count).append('_');
            }
            return key.append(ChronoUnit.MICROS.between(Instant.EPOCH, createdAt)).toString();
        }
    }
}
