-- ============================================================
-- Strength Training Database — analysis
--
-- Every query here reads from working_sets, the filtered view defined
-- in 03_quality_checks.sql. Run that file first.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Weekly training volume by muscle group
--
-- Volume is weight x reps summed over the week. date_trunc collapses
-- each date to the Monday of its week.
-- ------------------------------------------------------------
SELECT date_trunc('week', workout_date)::DATE AS week,
       muscle_group,
       COUNT(*)                               AS sets,
       SUM(volume_lb)                         AS volume_lb
FROM   working_sets
WHERE  muscle_group IS NOT NULL
GROUP  BY 1, 2
ORDER  BY 1 DESC, volume_lb DESC;


-- ------------------------------------------------------------
-- 2. Top set per exercise per month
--
-- The heaviest single set worked in each month, for movements trained
-- often enough for the trend to mean anything.
-- ------------------------------------------------------------
SELECT date_trunc('month', workout_date)::DATE AS month,
       exercise,
       MAX(weight_lb)                          AS top_weight_lb,
       COUNT(*)                                AS sets
FROM   working_sets
WHERE  exercise IN (
         SELECT exercise
         FROM   working_sets
         GROUP  BY exercise
         HAVING COUNT(*) >= 30
       )
GROUP  BY 1, 2
ORDER  BY exercise, month;


-- ------------------------------------------------------------
-- 3. Month-over-month change on the main lifts
--
-- LAG pulls the previous month's top set into the same row so the two
-- can be subtracted. PARTITION BY restarts that per exercise.
-- ------------------------------------------------------------
WITH monthly AS (
  SELECT date_trunc('month', workout_date)::DATE AS month,
         exercise,
         MAX(weight_lb) AS top_weight_lb
  FROM   working_sets
  WHERE  exercise IN ('Flat Barbell Bench Press',
                      'Incline Barbell Bench Press',
                      'Barbell Back Squat',
                      'Romanian Deadlift')
  GROUP  BY 1, 2
)
SELECT month,
       exercise,
       top_weight_lb,
       LAG(top_weight_lb) OVER (PARTITION BY exercise ORDER BY month) AS previous_month,
       top_weight_lb
         - LAG(top_weight_lb) OVER (PARTITION BY exercise ORDER BY month) AS change_lb
FROM   monthly
ORDER  BY exercise, month;


-- ------------------------------------------------------------
-- 4. Estimated one-rep max over time
--
-- Epley: 1RM ~= weight x (1 + reps / 30). Reasonable under about 10
-- reps and increasingly optimistic above that, which is why sets over
-- 12 reps are left out.
-- ------------------------------------------------------------
SELECT exercise,
       workout_date,
       ROUND(MAX(weight_lb * (1 + reps / 30.0)), 1) AS est_1rm_lb
FROM   working_sets
WHERE  reps BETWEEN 1 AND 12
  AND  exercise IN ('Flat Barbell Bench Press', 'Incline Barbell Bench Press')
GROUP  BY exercise, workout_date
ORDER  BY exercise, workout_date;


-- ------------------------------------------------------------
-- 5. Training frequency by split
-- ------------------------------------------------------------
SELECT date_trunc('month', workout_date)::DATE AS month,
       split,
       COUNT(*)                                AS sessions
FROM   workouts
WHERE  split IS NOT NULL
  AND  split <> 'Rest'
GROUP  BY 1, 2
ORDER  BY 1, sessions DESC;


-- ------------------------------------------------------------
-- 6. Most trained movements
-- ------------------------------------------------------------
SELECT exercise,
       muscle_group,
       COUNT(*)                          AS sets,
       COUNT(DISTINCT workout_id)        AS sessions,
       ROUND(AVG(weight_lb), 1)          AS avg_weight_lb,
       MAX(weight_lb)                    AS best_weight_lb,
       SUM(volume_lb)                    AS total_volume_lb
FROM   working_sets
GROUP  BY exercise, muscle_group
HAVING COUNT(*) >= 20
ORDER  BY total_volume_lb DESC
LIMIT  25;


-- ------------------------------------------------------------
-- 7. Personal record per exercise, with the date it happened
--
-- DISTINCT ON keeps the first row of each exercise group after the
-- ORDER BY, which makes it the heaviest set.
-- ------------------------------------------------------------
SELECT DISTINCT ON (exercise)
       exercise,
       muscle_group,
       weight_lb AS pr_weight_lb,
       reps,
       workout_date AS set_on
FROM   working_sets
ORDER  BY exercise, weight_lb DESC, reps DESC, workout_date;


-- ------------------------------------------------------------
-- 8. Sets taken to failure, by muscle group
-- ------------------------------------------------------------
SELECT muscle_group,
       COUNT(*)                                     AS sets,
       COUNT(*) FILTER (WHERE to_failure)           AS to_failure,
       ROUND(100.0 * COUNT(*) FILTER (WHERE to_failure) / COUNT(*), 1) AS pct_to_failure
FROM   working_sets
WHERE  muscle_group IS NOT NULL
GROUP  BY muscle_group
ORDER  BY pct_to_failure DESC;
