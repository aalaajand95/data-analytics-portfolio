# Medical Appointment No-Shows — SQL Analysis

**Status: 🚧 In progress**

A SQL-first portfolio project analyzing ~110K medical appointments from public clinics in Vitória, Brazil (April–June 2016), to answer one business question:

> **Why do ~20% of patients miss their scheduled medical appointments, and what factors predict a no-show?**

Missed appointments waste clinical capacity and delay care. If we can identify which appointments are at risk, clinics can target reminders, adjust overbooking, and reduce wasted slots.

**Dataset:** [Medical Appointment No Shows (Kaggle)](https://www.kaggle.com/datasets/joniarroba/noshowappointments) — 110,527 rows, 14 columns, one row per appointment.

## Why this project is SQL-focused

The entire pipeline — loading, quality checks, cleaning, transformation, and analysis — is done in SQL (SQLite). Python/Tableau are only used at the end for presentation. The project demonstrates:

- **DDL & data loading** — staging vs. analysis tables, appropriate types
- **Data profiling in SQL** — duplicates, invalid values, logical contradictions
- **Cleaning & transformation** — `CASE`, date functions, derived columns, renamed misspelled fields
- **Analysis** — `GROUP BY`, conditional aggregation, CTEs
- **Advanced SQL** — window functions over patient history (does a past no-show predict the next one?)

## Data dictionary (raw)

| Column | Description | Known issues |
|---|---|---|
| `PatientId` | Patient identifier (62,299 unique patients → repeat visits) | Stored as a huge number |
| `AppointmentID` | Unique appointment identifier | — |
| `Gender` | F / M | — |
| `ScheduledDay` | Timestamp the appointment was booked | 5 rows are *after* the appointment day |
| `AppointmentDay` | Date of the appointment (time is always 00:00) | — |
| `Age` | Patient age | One row = -1; a few > 100 |
| `Neighbourhood` | Clinic neighbourhood (81 unique) | — |
| `Scholarship` | 1 = enrolled in Bolsa Família welfare program | — |
| `Hipertension` | 1 = has hypertension | Misspelled |
| `Diabetes` | 1 = has diabetes | — |
| `Alcoholism` | 1 = alcoholism | — |
| `Handcap` | Disability indicator | Misspelled; values 0–4, not 0/1 |
| `SMS_received` | 1 = reminder SMS sent | Only sent for appointments booked in advance |
| `No-show` | **"Yes" = patient missed the appointment** (confusing polarity!) | Hyphen in name; inverted-sounding values |

## Project roadmap

| Step | Deliverable | Status |
|---|---|---|
| 1. Load raw data into SQLite staging table | [`sql/01_load_raw_data.sql`](sql/01_load_raw_data.sql) | ✅ |
| 2. Profile data quality in SQL | [`sql/02_data_profiling.sql`](sql/02_data_profiling.sql) | ✅ |
| 3. Clean & transform into an analysis table | [`sql/03_clean_transform.sql`](sql/03_clean_transform.sql) | ✅ |
| 4. Core analysis: who no-shows and why | [`sql/04_analysis_no_show_drivers.sql`](sql/04_analysis_no_show_drivers.sql) | ⬜ |
| 5. Advanced: patient history with window functions | [`sql/05_patient_history_window_functions.sql`](sql/05_patient_history_window_functions.sql) | ⬜ |
| 6. Findings write-up with recommendations | `report/findings.md` | ⬜ |
| 7. (Optional) Tableau dashboard of key metrics | `tableau/` | ⬜ |

## How to run

Requires only `sqlite3` (pre-installed on macOS/Linux):

```bash
cd medical-appointment-no-shows-sql

# Step 1 — create the database and load the CSV
sqlite3 appointments.db < sql/01_load_raw_data.sql

# Step 2 — run the profiling queries
sqlite3 appointments.db < sql/02_data_profiling.sql

# Step 3 — build the clean `appointments` analysis table
sqlite3 appointments.db < sql/03_clean_transform.sql
```

The generated `appointments.db` is disposable and not committed — the SQL scripts are the source of truth.

## Key analysis questions

1. What is the overall no-show rate? (Baseline: ~20.2%)
2. How does no-show rate vary by **age band**, **gender**, and **neighbourhood**?
3. Does **booking lead time** (days between scheduling and appointment) drive no-shows? 35% of appointments are booked same-day — do those ever no-show?
4. The **SMS paradox**: patients who received an SMS reminder no-show *more*. Why? (Hint: SMS is only sent when there's lead time — a confounder worth untangling in SQL.)
5. Do **welfare enrollment** (Scholarship) or **chronic conditions** correlate with attendance?
6. Does a patient's **past no-show history** predict their next appointment? (Window functions over 62K repeat patients.)
7. Which **day of week** has the worst attendance?
