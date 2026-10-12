# 와다닥 DB 구조

지금 구현된 DB를 정리한 문서다. 기준은 마이그레이션 파일(`BackEnd/src/main/resources/db/migration/`)이고, 이 문서는 그 결과를 설명한다.

> **마이그레이션을 추가하는 PR에서 이 문서도 같이 고친다.** ERD, 스키마 목록, 테이블 설명을 마이그레이션 결과와 맞춘다([개발 정책 v3](개발%20정책%20v3.md) 6.5·10.5).

## 1. 개요

- PostgreSQL 17 + PostGIS 3.5. 로컬은 `BackEnd/compose.yaml`로 띄운다(포트 5433).
- 모듈마다 스키마 하나를 쓴다. 다른 모듈의 스키마는 조회·JOIN·FK 모두 하지 않는다(개발 정책 2장·6.1).

| 스키마 | 모듈 | 테이블 |
| --- | --- | --- |
| `member` | member | `members`, `agreements`, `refresh_tokens` |
| `course` | course | `courses`, `daily_registration_counts`, `registration_requests` |
| `ranking` | ranking | `course_ranking_entries`, `course_status_copies`, `member_visibility_copies`, `withdrawn_members` |
| `common` | common | `region`, `event_publication`, `shedlock`, `flyway_schema_history` |

run, review, notification 스키마는 아직 없다. 해당 모듈을 구현할 때 이 문서에 추가한다.

### 공통 규칙 (개발 정책 6장)

- **PK**: 애플리케이션이 만든 UUID v7(`UuidV7.create()`). 예외는 `region`(법정동 코드), `shedlock`(작업 이름), `event_publication`(Modulith가 만듦), `flyway_schema_history`(Flyway가 관리)다.
  - 다른 모듈의 행 하나에 정확히 한 행이 대응하는 테이블은 그 모듈의 ID를 PK로 쓴다. 이벤트를 다시 받아도 PK로 한 번만 저장된다(개발 정책 5.4). 예: `course_ranking_entries`(run 기록 ID), 복사본 테이블(코스·회원 ID)
- **시각**: `TIMESTAMPTZ`에 UTC로 저장한다. 엔티티 테이블은 모두 `created_at`·`updated_at`을 가진다(`BaseEntity`).
- **enum**: Java enum 이름을 `VARCHAR`로 저장하고 `CHECK`로 값을 제한한다.
- **낙관적 락**: 상태 변경 이벤트를 발행하는 테이블(`members`, `courses`)은 `version` 컬럼을 가진다.
- **FK**: 같은 스키마 안에서만 건다. 다른 모듈 ID는 값만 저장하고 인덱스를 만든다.
- **공간**: SRID 4326. 반경 검색은 `geography`, 경로 계산은 `geometry`(개발 정책 6.4).

## 2. ERD

- 실선: 같은 스키마 안의 FK
- 점선: 다른 모듈(스키마)의 ID를 값으로만 저장한 참조. FK 없음
- 모든 엔티티 테이블에 있는 `created_at`·`updated_at`은 생략했다. `common`의 인프라 테이블(`event_publication`, `shedlock`, `flyway_schema_history`)은 다른 테이블과 관계가 없어 3.4에서만 설명한다.
- `course_ranking_entries.run_record_id`는 run 모듈의 러닝 기록 ID다. run 스키마가 생기면 ERD에 잇는다.

