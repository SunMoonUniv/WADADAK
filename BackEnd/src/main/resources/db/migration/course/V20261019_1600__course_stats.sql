-- 코스 통계(F11, 개발 정책 5.6). 완주 · 기록 삭제 · 리뷰 이벤트와 코스 상세 조회로 늘고 준다.
-- 증감은 원자적 UPSERT로 하고(개발 정책 5.4), 같은 이벤트를 두 번 반영하지 않게 processed_events에 먼저 적는다.
-- 행은 첫 증감 때 만든다. 행이 없는 코스는 모두 0이다. 공개 중(ACTIVE)인 코스만 바뀌고,
-- 코스가 DELETED가 되면 그 코스의 두 통계 행을 지운다(개발 정책 6.2).
-- 도전 수(인기순)는 run이 CourseRunStartedEvent를 발행하면 열을 더한다.

-- 코스 누적 통계(코스와 1:1).
CREATE TABLE course.course_stats
(
    course_id          UUID        NOT NULL PRIMARY KEY REFERENCES course.courses (id),
    -- 서버가 확정한 완주 수와 그 완주들의 코스 총 소요시간 합(초).
    -- 평균 페이스 = 합 ÷ 완주 수 ÷ 코스 거리(km). 경로는 바꿀 수 없어 코스 거리가 곧 완주 거리다(정책 B7).
    completion_count   INTEGER     NOT NULL DEFAULT 0,
    completion_seconds BIGINT      NOT NULL DEFAULT 0,
    -- 코스 상세(B1) 조회 수. 인기순 2차 기준(FIL-01)
    view_count         BIGINT      NOT NULL DEFAULT 0,
    -- 리뷰 전체 별점 합과 리뷰 수. 평점 = 합 ÷ 수, 소수 첫째 자리 반올림(리뷰 API와 같다)
    rating_sum         INTEGER     NOT NULL DEFAULT 0,
    review_count       INTEGER     NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL,
    updated_at         TIMESTAMPTZ NOT NULL
);

-- 코스 일별 통계(Asia/Seoul 날짜). 기간 정렬(FIL-09)이 고른 기간의 합을 낸다.
CREATE TABLE course.course_daily_stats
(
    id           UUID        NOT NULL PRIMARY KEY,
    course_id    UUID        NOT NULL REFERENCES course.courses (id),
    stat_date    DATE        NOT NULL,
    view_count   INTEGER     NOT NULL DEFAULT 0,
    -- 리뷰는 작성일 행에 반영한다. 수정 · 삭제도 작성일 행을 바꾼다(개발 정책 5.6)
    rating_sum   INTEGER     NOT NULL DEFAULT 0,
    review_count INTEGER     NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL,
    updated_at   TIMESTAMPTZ NOT NULL,
    CONSTRAINT course_daily_stats_uk UNIQUE (course_id, stat_date)
);

-- 증감형 이벤트 처리 기록(개발 정책 5.4). 같은 이벤트를 다시 받으면 0행이라 증감하지 않는다.
-- listener는 처리하는 곳의 이름이다. 코드에서 상수로 두고 바꾸지 않는다.
CREATE TABLE course.processed_events
(
    event_id     UUID         NOT NULL,
    listener     VARCHAR(100) NOT NULL,
    processed_at TIMESTAMPTZ  NOT NULL,
    PRIMARY KEY (event_id, listener)
);
