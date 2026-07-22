/* ============================================================================
   Hospital Readmission Prediction — cleaning & feature engineering (DuckDB)
   Input : data/diabetic_data.csv   (101,766 raw encounters, '?' = missing)
   Output: data/analytic_table.csv  (one row per patient, model-ready)

   Decisions encoded here (all documented in README):
     - Target binarized: readmitted = '<30'  -> 1, else 0  (only <30 is CMS-penalized)
     - Exclude death/hospice dispositions (11,13,14,19,20,21): cannot be readmitted
     - Exclude gender = 'Unknown/Invalid' (3 rows)
     - Keep each patient's FIRST encounter only (min encounter_id): no leakage
     - Drop weight (96.9% ?), medical_specialty (49.1% ?), payer_code (39.6% ?)
     - '?' -> 'Unknown' for race; A1C/glucose 'not measured' becomes a signal, not imputed
   ============================================================================ */

CREATE OR REPLACE TABLE raw AS
SELECT * FROM read_csv_auto('../data/diabetic_data.csv', header=true, all_varchar=true);

-- Step 1: row-level exclusions (death/hospice, invalid gender) applied BEFORE
--         first-encounter selection, so we never pick an invalid encounter.
CREATE OR REPLACE TABLE eligible AS
SELECT *
FROM raw
WHERE discharge_disposition_id NOT IN ('11','13','14','19','20','21')  -- death / hospice
  AND gender <> 'Unknown/Invalid';

-- Step 2: keep each patient's earliest encounter (encounter_id is assigned
--         sequentially, so min(encounter_id) is the first chronological visit).
CREATE OR REPLACE TABLE first_enc AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY patient_nbr ORDER BY CAST(encounter_id AS BIGINT)) AS rn
    FROM eligible
)
WHERE rn = 1;

-- Step 3: build the analytic table with engineered features.
CREATE OR REPLACE TABLE analytic AS
SELECT
    CAST(encounter_id AS BIGINT)                          AS encounter_id,
    CAST(patient_nbr  AS BIGINT)                          AS patient_nbr,

    /* ---- TARGET ---- */
    CASE WHEN readmitted = '<30' THEN 1 ELSE 0 END        AS readmitted_30,

    /* ---- DEMOGRAPHICS ---- */
    CASE WHEN race = '?' THEN 'Unknown' ELSE race END     AS race,
    gender,
    age                                                   AS age_band,
    -- ordered 1..10 so logistic regression can use age as a single monotonic term
    (CAST(REGEXP_EXTRACT(age, '\d+') AS INT) / 10) + 1    AS age_ordinal,

    /* ---- PRIOR UTILIZATION (preceding year) — expected strongest predictors ---- */
    CAST(number_outpatient AS INT)                        AS number_outpatient,
    CAST(number_emergency  AS INT)                        AS number_emergency,
    CAST(number_inpatient  AS INT)                        AS number_inpatient,

    /* ---- CURRENT ENCOUNTER COMPLEXITY ---- */
    CAST(time_in_hospital   AS INT)                       AS time_in_hospital,
    CAST(num_lab_procedures AS INT)                       AS num_lab_procedures,
    CAST(num_procedures     AS INT)                       AS num_procedures,
    CAST(num_medications    AS INT)                       AS num_medications,
    CAST(number_diagnoses   AS INT)                       AS number_diagnoses,

    /* ---- CLINICAL SIGNALS ---- */
    -- "was the test performed" is the signal (A1C is 83% not-measured), not the value
    CASE WHEN A1Cresult    <> 'None' AND A1Cresult    IS NOT NULL THEN 1 ELSE 0 END AS a1c_tested,
    CASE WHEN max_glu_serum<> 'None' AND max_glu_serum IS NOT NULL THEN 1 ELSE 0 END AS glucose_tested,
    CASE WHEN change     = 'Ch'  THEN 1 ELSE 0 END        AS med_changed,
    CASE WHEN diabetesMed = 'Yes' THEN 1 ELSE 0 END       AS on_diabetes_med,
    CASE WHEN insulin <> 'No' THEN 1 ELSE 0 END           AS on_insulin,

    /* ---- PRIMARY DIAGNOSIS grouped from ICD-9 (Strack et al. 2014 buckets) ---- */
    CASE
        WHEN diag_1 = '?'                                    THEN 'Missing'
        WHEN diag_1 LIKE 'E%' OR diag_1 LIKE 'V%'            THEN 'Other'
        WHEN diag_1 LIKE '250%'                              THEN 'Diabetes'
        WHEN TRY_CAST(diag_1 AS DOUBLE) BETWEEN 390 AND 459
             OR TRY_CAST(diag_1 AS DOUBLE) = 785            THEN 'Circulatory'
        WHEN TRY_CAST(diag_1 AS DOUBLE) BETWEEN 460 AND 519
             OR TRY_CAST(diag_1 AS DOUBLE) = 786            THEN 'Respiratory'
        WHEN TRY_CAST(diag_1 AS DOUBLE) BETWEEN 520 AND 579
             OR TRY_CAST(diag_1 AS DOUBLE) = 787            THEN 'Digestive'
        WHEN TRY_CAST(diag_1 AS DOUBLE) BETWEEN 800 AND 999 THEN 'Injury'
        WHEN TRY_CAST(diag_1 AS DOUBLE) BETWEEN 710 AND 739 THEN 'Musculoskeletal'
        WHEN TRY_CAST(diag_1 AS DOUBLE) BETWEEN 580 AND 629
             OR TRY_CAST(diag_1 AS DOUBLE) = 788            THEN 'Genitourinary'
        WHEN TRY_CAST(diag_1 AS DOUBLE) BETWEEN 140 AND 239 THEN 'Neoplasms'
        ELSE 'Other'
    END                                                   AS diag1_group,

    /* ---- DISCHARGE DISPOSITION grouped (home vs onward transfer) ---- */
    CASE WHEN discharge_disposition_id IN ('1','6','8') THEN 'Home'
         ELSE 'Transferred/Other' END                     AS discharge_group,

    /* ---- ADMISSION TYPE grouped (rare codes 4/5/6/7/8 -> Other to avoid
            perfect separation in the logistic fit) ---- */
    CASE admission_type_id
         WHEN '1' THEN 'Emergency'
         WHEN '2' THEN 'Urgent'
         WHEN '3' THEN 'Elective'
         ELSE 'Other' END                                 AS admission_type_grp

FROM first_enc;

COPY analytic TO '../data/analytic_table.csv' (HEADER, DELIMITER ',');

-- Reconciliation report (printed by the runner)
SELECT
    (SELECT COUNT(*) FROM raw)                                   AS raw_rows,
    (SELECT COUNT(*) FROM eligible)                              AS after_exclusions,
    (SELECT COUNT(*) FROM first_enc)                             AS after_first_encounter,
    (SELECT COUNT(*) FROM analytic)                              AS analytic_rows,
    (SELECT ROUND(AVG(readmitted_30)*100, 2) FROM analytic)      AS readmit30_pct;
