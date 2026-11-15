-- Preserve original provenance while comparing exact unchanged geometry with current metadata.
ALTER TABLE run.ghost_starts ADD COLUMN source_course_version bigint;
