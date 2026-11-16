CREATE SCHEMA review;

-- 리뷰. 회원당 코스별 1개다. 다시 달린 뒤에는 기존 리뷰를 수정한다(정책 공통 5).
CREATE TABLE review.reviews
(
    id                    UUID        NOT NULL PRIMARY KEY,
    -- course·member·run 모듈 ID라 FK를 걸지 않는다(개발 정책 2장).
    course_id             UUID        NOT NULL,
    member_id             UUID        NOT NULL,
    -- 리뷰의 근거 기록(run 기록 ID). 기록이 삭제돼도 남겨 B10-1 "근거 기록이 삭제됐어요"를 알린다.
    source_run_record_id  UUID        NOT NULL,
    -- 전체 별점과 항목별 평가 4개. 모두 필수, 별 1~5개(정책 공통 5).
    rating                SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    safety_rating         SMALLINT    NOT NULL CHECK (safety_rating BETWEEN 1 AND 5),
    road_rating           SMALLINT    NOT NULL CHECK (road_rating BETWEEN 1 AND 5),
    lighting_rating       SMALLINT    NOT NULL CHECK (lighting_rating BETWEEN 1 AND 5),
    amenity_rating        SMALLINT    NOT NULL CHECK (amenity_rating BETWEEN 1 AND 5),
    -- 한줄 후기. 선택 입력, 200자까지.
    content               VARCHAR(200),
    -- 리뷰에 표시하는 그 회원의 이 코스 최고 진행도(%). 근거 기록이 삭제돼도 다시 계산하지 않는다(정책 공통 5).
    best_progress_percent SMALLINT    NOT NULL CHECK (best_progress_percent BETWEEN 0 AND 100),
    -- 작성 시각은 수정해도 바뀌지 않는다. 리뷰 이벤트의 createdAt이고 course 일별 평점이 이 날짜에 쌓인다(개발 정책 5.6).
    created_at            TIMESTAMPTZ NOT NULL,
    updated_at            TIMESTAMPTZ NOT NULL,
    CONSTRAINT reviews_member_course_uk UNIQUE (member_id, course_id)
);
-- B8·G2 정렬: 최신순, 높은 평점·낮은 평점(같은 별점은 최신순).
CREATE INDEX reviews_course_id_created_at_idx ON review.reviews (course_id, created_at DESC);
CREATE INDEX reviews_course_id_rating_idx ON review.reviews (course_id, rating, created_at DESC);

-- 리뷰 사진. 리뷰당 5장까지(정책 공통 5). S3 키만 저장한다(개발 정책 7장 사진 업로드).
CREATE TABLE review.review_photos
(
    id            UUID        NOT NULL PRIMARY KEY,
    review_id     UUID        NOT NULL REFERENCES review.reviews (id) ON DELETE CASCADE,
    photo_key     VARCHAR(100) NOT NULL CHECK (photo_key LIKE 'review/%'),
    display_order SMALLINT    NOT NULL CHECK (display_order BETWEEN 0 AND 4),
    created_at    TIMESTAMPTZ NOT NULL,
    updated_at    TIMESTAMPTZ NOT NULL,
    CONSTRAINT review_photos_review_order_uk UNIQUE (review_id, display_order)
);

-- 리뷰 태그. 정해진 4개 중 여러 개를 고른다(B2).
CREATE TABLE review.review_tags
(
    review_id UUID        NOT NULL REFERENCES review.reviews (id) ON DELETE CASCADE,
    tag       VARCHAR(20) NOT NULL CHECK (tag IN ('NIGHT_VIEW', 'FEW_SIGNALS', 'GOOD_SURFACE', 'CROWDED')),
    PRIMARY KEY (review_id, tag)
);

-- run이 확정한 코스 주행 기록 복사본(RunSessionEndedEvent). 리뷰 작성 자격과 리뷰 카드의 완주 횟수에 쓴다.
-- 완주해도 리뷰 자격이 없을 수 있어(예: 1km 코스를 0.95km 인정으로 완주) 두 판정을 따로 저장한다(정책 5.1).
-- run 기록 ID가 PK라서 같은 이벤트가 다시 와도 한 번만 저장된다(개발 정책 5.4 삽입형).
CREATE TABLE review.course_run_records
(
    run_record_id          UUID        NOT NULL PRIMARY KEY,
    course_id              UUID        NOT NULL,
    member_id              UUID        NOT NULL,
    review_eligible        BOOLEAN     NOT NULL,
    completed              BOOLEAN     NOT NULL,
    progress_percent       SMALLINT    NOT NULL CHECK (progress_percent BETWEEN 0 AND 100),
    -- B2 리뷰 작성 화면 상단 "5.2km · 2026.09.08 완주 100% · 27:14"
    course_distance_meters INTEGER     NOT NULL CHECK (course_distance_meters > 0),
    course_elapsed_seconds INTEGER     NOT NULL CHECK (course_elapsed_seconds >= 0),
    ended_at               TIMESTAMPTZ NOT NULL,
    -- 기록이 삭제됐다. 삭제가 주행 기록보다 먼저 처리돼도 되살아나지 않게 행을 남긴다.
    deleted                BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at             TIMESTAMPTZ NOT NULL,
    updated_at             TIMESTAMPTZ NOT NULL
);
-- 리뷰 자격 확인·최고 진행도·완주 횟수: 회원 × 코스
CREATE INDEX course_run_records_member_course_idx ON review.course_run_records (member_id, course_id) WHERE NOT deleted;
-- 코스 삭제 때 그 코스의 행을 지운다.
CREATE INDEX course_run_records_course_id_idx ON review.course_run_records (course_id);

-- 코스 상태 복사본(개발 정책 5.4 상태 복사형). 숨김·삭제된 코스만 행이 있고, 행이 없으면 ACTIVE다.
-- 삭제된 코스도 행을 남겨 늦게 온 주행 기록을 받지 않는다.
CREATE TABLE review.course_status_copies
(
    course_id      UUID        NOT NULL PRIMARY KEY,
    status         VARCHAR(10) NOT NULL CHECK (status IN ('HIDDEN', 'DELETED')),
    source_version BIGINT      NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL
);

-- 탈퇴 회원. 리뷰(사진 포함)와 주행 기록 복사본을 모두 지우고 이 표시만 남겨, 탈퇴 뒤에 도착한 주행 기록을 받지 않는다.
CREATE TABLE review.withdrawn_members
(
    member_id    UUID        NOT NULL PRIMARY KEY,
    withdrawn_at TIMESTAMPTZ NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL,
    updated_at   TIMESTAMPTZ NOT NULL
);
