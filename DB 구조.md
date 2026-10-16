# 와다닥 DB 구조

지금 구현된 DB를 정리한 문서다. 기준은 마이그레이션 파일(`BackEnd/src/main/resources/db/migration/`)이고, 이 문서는 그 결과를 설명한다.

> **마이그레이션을 추가하는 PR에서 이 문서도 같이 고친다.** ERD, 스키마 목록, 테이블 설명을 마이그레이션 결과와 맞춘다([개발 정책 v3](개발%20정책%20v3.md) 6.5·10.5).

## 1. 개요

- PostgreSQL 17 + PostGIS 3.5.
  - 로컬: `BackEnd/compose.yaml`(포트 5433)
  - 팀 공용 서버: `deploy/compose.yaml`. 서버 PC의 Docker에 따로 뜨고 포트를 열지 않는다. 접속·초기화는 [deploy/README.md](deploy/README.md)의 운영 표를 따른다.
  - 서버가 뜰 때 Flyway가 마이그레이션을 적용한다. 공용 서버 DB에는 머지된 마이그레이션이 이미 적용돼 있어서, 머지된 파일을 고치면 체크섬이 어긋나 서버가 뜨지 않는다(개발 정책 6.5).
- 모듈마다 스키마 하나를 쓴다. 다른 모듈의 스키마는 조회·JOIN·FK 모두 하지 않는다(개발 정책 2장·6.1).

| 스키마 | 모듈 | 테이블 |
| --- | --- | --- |
| `member` | member | `members`, `agreements`, `refresh_tokens` |
| `course` | course | `courses`, `daily_registration_counts`, `registration_requests` |
| `ranking` | ranking | `course_ranking_entries`, `distance_run_records`, `course_status_copies`, `member_visibility_copies`, `withdrawn_members` |
| `review` | review | `reviews`, `review_photos`, `course_run_records`, `course_status_copies`, `withdrawn_members` |
| `run` | run | `sessions`, `inputs`, `records`, `deleted_records`, `withdrawn_members` |
| `common` | common | `region`, `event_publication`, `shedlock`, `flyway_schema_history` |

notification 스키마는 아직 없다. 해당 모듈을 구현할 때 이 문서에 추가한다.

### 공통 규칙 (개발 정책 6장)

- **PK**: 애플리케이션이 만든 UUID v7(`UuidV7.create()`). 예외는 `region`(법정동 코드), `shedlock`(작업 이름), `event_publication`(Modulith가 만듦), `flyway_schema_history`(Flyway가 관리)다.
  - 다른 모듈의 행 하나에 정확히 한 행이 대응하는 테이블은 그 모듈의 ID를 PK로 쓴다. 이벤트를 다시 받아도 PK로 한 번만 저장된다(개발 정책 5.4). 예: `course_ranking_entries`·`review.course_run_records`(run 기록 ID), 복사본 테이블(코스·회원 ID)
- **시각**: `TIMESTAMPTZ`에 UTC로 저장한다. 엔티티 테이블은 모두 `created_at`·`updated_at`을 가진다(`BaseEntity`).
- **enum**: Java enum 이름을 `VARCHAR`로 저장하고 `CHECK`로 값을 제한한다.
- **낙관적 락**: 상태 변경 이벤트를 발행하는 테이블(`members`, `courses`)은 `version` 컬럼을 가진다.
- **FK**: 같은 스키마 안에서만 건다. 다른 모듈 ID는 값만 저장하고 인덱스를 만든다.
- **공간**: SRID 4326. 반경 검색은 `geography`, 경로 계산은 `geometry`(개발 정책 6.4).

## 2. ERD

