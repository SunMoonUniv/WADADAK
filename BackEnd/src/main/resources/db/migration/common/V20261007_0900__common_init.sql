-- Spring Modulith 2.1 이벤트 발행 저장소(아웃박스). spring-modulith-events-jdbc v2 PostgreSQL 스키마와 같다.
CREATE TABLE common.event_publication
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
CREATE INDEX event_publication_serialized_event_hash_idx ON common.event_publication USING hash (serialized_event);
CREATE INDEX event_publication_by_completion_date_idx ON common.event_publication (completion_date);

-- ShedLock. usingDbTime()으로 DB 시각을 쓴다.
CREATE TABLE common.shedlock
(
    name       VARCHAR(64)  NOT NULL,
    lock_until TIMESTAMP    NOT NULL,
    locked_at  TIMESTAMP    NOT NULL,
    locked_by  VARCHAR(255) NOT NULL,
    PRIMARY KEY (name)
);
