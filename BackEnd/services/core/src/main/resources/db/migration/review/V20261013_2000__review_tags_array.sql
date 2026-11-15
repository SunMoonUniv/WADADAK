-- 태그를 course 태그와 같은 배열 컬럼으로 옮기고 review_tags 테이블을 지운다.
-- 별점·진행도·사진 순서는 다른 모듈처럼 INTEGER로 맞춘다(엔티티 int와 바로 맞음).
ALTER TABLE review.reviews
    ADD COLUMN tags VARCHAR(20)[] NOT NULL DEFAULT '{}'
        CHECK (tags <@ ARRAY ['NIGHT_VIEW', 'FEW_SIGNALS', 'GOOD_SURFACE', 'CROWDED']::VARCHAR(20)[]);

UPDATE review.reviews r
SET tags = t.tags
FROM (SELECT review_id, array_agg(tag ORDER BY tag)::VARCHAR(20)[] AS tags FROM review.review_tags GROUP BY review_id) t
WHERE t.review_id = r.id;

DROP TABLE review.review_tags;

ALTER TABLE review.reviews
    ALTER COLUMN rating TYPE INTEGER,
    ALTER COLUMN safety_rating TYPE INTEGER,
    ALTER COLUMN road_rating TYPE INTEGER,
    ALTER COLUMN lighting_rating TYPE INTEGER,
    ALTER COLUMN amenity_rating TYPE INTEGER,
    ALTER COLUMN best_progress_percent TYPE INTEGER;

ALTER TABLE review.review_photos
    ALTER COLUMN display_order TYPE INTEGER;

ALTER TABLE review.course_run_records
    ALTER COLUMN progress_percent TYPE INTEGER;
