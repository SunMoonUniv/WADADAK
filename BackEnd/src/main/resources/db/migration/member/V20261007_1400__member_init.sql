CREATE SCHEMA member;

CREATE TABLE member.members
(
    id                 UUID        NOT NULL PRIMARY KEY,
    status             VARCHAR(20) NOT NULL CHECK (status IN ('ACTIVE', 'WITHDRAWN')),
    social_provider    VARCHAR(10) NOT NULL CHECK (social_provider IN ('KAKAO', 'APPLE', 'GOOGLE')),
    -- 탈퇴 시 개인정보와 함께 비운다(개발 정책 6.2).
    social_id          VARCHAR(255),
    email              VARCHAR(255),
    nickname           VARCHAR(10),
    bio                VARCHAR(50),
    -- 활동 지역(시·군·구) 법정동 코드. common.regions에 FK를 걸지 않는다(개발 정책 2장).
    region_code        VARCHAR(10) NOT NULL,
    affiliation        VARCHAR(30),
    running_experience VARCHAR(20) NOT NULL CHECK (running_experience IN ('BEGINNER', 'MONTHS_6', 'YEAR_1', 'YEAR_3')),
    info_public        BOOLEAN     NOT NULL DEFAULT TRUE,
    profile_searchable BOOLEAN     NOT NULL DEFAULT TRUE,
    -- 가입 시 필수 약관(만 14세·서비스·개인정보·위치기반서비스·프로필 정보) 동의 시각.
    terms_agreed_at    TIMESTAMPTZ NOT NULL,
    withdrawn_at       TIMESTAMPTZ,
    version            BIGINT      NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL,
    updated_at         TIMESTAMPTZ NOT NULL,
    CONSTRAINT members_social_uk UNIQUE (social_provider, social_id)
);
CREATE UNIQUE INDEX members_nickname_uk ON member.members (lower(nickname));

-- 리프레시 토큰은 원문 대신 SHA-256 해시만 저장한다. 사용할 때마다 새 토큰으로 교체한다.
CREATE TABLE member.refresh_tokens
(
    token_hash VARCHAR(64) NOT NULL PRIMARY KEY,
    member_id  UUID        NOT NULL REFERENCES member.members (id),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX refresh_tokens_member_id_idx ON member.refresh_tokens (member_id);
