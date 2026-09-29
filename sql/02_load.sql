-- ============================================================
-- Strength Training Database — load and transform
-- Run after 01_schema.sql and after importing data/workout_sets.csv
-- into staging_sets.
--
-- Import in DBeaver: right-click staging_sets > Import Data > CSV >
-- pick workout_sets.csv > Next through the wizard > Proceed.
-- Confirm before continuing:
--     SELECT COUNT(*) FROM staging_sets;   -- expect 2799
-- ============================================================


-- ------------------------------------------------------------
-- Note on the boolean columns
--
-- The CSV writes booleans as TRUE / FALSE in caps. Comparing them to
-- the string 'True' silently matches nothing: the load appears to
-- succeed and `sets` comes out empty. Casting to BOOLEAN instead of
-- string-matching handles TRUE, true and t alike, and throws a loud
-- error on anything it does not recognize.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- exercises: one row per distinct movement
--
-- is_fragment marks lines the parser could not resolve into a real
-- movement — 'An', 'Inc', 'Ss', 'Warm-Up Target Muscles'. Without this
-- filter they become 11 junk rows in the exercise list.
-- ------------------------------------------------------------
INSERT INTO exercises (name, muscle_group)
SELECT DISTINCT ON (exercise)
       exercise,
       NULLIF(muscle_group, '')
FROM   staging_sets
WHERE  COALESCE(exercise, '') <> ''
  AND  NOT is_fragment::BOOLEAN
ORDER  BY exercise, muscle_group NULLS LAST;


-- ------------------------------------------------------------
-- workouts: one row per training day and label
--
-- Rest and skipped days are loaded too. A gap in training is a fact
-- about the training, so dropping those rows would hide it.
-- 'Skipped' is folded into 'Skip' — same thing, two spellings.
-- ------------------------------------------------------------
INSERT INTO workouts (workout_date, split, split_raw, status, section)
SELECT DISTINCT ON (workout_date::DATE, split_raw)
       workout_date::DATE,
       NULLIF(split, ''),
       NULLIF(split_raw, ''),
       CASE NULLIF(workout_status, '')
            WHEN 'Skipped' THEN 'Skip'
            ELSE NULLIF(workout_status, '')
       END,
       NULLIF(section, '')
FROM   staging_sets
WHERE  COALESCE(workout_date, '') <> ''
ORDER  BY workout_date::DATE, split_raw, workout_status NULLS LAST;


-- ------------------------------------------------------------
-- sets: only rows that actually recorded a set
--
-- logged_sets is FALSE on rest days, skipped days and header lines —
-- 156 rows that carry a date but no set.
-- ------------------------------------------------------------
INSERT INTO sets (workout_id, exercise_id, set_number, weight_lb, reps,
                  grip, attachment, orig_unit,
                  added_weight, to_failure, is_warmup, is_cardio,
                  self_flagged_uncertain, unverified_block,
                  source_line, raw_line)
SELECT w.workout_id,
       e.exercise_id,
       NULLIF(s.set_number, '')::INT,
       NULLIF(s.weight_lb,  '')::NUMERIC,
       NULLIF(s.reps,       '')::NUMERIC,
       NULLIF(s.grip,       ''),
       NULLIF(s.attachment, ''),
       NULLIF(s.orig_unit,  ''),
       s.added_weight::BOOLEAN,
       s.to_failure::BOOLEAN,
       s.is_warmup::BOOLEAN,
       s.is_cardio::BOOLEAN,
       s.self_flagged_uncertain::BOOLEAN,
       s.unverified_block::BOOLEAN,
       NULLIF(s.source_line, '')::INT,
       s.raw_line
FROM   staging_sets s
JOIN   workouts  w ON w.workout_date = s.workout_date::DATE
                  AND w.split_raw IS NOT DISTINCT FROM NULLIF(s.split_raw, '')
JOIN   exercises e ON e.name = s.exercise
WHERE  s.logged_sets::BOOLEAN
  AND  NOT s.is_fragment::BOOLEAN;


-- ------------------------------------------------------------
-- Manual exclusions
-- ------------------------------------------------------------
INSERT INTO excluded_sets (source_line, reason) VALUES
  (1647, 'Squat 25x8/25x12 on 2026-08-31. 250 lb below the surrounding months and I cannot account for it. Weight is not trustworthy, so the sets are excluded rather than guessed at.')
ON CONFLICT (source_line) DO NOTHING;


-- ------------------------------------------------------------
-- Load check. All three numbers should match exactly.
-- ------------------------------------------------------------
SELECT 'exercises' AS table_name, COUNT(*) AS rows, 272 AS expected FROM exercises
UNION ALL SELECT 'workouts', COUNT(*), 257 FROM workouts
UNION ALL SELECT 'sets',     COUNT(*), 2643 FROM sets;
