-- run 서비스 DB 계정(MSA 분리 4단계, deploy/MSA 분리 준비와 CI·CD 7.4). compose의 db-init이 배포마다 돌린다.
-- 몇 번을 돌려도 결과가 같다: 처음에만 계정을 만들고 소유자를 넘긴다. 비밀번호는 매번 GitHub Secrets 값으로 맞춘다.
-- 비밀번호는 psql 변수 run_pw로 받는다(compose가 RUN_DB_PASSWORD를 넘긴다). 파일에 적지 않는다.
\set ON_ERROR_STOP on
-- 이미 있는 것을 건너뛸 때 나오는 NOTICE를 배포 로그에 남기지 않는다
SET client_min_messages = warning;

SELECT 'CREATE ROLE wadadak_run LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'wadadak_run') \gexec

-- 값은 %L로 따옴표 처리해 넣는다. 결과 문장은 화면 · 로그에 찍지 않는다(psql -q, \gexec는 실행만 한다).
SELECT format('ALTER ROLE wadadak_run WITH LOGIN PASSWORD %L', :'run_pw') \gexec

-- 새 DB(로컬 처음 띄울 때)에는 run 스키마가 없다. run 계정은 스키마를 만들 권한이 없어 여기서 만들어 준다.
-- 빈 스키마면 run 서비스 Flyway가 처음부터 마이그레이션한다(baseline은 테이블이 있을 때만 쓴다).
CREATE SCHEMA IF NOT EXISTS run AUTHORIZATION wadadak_run;
-- 첫 run 마이그레이션의 CREATE SCHEMA IF NOT EXISTS run은 스키마가 있어도 DB의 CREATE 권한을 본다(PostgreSQL).
-- 새 스키마를 만들 수만 있고 다른 스키마의 데이터는 여전히 읽지 못한다.
GRANT CREATE ON DATABASE wadadak TO wadadak_run;

-- 운영 DB의 run 스키마 · 테이블은 모놀리스 계정(wadadak)이 만들었다. 이후 run 마이그레이션(ALTER 등)을 run 계정이 돌리도록 넘긴다.
-- 이미 넘긴 것은 건드리지 않는다(ALTER TABLE OWNER는 테이블을 잠깐 잠근다). run 스키마에는 테이블만 있다.
SELECT 'ALTER SCHEMA run OWNER TO wadadak_run'
FROM pg_namespace
WHERE nspname = 'run' AND nspowner <> 'wadadak_run'::regrole \gexec

SELECT format('ALTER TABLE run.%I OWNER TO wadadak_run', tablename)
FROM pg_tables
WHERE schemaname = 'run' AND tableowner <> 'wadadak_run' \gexec

-- 다른 스키마(common · course · member · ranking · review · notification)에는 권한을 주지 않는다.
-- run 코드가 경계를 넘으면 run 서비스가 바로 실패한다(개발 정책 11.3).
