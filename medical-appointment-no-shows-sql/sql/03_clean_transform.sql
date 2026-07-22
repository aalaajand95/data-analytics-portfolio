-- ============================================================
-- Step 3: Clean & transform
-- Build the analysis table `appointments` from raw_appointments.
-- Run: sqlite3 appointments.db < sql/03_clean_transform.sql
-- ============================================================
-- Cleaning rules (all decided from Step 2 profiling):
--   1. Drop the row with Age = -1 (impossible value).
--   2. Drop the 5 rows where the appointment was "scheduled" after it
--      happened (date(ScheduledDay) > date(AppointmentDay)).
--   3. Rename the source-misspelled / awkward columns to clean names.
--   4. Flip the confusing target: no_show = 1 when the patient MISSED
--      ('Yes'), 0 when they attended ('No'). Now AVG(no_show) reads
--      directly as a no-show rate.
--   5. Cast everything to its proper type (INTEGER flags, real dates).
--
-- Derived columns:
--   * scheduled_date / appointment_date : ISO dates
--   * lead_time_days : whole days between booking and appointment
--   * appointment_dow / appointment_dow_name : day of week
--   * age_band : readable age buckets
--   * has_disability : Handcap collapsed from 0-4 to a 0/1 flag
--   * lead_time_bucket : same day / 1-3 / 4-7 / 8-14 / 15-30 / 31+
-- ============================================================

DROP TABLE IF EXISTS appointments;

CREATE TABLE appointments AS
SELECT
    -- ---- identifiers -------------------------------------------------
    CAST(PatientId AS INTEGER)          AS patient_id,
    CAST(AppointmentID AS INTEGER)      AS appointment_id,

    -- ---- demographics ------------------------------------------------
    Gender                              AS gender,
    CAST(Age AS INTEGER)                AS age,
    CASE
        WHEN CAST(Age AS INTEGER) < 12 THEN '00-11'
        WHEN CAST(Age AS INTEGER) < 18 THEN '12-17'
        WHEN CAST(Age AS INTEGER) < 35 THEN '18-34'
        WHEN CAST(Age AS INTEGER) < 50 THEN '35-49'
        WHEN CAST(Age AS INTEGER) < 65 THEN '50-64'
        ELSE '65+'
    END                                 AS age_band,
    Neighbourhood                       AS neighbourhood,

    -- ---- dates & lead time ------------------------------------------
    date(ScheduledDay)                  AS scheduled_date,
    date(AppointmentDay)                AS appointment_date,
    CAST(julianday(date(AppointmentDay)) - julianday(date(ScheduledDay)) AS INTEGER)
                                        AS lead_time_days,
    CASE CAST(strftime('%w', date(AppointmentDay)) AS INTEGER)
        WHEN 0 THEN 'Sunday'    WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'   WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'  WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END                                 AS appointment_dow_name,
    CAST(strftime('%w', date(AppointmentDay)) AS INTEGER)
                                        AS appointment_dow,
    CASE
        WHEN julianday(date(AppointmentDay)) - julianday(date(ScheduledDay)) = 0  THEN '0  same day'
        WHEN julianday(date(AppointmentDay)) - julianday(date(ScheduledDay)) <= 3 THEN '1  1-3 days'
        WHEN julianday(date(AppointmentDay)) - julianday(date(ScheduledDay)) <= 7 THEN '2  4-7 days'
        WHEN julianday(date(AppointmentDay)) - julianday(date(ScheduledDay)) <= 14 THEN '3  8-14 days'
        WHEN julianday(date(AppointmentDay)) - julianday(date(ScheduledDay)) <= 30 THEN '4  15-30 days'
        ELSE '5  31+ days'
    END                                 AS lead_time_bucket,

    -- ---- welfare & health flags -------------------------------------
    CAST(Scholarship AS INTEGER)        AS scholarship,
    CAST(Hipertension AS INTEGER)       AS hypertension,   -- fixed spelling
    CAST(Diabetes AS INTEGER)           AS diabetes,
    CAST(Alcoholism AS INTEGER)         AS alcoholism,
    CAST(Handcap AS INTEGER)            AS disability_count,
    CASE WHEN CAST(Handcap AS INTEGER) > 0 THEN 1 ELSE 0 END
                                        AS has_disability,
    CAST(SMS_received AS INTEGER)       AS sms_received,

    -- ---- target ------------------------------------------------------
    CASE WHEN No_show = 'Yes' THEN 1 ELSE 0 END
                                        AS no_show          -- 1 = missed
FROM raw_appointments
WHERE CAST(Age AS INTEGER) >= 0                             -- rule 1
  AND date(ScheduledDay) <= date(AppointmentDay);          -- rule 2

-- ---- verification ---------------------------------------------------
.mode column
.headers on

-- Expect 110,521 rows (110,527 raw minus 1 bad age minus 5 bad dates).
SELECT 'rows_after_cleaning' AS check_name, COUNT(*) AS value FROM appointments
UNION ALL
SELECT 'rows_dropped', (SELECT COUNT(*) FROM raw_appointments) - COUNT(*) FROM appointments
UNION ALL
SELECT 'negative_ages_remaining', COUNT(*) FROM appointments WHERE age < 0
UNION ALL
SELECT 'bad_date_rows_remaining', COUNT(*) FROM appointments WHERE lead_time_days < 0
UNION ALL
SELECT 'no_show_missed', COUNT(*) FROM appointments WHERE no_show = 1;

-- Peek: does the clean target still match the raw 20.2% no-show rate?
SELECT ROUND(100.0 * AVG(no_show), 1) AS no_show_rate_pct FROM appointments;

-- Peek at 5 fully transformed rows.
SELECT patient_id, age, age_band, appointment_date, appointment_dow_name,
       lead_time_days, lead_time_bucket, has_disability, sms_received, no_show
FROM appointments
LIMIT 5;
