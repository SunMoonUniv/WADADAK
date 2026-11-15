-- Private run-owned references are not registered courses or course attempts.
CREATE TABLE run.free_ghost_starts (
    session_id uuid PRIMARY KEY REFERENCES run.sessions(id) ON DELETE CASCADE,
    member_id uuid NOT NULL,
    reference_hash varchar(64) NOT NULL,
    approval_json text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX free_ghost_starts_member ON run.free_ghost_starts(member_id);
CREATE TABLE run.free_ghost_results (
    session_id uuid PRIMARY KEY REFERENCES run.free_ghost_starts(session_id) ON DELETE CASCADE,
    finalized_at timestamptz NOT NULL,
    result_json text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
