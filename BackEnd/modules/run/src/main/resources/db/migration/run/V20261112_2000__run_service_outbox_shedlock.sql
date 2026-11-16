-- run 서비스가 분리 뒤 쓸 아웃박스·ShedLock(MSA 분리 1단계, 개발 정책 11.3).
-- 모놀리스는 아직 common 스키마의 테이블을 쓴다. 분리 전환 배포에는 마이그레이션을 넣지 않으므로 미리 만든다.
-- run 서비스는 ddl-auto: validate라 이 테이블이 없으면 뜨지 않는다. 구조는 common과 같다(V20261007_0900).
CREATE TABLE run.event_publication
(
    id                     UUID                     NOT NULL,
    listener_id            TEXT                     NOT NULL,
    event_type             TEXT                     NOT NULL,
    serialized_event       TEXT                     NOT NULL,
    publication_date       TIMESTAMP WITH TIME ZONE NOT NULL,
    completion_date        TIMESTAMP WITH TIME ZONE,
    status                 TEXT,
    completion_attempts    INT,
    last_resubmission_date TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (id)
);
CREATE INDEX event_publication_serialized_event_hash_idx ON run.event_publication USING hash (serialized_event);
CREATE INDEX event_publication_by_completion_date_idx ON run.event_publication (completion_date);

CREATE TABLE run.shedlock
(
    name       VARCHAR(64)  NOT NULL,
    lock_until TIMESTAMP    NOT NULL,
    locked_at  TIMESTAMP    NOT NULL,
    locked_by  VARCHAR(255) NOT NULL,
    PRIMARY KEY (name)
);
