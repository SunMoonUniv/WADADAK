CREATE SCHEMA course;

CREATE TABLE course.courses
(
    id               UUID                   NOT NULL PRIMARY KEY,
    -- 등록자. member 모듈 ID라 FK를 걸지 않는다(개발 정책 2장).
    creator_id       UUID                   NOT NULL,
    -- CUSTOM: 사용자 지정(지도에 입력점), GPS: GPS 주행 등록(정책 공통 3)
    course_type      VARCHAR(10)            NOT NULL CHECK (course_type IN ('CUSTOM', 'GPS')),
    name             VARCHAR(50)            NOT NULL,
    difficulty       VARCHAR(10)            NOT NULL CHECK (difficulty IN ('EASY', 'MEDIUM', 'HARD')),
    -- 코스 특징(FIL-04). 태그를 모두 가진 코스 조회(AND)를 GIN 인덱스로 한다.
    tags             VARCHAR(20)[]          NOT NULL DEFAULT '{}',
    -- 기준 경로. 좌표 순서 = 코스 방향(첫 점 출발, 마지막 점 도착, 개발 정책 6.4).
    route            geometry(LineString, 4326) NOT NULL,
    distance_meters  INTEGER                NOT NULL CHECK (distance_meters > 0),
    -- 반경 검색용 출발점(route의 첫 점).
    start_point      geography(Point, 4326) NOT NULL,
    -- 출발점이 속한 법정동 코드. common.region에 FK를 걸지 않는다(개발 정책 2장).
    -- 시·도·시·군·구 단위 집계를 JOIN 없이 하려고 셋 다 저장한다.
    emd_code         VARCHAR(10)            NOT NULL,
    sigungu_code     VARCHAR(10)            NOT NULL,
    sido_code        VARCHAR(10)            NOT NULL,
    -- ACTIVE → HIDDEN → DELETED 한 방향(정책 공통 4). HIDDEN·DELETED는 사유와 숨긴 시각을 가진다.
    status           VARCHAR(10)            NOT NULL CHECK (status IN ('ACTIVE', 'HIDDEN', 'DELETED')),
    status_reason    VARCHAR(20) CHECK (status_reason IN ('EXPIRED', 'USER_DELETED')),
    hidden_at        TIMESTAMPTZ,
    -- 만료 시각(만료일 23:59:59 Asia/Seoul). 완주로 연장되면 늦춘다.
    expires_at       TIMESTAMPTZ            NOT NULL,
    version          BIGINT                 NOT NULL,
    created_at       TIMESTAMPTZ            NOT NULL,
    updated_at       TIMESTAMPTZ            NOT NULL,
    CONSTRAINT courses_status_reason_ck CHECK (
        (status = 'ACTIVE' AND status_reason IS NULL AND hidden_at IS NULL)
            OR (status <> 'ACTIVE' AND status_reason IS NOT NULL AND hidden_at IS NOT NULL))
);

CREATE INDEX courses_creator_id_idx ON course.courses (creator_id);
-- 활성 코스만 대상인 부분 인덱스(개발 정책 6.2).
CREATE UNIQUE INDEX courses_name_uk ON course.courses (lower(name)) WHERE status = 'ACTIVE';
CREATE INDEX courses_start_point_gix ON course.courses USING gist (start_point) WHERE status = 'ACTIVE';
-- 85% 유사도 검사에서 겹칠 수 있는 기존 코스를 찾는다.
CREATE INDEX courses_route_gix ON course.courses USING gist (route) WHERE status = 'ACTIVE';
CREATE INDEX courses_tags_gin ON course.courses USING gin (tags) WHERE status = 'ACTIVE';
CREATE INDEX courses_emd_code_idx ON course.courses (emd_code) WHERE status = 'ACTIVE';
CREATE INDEX courses_sigungu_code_idx ON course.courses (sigungu_code) WHERE status = 'ACTIVE';
CREATE INDEX courses_sido_code_idx ON course.courses (sido_code) WHERE status = 'ACTIVE';
-- 만료·삭제 배치(F11)
CREATE INDEX courses_expires_at_idx ON course.courses (expires_at) WHERE status = 'ACTIVE';
CREATE INDEX courses_hidden_at_idx ON course.courses (hidden_at) WHERE status = 'HIDDEN';

-- 일일 등록 한도(정책 공통 3: 사용자 지정 1개, GPS 3개). 날짜는 Asia/Seoul, 성공한 등록만 센다.
CREATE TABLE course.daily_registration_counts
(
    member_id         UUID        NOT NULL,
    registration_date DATE        NOT NULL,
    course_type       VARCHAR(10) NOT NULL CHECK (course_type IN ('CUSTOM', 'GPS')),
    registered_count  INTEGER     NOT NULL CHECK (registered_count >= 0),
    created_at        TIMESTAMPTZ NOT NULL,
    updated_at        TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (member_id, registration_date, course_type)
);

-- 등록 멱등성(STA-05). 같은 키로 다시 요청하면 이미 만든 코스를 돌려준다.
CREATE TABLE course.registration_requests
(
    member_id       UUID        NOT NULL,
    idempotency_key UUID        NOT NULL,
    course_id       UUID        NOT NULL REFERENCES course.courses (id),
    created_at      TIMESTAMPTZ NOT NULL,
    updated_at      TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (member_id, idempotency_key)
);
