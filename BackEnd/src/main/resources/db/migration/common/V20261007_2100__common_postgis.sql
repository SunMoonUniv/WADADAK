-- PostGIS는 DB 단위 확장이다. 모든 모듈이 스키마 이름 없이 쓰도록 public에 둔다(SRID 4326, 개발 정책 6.4).
-- 관리형 DB는 확장 생성 권한이 있는 계정으로 마이그레이션해야 한다.
CREATE EXTENSION IF NOT EXISTS postgis SCHEMA public;
