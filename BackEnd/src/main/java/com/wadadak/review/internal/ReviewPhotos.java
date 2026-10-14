package com.wadadak.review.internal;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.common.storage.UploadForm;
import com.wadadak.review.ReviewErrorCode;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * 리뷰 사진(정책 공통 5: 리뷰당 5장). 파일은 앱이 저장소에 직접 올리고, 여기에는 키만 순서대로 둔다(개발 정책 7장 사진 업로드).
 *
 * <p>엔티티 없이 {@link JdbcClient}로 다룬다. 수정하면 목록을 통째로 바꾸는데, JPA로 지우고 다시 넣으면
 * INSERT가 DELETE보다 먼저 나가서 순서 유니크(review_id, display_order)에 걸린다.
 */
@Component
@RequiredArgsConstructor
class ReviewPhotos {

    static final String MODULE = "review";
    static final int MAX_PHOTOS = 5;

    private final JdbcClient jdbc;
    private final ObjectStorage storage;

    /** 사진 한 장을 올릴 폼 */
    UploadForm uploadForm() {
        return storage.photoUploadForm(MODULE);
    }

    /**
     * 사진을 이 목록(보이는 순서)으로 바꾼다. 빠진 사진 파일은 커밋한 뒤 지운다.
     * 5장 넘으면 REVIEW-006, 올라오지 않았거나 겹치거나 다른 리뷰의 사진이면 REVIEW-007.
     */
    List<ReviewView.Photo> replace(UUID reviewId, List<String> keys) {
        if (keys.size() > MAX_PHOTOS) {
            throw new AppException(ReviewErrorCode.TOO_MANY_PHOTOS);
        }
        if (new HashSet<>(keys).size() < keys.size() || !keys.stream().allMatch(key -> storage.isUploadedPhoto(MODULE, key))) {
            throw new AppException(ReviewErrorCode.PHOTO_NOT_FOUND);
        }
        List<String> before = keys(reviewId);
        jdbc.sql("DELETE FROM review.review_photos WHERE review_id = :reviewId").param("reviewId", reviewId).update();
        try {
            for (int order = 0; order < keys.size(); order++) {
                jdbc.sql("""
                                INSERT INTO review.review_photos (id, review_id, photo_key, display_order, created_at, updated_at)
                                VALUES (:id, :reviewId, :key, :order, now(), now())""")
                        .param("id", UuidV7.create())
                        .param("reviewId", reviewId)
                        .param("key", keys.get(order))
                        .param("order", order)
                        .update();
            }
        } catch (DuplicateKeyException e) {
            // 사진 주소에 키가 보여서 남의 사진을 가져다 붙일 수 있다. 막지 않으면 그 리뷰를 지울 때 원래 리뷰의 사진 파일도 지워진다
            throw new AppException(ReviewErrorCode.PHOTO_NOT_FOUND);
        }
        storage.deleteAfterCommit(before.stream().filter(key -> !keys.contains(key)).toList());
        return views(keys);
    }

    /** 리뷰를 지울 때 사진 파일도 커밋한 뒤 지운다. 사진 행은 DB가 함께 지운다(ON DELETE CASCADE). */
    void deleteFiles(UUID reviewId) {
        storage.deleteAfterCommit(keys(reviewId));
    }

    /**
     * 삭제된 코스의 리뷰 사진 파일을 커밋한 뒤 지운다. 사진 행은 리뷰를 지울 때 DB가 함께 지우므로(ON DELETE CASCADE)
     * 리뷰를 지우기 전에 불러야 키를 읽을 수 있다.
     */
    void deleteFilesOfCourse(UUID courseId) {
        storage.deleteAfterCommit(jdbc.sql("""
                        SELECT p.photo_key
                        FROM review.review_photos p
                        JOIN review.reviews r ON r.id = p.review_id
                        WHERE r.course_id = :courseId""")
                .param("courseId", courseId)
                .query(String.class)
                .list());
    }

    /**
     * 여러 리뷰의 사진을 한 번에 읽는다(B8·G2 목록). 카드마다 따로 읽으면 리뷰 수만큼 쿼리가 나간다(N+1).
     * 리뷰마다 보이는 순서대로이고, 사진이 없는 리뷰는 결과에 없다.
     */
    Map<UUID, List<ReviewView.Photo>> photosOf(Collection<UUID> reviewIds) {
        if (reviewIds.isEmpty()) {
            return Map.of(); // 빈 IN ()은 SQL 문법 오류라 DB까지 가지 않는다
        }
        return jdbc.sql("""
                        SELECT review_id, photo_key FROM review.review_photos
                        WHERE review_id IN (:reviewIds)
                        ORDER BY review_id, display_order""")
                .param("reviewIds", reviewIds)
                .query((rs, rowNum) -> Map.entry(rs.getObject("review_id", UUID.class), rs.getString("photo_key")))
                .list()
                .stream()
                // 리뷰 ID별로 묶는다. 읽은 순서(display_order)가 그대로 목록 순서가 된다
                .collect(Collectors.groupingBy(Map.Entry::getKey,
                        Collectors.mapping(row -> new ReviewView.Photo(row.getValue(), storage.url(row.getValue())),
                                Collectors.toList())));
    }

    private List<String> keys(UUID reviewId) {
        return jdbc.sql("SELECT photo_key FROM review.review_photos WHERE review_id = :reviewId ORDER BY display_order")
                .param("reviewId", reviewId)
                .query(String.class)
                .list();
    }

    private List<ReviewView.Photo> views(List<String> keys) {
        return keys.stream().map(key -> new ReviewView.Photo(key, storage.url(key))).toList();
    }
}
