-- A course attempt exists before upload creates run.sessions. No FK to the source record:
-- deleting the opponent after approval must not delete another ongoing duel's fixed material.
CREATE TABLE run.ghost_starts (
    session_id uuid PRIMARY KEY REFERENCES run.course_attempts(session_id) ON DELETE CASCADE,
    source_record_id uuid NOT NULL,
    started_at timestamptz NOT NULL,
    approved_at timestamptz NOT NULL,
    course_validated_at timestamptz NOT NULL,
    approval_version varchar(40) NOT NULL,
    playback_version varchar(40) NOT NULL,
    source_policy_version varchar(40) NOT NULL,
    source_calculation_version varchar(40) NOT NULL,
    source_elapsed_seconds bigint NOT NULL,
    source_duration_ms bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX run_ghost_starts_source ON run.ghost_starts(source_record_id);

-- Derived time/course-position data only. No source GPS input stream or member profile.
-- Separate detail from the approval identity; final-verdict retention comes in the verdict slice.
CREATE TABLE run.ghost_start_playbacks (
    session_id uuid PRIMARY KEY REFERENCES run.ghost_starts(session_id) ON DELETE CASCADE,
    playback_json text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