```mermaid
erDiagram
    members ||--o{ agreements : "member_id"
    members ||--o{ refresh_tokens : "member_id"
    courses ||--o{ registration_requests : "course_id"
    members ||..o{ courses : "creator_id"
    members ||..o{ daily_registration_counts : "member_id"
    members ||..o{ registration_requests : "member_id"
    region ||..o{ members : "region_code"
    region ||..o{ courses : "emd_code, sigungu_code, sido_code"
    courses ||..o{ course_ranking_entries : "course_id"
    members ||..o{ course_ranking_entries : "member_id"
    courses ||..o| course_status_copies : "course_id"
    members ||..o| member_visibility_copies : "member_id"
    members ||..o| withdrawn_members : "member_id"

    members {
        uuid id PK
        varchar(20) status "ACTIVE, WITHDRAWN"
        varchar(10) social_provider "KAKAO, APPLE, GOOGLE"
        varchar(255) social_id "소셜 회원번호"
        varchar(10) nickname UK "대소문자 무시 유일"
        varchar(50) bio
        varchar(10) region_code "활동 지역(시·군·구)"
        varchar(30) affiliation
        varchar(20) running_experience
        boolean info_public
        boolean profile_searchable
        timestamptz withdrawn_at
        bigint version
    }
    agreements {
        uuid id PK
        uuid member_id FK
        varchar(30) type "약관 항목"
        varchar(20) version "약관 버전"
        boolean agreed
    }
    refresh_tokens {
        uuid id PK
        varchar(64) token_hash UK "SHA-256"
        uuid member_id FK
        timestamptz expires_at
    }
    courses {
        uuid id PK
        uuid creator_id "member ID"
        varchar(10) course_type "CUSTOM, GPS"
        varchar(50) name
        varchar(50) name_key "활성 코스끼리 유일"
        varchar(10) difficulty "EASY, MEDIUM, HARD"
        varchar(20)[] tags
        geometry route "LineString"
        integer distance_meters
        geography start_point "Point"
        varchar(10) emd_code
        varchar(10) sigungu_code
        varchar(10) sido_code
        varchar(10) status "ACTIVE, HIDDEN, DELETED"
        varchar(20) status_reason "EXPIRED, USER_DELETED"
        timestamptz hidden_at
        timestamptz expires_at
        bigint version
    }
    daily_registration_counts {
        uuid id PK
        uuid member_id "member ID"
        date registration_date "Asia/Seoul"
        varchar(10) course_type
        integer registered_count
    }
    registration_requests {
        uuid id PK
        uuid member_id "member ID"
        uuid idempotency_key
        uuid course_id FK
    }
    course_ranking_entries {
        uuid run_record_id PK "run 기록 ID"
        uuid course_id "course ID"
        uuid member_id "member ID"
        integer course_elapsed_seconds "정수 초"
        integer course_distance_meters
        timestamptz completed_at
        timestamptz registered_at "기간 기준"
        boolean deleted
    }
    course_status_copies {
        uuid course_id PK "course ID"
        varchar(10) status "HIDDEN, DELETED"
        bigint source_version
    }
    member_visibility_copies {
        uuid member_id PK "member ID"
        boolean visible
        bigint source_version
    }
    withdrawn_members {
        uuid member_id PK "member ID"
        timestamptz withdrawn_at
    }
    region {
        varchar(10) code PK "법정동 코드"
        varchar(15) level "SIDO, SIGUNGU, EUPMYEONDONG"
        varchar(40) name
        varchar(100) full_name
        geometry boundary "MultiPolygon"
    }
```

## 3. 테이블

표의 NULL 칸에 O가 있으면 NULL을 허용한다. 비어 있으면 `NOT NULL`이다.

### 3.1 member

#### `member.members` — 회원

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `id` | `UUID` | | PK |
| `status` | `VARCHAR(20)` | | `ACTIVE`, `WITHDRAWN` |
| `social_provider` | `VARCHAR(10)` | | `KAKAO`, `APPLE`, `GOOGLE` |
| `social_id` | `VARCHAR(255)` | O | 소셜 회원번호. 카카오는 회원번호, Apple·Google은 ID 토큰의 `sub`. 탈퇴하면 비운다 |
| `nickname` | `VARCHAR(10)` | O | 2~10자 한글·영문·숫자. 탈퇴하면 비운다 |
| `bio` | `VARCHAR(50)` | O | 한 줄 소개 |
| `region_code` | `VARCHAR(10)` | | 활동 지역(시·군·구) 법정동 코드. `common.region` 값이지만 FK는 없다 |
| `affiliation` | `VARCHAR(30)` | O | 소속(학교·회사·크루) |
| `running_experience` | `VARCHAR(20)` | | `BEGINNER`, `MONTHS_6`, `YEAR_1`, `YEAR_3` |
| `info_public` | `BOOLEAN` | | 정보 공개. 기본 `true` |
| `profile_searchable` | `BOOLEAN` | | 프로필 검색 허용. 기본 `true` |
| `withdrawn_at` | `TIMESTAMPTZ` | O | 탈퇴 시각 |
| `version` | `BIGINT` | | 낙관적 락 |

- `members_social_uk`: `UNIQUE (social_provider, social_id)`. 로그인할 때 소셜 계정으로 회원을 찾는다.
- `members_nickname_uk`: `UNIQUE (lower(nickname))`. 대소문자만 다른 닉네임도 중복으로 본다.
- 탈퇴 처리와 공개·검색 설정을 바꾸는 기능은 아직 없다. 지금은 가입할 때의 기본값만 들어간다.

