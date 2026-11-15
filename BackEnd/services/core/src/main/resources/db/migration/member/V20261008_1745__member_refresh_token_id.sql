-- PK를 애플리케이션이 만든 UUID로 바꾼다(개발 정책 6.1). 조회는 계속 해시로 하므로 해시는 유니크로 남긴다.
ALTER TABLE member.refresh_tokens
    DROP CONSTRAINT refresh_tokens_pkey,
    ADD COLUMN id UUID;

-- 기존 행만 DB에서 채운다(v4). 새 행은 애플리케이션이 v7로 만든다.
UPDATE member.refresh_tokens SET id = gen_random_uuid();

ALTER TABLE member.refresh_tokens
    ADD PRIMARY KEY (id),
    ADD CONSTRAINT refresh_tokens_uk UNIQUE (token_hash);
