-- ============================================================
-- Step 5: Patient-history analysis with window functions
-- Run: sqlite3 appointments.db < sql/05_patient_history_window_functions.sql
-- (Requires the `appointments` table built in Step 3.)
-- ============================================================
-- 62,299 unique patients across 110K appointments means many patients
-- appear more than once. That lets us study behaviour OVER TIME -- the
-- most advanced SQL in this project. We order each patient's history by
-- scheduled_date and use window frames to look at what came *before*
-- each appointment.
--
-- IMPORTANT ordering note: AppointmentDay has no time component, so we
-- order a patient's timeline by scheduled_date (when they booked) and
-- break ties with appointment_id for a stable, deterministic sequence.
-- ============================================================
.mode column
.headers on

-- ------------------------------------------------------------
-- Q1. Visit frequency: how many appointments do patients have?
--   Bucket patients by their total appointment count.
-- ------------------------------------------------------------
WITH per_patient AS (
    SELECT patient_id, COUNT(*) AS visits
    FROM appointments
    GROUP BY patient_id
)
SELECT
    CASE
        WHEN visits = 1 THEN '1 (one-time)'
        WHEN visits BETWEEN 2 AND 3 THEN '2-3'
        WHEN visits BETWEEN 4 AND 6 THEN '4-6'
        ELSE '7+'
    END                                      AS visit_group,
    COUNT(*)                                 AS patients,
    SUM(visits)                              AS appointments
FROM per_patient
GROUP BY visit_group
ORDER BY MIN(visits);
-- FINDING: ~61% of patients (37,920 of 62,298) are one-timers, but a
-- long tail of frequent visitors matters: 945 patients with 7+
-- appointments generate ~9,900 appointments between them. Repeat
-- patients are where history-based targeting (Q2) becomes possible.

-- ------------------------------------------------------------
-- Q2. Does history predict the future?
--   For each appointment, count the patient's PRIOR no-shows using a
--   window frame that excludes the current row (…AND 1 PRECEDING).
--   Then compare the no-show rate by how many times the patient has
--   missed BEFORE this appointment.
-- ------------------------------------------------------------
WITH history AS (
    SELECT
        no_show,
        SUM(no_show) OVER (
            PARTITION BY patient_id
            ORDER BY scheduled_date, appointment_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prior_no_shows
    FROM appointments
)
SELECT
    CASE
        WHEN prior_no_shows IS NULL OR prior_no_shows = 0 THEN '0 prior misses'
        WHEN prior_no_shows = 1 THEN '1 prior miss'
        WHEN prior_no_shows = 2 THEN '2 prior misses'
        ELSE '3+ prior misses'
    END                                      AS prior_history,
    COUNT(*)                                 AS appointments,
    ROUND(100.0 * AVG(no_show), 1)           AS no_show_rate_pct
FROM history
GROUP BY prior_history
ORDER BY MIN(COALESCE(prior_no_shows, 0));
-- FINDING: The single most actionable signal in the whole project.
-- Risk rises monotonically with past misses: 0 prior -> 19.0%,
-- 1 -> 25.1%, 2 -> 27.0%, 3+ -> 38.0%. A patient with three or more
-- prior no-shows is twice as likely to miss as a clean-history patient.
-- Past behaviour clearly predicts future behaviour, which points
-- straight at a targeting strategy.

-- ------------------------------------------------------------
-- Q3. First appointment vs. returning appointments
--   ROW_NUMBER() over each patient's timeline: is a patient more or
--   less reliable on their very first visit vs later ones?
-- ------------------------------------------------------------
WITH seq AS (
    SELECT
        no_show,
        ROW_NUMBER() OVER (
            PARTITION BY patient_id
            ORDER BY scheduled_date, appointment_id
        ) AS visit_number
    FROM appointments
)
SELECT
    CASE WHEN visit_number = 1 THEN 'first appointment'
         ELSE 'returning appointment' END    AS visit_type,
    COUNT(*)                                 AS appointments,
    ROUND(100.0 * AVG(no_show), 1)           AS no_show_rate_pct
FROM seq
GROUP BY visit_type
ORDER BY visit_type;
-- FINDING: First-ever appointments are missed MORE often than returning
-- ones. A patient who has already shown up once is more likely to keep
-- showing up -- new patients are the riskier cohort to remind.

-- ------------------------------------------------------------
-- Q4. Longest consecutive no-show streaks (gaps-and-islands)
--   The classic trick: subtract a ROW_NUMBER() ordered over ALL of a
--   patient's rows from a ROW_NUMBER() ordered over only their missed
--   rows. Within a run of consecutive misses that difference is
--   constant, so it identifies each streak; we count the longest.
-- ------------------------------------------------------------
WITH numbered AS (
    SELECT
        patient_id,
        no_show,
        ROW_NUMBER() OVER (PARTITION BY patient_id
                           ORDER BY scheduled_date, appointment_id) AS rn_all,
        ROW_NUMBER() OVER (PARTITION BY patient_id, no_show
                           ORDER BY scheduled_date, appointment_id) AS rn_flag
    FROM appointments
),
streaks AS (
    SELECT patient_id, (rn_all - rn_flag) AS grp, COUNT(*) AS streak_len
    FROM numbered
    WHERE no_show = 1                       -- islands of consecutive misses
    GROUP BY patient_id, grp
)
SELECT
    streak_len                               AS consecutive_misses,
    COUNT(*)                                 AS number_of_such_streaks
FROM streaks
GROUP BY streak_len
ORDER BY streak_len DESC;
-- FINDING: Most missed appointments are isolated, but a small group of
-- patients rack up long unbroken no-show streaks. These chronic
-- no-showers are prime candidates for a phone call rather than another
-- ignored SMS.
