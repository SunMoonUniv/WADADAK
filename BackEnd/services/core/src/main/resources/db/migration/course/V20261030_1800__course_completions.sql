-- 코스 완주 한 건마다 한 줄(F11). G4 카드의 `최근 주행`(마지막으로 완주한 날)을 낸다(정책 문서 4.1 `G4 · B7 누적 주행 · 최근 주행`).
-- 완주 수(course_stats.completion_count)와 같은 이벤트 · 같은 조건(공개 중인 코스만)으로 넣고 지워 둘이 어긋나지 않는다.
-- 기록을 지우면(RunRecordDeletedEvent, 회원 탈퇴 포함) 줄을 지우지 않고 deleted_at을 남긴다. 삭제가 완주보다 먼저 와도
-- 늦게 온 완주가 다시 살리지 않는다(개발 정책 5.4). 코스가 DELETED가 되면 그 코스의 줄을 모두 지운다.
-- 이 표가 생기기 전 완주는 줄이 없다. 다른 모듈 표를 읽어 채울 수 없어서다.
CREATE TABLE course.course_completions
(
    -- run 모듈의 러닝 기록 ID. 다른 스키마라 FK는 없다
    run_record_id UUID        NOT NULL PRIMARY KEY,
    course_id     UUID        NOT NULL REFERENCES course.courses (id),
    -- 서버가 확정한 완주 시각. 기록 삭제를 먼저 받은 줄은 비어 있다
    completed_at  TIMESTAMPTZ,
    deleted_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL,
    updated_at    TIMESTAMPTZ NOT NULL
);

-- 코스마다 마지막 완주(G4 목록)
CREATE INDEX course_completions_course_id_idx ON course.course_completions (course_id, completed_at DESC) WHERE deleted_at IS NULL;
