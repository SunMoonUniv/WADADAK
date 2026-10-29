ALTER TABLE run.ghost_starts ADD COLUMN public_period varchar(8);
-- Legacy saved START inputs may legitimately have a null calculation version.
ALTER TABLE run.ghost_starts ALTER COLUMN source_calculation_version DROP NOT NULL;
ALTER TABLE run.ghost_starts ADD CONSTRAINT ghost_public_period_valid
    CHECK (public_period IS NULL OR public_period IN ('ALL','MONTH','WEEK'));

-- Run owns this event projection. No cross-schema lookup/FK or timed ghost expiry.
CREATE TABLE run.member_visibility_copies (
    member_id uuid PRIMARY KEY,
    visible boolean NOT NULL,
    source_version bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
