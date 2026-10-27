-- Immutable summary; no source record FK and no playback/GPS/profile copy.
-- Preserve replay for the duel and subsequent result comparison; no timed expiry.
CREATE TABLE run.ghost_results (
    session_id uuid PRIMARY KEY REFERENCES run.ghost_starts(session_id) ON DELETE CASCADE,
    finalized_at timestamptz NOT NULL,
    result_json text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
