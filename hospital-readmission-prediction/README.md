# Hospital Readmission Prediction — Diabetic Inpatients

**Which discharged patients should get the limited follow-up slots?** A logistic
regression model that ranks diabetic inpatients by their risk of a 30-day
readmission, so a capacity-constrained care-management team can call the patients
most likely to come back.

> **Domain note:** this dataset was extracted from Cerner's *Health Facts* national
> clinical data warehouse. I spent six years at Cerner building clinical scheduling
> software that generated exactly this kind of encounter record — this project looks
> at that same data from the analytics side.

**Built with:** SQL (DuckDB) for cleaning & feature engineering → Python
(scikit-learn, statsmodels) for modeling → Power BI for the dashboard.

---

## The headline

- A model that predicts *"no readmission"* for everyone scores **91% accuracy** — and
  is **useless**, because it never flags a single at-risk patient. This is the
  **accuracy trap**, and it's the centerpiece of the analysis.
- The real model reaches **ROC-AUC 0.642** (5-fold CV 0.633 ± 0.014) — modest, and
  honestly consistent with published models on this dataset. Readmission is genuinely
  hard to predict from discharge data.
- **The value is in ranking, not labeling:** contacting the **top 20%** of patients by
  predicted risk reaches **36% of all eventual 30-day readmissions** — 1.8× better than
  untargeted outreach. The top risk decile readmits at **17.9% vs a 9.0% baseline (2.0× lift)**.

## Why logistic regression

The outcome is binary, and a care manager has to be able to see *why* a patient was
flagged. Logistic regression yields **odds ratios** — "each prior inpatient visit
multiplies readmission odds by 1.40" — which a black-box model with marginally higher
accuracy could not. It also outputs calibrated probabilities, which is exactly what a
capacity-constrained triage decision needs.

**Strongest predictors (odds ratio, all p < 0.001):**

| Predictor | Odds ratio | Interpretation |
|---|---|---|
| Discharged not to home (SNF/transfer) | 1.84 | Sicker disposition → +84% odds |
| Prior inpatient visits (per visit) | 1.40 | Strongest utilization signal |
| On diabetes medication | 1.22 | |
| Prior emergency visits (per visit) | 1.10 | |
| **A1C tested** | **0.90** | *Lower* odds — testing proxies attentive diabetes management |

---

## Data-quality decisions (the part that matters)

The UCI Diabetes 130-US Hospitals dataset (101,766 encounters, 1999–2008) has several
traps. Each was handled deliberately:

1. **Missing values are encoded as `?`, not `NULL`.** Weight (96.9% missing),
   medical specialty (49.1%), and payer code (39.6%) were dropped; race (2.2%) was
   kept as an "Unknown" category.
2. **The target has three classes** (readmitted <30 days, >30 days, never). Only the
   **<30-day** window carries CMS penalties, so it was binarized to
   `<30 = 1, {>30, NO} = 0`.
3. **Deceased and hospice patients cannot be readmitted.** Discharge dispositions
   11/13/14/19/20/21 were identified from `IDS_mapping.csv` and **excluded (2,423 rows)** —
   their observed <30-day readmit rates confirm it (0%, 4.8%, 6.5%…).
4. **Patients repeat** (101,766 encounters, 71,518 patients). To avoid train/test
   leakage, only each patient's **first encounter** was kept → **69,987 patients**.
   This drops the baseline readmit rate from 11.2% to a cleaner **9.0%** (frequent-flyer
   encounters removed).
5. **Class imbalance (~9%)** makes accuracy meaningless — see the accuracy trap above.
   Evaluation uses **AUC, precision, recall, and a gains curve**, and the classification
   **threshold is tuned for recall** because a missed readmission (costly, penalized) is
   far worse than an extra phone call (cheap).

**On PCA:** deliberately *not* used. A VIF check found max VIF = **1.68** (no meaningful
multicollinearity), so PCA would only trade away the interpretability that is the whole
point of a clinical risk model.

---

## Repository layout

```
hospital-readmission-prediction/
├── sql/       01_clean_and_engineer.sql      — DuckDB cleaning & feature engineering
├── notebook/  01_profile.py                  — data-quality audit (Phase 1)
│              02_run_sql.py                   — runs the SQL, reconciles row counts
│              03_logistic_regression.py       — model, odds ratios, accuracy trap
│              04_charts.py                    — ROC, decile, gains, odds-ratio charts
│              05_vif_and_dashboard_export.py  — VIF check + Power BI export tables
├── charts/    generated PNGs + supporting CSVs
├── dashboard/ Power BI file, import-ready tables, and a build guide
└── data/      raw diabetic_data.csv + IDS_mapping.csv, and the cleaned analytic_table.csv
```

## Reproduce it

```bash
pip install pandas numpy scikit-learn statsmodels matplotlib duckdb
cd notebook
python 02_run_sql.py                 # clean + engineer -> data/analytic_table.csv
python 03_logistic_regression.py     # model + metrics + odds ratios
python 04_charts.py                  # charts -> charts/
python 05_vif_and_dashboard_export.py# VIF + dashboard tables -> dashboard/
```

**Dataset:** [Diabetes 130-US Hospitals, 1999–2008 (UCI)](https://archive.ics.uci.edu/dataset/296/diabetes+130-us+hospitals+for+years+1999-2008)
· 101,766 encounters · 50 features · 130 hospitals.
