-- ============================================================
-- Strength Training Database — schema
-- Target: PostgreSQL 18, database `fitness`
--
-- Run order: 01_schema.sql -> import CSV -> 02_load.sql
-- In DBeaver run whole files with Alt+X. Ctrl+Enter runs one statement.
-- ============================================================


-- ------------------------------------------------------------
-- Staging
--
-- Every column lands as TEXT. Casting happens in 02_load.sql, after
-- the data is already in the database. Loading straight into typed
-- columns means one malformed row aborts the whole import and the
-- error never tells you which row did it.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS staging_sets CASCADE;

CREATE TABLE staging_sets (
  workout_date            TEXT,
  split                   TEXT,
  split_raw               TEXT,
  workout_status          TEXT,
  exercise                TEXT,
  muscle_group            TEXT,
  grip                    TEXT,
  attachment              TEXT,
  exercise_detail         TEXT,
  set_number              TEXT,
  weight_lb               TEXT,
  reps                    TEXT,
  added_weight            TEXT,
  orig_unit               TEXT,
  to_failure              TEXT,
  is_warmup               TEXT,
  is_cardio               TEXT,
  is_skipped              TEXT,
  logged_sets             TEXT,
  date_collision          TEXT,
  unverified_block        TEXT,
  is_fragment             TEXT,
  self_flagged_uncertain  TEXT,
  section                 TEXT,
  source_line             TEXT,
  raw_line                TEXT
);

COMMENT ON TABLE staging_sets IS
  'Raw CSV landing zone. One row per parsed set. Dropped and reloaded freely.';


-- ------------------------------------------------------------
-- Normalized tables
-- ------------------------------------------------------------
DROP TABLE IF EXISTS sets      CASCADE;
DROP TABLE IF EXISTS workouts  CASCADE;
DROP TABLE IF EXISTS exercises CASCADE;


CREATE TABLE exercises (
  exercise_id   SERIAL PRIMARY KEY,
  name          TEXT NOT NULL UNIQUE CHECK (name <> ''),
  muscle_group  TEXT
);

COMMENT ON TABLE exercises IS
  'One row per distinct movement. Parser fragments are excluded at load time.';


CREATE TABLE workouts (
  workout_id    SERIAL PRIMARY KEY,
  workout_date  DATE NOT NULL,
  split         TEXT,   -- cleaned vocabulary: Push/Pull/Legs/Upper/Lower/Arms/Sharms/Rest
  split_raw     TEXT,   -- exactly as written in the notes, e.g. 'Lower + Abs'
  status        TEXT,   -- Rest / Skip / Nothing / No exercises logged
  section       TEXT,   -- which block of the source notes this came from

  CONSTRAINT workouts_date_label_uniq UNIQUE (workout_date, split_raw),
  CONSTRAINT workouts_status_vocab CHECK (
    status IS NULL OR status IN ('Rest', 'Skip', 'Nothing', 'No exercises logged')
  )
);

COMMENT ON TABLE workouts IS
  'One row per training day and label. Rest and skipped days are kept so gaps are visible.';


CREATE TABLE sets (
  set_id        SERIAL PRIMARY KEY,
  workout_id    INT NOT NULL REFERENCES workouts(workout_id)  ON DELETE CASCADE,
  exercise_id   INT NOT NULL REFERENCES exercises(exercise_id),
  set_number    INT,
  weight_lb     NUMERIC(6,1),  -- NULL = the set was logged, the weight was not
  reps          NUMERIC(4,1),  -- NULL = reps not recorded. Decimals are half reps.
  grip          TEXT,          -- Close / Neutral / Wide / Underhand
  attachment    TEXT,          -- Rope / V-Bar / EZ Bar / Straight Bar / Single Arm
  orig_unit     TEXT,          -- lb / kg (converted on the way in) / bw (bodyweight)

  added_weight            BOOLEAN NOT NULL DEFAULT FALSE,  -- '+' = plate added to a loaded machine
  to_failure              BOOLEAN NOT NULL DEFAULT FALSE,
  is_warmup               BOOLEAN NOT NULL DEFAULT FALSE,
  is_cardio               BOOLEAN NOT NULL DEFAULT FALSE,
  self_flagged_uncertain  BOOLEAN NOT NULL DEFAULT FALSE,  -- the note itself says 'idk' / '?' / 'forgot'
  unverified_block        BOOLEAN NOT NULL DEFAULT FALSE,  -- backfilled from memory, not logged same day

  source_line   INT,   -- line number in the original notes
  raw_line      TEXT,  -- the original text, kept so any row can be audited

  CONSTRAINT sets_weight_sane CHECK (weight_lb IS NULL OR weight_lb BETWEEN 0 AND 1000),
  CONSTRAINT sets_reps_sane   CHECK (reps      IS NULL OR reps      BETWEEN 0 AND 200),
  CONSTRAINT sets_number_sane CHECK (set_number IS NULL OR set_number > 0)
);

COMMENT ON TABLE sets IS
  'One row per working set. Warmups are kept and flagged rather than discarded.';
COMMENT ON COLUMN sets.unverified_block IS
  'TRUE where the source notes were written from memory after the fact. 163 rows.';
COMMENT ON COLUMN sets.weight_lb IS
  'Bodyweight movements store 0 with orig_unit = ''bw''. Exclude them from volume math.';


-- ------------------------------------------------------------
-- Indexes
--
-- The three access patterns this database actually has:
--   filter a date range, join sets to workouts, join sets to exercises.
-- ------------------------------------------------------------
CREATE INDEX idx_workouts_date   ON workouts(workout_date);
CREATE INDEX idx_sets_workout    ON sets(workout_id);
CREATE INDEX idx_sets_exercise   ON sets(exercise_id);

-- Volume and progression queries all filter warmups out first.
CREATE INDEX idx_sets_working    ON sets(exercise_id, workout_id) WHERE NOT is_warmup;