#### `member.agreements` — 약관 동의 이력

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `id` | `UUID` | | PK |
| `member_id` | `UUID` | | FK → `members.id` |
| `type` | `VARCHAR(30)` | | `OVER_14`(만 14세 이상), `SERVICE_TERMS`(서비스 이용약관), `PRIVACY_POLICY`(개인정보 수집·이용), `LOCATION_TERMS`(위치기반서비스 이용약관), `PROFILE_INFO`(프로필 정보) |
| `version` | `VARCHAR(20)` | | 동의한 약관 버전. 현재 버전은 `AgreementType`에 있다 |
| `agreed` | `BOOLEAN` | | 동의 여부 |
| `created_at` | `TIMESTAMPTZ` | | 동의 시각 |

- 행을 쌓기만 하고 고치지 않는다. 회원·항목별 현재 상태는 그 회원·항목의 마지막 행이다.
- 가입하면 5개 항목이 모두 현재 버전, `agreed = true`로 한 줄씩 생긴다. 모두 필수 항목이다.
- 약관 내용을 바꾸면 `AgreementType`의 버전을 올린다.
- `agreements_member_id_idx`: `(member_id)`

#### `member.refresh_tokens` — 리프레시 토큰

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `id` | `UUID` | | PK |
| `token_hash` | `VARCHAR(64)` | | 토큰 원문의 SHA-256(hex). 원문은 저장하지 않는다 |
| `member_id` | `UUID` | | FK → `members.id` |
| `expires_at` | `TIMESTAMPTZ` | | 발급 후 7일 |

- `refresh_tokens_uk`: `UNIQUE (token_hash)`. 갱신·로그아웃 때 해시로 찾는다.
- `refresh_tokens_member_id_idx`: `(member_id)`
- 토큰은 한 번만 쓴다. 갱신하면 그 행을 지우고 새 행을 만들고, 로그아웃하면 지운다.
- 만료된 행을 지우는 배치는 아직 없다.

### 3.2 course

#### `course.courses` — 코스

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `id` | `UUID` | | PK |
| `creator_id` | `UUID` | | 등록한 회원 ID(member 모듈, FK 없음) |
| `course_type` | `VARCHAR(10)` | | `CUSTOM`(지도에 입력점을 찍어 만든 코스), `GPS`(달린 기록으로 만든 코스) |
| `name` | `VARCHAR(50)` | | 표시용 이름. NFC 정규화, 앞뒤 공백 제거, 연속 공백은 한 칸 |
| `name_key` | `VARCHAR(50)` | | 중복 비교용 이름. NFC 정규화, 공백 전부 제거, 소문자. `한강 러닝`과 `한강러닝`은 같은 키 |
| `difficulty` | `VARCHAR(10)` | | `EASY`, `MEDIUM`, `HARD` |
| `tags` | `VARCHAR(20)[]` | | 코스 특징. 기본 `{}`. `FLAT`, `UPHILL`, `SHADE`, `RIVERSIDE`, `NIGHT_LIGHT`, `RESTROOM`, `CONVENIENCE_STORE`, `TRACK` |
| `route` | `geometry(LineString, 4326)` | | 기준 경로. 좌표 순서가 코스 방향이다(첫 점 출발, 마지막 점 도착) |
| `distance_meters` | `INTEGER` | | 경로 길이(m). 0보다 크다 |
| `start_point` | `geography(Point, 4326)` | | 출발점(`route`의 첫 점). 반경 검색용 |
| `emd_code` | `VARCHAR(10)` | | 출발점의 읍·면·동 법정동 코드 |
| `sigungu_code` | `VARCHAR(10)` | | 출발점의 시·군·구 코드 |
| `sido_code` | `VARCHAR(10)` | | 출발점의 시·도 코드 |
| `status` | `VARCHAR(10)` | | `ACTIVE` → `HIDDEN` → `DELETED`. 한 방향으로만 바뀐다 |
| `status_reason` | `VARCHAR(20)` | O | `EXPIRED`, `USER_DELETED` |
| `hidden_at` | `TIMESTAMPTZ` | O | 숨긴 시각 |
| `expires_at` | `TIMESTAMPTZ` | | 만료 시각. 등록일 포함 30일째 23:59:59(Asia/Seoul) |
| `version` | `BIGINT` | | 낙관적 락 |

- `courses_status_reason_ck`: `ACTIVE`면 `status_reason`·`hidden_at`이 모두 NULL이고, 그 밖의 상태면 둘 다 값이 있다.
- 지역 코드 3개는 시·도, 시·군·구 단위로 집계할 때 `common.region`을 JOIN하지 않으려고 모두 저장한다.
- 인덱스. `creator_id`를 빼면 모두 활성 코스만 대상으로 하는 부분 인덱스다(개발 정책 6.2).

