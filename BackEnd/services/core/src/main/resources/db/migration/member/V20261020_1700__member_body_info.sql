-- 신체 정보(정책 공통 9). 선택 입력이라 NULL을 허용하고, 네 값은 모두 있거나 모두 없다.
-- 출생연도 범위(올해 − 100 ~ 올해 − 15)는 해마다 바뀌어 서버가 확인한다.
ALTER TABLE member.members
    ADD COLUMN birth_year SMALLINT,
    ADD COLUMN height_cm  SMALLINT CHECK (height_cm BETWEEN 100 AND 250),
    ADD COLUMN weight_kg  SMALLINT CHECK (weight_kg BETWEEN 20 AND 300),
    ADD COLUMN gender     VARCHAR(10) CHECK (gender IN ('MALE', 'FEMALE')),
    ADD CONSTRAINT members_body_info_ck CHECK (
        (birth_year IS NULL) = (height_cm IS NULL)
            AND (height_cm IS NULL) = (weight_kg IS NULL)
            AND (weight_kg IS NULL) = (gender IS NULL));

-- 신체 정보 수집 및 이용 동의(선택). 기존 회원은 이 행이 없고, 없으면 동의하지 않은 것이다.
ALTER TABLE member.agreements DROP CONSTRAINT agreements_type_check;
ALTER TABLE member.agreements ADD CONSTRAINT agreements_type_check
    CHECK (type IN ('OVER_14', 'SERVICE_TERMS', 'PRIVACY_POLICY', 'LOCATION_TERMS', 'PROFILE_INFO', 'BODY_INFO'));
