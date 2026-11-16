-- No FK to source sessions/records: deletion keeps a tombstone, not another personal record.
CREATE TABLE run.gps_source_links (
    source_record_id uuid PRIMARY KEY,
    course_id uuid NOT NULL UNIQUE,
    member_id uuid NOT NULL,
    registration_event_id uuid NOT NULL,
    snapshot_json text,
    status varchar(16) NOT NULL CHECK (status IN ('PENDING','LINKED','REJECTED','REMOVED')),
    failure varchar(64),
    performance_json text,
    registered_at timestamptz,
    completed_at timestamptz,
    course_elapsed_seconds bigint,
    elapsed_ms bigint,
    linked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX gps_source_links_pending ON run.gps_source_links(created_at) WHERE status='PENDING';
CREATE INDEX gps_source_links_member ON run.gps_source_links(member_id,course_id) WHERE status='LINKED';
CREATE TABLE run.gps_course_status_copies (
    course_id uuid PRIMARY KEY,
    status varchar(16) NOT NULL,
    source_version bigint NOT NULL
);
