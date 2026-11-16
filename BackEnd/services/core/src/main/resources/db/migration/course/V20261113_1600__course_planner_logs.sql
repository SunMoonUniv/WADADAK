-- 코스 자동 생성 분석 로그(개발 정책 B3 · 로그, 2026-11-13). 내부 테스트 · 논문 분석용이고, 분석이 끝나면 두 테이블을 비운다.
-- 회원 ID와 사용자의 현재 위치는 남기지 않는다(후보 경로 점은 남긴다). member_hash = sha256(회원 ID)라 같은 사람끼리만 묶이고 누구인지는 표에서 바로 알 수 없다.

-- 문장 → 폼(조건 자동 채우기) 한 번에 한 줄
CREATE TABLE course.planner_parse_logs
(
    id          UUID        NOT NULL PRIMARY KEY,
    member_hash VARCHAR(64) NOT NULL,
    -- 사용자가 쓴 문장 원문(1~200자)
    sentence    TEXT        NOT NULL,
    -- Jev 답(질문별 noul 또는 choice + probabilities). Jev를 못 썼으면(실패 · 키 없음) null이고 그때 폼은 규칙만으로 채웠다
    jev_answers JSONB,
    -- 앱에 돌려준 폼. 코스와 무관한 문장이면 message만 있다
    form        JSONB       NOT NULL,
    elapsed_ms  INTEGER     NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL
);

-- 폼 → 코스(코스 찾기) 한 번에 한 줄. 길찾기 서버 장애로 오류가 난 요청은 남지 않는다
CREATE TABLE course.planner_plan_logs
(
    id              UUID        NOT NULL PRIMARY KEY,
    member_hash     VARCHAR(64) NOT NULL,
    -- 같은 사람이 10분 안에 보낸 마지막 채우기 로그. 직접 조건을 골랐거나 10분이 지났으면 null
    parse_log_id    UUID REFERENCES course.planner_parse_logs (id) ON DELETE SET NULL,
    -- 사용자가 확인 · 수정해서 보낸 폼
    form            JSONB       NOT NULL,
    -- 목표 거리(m). 시간이면 페이스로 환산한 값, 편도 · 경유에서 비우면 null
    target_meters   INTEGER,
    candidate_count INTEGER     NOT NULL,
    -- 후보가 없을 때의 사유(PLACE_NOT_FOUND · PLACE_TOO_FAR · NO_CANDIDATES · SIMILAR_EXISTS). 후보가 있으면 null
    reason          VARCHAR(20),
    -- 앱에 돌려준 후보 전부: 경로 점(anchorPoints)과 지표(거리 · 큰길 비율 · 편의점 수 등)
    candidates      JSONB       NOT NULL,
    -- 단계별 시간. 장소에서 끝났으면 route_ms · select_ms는 null
    place_ms        INTEGER     NOT NULL,
    route_ms        INTEGER,
    select_ms       INTEGER,
    created_at      TIMESTAMPTZ NOT NULL
);

-- 코스 찾기 때 "같은 사람의 마지막 채우기"를 찾는다
CREATE INDEX planner_parse_logs_member_idx ON course.planner_parse_logs (member_hash, created_at DESC);
