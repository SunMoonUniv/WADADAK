-- Per-record insertion copy: primary key makes repeated delivery idempotent.
-- A deletion can arrive before registration; retain its tombstone.
CREATE TABLE ranking.distance_run_records (
    run_record_id uuid PRIMARY KEY,
    member_id uuid NOT NULL,
    distance_meters double precision NOT NULL CHECK (distance_meters >= 0),
    registered_at timestamptz NOT NULL,
    deleted boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX distance_run_records_member_idx ON ranking.distance_run_records(member_id);
CREATE INDEX distance_run_records_registered_idx ON ranking.distance_run_records(registered_at) WHERE NOT deleted;
