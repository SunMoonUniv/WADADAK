-- Existing migrations remain immutable. Summary reads never load route/lap JSON.
ALTER TABLE run.records ADD COLUMN summary_json text;
UPDATE run.records SET summary_json = (result_json::jsonb - 'routeSegments' - 'laps')::text;
ALTER TABLE run.records ALTER COLUMN summary_json SET NOT NULL;

CREATE TABLE run.withdrawn_members (
    member_id uuid PRIMARY KEY,
    withdrawn_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE run.sessions ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE run.sessions ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE run.inputs ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE run.inputs ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE run.records ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE run.records ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE run.deleted_records ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE run.deleted_records ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

-- Durable one-time publication for records that existed before the event contract.
ALTER TABLE run.records ADD COLUMN registration_published boolean NOT NULL DEFAULT false;
CREATE INDEX run_records_unpublished ON run.records(registered_at) WHERE NOT registration_published;
