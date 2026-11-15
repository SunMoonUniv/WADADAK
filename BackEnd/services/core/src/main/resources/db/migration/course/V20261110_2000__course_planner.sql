-- 코스 자동 생성(정책 B3 `자동 생성`)의 하루 한도와 후보 지표용 공공 POI.

-- 자동 생성 요청 수(회원·날짜·종류). PLAN = 코스 자동 생성(하루 20회), PARSE = 조건 자동 채우기(하루 50회).
-- 요청 전에 한도 안에서만 1을 더하고, 세지 않는 요청(B3-A05)이면 다시 1을 뺀다.
CREATE TABLE course.daily_plan_counts
(
    id         UUID        NOT NULL PRIMARY KEY,
    -- member 모듈의 회원 ID. 다른 스키마라 FK는 없다
    member_id  UUID        NOT NULL,
    -- Asia/Seoul 날짜
    plan_date  DATE        NOT NULL,
    kind       VARCHAR(10) NOT NULL CHECK (kind IN ('PLAN', 'PARSE')),
    plan_count INTEGER     NOT NULL CHECK (plan_count >= 0),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT daily_plan_counts_uk UNIQUE (member_id, plan_date, kind)
);

-- 후보 지표용 공공 POI. 원본 식별자가 자연키다(지역 시드와 같은 방식)
CREATE TABLE course.planner_pois
(
    -- 'sbiz:' + 상가업소번호
    source_id  VARCHAR(40)            NOT NULL PRIMARY KEY,
    kind       VARCHAR(20)            NOT NULL CHECK (kind IN ('CONVENIENCE', 'TOILET')),
    location   GEOGRAPHY(Point, 4326) NOT NULL,
    -- 원본 기준 월. 예: '2026-09'
    base_month VARCHAR(7)             NOT NULL,
    created_at TIMESTAMPTZ            NOT NULL,
    updated_at TIMESTAMPTZ            NOT NULL
);

-- 후보 경로 가까이의 편의점 수
CREATE INDEX planner_pois_location_idx ON course.planner_pois USING gist (location);
