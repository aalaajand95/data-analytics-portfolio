-- ============================================================
-- Step 6b: Export a clean, Tableau-ready extract
-- Run: sqlite3 appointments.db < sql/06_export_for_tableau.sql
-- (Requires the `appointments` table built in Step 3.)
-- Produces: tableau/appointments_clean.csv
-- ============================================================
-- We feed Tableau the ROW-LEVEL clean table (not pre-aggregated
-- summaries) so every chart can be built from one source and the
-- no-show RATE can be computed in Tableau as AVG([no_show]) * 100.
--
-- We also attach each appointment's prior_no_shows (the window-function
-- column from Step 5) so the "history risk curve" chart is possible
-- without re-deriving it inside Tableau.
-- ============================================================

DROP TABLE IF EXISTS appt_tableau;

CREATE TABLE appt_tableau AS
SELECT
    *,
    COALESCE(
        SUM(no_show) OVER (
            PARTITION BY patient_id
            ORDER BY scheduled_date, appointment_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), 0) AS prior_no_shows
FROM appointments;

-- Write the extract to CSV
.headers on
.mode csv
.output tableau/appointments_clean.csv
SELECT * FROM appt_tableau;
.output stdout

-- Confirm (expect 110,521)
SELECT 'exported_rows' AS check_name, COUNT(*) AS value FROM appt_tableau;
