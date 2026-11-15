-- 약관 동의 이력. 항목·버전마다 한 줄씩 쌓고 고치지 않는다. created_at이 동의 시각이다.
-- 항목별 현재 상태는 회원·항목의 마지막 행이다.
CREATE TABLE member.agreements
(
    id         UUID        NOT NULL PRIMARY KEY,
    member_id  UUID        NOT NULL REFERENCES member.members (id),
    type       VARCHAR(30) NOT NULL CHECK (type IN ('OVER_14', 'SERVICE_TERMS', 'PRIVACY_POLICY', 'LOCATION_TERMS', 'PROFILE_INFO')),
    -- 동의한 약관 버전(AgreementType). 약관을 바꾸면 버전을 올리고 다시 동의를 받는다.
    version    VARCHAR(20) NOT NULL,
    agreed     BOOLEAN     NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX agreements_member_id_idx ON member.agreements (member_id);

-- 기존 회원은 가입 때 필수 5개에 모두 동의했다(terms_agreed_at). 이력으로 옮기고 컬럼은 지운다.
INSERT INTO member.agreements (id, member_id, type, version, agreed, created_at, updated_at)
SELECT gen_random_uuid(), m.id, t.type, '1', TRUE, m.terms_agreed_at, m.terms_agreed_at
FROM member.members m
         CROSS JOIN (VALUES ('OVER_14'), ('SERVICE_TERMS'), ('PRIVACY_POLICY'), ('LOCATION_TERMS'), ('PROFILE_INFO')) AS t (type);

ALTER TABLE member.members DROP COLUMN terms_agreed_at;
