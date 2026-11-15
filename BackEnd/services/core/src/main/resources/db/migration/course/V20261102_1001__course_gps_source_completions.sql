-- The registration snapshot and outbox publication are committed with the GPS registration.
ALTER TABLE course.gps_course_sources ADD COLUMN completion_snapshot_json text;
CREATE TABLE course.gps_source_completion_receipts (
    run_record_id uuid PRIMARY KEY,
    course_id uuid NOT NULL,
    member_id uuid NOT NULL,
    course_elapsed_seconds bigint NOT NULL,
    applied boolean NOT NULL DEFAULT false,
    removed boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
