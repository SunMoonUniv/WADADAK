CREATE TABLE run.deleted_records (
    id uuid PRIMARY KEY,
    member_id uuid NOT NULL,
    deleted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX run_deleted_owner ON run.deleted_records(member_id);
