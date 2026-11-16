CREATE SCHEMA ranking;

-- 코스 랭킹 엔트리. 서버가 확정한 완주 기록 1건이 1행이다(정책 공통 6).
-- run 기록 ID가 PK라서 같은 완주 이벤트가 다시 와도 한 번만 저장된다(개발 정책 5.4 삽입형).
-- 회원별 대표 기록과 순위는 조회할 때 기간·공개 여부를 걸러 계산한다.
CREATE TABLE ranking.course_ranking_entries
(
    run_record_id          UUID        NOT NULL PRIMARY KEY,
    -- course·member 모듈 ID라 FK를 걸지 않는다(개발 정책 2장).
    course_id              UUID        NOT NULL,
    member_id              UUID        NOT NULL,
    -- 코스 총 소요시간(정수 초). 순위는 이 값으로만 매긴다.
    course_elapsed_seconds INTEGER     NOT NULL CHECK (course_elapsed_seconds > 0),
    -- 페이스 계산용 코스 전체 거리(m)
    course_distance_meters INTEGER     NOT NULL CHECK (course_distance_meters > 0),
    completed_at           TIMESTAMPTZ NOT NULL,
    -- 기간(이번 주·이번 달)을 나누는 기준
    registered_at          TIMESTAMPTZ NOT NULL,
    -- 기록이 삭제됐다. 삭제가 완주보다 먼저 처리돼도 되살아나지 않게 행을 남긴다.
    deleted                BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at             TIMESTAMPTZ NOT NULL,
    updated_at             TIMESTAMPTZ NOT NULL
);
CREATE INDEX course_ranking_entries_course_id_idx ON ranking.course_ranking_entries (course_id) WHERE NOT deleted;
CREATE INDEX course_ranking_entries_member_id_idx ON ranking.course_ranking_entries (member_id);

-- 코스 상태 복사본(개발 정책 5.4 상태 복사형). 숨김·삭제된 코스만 행이 있고, 행이 없으면 ACTIVE다.
-- 삭제된 코스도 행을 남겨 늦게 온 완주 기록을 받지 않는다.
CREATE TABLE ranking.course_status_copies
(
    course_id      UUID        NOT NULL PRIMARY KEY,
    status         VARCHAR(10) NOT NULL CHECK (status IN ('HIDDEN', 'DELETED')),
    source_version BIGINT      NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL
);

-- 회원 공개 복사본(상태 복사형). 행이 없으면 공개다. 비공개 회원은 순위 계산과 고스트 후보에서 빠진다.
CREATE TABLE ranking.member_visibility_copies
(
    member_id      UUID        NOT NULL PRIMARY KEY,
    visible        BOOLEAN     NOT NULL,
    source_version BIGINT      NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL
);

-- 탈퇴 회원. 랭킹 기록은 모두 지우고 이 표시만 남겨, 탈퇴 뒤에 도착한 완주 기록을 받지 않는다.
CREATE TABLE ranking.withdrawn_members
(
    member_id    UUID        NOT NULL PRIMARY KEY,
    withdrawn_at TIMESTAMPTZ NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL,
    updated_at   TIMESTAMPTZ NOT NULL
);