| 인덱스 | 대상 | 조건 | 용도 |
| --- | --- | --- | --- |
| `courses_creator_id_idx` | `creator_id` | | 회원이 등록한 코스 |
| `courses_name_key_uk` | `name_key` (UNIQUE) | `ACTIVE` | 이름 중복 검사 |
| `courses_start_point_gix` | `start_point` (GiST) | `ACTIVE` | 반경 검색 |
| `courses_route_gix` | `route` (GiST) | `ACTIVE` | 유사 코스 후보 찾기 |
| `courses_tags_gin` | `tags` (GIN) | `ACTIVE` | 태그를 모두 가진 코스 조회 |
| `courses_emd_code_idx`, `courses_sigungu_code_idx`, `courses_sido_code_idx` | 지역 코드 | `ACTIVE` | 지역별 조회 |
| `courses_expires_at_idx` | `expires_at` | `ACTIVE` | 만료 배치 |
| `courses_hidden_at_idx` | `hidden_at` | `HIDDEN` | 숨긴 지 24시간 지난 코스 삭제 배치 |

- 지금은 사용자 지정(`CUSTOM`) 코스 등록만 행을 만든다. GPS 코스 등록과 숨김·삭제·만료 배치는 아직 없다.

#### `course.daily_registration_counts` — 일일 등록 수

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `id` | `UUID` | | PK |
| `member_id` | `UUID` | | 회원 ID(member 모듈, FK 없음) |
| `registration_date` | `DATE` | | 등록 날짜(Asia/Seoul) |
| `course_type` | `VARCHAR(10)` | | `CUSTOM`, `GPS` |
| `registered_count` | `INTEGER` | | 그날 성공한 등록 수. 0 이상 |

- `daily_registration_counts_uk`: `UNIQUE (member_id, registration_date, course_type)`
- 하루 한도는 `CUSTOM` 1개, `GPS` 3개다. 성공한 등록만 센다.
- 그날 첫 등록이면 0건 행을 `INSERT … ON CONFLICT DO NOTHING`으로 만들고, 행을 잠근 뒤 1을 더한다. 같은 회원의 동시 등록이 함께 한도를 넘지 않는다.

#### `course.registration_requests` — 등록 멱등 키

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `id` | `UUID` | | PK |
| `member_id` | `UUID` | | 회원 ID(member 모듈, FK 없음) |
| `idempotency_key` | `UUID` | | 앱이 등록 시도마다 만드는 키(`Idempotency-Key` 헤더) |
| `course_id` | `UUID` | | FK → `courses.id`. 그 키로 만든 코스 |

- `registration_requests_uk`: `UNIQUE (member_id, idempotency_key)`. 같은 키로 다시 요청하면 새로 만들지 않고 이 코스를 돌려준다.
- `registration_requests_created_at_idx`: `(created_at)`. 24시간 지난 행을 지우는 데 쓴다.
- 24시간 지난 행을 지우는 배치는 아직 없다.

### 3.3 ranking

순위는 저장하지 않고 조회할 때 계산한다. 기간·공개 여부로 거른 뒤 회원마다 가장 짧은 기록 1건을 대표로 고르고, `RANK()`로 공동순위(1·2·2·4)를 매긴다(정책 공통 6). 같은 순위 안에서는 먼저 등록된 기록이 앞이다.

#### `ranking.course_ranking_entries` — 코스 랭킹 엔트리

서버가 확정한 완주 기록 1건이 1행이다.

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `run_record_id` | `UUID` | | PK. run 모듈의 러닝 기록 ID. 같은 완주 이벤트가 다시 와도 한 번만 저장된다 |
| `course_id` | `UUID` | | 코스 ID(course 모듈, FK 없음) |
| `member_id` | `UUID` | | 회원 ID(member 모듈, FK 없음) |
| `course_elapsed_seconds` | `INTEGER` | | 코스 총 소요시간(정수 초). 순위는 이 값으로만 매긴다 |
| `course_distance_meters` | `INTEGER` | | 코스 전체 거리(m). 페이스 계산용 |
| `completed_at` | `TIMESTAMPTZ` | | 완주 시각. 화면에 보이는 날짜 |
| `registered_at` | `TIMESTAMPTZ` | | 기록 등록 시각. 이번 주·이번 달을 이 값으로 나눈다(Asia/Seoul) |
| `deleted` | `BOOLEAN` | | 기록이 삭제됐다. 기본 `false` |

