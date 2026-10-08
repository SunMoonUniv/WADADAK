-- 법정구역(시·도·시·군·구·읍·면·동). 읽기 전용 참조 데이터이며 데이터는 다음 마이그레이션(시드)이 넣는다.
-- 다른 모듈은 code 값만 저장하고 FK를 걸지 않는다(개발 정책 2장).
CREATE TABLE common.region
(
    -- 법정동 코드 10자리. 시·도는 앞 2자리, 시·군·구는 앞 5자리 뒤를 0으로 채운다.
    code      VARCHAR(10)  NOT NULL PRIMARY KEY,
    level     VARCHAR(15)  NOT NULL CHECK (level IN ('SIDO', 'SIGUNGU', 'EUPMYEONDONG')),
    name      VARCHAR(40)  NOT NULL,
    -- 상위 구역을 붙인 이름. 예: 충청남도 아산시 탕정면
    full_name VARCHAR(100) NOT NULL,
    -- 읍·면·동만 가진다. 좌표 판별(RegionResolver)은 읍·면·동으로 하고 상위 구역은 코드 앞자리로 묶는다.
    boundary  geometry(MultiPolygon, 4326)
);
CREATE INDEX region_boundary_gix ON common.region USING gist (boundary);
