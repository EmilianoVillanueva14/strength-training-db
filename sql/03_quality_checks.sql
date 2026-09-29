-- ============================================================
-- Strength Training Database — data quality
--
-- This is a log of workouts kept by hand in a notes app over 14
-- months. Some of it was written days later from memory. These checks
-- make what is unreliable visible instead of quietly averaging it in.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Referential integrity. Both counts must be 0.
-- ------------------------------------------------------------
SELECT 'sets with no workout' AS check_name, COUNT(*) AS bad_rows
FROM   sets s
LEFT   JOIN workouts w USING (workout_id)
WHERE  w.workout_id IS NULL

UNION ALL

SELECT 'sets with no exercise', COUNT(*)
FROM   sets s
LEFT   JOIN exercises e USING (exercise_id)
WHERE  e.exercise_id IS NULL;


-- ------------------------------------------------------------
-- 2. Completeness, stated plainly rather than hidden
-- ------------------------------------------------------------
SELECT COUNT(*)                                          AS total_sets,
       COUNT(*) FILTER (WHERE weight_lb IS NULL)         AS missing_weight,
       COUNT(*) FILTER (WHERE reps      IS NULL)         AS missing_reps,
       COUNT(*) FILTER (WHERE unverified_block)          AS written_from_memory,
       COUNT(*) FILTER (WHERE self_flagged_uncertain)    AS noted_as_unsure,
       ROUND(100.0 * COUNT(*) FILTER (WHERE unverified_block) / COUNT(*), 1)
                                                         AS pct_from_memory
FROM   sets;


-- ------------------------------------------------------------
-- 3. Implausible rows
--
-- A view rather than a one-off query, so every analysis below can
-- exclude it by name. These are not corrected in place: the raw line
-- is kept so the judgement call stays visible.
--
-- 300 lb x 100 reps is a stray zero. So is 235 x 60.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW suspect_sets AS
SELECT s.set_id,
       w.workout_date,
       e.name AS exercise,
       s.weight_lb,
       s.reps,
       s.raw_line,
       CASE
         WHEN s.reps > 30                        THEN 'rep count implausible'
         WHEN s.weight_lb > 500                  THEN 'weight implausible'
         WHEN s.weight_lb = 0 AND s.orig_unit <> 'bw'
                                                 THEN 'zero weight, not bodyweight'
         WHEN s.reps IS NULL AND s.weight_lb IS NULL
                                                 THEN 'set recorded with no numbers'
         WHEN x.source_line IS NOT NULL          THEN 'manually excluded: ' || x.reason
       END AS reason
FROM   sets s
JOIN   workouts  w USING (workout_id)
JOIN   exercises e USING (exercise_id)
LEFT   JOIN excluded_sets x ON x.source_line = s.source_line
WHERE  s.reps > 30
   OR  s.weight_lb > 500
   OR (s.weight_lb = 0 AND s.orig_unit <> 'bw')
   OR (s.reps IS NULL AND s.weight_lb IS NULL)
   OR  x.source_line IS NOT NULL;

SELECT * FROM suspect_sets ORDER BY workout_date;


-- ------------------------------------------------------------
-- 3b. Exercise names that look like parse artifacts
--
-- A movement name should not contain digits. 'Romanian Deadlift 135Wu'
-- is a warmup weight that got swallowed into the name and should be
-- folded back into 'Romanian Deadlift'.
-- ------------------------------------------------------------
SELECT e.exercise_id,
       e.name,
       COUNT(s.set_id) AS sets
FROM   exercises e
LEFT   JOIN sets s USING (exercise_id)
WHERE  e.name ~ '[0-9]'
GROUP  BY e.exercise_id, e.name
ORDER  BY sets DESC;


-- ------------------------------------------------------------
-- 4. Trustworthy working sets
--
-- The base view every analysis query builds on. Warmups, cardio,
-- bodyweight-only movements and the suspect rows are all excluded,
-- so volume numbers mean one thing consistently.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW working_sets AS
SELECT s.set_id,
       w.workout_id,
       w.workout_date,
       w.split,
       e.exercise_id,
       e.name         AS exercise,
       e.muscle_group,
       s.set_number,
       s.weight_lb,
       s.reps,
       s.weight_lb * s.reps        AS volume_lb,
       s.to_failure,
       s.unverified_block
FROM   sets s
JOIN   workouts  w USING (workout_id)
JOIN   exercises e USING (exercise_id)
WHERE  NOT s.is_warmup
  AND  NOT s.is_cardio
  AND  s.weight_lb IS NOT NULL
  AND  s.reps      IS NOT NULL
  AND  s.orig_unit <> 'bw'
  AND  s.set_id NOT IN (SELECT set_id FROM suspect_sets);

-- How much of the log survives that filter
SELECT (SELECT COUNT(*) FROM sets)          AS all_sets,
       (SELECT COUNT(*) FROM working_sets)  AS analysable_sets,
       (SELECT COUNT(*) FROM suspect_sets)  AS suspect_sets;


-- ------------------------------------------------------------
-- 5. Gaps in training
--
-- LAG reads the previous workout date within the ordered list, so the
-- difference between the two is the rest gap.
-- ------------------------------------------------------------
SELECT workout_date,
       LAG(workout_date) OVER (ORDER BY workout_date)              AS previous_workout,
       workout_date - LAG(workout_date) OVER (ORDER BY workout_date) AS days_off
FROM   (SELECT DISTINCT workout_date FROM workouts) d
ORDER  BY days_off DESC NULLS LAST
LIMIT  10;
