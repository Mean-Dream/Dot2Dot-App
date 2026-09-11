-- Supersedes 20260306142237_initial_schema.sql, which described a schema that
-- was never used. This file documents the real live schema and is safe to run
-- against an existing database — all statements are idempotent.
--
-- Execution order on a FRESH database:
--   1. 20260306142237_initial_schema.sql  (creates wrong projects + dead tables)
--   2. 20260615000001_actual_schema.sql   ← THIS FILE (corrects schema)
--   3. 20260615000000_rls_policies.sql    (RLS — note: timestamp is lower but
--      should be applied after schema is correct; reorder if re-running from
--      scratch by renaming that file to 20260615000002_rls_policies.sql)

-- ── 1. Remove dead tables from the superseded migration ───────────────────────
DROP TABLE IF EXISTS exports;
DROP TABLE IF EXISTS credits_ledger;
DROP TABLE IF EXISTS entitlements;
DROP TABLE IF EXISTS gallery_items;

-- ── 2. Correct projects table ─────────────────────────────────────────────────
-- Creates the table when starting from scratch.
-- If it already exists (live DB), the ALTER TABLE block below handles it.
CREATE TABLE IF NOT EXISTS projects (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         REFERENCES auth.users NOT NULL,
    name            TEXT         NOT NULL DEFAULT 'Untitled Puzzle',
    image_path      TEXT,
    status          TEXT         NOT NULL DEFAULT 'processing',
    dots            JSONB        NOT NULL DEFAULT '[]',
    erased_points   JSONB        NOT NULL DEFAULT '[]',
    sparsity        INTEGER      NOT NULL DEFAULT 20,
    dot_count       INTEGER      NOT NULL DEFAULT 0,
    difficulty      TEXT         NOT NULL DEFAULT 'Easy',
    last_index      INTEGER      NOT NULL DEFAULT 0,
    remove_bg       BOOLEAN      NOT NULL DEFAULT false,
    easy_cleared    BOOLEAN      NOT NULL DEFAULT false,
    medium_cleared  BOOLEAN      NOT NULL DEFAULT false,
    hard_cleared    BOOLEAN      NOT NULL DEFAULT false,
    dots_easy       JSONB,
    dots_medium     JSONB,
    dots_hard       JSONB,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Additive guards for a database that ran the old migration first.
-- ADD COLUMN IF NOT EXISTS is a no-op when the column already exists.
ALTER TABLE projects ADD COLUMN IF NOT EXISTS name            TEXT        NOT NULL DEFAULT 'Untitled Puzzle';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS image_path      TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS status          TEXT        NOT NULL DEFAULT 'processing';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS dots            JSONB       NOT NULL DEFAULT '[]';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS erased_points   JSONB       NOT NULL DEFAULT '[]';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS sparsity        INTEGER     NOT NULL DEFAULT 20;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS dot_count       INTEGER     NOT NULL DEFAULT 0;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS difficulty      TEXT        NOT NULL DEFAULT 'Easy';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS last_index      INTEGER     NOT NULL DEFAULT 0;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS remove_bg       BOOLEAN     NOT NULL DEFAULT false;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS easy_cleared    BOOLEAN     NOT NULL DEFAULT false;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS medium_cleared  BOOLEAN     NOT NULL DEFAULT false;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS hard_cleared    BOOLEAN     NOT NULL DEFAULT false;

-- ── 3. Index ──────────────────────────────────────────────────────────────────
-- Speeds up the most common query: list a user's projects, newest first.
CREATE INDEX IF NOT EXISTS projects_user_id_created_at_idx
    ON projects (user_id, created_at DESC);

-- ── 4. Storage bucket ─────────────────────────────────────────────────────────
-- Public bucket; the service-role key (used by Node API) is required to write.
-- Anon users can read (public URLs work without auth).
INSERT INTO storage.buckets (id, name, public)
VALUES ('images', 'images', true)
ON CONFLICT (id) DO NOTHING;
