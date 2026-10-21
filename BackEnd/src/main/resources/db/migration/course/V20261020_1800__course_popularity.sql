-- 인기순 · 실시간순(FIL-01, 개발 정책 5.6). run의 코스 러닝 시작 · 현재 러너 수 이벤트로 바뀐다.

-- 도전 수(인기순 1차 기준). 코스 러닝을 실제로 시작한 세션 수다(CourseRunStartedEvent +1).
-- 그 세션 기록을 지우면(RunRecordDeletedEvent) 시작한 날짜 행에서 뺀다.
-- 기간 인기순(FIL-09)은 일별 행을 기간만큼 더한다.
ALTER TABLE course.course_stats
    ADD COLUMN challenge_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE course.course_daily_stats
    ADD COLUMN challenge_count INTEGER NOT NULL DEFAULT 0;

-- 현재 러너 수 복사본(상태 복사형, 개발 정책 5.4). CourseActiveRunnersChangedEvent의 version이 저장된 값보다 클 때만 바꾼다.
-- 행이 없는 코스는 0명이다. 공개 중(ACTIVE)인 코스만 바뀌고, 코스가 DELETED가 되면 지운다(개발 정책 6.2).
CREATE TABLE course.course_active_runners
(
    course_id      UUID        NOT NULL PRIMARY KEY REFERENCES course.courses (id),
    active_count   INTEGER     NOT NULL,
    source_version BIGINT      NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL
);
