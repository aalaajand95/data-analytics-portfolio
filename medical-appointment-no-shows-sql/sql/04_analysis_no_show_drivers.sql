-- ============================================================
-- Step 4: Core analysis — who no-shows and why
-- Run: sqlite3 appointments.db < sql/04_analysis_no_show_drivers.sql
-- (Requires the `appointments` table built in Step 3.)
-- ============================================================
-- Each query answers one business question. The finding observed in
-- the data is noted in a comment beneath it and carried into
-- report/findings.md. no_show = 1 means the patient MISSED, so
-- ROUND(100.0 * AVG(no_show), 1) is the no-show rate as a percent.
-- ============================================================
.mode column
.headers on

-- ------------------------------------------------------------
-- Q1. Overall no-show rate (the baseline every cut compares to)
-- ------------------------------------------------------------
SELECT
    COUNT(*)                         AS appointments,
    SUM(no_show)                     AS missed,
    ROUND(100.0 * AVG(no_show), 1)   AS no_show_rate_pct
FROM appointments;
-- FINDING: 110,521 appointments, 20.2% missed. This is the baseline.

-- ------------------------------------------------------------
-- Q2. No-show rate by gender
-- ------------------------------------------------------------
SELECT
    gender,
    COUNT(*)                         AS appointments,
    ROUND(100.0 * AVG(no_show), 1)   AS no_show_rate_pct
FROM appointments
GROUP BY gender
ORDER BY no_show_rate_pct DESC;
-- FINDING: Women book ~65% of appointments but attend at the same rate
-- as men (both ~20%). Gender is NOT a driver of no-shows.

-- ------------------------------------------------------------
-- Q3. No-show rate by age band
-- ------------------------------------------------------------
SELECT
    age_band,
    COUNT(*)                         AS appointments,
    ROUND(100.0 * AVG(no_show), 1)   AS no_show_rate_pct
FROM appointments
GROUP BY age_band
ORDER BY age_band;
-- FINDING: Clear age gradient. Teens/young adults (12-34) miss the most
-- (~23-26%); older patients (65+) are the most reliable (~15%).
-- Age IS a driver.

-- ------------------------------------------------------------
-- Q4. No-show rate by booking lead time  (the strongest driver)
-- ------------------------------------------------------------
SELECT
    lead_time_bucket,
    COUNT(*)                         AS appointments,
    ROUND(100.0 * AVG(no_show), 1)   AS no_show_rate_pct
FROM appointments
GROUP BY lead_time_bucket
ORDER BY lead_time_bucket;
-- FINDING: The single biggest signal. Same-day bookings almost always
-- show up (~4.6% miss). Risk climbs steeply with wait: 31+ days out,
-- ~1 in 3 appointments is missed. Lead time is the headline driver.

-- ------------------------------------------------------------
-- Q5. The SMS paradox
--   5a. Raw comparison — looks like SMS makes no-shows WORSE.
--   5b. Fair comparison — restrict to advance bookings only, so
--       same-day appointments (which never get an SMS) don't skew it.
-- ------------------------------------------------------------
-- 5a: raw, misleading
SELECT
    sms_received,
    COUNT(*)                         AS appointments,
    ROUND(100.0 * AVG(no_show), 1)   AS no_show_rate_pct
FROM appointments
GROUP BY sms_received;
-- FINDING (5a): Patients who got an SMS miss MORE (~27.6%) than those who
-- didn't (~16.7%). Taken alone this suggests reminders backfire.

-- 5b: like-for-like, advance bookings only (lead_time_days > 0)
SELECT
    sms_received,
    COUNT(*)                         AS appointments,
    ROUND(100.0 * AVG(no_show), 1)   AS no_show_rate_pct
FROM appointments
WHERE lead_time_days > 0
GROUP BY sms_received;
-- FINDING (5b): Once we remove same-day appointments (which are ~95%
-- reliable and never receive an SMS), the paradox REVERSES: among
-- advance bookings, patients who got an SMS miss slightly LESS (27.6%)
-- than those who didn't (29.4%). The raw "SMS backfires" result in 5a
-- was entirely a lead-time confound -- same-day, no-SMS appointments
-- dragged the no-SMS group's rate down. Compared like-for-like,
-- reminders help. This is the analytical centerpiece of the project.

-- ------------------------------------------------------------
-- Q6. Welfare enrollment and chronic conditions
-- ------------------------------------------------------------
SELECT 'scholarship'  AS factor, scholarship  AS has_flag, COUNT(*) AS appointments,
       ROUND(100.0 * AVG(no_show), 1) AS no_show_rate_pct
FROM appointments GROUP BY scholarship
UNION ALL
SELECT 'hypertension', hypertension, COUNT(*), ROUND(100.0 * AVG(no_show), 1)
FROM appointments GROUP BY hypertension
UNION ALL
SELECT 'diabetes', diabetes, COUNT(*), ROUND(100.0 * AVG(no_show), 1)
FROM appointments GROUP BY diabetes
UNION ALL
SELECT 'alcoholism', alcoholism, COUNT(*), ROUND(100.0 * AVG(no_show), 1)
FROM appointments GROUP BY alcoholism
UNION ALL
SELECT 'has_disability', has_disability, COUNT(*), ROUND(100.0 * AVG(no_show), 1)
FROM appointments GROUP BY has_disability;
-- FINDING: Bolsa Familia (Scholarship) patients miss slightly MORE
-- (~23.7% vs 19.8%). Patients with chronic conditions (hypertension,
-- diabetes) miss slightly LESS -- these skew older, tying back to Q3.
-- All effects are small compared with lead time.

-- ------------------------------------------------------------
-- Q7. Day of week
-- ------------------------------------------------------------
SELECT
    appointment_dow,
    appointment_dow_name,
    COUNT(*)                         AS appointments,
    ROUND(100.0 * AVG(no_show), 1)   AS no_show_rate_pct
FROM appointments
GROUP BY appointment_dow, appointment_dow_name
ORDER BY appointment_dow;
-- FINDING: Weekdays are flat (~20%). Saturday has very few appointments
-- and a slightly higher miss rate; there are no Sunday appointments.
-- Day of week is not a meaningful driver here.

-- ------------------------------------------------------------
-- Q8. Neighbourhoods ranked by no-show rate
--   CTE aggregates per neighbourhood; a minimum-volume filter keeps
--   tiny clinics from topping the list on a handful of appointments;
--   RANK() window functions label the worst and best.
-- ------------------------------------------------------------
WITH by_neighbourhood AS (
    SELECT
        neighbourhood,
        COUNT(*)                         AS appointments,
        ROUND(100.0 * AVG(no_show), 1)   AS no_show_rate_pct
    FROM appointments
    GROUP BY neighbourhood
    HAVING COUNT(*) >= 500                       -- ignore low-volume clinics
),
ranked AS (
    SELECT *,
        RANK() OVER (ORDER BY no_show_rate_pct DESC) AS worst_rank,
        RANK() OVER (ORDER BY no_show_rate_pct ASC)  AS best_rank
    FROM by_neighbourhood
)
SELECT worst_rank, neighbourhood, appointments, no_show_rate_pct
FROM ranked
WHERE worst_rank <= 5 OR best_rank <= 5
ORDER BY no_show_rate_pct DESC;
-- FINDING: Among clinics with >=500 appointments, no-show rates range
-- from ~16% to ~28%. Location matters, but the spread is far narrower
-- than the lead-time spread -- reinforcing that WHEN a patient books
-- matters more than WHERE.
