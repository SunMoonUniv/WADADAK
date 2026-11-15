CREATE SCHEMA IF NOT EXISTS run;
CREATE TABLE run.sessions (
    id uuid PRIMARY KEY,
    member_id uuid NOT NULL,
    started_at timestamptz NOT NULL,
    final_seq bigint,
    processing varchar(20) NOT NULL CHECK (processing IN ('PREPARED','NEEDS_DATA','PROCESSING','DONE','FAILED')),
    failure varchar(40)
);
CREATE INDEX run_sessions_owner ON run.sessions(member_id, started_at DESC);
CREATE INDEX run_sessions_processing ON run.sessions(started_at) WHERE processing='PROCESSING';
CREATE TABLE run.inputs (
    session_id uuid NOT NULL REFERENCES run.sessions(id),
    stream_seq bigint NOT NULL CHECK (stream_seq>=0),
    payload text NOT NULL,
    PRIMARY KEY(session_id,stream_seq)
);
CREATE TABLE run.records (
    id uuid PRIMARY KEY REFERENCES run.sessions(id),
    registered_at timestamptz NOT NULL,
    result_json text NOT NULL
);
CREATE INDEX run_records_registered ON run.records(registered_at DESC, id DESC);