- 실선: 같은 스키마 안의 FK
- 점선: 다른 모듈(스키마)의 ID를 값으로만 저장한 참조. FK 없음
- 모든 엔티티 테이블에 있는 `created_at`·`updated_at`은 생략했다. `common`의 인프라 테이블(`event_publication`, `shedlock`, `flyway_schema_history`)은 다른 테이블과 관계가 없어 3.5에서만 설명한다.
- `course_ranking_entries.run_record_id`, `course_run_records.run_record_id`, `reviews.source_run_record_id`는 run 모듈의 러닝 기록 ID다. 아래 `run_records`에 점선으로 연결했다. 다른 스키마이므로 FK는 없다.
- `course_status_copies`·`withdrawn_members`는 ranking과 review에 같은 이름으로 있다. ERD에서는 review 쪽을 `review_` 접두사로 구분했다.

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
    reviews ||--o{ review_photos : "review_id"
    courses ||..o{ reviews : "course_id"
    members ||..o{ reviews : "member_id"
    course_run_records ||..o{ reviews : "source_run_record_id"
    courses ||..o{ course_run_records : "course_id"
    members ||..o{ course_run_records : "member_id"
    courses ||..o| review_course_status_copies : "course_id"
    members ||..o| review_withdrawn_members : "member_id"

    members {
        uuid id PK
        varchar(20) status "ACTIVE, WITHDRAWN"
        varchar(10) social_provider "KAKAO, APPLE, GOOGLE"
        varchar(255) social_id "소셜 회원번호"
        varchar(10) nickname UK "대소문자 무시 유일"
        varchar(50) bio
        varchar(10) region_code "활동 지역(시·군·구)"
        varchar(30) affiliation
        varchar(100) profile_image_key UK "member/..."
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
    reviews {
        uuid id PK
        uuid course_id "course ID"
        uuid member_id "member ID"
        uuid source_run_record_id "run 기록 ID"
        integer rating "1~5"
        integer safety_rating "1~5"
        integer road_rating "1~5"
        integer lighting_rating "1~5"
        integer amenity_rating "1~5"
        varchar(200) content "선택"
        varchar_array tags "NIGHT_VIEW, FEW_SIGNALS, GOOD_SURFACE, CROWDED"
        integer best_progress_percent "0~100"
    }
    review_photos {
        uuid id PK
        uuid review_id FK
        varchar(100) photo_key UK "review/..."
        integer display_order "0~4"
    }
    course_run_records {
        uuid run_record_id PK "run 기록 ID"
        uuid course_id "course ID"
        uuid member_id "member ID"
        boolean review_eligible
        boolean completed
        integer progress_percent "0~100"
        integer course_distance_meters
        integer course_elapsed_seconds
        timestamptz ended_at
        boolean deleted
    }
    review_course_status_copies {
        uuid course_id PK "course ID"
        varchar(10) status "HIDDEN, DELETED"
        bigint source_version
    }
    review_withdrawn_members {
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
    members ||..o{ run_sessions : "member_id"
    run_sessions ||--o{ run_inputs : "session_id"
    run_sessions ||--o| run_records : "id"
    members ||..o{ run_deleted_records : "member_id"
    members ||..o| run_withdrawn_members : "member_id"
    run_records ||..o| course_ranking_entries : "run_record_id"
    run_records ||..o| course_run_records : "run_record_id"
    run_records ||..o| distance_run_records : "run_record_id"
    members ||..o{ distance_run_records : "member_id"
    run_sessions {
        UUID id PK
        UUID member_id
        TIMESTAMPTZ started_at
        BIGINT final_seq
        VARCHAR processing
        VARCHAR failure
    }
    run_inputs {
        UUID session_id PK,FK
        BIGINT stream_seq PK
        TEXT payload
    }
    run_records {
        UUID id PK,FK
        TIMESTAMPTZ registered_at
        TEXT result_json
        TEXT summary_json
        BOOLEAN registration_published
    }
    run_deleted_records {
        UUID id PK
        UUID member_id
        TIMESTAMPTZ deleted_at
    }
    run_withdrawn_members {
        UUID member_id PK
        TIMESTAMPTZ withdrawn_at
    }
    distance_run_records {
        UUID run_record_id PK
        UUID member_id
        DOUBLE distance_meters
        TIMESTAMPTZ registered_at
        BOOLEAN deleted
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
| `region_code` | `VARCHAR(10)` | | 활동 지역(시·군·구) 법정동 코드. FK가 없어 가입할 때 `common.region`의 시·군·구인지 확인한다 |
| `affiliation` | `VARCHAR(30)` | O | 소속(학교·회사·크루) |
| `profile_image_key` | `VARCHAR(100)` | O | 프로필 사진의 저장소 키. `member/`로 시작한다(개발 정책 7장 사진 업로드). 사진이 없으면 NULL. 탈퇴하면 비우고 파일도 지운다 |
| `running_experience` | `VARCHAR(20)` | | `BEGINNER`, `MONTHS_6`, `YEAR_1`, `YEAR_3` |
| `info_public` | `BOOLEAN` | | 정보 공개. 기본 `true` |
| `profile_searchable` | `BOOLEAN` | | 프로필 검색 허용. 기본 `true` |
| `withdrawn_at` | `TIMESTAMPTZ` | O | 탈퇴 시각 |
| `version` | `BIGINT` | | 낙관적 락 |

- `members_social_uk`: `UNIQUE (social_provider, social_id)`. 로그인할 때 소셜 계정으로 회원을 찾는다.
- `members_nickname_uk`: `UNIQUE (lower(nickname))`. 대소문자만 다른 닉네임도 중복으로 본다.
- `members_profile_image_key_uk`: `UNIQUE (profile_image_key)`. 사진 주소에 키가 보이므로, 남의 키를 가져다 쓰면 그 회원이 사진을 바꾸거나 탈퇴할 때 원래 파일이 지워진다. 그래서 키 하나는 회원 하나만 쓴다(MEMBER-008).
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
| `courses_start_point_gix` | `start_point` (GiST) | `ACTIVE` | 반경 검색, 지도 범위 안 코스(A2·A5)·지역별 코스 수(A4)·코스 목록(A2·A6) |
| `courses_created_at_idx` | `created_at DESC, id DESC` | `ACTIVE` | 코스 목록 최신순(A2·A6), 지도 범위 안 코스 순서(A5) |
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

#### `ranking.distance_run_records` — 기록별 누적 거리 집계 원천 복사본

`RunSessionEndedEvent`·`RunRecordDeletedEvent`를 받아 자기 스키마에 보관한다. 자유 러닝도 포함한다. 실제 랭킹 조회·자정 스냅샷을 대체하는 구현은 아니며 기존 F12 스텁 화면은 유지한다.

| 컬럼 | 타입 | 설명 |
| --- | --- | --- |
| `run_record_id` | UUID PK | 원천 run 기록 ID. 다른 스키마이므로 FK 없음 |
| `member_id` | UUID | 회원 ID, 인덱스 있음 |
| `distance_meters` | DOUBLE PRECISION | 서버 확정 거리 원본. 집계 전 임의 정수 반올림하지 않음 |
| `registered_at` | TIMESTAMPTZ | 원래 기록 등록 시각. 재전송 때 바꾸지 않음 |
| `deleted` | BOOLEAN | 삭제가 먼저 도착해도 유지하는 삭제 표시 |
| `created_at`, `updated_at` | TIMESTAMPTZ | 복사본 생성·변경 시각 |

- 기록 ID PK와 `deleted OR EXCLUDED.deleted`로 중복·역순 전달을 처리한다. 증감 UPDATE가 아니라 기록별 삽입 복사본이므로 별도 `processed_event` 증감 원장은 필요하지 않다.
- 회원 탈퇴 시 이 회원의 행을 실제 삭제한다. 기존 `ranking.withdrawn_members`를 확인해 늦은 이벤트는 받지 않는다. 탈퇴와 기록 이벤트는 같은 회원 잠금으로 직렬화한다.
- `registered_at`의 미삭제 부분 인덱스를 둔다. F12의 기간·주간·전체 순위 계산은 해당 기능에서 정책대로 구현한다.

### 3.4 review

평점 요약(전체 평균·분포·항목 평균)은 저장하지 않고 조회할 때 `reviews`에서 계산한다(B8·G2). 코스 목록 정렬·필터용 평점 합계는 course가 리뷰 이벤트로 따로 가진다(개발 정책 5.6).

#### `review.reviews` — 리뷰

회원당 코스별 1개다(`reviews_member_course_uk`). 다시 달린 뒤에는 기존 리뷰를 수정한다(정책 공통 5).

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `id` | `UUID` | | PK |
| `course_id` | `UUID` | | 코스 ID(course 모듈, FK 없음) |
| `member_id` | `UUID` | | 회원 ID(member 모듈, FK 없음) |
| `source_run_record_id` | `UUID` | | 근거 기록 ID(run 모듈). 기록이 삭제돼도 남긴다. `course_run_records.deleted`로 B10-1 "근거 기록이 삭제됐어요"를 알린다 |
| `rating` | `INTEGER` | | 전체 별점 1~5 |
| `safety_rating` · `road_rating` · `lighting_rating` · `amenity_rating` | `INTEGER` | | 항목별 평가 1~5: 안전성·도로 상태·야간 조명·편의시설. 모두 필수 |
| `content` | `VARCHAR(200)` | ✓ | 한줄 후기. 선택 입력 |
| `tags` | `VARCHAR(20)[]` | | 태그. `NIGHT_VIEW`(야경 좋음), `FEW_SIGNALS`(신호 적음), `GOOD_SURFACE`(노면 좋음), `CROWDED`(붐빔) 중 여러 개(B2). 기본 빈 배열. course 태그와 같은 배열 컬럼이다(`V20261013_2000`에서 `review_tags` 테이블을 옮김) |
| `best_progress_percent` | `INTEGER` | | 리뷰에 표시하는 그 회원의 이 코스 최고 진행도(%). 근거 기록이 삭제돼도 다시 계산하지 않는다 |
| `created_at` | `TIMESTAMPTZ` | | 작성 시각. 수정해도 바뀌지 않는다. 리뷰 이벤트의 `createdAt`이고 course 일별 평점이 이 날짜에 쌓인다 |

- `reviews_course_id_created_at_idx`: `(course_id, created_at DESC)`. 최신순
- `reviews_course_id_rating_idx`: `(course_id, rating, created_at DESC)`. 높은·낮은 평점순
- `member_id`는 유니크 제약 `(member_id, course_id)`의 앞 컬럼이라 따로 인덱스를 두지 않는다. `source_run_record_id`는 같은 스키마 `course_run_records`의 PK로 찾기만 해서 인덱스가 없다.
- `source_run_record_id`는 같은 스키마지만 FK를 걸지 않는다. 자격 복사본이 이벤트로 오기 전에 run에 직접 확인하고 쓰는 경우가 있다(개발 정책 4.3 `RunApi`).
- 리뷰 카드의 완주 횟수는 저장하지 않고 `course_run_records`에서 센다(정책 제4부 4.1 D-09).

#### `review.review_photos` — 리뷰 사진

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `id` | `UUID` | | PK |
| `review_id` | `UUID` | | FK `reviews.id`. 리뷰를 지우면 함께 지운다(`ON DELETE CASCADE`) |
| `photo_key` | `VARCHAR(100)` | | S3 키. `review/`로 시작한다(개발 정책 7장 사진 업로드) |
| `display_order` | `INTEGER` | | 표시 순서 0~4. 리뷰당 5장까지 |

- `review_photos_review_order_uk`: `(review_id, display_order)`. B8·G2 "사진만" 조건도 이 인덱스로 찾는다.
- `review_photos_key_uk`: `UNIQUE (photo_key)`. 사진 주소에 키가 보이므로, 남의 리뷰 사진 키를 가져다 붙이면 그 리뷰를 지울 때 원래 리뷰의 파일까지 지워진다. 그래서 키 하나는 리뷰 하나만 쓴다(REVIEW-007).
- 리뷰를 수정하면 사진 행을 모두 지우고 보낸 순서대로 다시 넣는다(`ReviewPhotos`). 빠진 사진과 지운 리뷰의 사진 파일은 커밋한 뒤 저장소에서 지운다. 회원 탈퇴 때 지우는 처리는 탈퇴 이벤트를 받을 때 붙인다.

#### `review.course_run_records` — 코스 주행 기록 복사본

run이 확정한 코스 주행 기록 1건이 1행이다(`RunSessionEndedEvent`, 자유 러닝은 받지 않는다). 리뷰 작성 자격과 리뷰 카드의 완주 횟수에 쓴다.

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `run_record_id` | `UUID` | | PK. run 모듈의 러닝 기록 ID. 같은 이벤트가 다시 와도 한 번만 저장된다 |
| `course_id` | `UUID` | | 코스 ID(course 모듈) |
| `member_id` | `UUID` | | 회원 ID(member 모듈) |
| `review_eligible` | `BOOLEAN` | ✓ | 리뷰 자격(정책 5.1: 한 세션 인정 거리 ≥ max(1km, 전체 × 20%)). run이 판정한 값을 그대로 저장한다 |
| `completed` | `BOOLEAN` | | 서버 완주 판정. 리뷰 자격과 따로 저장한다. 완주해도 자격이 없을 수 있다(1km 코스를 0.95km 인정으로 완주 등) |
| `progress_percent` | `INTEGER` | ✓ | 코스 진행도(%) 0~100. 이벤트의 `progress`(인정 거리 ÷ 전체 × 100)를 내림한다 |
| `course_distance_meters` · `course_elapsed_seconds` · `ended_at` | | `course_distance_meters`만 ✓ | B2 상단 근거 기록 표시("5.2km · 2026.09.08 완주 100% · 27:14") |
| `deleted` | `BOOLEAN` | | 기록이 삭제됐다. 기본 `false` |

- `course_run_records_member_course_idx`: `(member_id, course_id)`, 삭제되지 않은 행만. 리뷰 자격·최고 진행도·완주 횟수
- `course_run_records_course_id_idx`: `(course_id)`. 코스 삭제 때 정리
- 기록을 지우면 행을 지우지 않고 `deleted`만 켠다. 그 기록으로 얻은 자격은 사라지고 다른 기록의 자격은 남는다. 이미 쓴 리뷰는 그대로다(정책 제4부 4.1 D-09).
- 완주 횟수는 `completed`이고 삭제되지 않은 행 수다. 0이면 리뷰 카드에 표시하지 않는다.
- `RunSessionEndedEvent`로 행을 넣는다. 자유 러닝, 숨김·삭제된 코스, 탈퇴 회원의 기록은 받지 않는다. 이미 쓴 리뷰의 `best_progress_percent`는 여기서 올리지 않고 리뷰를 수정할 때 올린다(정책 제4부 4.1 D-09).
- `RunRecordDeletedEvent`로 `deleted`를 켠다. 삭제가 주행 기록보다 먼저 처리되면 삭제 표시 행을 먼저 만든다. 삭제 이벤트에는 리뷰 자격·진행도·코스 거리가 없어 그 칸은 비어 있고(NULL, `V20261015_1000`), 주행 기록이 늦게 오면 채운다. 읽는 쪽은 모두 삭제되지 않은 행만 본다.

#### `review.course_status_copies` — 코스 상태 복사본

ranking의 같은 이름 테이블과 같다(3.3). 숨김·삭제된 코스만 행이 있고, 행이 없으면 `ACTIVE`다.

- 숨김·삭제된 코스에는 새 리뷰를 쓸 수 없다(`REVIEW-005`). 숨김 코스의 리뷰는 보이지 않는다.
- 코스가 `DELETED`가 되면 그 코스의 리뷰(사진 포함)와 주행 기록 복사본을 지운다. 이때 `ReviewDeletedEvent`는 발행하지 않는다(course가 그 코스 통계를 직접 지운다, 개발 정책 5.6).

#### `review.withdrawn_members` — 탈퇴 회원

ranking의 같은 이름 테이블과 같다(3.3).

- `MemberWithdrawnEvent`를 받으면 그 회원의 리뷰(사진·S3 파일 포함)와 주행 기록 복사본을 바로 지우고 이 행을 남긴다. 리뷰마다 `ReviewDeletedEvent`를 발행해 course 평점에서 뺀다(정책 공통 4·5).
- 탈퇴 뒤에 도착한 그 회원의 주행 기록은 받지 않는다.

### 3.5 common

#### `common.region` — 법정구역

읽기 전용 참조 데이터다. 시드 마이그레이션이 데이터를 넣는다. 시드 파일은 `BackEnd/scripts/region/build-seed.sh`로 만들고 직접 고치지 않는다.

- 원본: 국가공간정보포털 법정구역 경계(`AL_D001_00_20260909`). 경계는 20m로 단순화했다.
- 행 수: 시·도 16, 시·군·구 256, 읍·면·동 5,067(모두 5,339). 광주·전남은 시·도 하나(`전남광주통합특별시`, `1200000000`)다.

| 컬럼 | 타입 | NULL | 설명 |
| --- | --- | --- | --- |
| `code` | `VARCHAR(10)` | | PK. 법정동 코드 10자리. 시·도는 앞 2자리, 시·군·구는 앞 5자리만 쓰고 나머지를 0으로 채운다 |
| `level` | `VARCHAR(15)` | | `SIDO`, `SIGUNGU`, `EUPMYEONDONG` |
| `name` | `VARCHAR(40)` | | 구역 이름. 예: `탕정면` |
| `full_name` | `VARCHAR(100)` | | 상위 구역을 붙인 이름. 예: `충청남도 아산시 탕정면` |
| `boundary` | `geometry(MultiPolygon, 4326)` | O | 경계. 읍·면·동만 가진다 |

- `region_boundary_gix`: `boundary` GiST. 좌표가 속한 읍·면·동을 찾는다(`RegionResolver`, 코스 등록). 상위 구역은 코드 앞자리로 정한다.
- 시·군·구 이름 검색(`RegionDirectory`, `GET /api/v1/regions`)은 `name`·`full_name`에 검색어가 들어간 행을 찾는다. 가입 활동 지역과 지역 랭킹의 지역 선택에 쓴다. 5천여 행이라 이름 인덱스 없이 훑는다.
- 다른 모듈은 코드 값만 저장하고 FK를 걸지 않는다.

#### `common.event_publication` — 이벤트 아웃박스

Spring Modulith가 관리한다. 이벤트를 발행하면 리스너마다 한 행이 생기고, 리스너가 처리를 마치면 지운다(`completion-mode: delete`).

- 주요 컬럼: `listener_id`, `event_type`, `serialized_event`, `publication_date`, `completion_date`, `status`, `completion_attempts`
- 남아 있는 행은 처리되지 않은 이벤트다. 앱을 다시 시작하면 다시 발행하고, `EventMonitor`·`EventRetryScheduler`가 1분마다 확인한다(개발 정책 5.5).

#### `common.shedlock` — 스케줄 작업 잠금

여러 인스턴스 중 한 곳에서만 스케줄 작업을 실행하게 한다(개발 정책 8.1). 행 하나가 작업 하나다(`common.event-monitor`, `common.event-retry`). 시각은 DB 시각(`TIMESTAMP`)을 쓴다.

#### `common.flyway_schema_history` — 마이그레이션 이력

Flyway가 관리한다. 모든 모듈의 마이그레이션 이력을 여기 한 곳에 둔다(개발 정책 6.5).


### 3.6 run

자유 러닝의 종료 원본 업로드·재계산·기록 조회·삭제를 담당한다. 코스·고스트 테이블은 아직 구현하지 않았다. 아래 테이블은 모두 `created_at`·`updated_at`을 갖는다. 2026-10-14 보완 마이그레이션으로 컬럼을 추가한 기존 행은 마이그레이션 시각을 기본값으로 가지며, 실제 러닝 시각은 `started_at`·결과의 `endedAt`로 구분한다.

#### `run.sessions` — 종료 기록 수집·처리 상태

| 컬럼 | 타입 | 설명 |
| --- | --- | --- |
| `id` | UUID PK | 앱이 생성하는 기록/세션 ID. 새 앱은 팀 규칙대로 UUID v7 사용. 기존 ID는 변경하지 않음 |
| `member_id` | UUID | 소유자 ID. 다른 모듈 FK 없음 |
| `started_at` | TIMESTAMPTZ | 실제 측정 시작 시각 |
| `final_seq` | BIGINT nullable | 종료 원본의 마지막 순번 |
| `processing` | VARCHAR(20) | PREPARED / NEEDS_DATA / PROCESSING / DONE / FAILED |
| `failure` | VARCHAR(40) nullable | 처리 실패 사유 |

소유자·시작 시각 인덱스와 PROCESSING 부분 인덱스가 있다. 회원별 트랜잭션 잠금 후 기록별 잠금을 얻어 탈퇴·업로드·삭제·처리를 직렬화한다. 같은 ID의 재업로드는 기존 결과와 등록 시각을 유지한다.

#### `run.inputs` — 원본 입력 스트림

PK는 `(session_id, stream_seq)`, `session_id`만 같은 run 스키마 sessions에 FK를 둔다. `payload` TEXT에 START/GPS/PAUSE/RESUME/GAP/END/CADENCE 원본을 저장한다. GPS `measuredAt`은 실제 표본 UTC, `elapsedMs`는 수신 처리의 단조 경과 시각이다. CADENCE의 `sampleEndMs`는 센서 측정 구간의 단조 시각이다. 속도·속도 정확도·걸음 표본을 보존한다.

#### `run.records` — 서버 확정 결과와 목록 요약

| 컬럼 | 타입 | 설명 |
| --- | --- | --- |
| `id` | UUID PK/FK | sessions ID와 같은 기록 ID |
| `registered_at` | TIMESTAMPTZ | 최초 서버 등록 시각. 재전송으로 바꾸지 않음 |
| `result_json` | TEXT | 상세 경로·랩·시간·거리·케이던스·정책/계산 버전 |
| `summary_json` | TEXT | 목록용 RecordSummary. 경로·랩 없음 |
| `registration_published` | BOOLEAN | 등록 이벤트의 동일 트랜잭션 발행 완료 표시 |

목록은 `summary_json`만 읽는다. `(registered_at DESC, id DESC)` 인덱스를 사용하고 공통 Cursorable/CursorSlice 계약을 따른다. summary는 이미 저장된 결과에서 생성하며 거리 계산을 소급 변경하지 않는다. 새 결과의 정책 버전은 사용자 승인 날짜 `2026-10-14`, 계산 버전은 START의 `PACE_V2` 등이다. 과거 저장 결과에 없는 버전은 새 버전으로 소급 표기하지 않는다.

미발행 기록 조회에는 `WHERE NOT registration_published` 부분 인덱스를 사용한다. 등록 결과와 이벤트 발행 표시는 같은 트랜잭션에서 커밋한다. 기존 서버 기록도 미발행 상태로 한 번 발행할 수 있으나 원래 결과·등록 시각을 유지한다. 이벤트 전달/재시도는 공통 Modulith 아웃박스를 사용한다.

#### `run.deleted_records` — 삭제 ID 예약

`id` UUID PK, `member_id` UUID, `deleted_at` TIMESTAMPTZ. 좌표나 결과는 보관하지 않는다. 실제 inputs·records·sessions는 삭제하고 ID 예약만 남겨 늦은 업로드가 기록을 재생성하지 못하게 한다. 소유자 인덱스가 있다.

#### `run.withdrawn_members` — 탈퇴 후 업로드 차단

`member_id` UUID PK, `withdrawn_at` TIMESTAMPTZ. MemberWithdrawnEvent 수신 후 원본·결과를 실제 삭제하고 이후 prepare/upload/처리를 차단한다. 등록된 기록마다 RunRecordDeletedEvent를 발행한다. 이벤트 재수신은 멱등이다.

#### 기기 SQLite와 서버 DB의 구분

앱의 `runs_v1.db`(현재 스키마 v3)는 별개다. 파일명은 기존 기기 기록을 유지하기 위해 바꾸지 않는다. 서버의 미종료 세션 관리 DB가 아니라 통신 없이 측정·저장·복구할 원본 저장소이며, 서버 확정 전후 화면은 같은 기록 ID로 합친다.

| 기기 테이블 | 저장 내용 |
| --- | --- |
| `sessions` | 계정·러닝 상태·복구 지점·업로드 대기/실패 상태, 서버 상세 `result`, 목록용 `summary` |
| `inputs` | `(session_id, seq)`별 원본 입력 JSON. 서버 등록 후에도 원본 유지 |
| `run_settings` | 계정별 음성 안내 설정 |
| `run_deletions` | `(owner, id)`별 삭제 ID와 서버 삭제 전송 대기 상태. 좌표·결과 없음 |

- v3는 `sessions.summary TEXT`만 추가한다. v1→v2의 계정별 설정·삭제 테이블 이관도 유지한다. 기존 원본·결과·등록 시각·삭제 ID를 삭제하거나 새 계산 버전으로 다시 쓰지 않는다.
- 종료 입력·종료 상태·업로드 대기·기기 계산 요약은 같은 SQLite 트랜잭션으로 저장한다. 서버 확인 시 상세 결과와 서버 요약·동기화 완료도 같은 갱신으로 저장한다. 결과 ID가 다르면 저장하지 않는다.
- 목록은 경로·랩을 제외한 `summary`와 상태 컬럼만 읽는다. 상세를 열 때 선택한 ID의 원본·서버 결과를 읽고, 동기화는 미전송 종료 기록만, 복구는 미종료 기록만 읽는다. 기존 기록의 요약이 비어 있으면 최초 조회에 한 번 생성한다. 저장된 서버 확정 결과가 있으면 그 값과 최초 등록 시각을 그대로 요약한다.
- 기기에 삭제된 ID는 생성 단계에서도 재사용하지 못한다. 삭제 뒤 도착한 서버 응답은 행을 재생성하거나 삭제된 메모리 기록을 갱신하지 않는다. 삭제 ID는 서버 반영 후에도 유지한다.

서버 테이블은 이번 기기 조회 변경으로 바뀌지 않아 추가 Flyway 마이그레이션이 필요하지 않다. 서버의 원본/요약 분리·멱등 등록·삭제/탈퇴 잠금은 위 3.6의 기존 구조를 사용한다.


#### GPS 선택 고도 원본 (2026-10-15)

기기 `inputs.payload`와 서버 `run.inputs.payload`에 `altitudeM`·`altitudeAccuracyM`(m) 선택 JSON 필드를 보존한다. 실제 측정 0m·음수 고도를 허용하며 누락은 null/필드 생략이다. 고도 정확도는 고도가 있을 때만 보존하며 0 이상이다. 기존 JSON의 필드 누락은 호환되고 기존 좌표·순번·거리 계산·등록 시각을 수정하지 않는다.

이 변경은 테이블 컬럼을 추가하지 않아 SQLite는 v3를 유지하고 Flyway 마이그레이션을 추가하지 않는다. 목록용 summary와 기존 Result의 2차원 경로는 확장하지 않으며 고도 원본은 상세 분석/course-source 후속 기능에서 사용할 수 있도록 원본에만 남긴다. 고도 수집 성공을 누적 상승고도나 코스 고도 프로필 계산 완료로 해석하지 않는다.

#### 자유 러닝 RESULT_V1 추가 통계 (2026-10-16)

`run.records.result_json`·`summary_json`과 기기 `sessions.result`·`summary`에 선택 `stats` 객체를 추가한다. 필드는 `version="RESULT_V1"`, `elevationGainM`(nullable m), `elevationPartial`(boolean), `bestLapNumber`(nullable), `bestLapPaceSecondsPerKm`·`bestPaceSecondsPerKm`(nullable 초/km)다. 실제 측정된 상승 없음은 0, 원본 없음/분석 불가는 null이다.

테이블 컬럼과 원본 payload는 바꾸지 않으므로 SQLite v3를 유지하고 Flyway 이관은 없다. 새 종료 요약과 새 서버 결과에 stats를 함께 보존한다. stats 없는 과거 서버 결과는 상세 읽기 시 원본으로 stats만 보완하며 DB 원본·기존 결과·최초 등록 시각·랭킹 이벤트는 바꾸지 않는다. 기기에 보존된 원본으로도 이전 서버 결과의 stats를 보완할 수 있다. 목록용 요약의 경로·원본 제외 원칙은 유지한다.
