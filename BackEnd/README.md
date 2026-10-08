# 와다닥 백엔드 (MSA 분리 전)

Spring Boot 4.1 · Spring Modulith 2.1 · Java 21 · PostgreSQL 17 + PostGIS 3.5.
구조·규칙은 [`개발 정책 v3.md`](../개발%20정책%20v3.md)를 따른다.

## 로컬 실행

1. DB: `docker compose up -d`
2. JWT 키(최초 1회, Git Bash):
   ```sh
   mkdir -p .local/jwt
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out .local/jwt/private.pem
   openssl pkey -in .local/jwt/private.pem -pubout -out .local/jwt/public.pem
   ```
   `.local/`은 커밋하지 않는다. 운영은 `JWT_PUBLIC_KEY_LOCATION`·`JWT_PRIVATE_KEY_LOCATION`으로 같은 키 쌍을 넘긴다.
3. `./gradlew bootRun`
4. Swagger: http://localhost:8080/swagger-ui.html

DB는 로컬 PostgreSQL과 겹치지 않게 5433 포트를 쓴다. 접속 정보는 `DB_URL`·`DB_USERNAME`·`DB_PASSWORD`로 바꾼다.

로컬 로그인은 가짜 소셜 검증이다(`app.member.social.fake: true`). `POST /api/v1/members/auth/login`에 `{"provider": "KAKAO", "token": "아무문자열"}`을 보내면 그 문자열이 소셜 ID가 된다.

운영은 `prod` 프로필로 띄운다. 스텁·가짜 소셜 검증이 켜져 있으면 기동이 실패한다. `APP_MEMBER_SOCIAL_FAKE=false`와 `KAKAO_APP_ID`·`APPLE_CLIENT_IDS`·`GOOGLE_CLIENT_IDS`를 넘긴다.

## 테스트

`./gradlew test` — Docker가 떠 있어야 한다(Testcontainers).

- `ModularityTests`: 모듈 경계 검사(`verify()`)
- `{Module}ModuleTests`: 모듈 단독 기동(`@ApplicationModuleTest`)

## 모듈 추가 체크

- 공개 인터페이스·DTO·에러 코드는 모듈 루트, 나머지는 `internal/`
- `internal/`은 기능별 하위 패키지로 나눈다. 예: member는 `auth`(로그인·가입·토큰) · `account`(회원 계정·`MemberApi` 구현) · `social`(소셜 토큰 검증). 컨트롤러·서비스·DTO는 그 기능 폴더에 함께 둔다.
  - 하위 패키지끼리 쓰는 타입만 `public`으로 둔다. 다른 모듈은 `public`이어도 `internal`에 접근할 수 없다(`verify()`가 막는다).
- 공개 인터페이스 스텁: `internal/{기능}/{Xxx}ApiStub` + `StubImplementation` + `app.stub.{module}: true`
- 마이그레이션: `db/migration/{module}/V{yyyyMMdd_HHmm}__{module}_{설명}.sql`, 첫 파일에서 `CREATE SCHEMA {module};`
- 공간 컬럼(SRID 4326, JTS 타입): 반경 검색용은 `geography`라서 `@Column(columnDefinition = "geography(Point,4326)")`를 붙인다. 경로 판정용 `geometry`(`LineString` 등)는 그대로 매핑된다. PostGIS는 `public`에 있어 함수·타입에 스키마 이름을 붙이지 않는다.
- Swagger 그룹: 모듈 `internal`에 `GroupedOpenApi` 빈(`/api/v1/{prefix}/**`)
- 단독 기동 테스트: `@ApplicationModuleTest` + `@ActiveProfiles("test")` + `@Import(TestcontainersConfiguration.class)`