- `course_ranking_entries_course_id_idx`: `(course_id)`, 삭제되지 않은 행만
- `course_ranking_entries_member_id_idx`: `(member_id)`
- 기록을 지우면 행을 지우지 않고 `deleted`만 켠다. 삭제 이벤트가 완주 이벤트보다 먼저 처리돼도 완주 저장이 PK 충돌로 무시돼 되살아나지 않는다.
- 코스가 삭제되면 그 코스의 행을 모두 지운다.
- 행을 쌓는 run 완주·삭제 이벤트 처리는 아직 없다(run 이벤트 계약 대기).

#### `ranking.course_status_copies` — 코스 상태 복사본

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `course_id` | `UUID` | | PK. 코스 ID(course 모듈) |
| `status` | `VARCHAR(10)` | | `HIDDEN`, `DELETED` |
| `source_version` | `BIGINT` | | course가 보낸 버전. 더 큰 버전만 반영한다 |

- `CourseStatusChangedEvent`로 채운다. 숨김·삭제된 코스만 행이 있고, 행이 없으면 `ACTIVE`다.
- 행이 있는 코스는 랭킹을 비워서 돌려준다. 삭제된 코스도 행을 남겨 늦게 온 완주 기록을 받지 않는다.

#### `ranking.member_visibility_copies` — 회원 공개 복사본

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `member_id` | `UUID` | | PK. 회원 ID(member 모듈) |
| `visible` | `BOOLEAN` | | 내 정보 공개 |
| `source_version` | `BIGINT` | | member가 보낸 버전. 더 큰 버전만 반영한다 |

- `MemberVisibilityChangedEvent`로 채운다. 행이 없으면 공개다.
- 비공개 회원은 순위 계산·참여 수·평균·고스트 후보에서 빠진다. 엔트리는 남아 있어서 다시 공개하면 그대로 보인다.

#### `ranking.withdrawn_members` — 탈퇴 회원

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `member_id` | `UUID` | | PK. 회원 ID(member 모듈) |
| `withdrawn_at` | `TIMESTAMPTZ` | | 탈퇴 시각 |

- `MemberWithdrawnEvent`를 받으면 그 회원의 랭킹 엔트리와 공개 복사본을 바로 지우고 이 행을 남긴다.
- 탈퇴 뒤에 도착한 그 회원의 완주 기록은 받지 않는다.

### 3.4 common

#### `common.region` — 법정구역

읽기 전용 참조 데이터다. 시드 마이그레이션이 데이터를 넣는다. 시드 파일은 `BackEnd/scripts/region/build-seed.sh`로 만들고 직접 고치지 않는다.

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `code` | `VARCHAR(10)` | | PK. 법정동 코드 10자리. 시·도는 앞 2자리, 시·군·구는 앞 5자리만 쓰고 나머지를 0으로 채운다 |
| `level` | `VARCHAR(15)` | | `SIDO`, `SIGUNGU`, `EUPMYEONDONG` |
| `name` | `VARCHAR(40)` | | 구역 이름. 예: `탕정면` |
| `full_name` | `VARCHAR(100)` | | 상위 구역을 붙인 이름. 예: `충청남도 아산시 탕정면` |
| `boundary` | `geometry(MultiPolygon, 4326)` | O | 경계. 읍·면·동만 가진다 |

- `region_boundary_gix`: `boundary` GiST. 좌표가 속한 읍·면·동을 찾는다(`RegionResolver`). 상위 구역은 코드 앞자리로 정한다.
- 다른 모듈은 코드 값만 저장하고 FK를 걸지 않는다.

#### `common.event_publication` — 이벤트 아웃박스

Spring Modulith가 관리한다. 이벤트를 발행하면 리스너마다 한 행이 생기고, 리스너가 처리를 마치면 지운다(`completion-mode: delete`).

- 주요 컬럼: `listener_id`, `event_type`, `serialized_event`, `publication_date`, `completion_date`, `status`, `completion_attempts`
- 남아 있는 행은 처리되지 않은 이벤트다. 앱을 다시 시작하면 다시 발행하고, `EventMonitor`·`EventRetryScheduler`가 1분마다 확인한다(개발 정책 5.5).

#### `common.shedlock` — 스케줄 작업 잠금

여러 인스턴스 중 한 곳에서만 스케줄 작업을 실행하게 한다(개발 정책 8.1). 행 하나가 작업 하나다(`common.event-monitor`, `common.event-retry`). 시각은 DB 시각(`TIMESTAMP`)을 쓴다.

#### `common.flyway_schema_history` — 마이그레이션 이력

Flyway가 관리한다. 모든 모듈의 마이그레이션 이력을 여기 한 곳에 둔다(개발 정책 6.5).
