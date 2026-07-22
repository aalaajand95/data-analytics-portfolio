-- ============================================================
-- Step 2: Data profiling — interrogate the raw data before
-- trusting it. Every issue found here gets a cleaning rule
-- in Step 3.
-- Run: sqlite3 appointments.db < sql/02_data_profiling.sql
-- ============================================================
.mode column
.headers on

-- 2.1 Row count and uniqueness: is AppointmentID a valid primary key?
SELECT
    COUNT(*)                        AS total_rows,
    COUNT(DISTINCT AppointmentID)   AS unique_appointments,
    COUNT(DISTINCT PatientId)       AS unique_patients
FROM raw_appointments;
-- Expect: 110,527 rows = 110,527 unique appointments (no duplicates),
-- but only ~62,299 patients -> many patients have repeat visits.

-- 2.2 Target variable: what values does No_show take, and how often?
SELECT No_show, COUNT(*) AS n,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM raw_appointments), 1) AS pct
FROM raw_appointments
GROUP BY No_show;
-- Watch the polarity: 'Yes' means the patient MISSED the appointment.

-- 2.3 Age: out-of-range values
SELECT MIN(CAST(Age AS INTEGER)) AS min_age,
       MAX(CAST(Age AS INTEGER)) AS max_age,
       SUM(CAST(Age AS INTEGER) < 0)   AS negative_ages,
       SUM(CAST(Age AS INTEGER) > 100) AS over_100
FROM raw_appointments;
-- Expect: one Age = -1 (impossible -> drop), 7 rows over 100 (plausible -> keep).

-- 2.4 Binary flags: are they really 0/1?
SELECT Handcap, COUNT(*) AS n
FROM raw_appointments
GROUP BY Handcap
ORDER BY CAST(Handcap AS INTEGER);
-- Expect: Handcap has values 0-4 (count of disabilities, not a flag).
-- Decision for Step 3: collapse to has_disability = (Handcap > 0).

-- 2.5 Date logic: was any appointment scheduled AFTER it happened?
SELECT COUNT(*) AS scheduled_after_appointment
FROM raw_appointments
WHERE date(ScheduledDay) > date(AppointmentDay);
-- Expect: 5 impossible rows -> drop in Step 3.

-- 2.6 Lead time distribution preview: how common are same-day bookings?
SELECT
    SUM(date(ScheduledDay) = date(AppointmentDay)) AS same_day,
    ROUND(100.0 * SUM(date(ScheduledDay) = date(AppointmentDay)) / COUNT(*), 1) AS same_day_pct
FROM raw_appointments;
-- Expect: ~35% of appointments are booked the same day.

-- 2.7 Date coverage of the dataset
SELECT MIN(date(AppointmentDay)) AS first_appointment,
       MAX(date(AppointmentDay)) AS last_appointment
FROM raw_appointments;
-- Expect: 2016-04-29 to 2016-06-08 (~6 weeks).

-- 2.8 Categorical sanity: Gender values and neighbourhood count
SELECT Gender, COUNT(*) AS n FROM raw_appointments GROUP BY Gender;
SELECT COUNT(DISTINCT Neighbourhood) AS neighbourhoods FROM raw_appointments;

-- 2.9 SMS vs lead time: first look at the confounder for the "SMS paradox"
SELECT SMS_received,
       SUM(date(ScheduledDay) = date(AppointmentDay)) AS same_day_bookings,
       COUNT(*) AS n
FROM raw_appointments
GROUP BY SMS_received;
-- Expect: SMS is (almost) never sent for same-day bookings. This matters
-- when interpreting SMS effectiveness in Step 4.
