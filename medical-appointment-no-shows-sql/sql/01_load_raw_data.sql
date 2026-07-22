-- ============================================================
-- Step 1: Load raw CSV into a staging table
-- Run: sqlite3 appointments.db < sql/01_load_raw_data.sql
-- ============================================================
-- Everything lands in a staging table as TEXT first. We never
-- trust raw data: typing, renaming, and cleaning happen in
-- Step 3, so the raw layer stays a faithful copy of the source.

DROP TABLE IF EXISTS raw_appointments;

CREATE TABLE raw_appointments (
    PatientId       TEXT,
    AppointmentID   TEXT,
    Gender          TEXT,
    ScheduledDay    TEXT,
    AppointmentDay  TEXT,
    Age             TEXT,
    Neighbourhood   TEXT,
    Scholarship     TEXT,
    Hipertension    TEXT,   -- source misspelling kept in raw layer
    Diabetes        TEXT,
    Alcoholism      TEXT,
    Handcap         TEXT,   -- source misspelling kept in raw layer
    SMS_received    TEXT,
    No_show         TEXT    -- "No-show" in the CSV header
);

-- Import the CSV, skipping the header row
.mode csv
.import --skip 1 data/KaggleV2May2016.csv raw_appointments

-- Sanity check: expect 110,527 rows
SELECT 'rows loaded' AS check_name, COUNT(*) AS value FROM raw_appointments;
