# Strength Training Database

A PostgreSQL database built from 14 months of my own weightlifting log.

The log started as free text in a notes app — lines like
`Incline Bench WU/185x8/195x6` — written between sets on a phone, and
sometimes filled in days later from memory. This project turns that into
a normalized relational database, then queries it for training volume,
progression and consistency.

**2,799 parsed sets · 257 training days · 272 distinct movements ·
July 2025 to September 2026**

---

## Why this project

Portfolio datasets are usually clean because someone cleaned them
already. This one is not. It has missing weights, three impossible rep
counts, a warmup weight swallowed into an exercise name, two spellings
of the same status, and 163 sets written down after the fact rather
than during the session.

Handling that honestly is the point. Nothing here is silently dropped or
quietly averaged over. Bad rows are kept, flagged, and excluded by name
from the analysis views.

---

## Schema

```
exercises                    workouts
---------                    --------
exercise_id  PK              workout_id    PK
name         UNIQUE          workout_date
muscle_group                 split              Push / Pull / Legs / Upper / Lower / Arms
                             split_raw          exactly as written
                             status             Rest / Skip / Nothing
                             section
                             UNIQUE (workout_date, split_raw)
        \                       /
         \                     /
          \                   /
              sets
              ----
              set_id       PK
              workout_id   FK -> workouts
              exercise_id  FK -> exercises
              set_number, weight_lb, reps
              grip, attachment, orig_unit
              added_weight, to_failure, is_warmup, is_cardio
              self_flagged_uncertain, unverified_block
              source_line, raw_line
```

Third normal form. Every set carries `source_line` and `raw_line`, so
any row in the database can be traced back to the exact line of the
original notes it came from.

Two views sit on top:

| View | Purpose |
|---|---|
| `suspect_sets` | Rows that fail a plausibility check, with the reason |
| `working_sets` | The analysable subset — warmups, cardio, bodyweight and suspect rows removed |

---

## Running it

Requires PostgreSQL 15 or later. Tested on 18.

```sql
-- 1. create the database, then against it:
\i sql/01_schema.sql
```

Import `data/workout_sets.csv` into `staging_sets`. In DBeaver:
right-click `staging_sets` → Import Data → CSV → select the file →
Next through the wizard → Proceed. Or with psql:

```
\copy staging_sets FROM 'data/workout_sets.csv' WITH (FORMAT csv, HEADER true)
```

Use `\copy`, not `COPY`. Plain `COPY` runs as the server process and
cannot read a file in your own home folder.

```sql
-- 2. transform staging into the normalized tables
\i sql/02_load.sql     -- expect exercises 272, workouts 257, sets 2643

-- 3. build the views and review the quality report
\i sql/03_quality_checks.sql

-- 4. the analysis
\i sql/04_analysis.sql
```

---

## Files

| File | What it does |
|---|---|
| `sql/01_schema.sql` | Staging table, normalized tables, constraints, indexes |
| `sql/02_load.sql` | Transforms staging into `exercises`, `workouts`, `sets` |
| `sql/03_quality_checks.sql` | Integrity checks, completeness report, the two views |
| `sql/04_analysis.sql` | Eight analysis queries |
| `data/workout_sets.csv` | The parsed source data, 2,799 rows |

---

## What the data says

- 2,643 of 2,799 parsed rows are actual recorded sets. The other 156
  are rest days, skipped days and header lines, kept so gaps in
  training stay visible.
- 2,446 sets survive the filter into `working_sets`. The rest are
  warmups, cardio, bodyweight movements with no external load, or sets
  missing a weight or a rep count.
- 163 sets (6.2%) come from blocks of the notes written from memory
  rather than logged during the session. They are flagged
  `unverified_block` and can be excluded from any query.
- The most trained movement is the lat pulldown at 199 working sets.
  Flat barbell bench press is the most trained barbell lift at 78.

---

## Known limitations

- **Bodyweight movements have no load.** Pull-ups and dips store
  `weight_lb = 0` with `orig_unit = 'bw'`, so they contribute nothing to
  volume totals. Fixing that would mean tracking bodyweight over time,
  which was not logged consistently enough to use.
- **Three rep counts are impossible** and are excluded, not corrected:
  300x100, 235x60 and 100x100 are all stray zeros. The original text is
  kept in `raw_line` so the call can be checked.
- **Volume is weight x reps.** It ignores rest, tempo and proximity to
  failure, so it compares like with like over time but should not be
  read as a measure of training quality.
- **One exercise name is still dirty.** `Romanian Deadlift 135Wu` is a
  parse artifact covering 2 sets, surfaced by the check in
  `03_quality_checks.sql` and left visible rather than patched over.

---

## Built with

PostgreSQL 18 · DBeaver Community Edition
