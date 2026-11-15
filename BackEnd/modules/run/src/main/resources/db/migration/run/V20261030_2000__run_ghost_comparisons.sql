CREATE TABLE run.ghost_comparisons (
    session_id UUID PRIMARY KEY,
    registered_session_id UUID UNIQUE REFERENCES run.ghost_starts(session_id) ON DELETE CASCADE,
    free_session_id UUID UNIQUE REFERENCES run.free_ghost_starts(session_id) ON DELETE CASCADE,
    member_id UUID NOT NULL,
    context_json TEXT NOT NULL,
    result_json TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((registered_session_id IS NOT NULL AND registered_session_id=session_id AND free_session_id IS NULL)
        OR (free_session_id IS NOT NULL AND free_session_id=session_id AND registered_session_id IS NULL))
);
