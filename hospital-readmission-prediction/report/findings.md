# Hospital Readmission Prediction — Findings & Recommendations

**Analyst:** Aalaa Jandali
**Dataset:** [Diabetes 130-US Hospitals, 1999–2008 (UCI)](https://archive.ics.uci.edu/dataset/296/diabetes+130-us+hospitals+for+years+1999-2008) — 101,766 inpatient encounters, 130 hospitals, extracted from Cerner's *Health Facts* national clinical data warehouse
**Tools:** SQL (DuckDB) for cleaning & feature engineering · Python (scikit-learn, statsmodels) for modeling · Power BI for the dashboard

---

## Executive summary

A hospital system under the CMS **Hospital Readmissions Reduction Program** runs a
post-discharge care-management program — follow-up calls, early appointments, home
visits — but can enroll only a fraction of discharged patients. The operational
question is not "will this patient be readmitted?" but **"which patients get the
limited follow-up slots?"**

Among diabetic inpatients (first encounter each), **9.0% are readmitted within 30
days**. A logistic-regression model ranks patients by that risk. The findings:

1. **Accuracy is a trap here.** A model that predicts *"no readmission"* for everyone
   scores **91.0% accuracy** — and is useless, because it flags **zero** at-risk
   patients. Accuracy rewards doing nothing on a 9%-prevalence problem.
2. **The model is a modest but honest ranker.** ROC-AUC **0.642** (5-fold CV 0.633 ±
   0.014) — in line with published models on this dataset. Readmission is genuinely
   hard to predict from discharge data.
3. **The value is in ranking, not labeling.** Contacting the **top 20%** of patients
   by predicted risk reaches **~36% of all eventual 30-day readmissions** — 1.8× better
   than untargeted outreach. The top risk decile readmits at **17.9% vs 9.0% baseline
   (2.0× lift)**.
4. **The strongest signals are prior utilization and discharge disposition.** Being
   discharged somewhere other than home multiplies readmission odds by **1.84**; each
   prior inpatient visit by **1.40**. A1C testing is *protective* (0.90) — a proxy for
   attentive diabetes management.

**Bottom line:** the care team should stop asking the model for yes/no labels and use
it to **rank** discharges, working down the list until follow-up capacity is full.
Targeting the top 20% by risk catches a third of readmissions for a fifth of the effort.

---

## Method

Work followed a SQL-then-Python split (see [`../sql/`](../sql/) and [`../notebook/`](../notebook/)):

1. **Profile** the raw data before trusting it — count `?`-encoded missingness per
   column, inspect the target's three classes, and identify structurally-impossible rows.
2. **Clean & engineer** in DuckDB: drop near-empty columns, group ICD-9 diagnoses into
   broad categories, order the age bands, consolidate 20+ medication columns into usable
   flags, and derive prior-utilization counts.
3. **Model** in Python: `statsmodels` Logit (unscaled) for interpretable **odds ratios**,
   and a `scikit-learn` pipeline for honest predictive metrics and threshold tuning.
4. **Evaluate** with AUC, precision/recall, a confusion matrix, risk deciles, and a gains
   curve — never accuracy alone.

All metrics below are reported on a **held-out 25% test set (17,497 patients the model
never saw)**, so every number reflects out-of-sample performance.

---

## Data-quality decisions (the part that matters)

This dataset has four well-known traps. Each was handled deliberately and documented.

| # | Trap | Decision |
|---|---|---|
| 1 | **Missing values are `?`, not `NULL`** — every naive null check reports zero missing | Counted `?` per column. Dropped weight (96.9% missing), medical specialty (49.1%), payer code (39.6%); kept race (2.2%) as an explicit "Unknown" category |
| 2 | **The target has three classes** (<30 days, >30 days, never) | Only the **<30-day** window carries CMS penalties, so binarized `<30 = 1`, `{>30, NO} = 0`. This is a choice, stated as one |
| 3 | **Deceased & hospice patients cannot be readmitted** | Discharge dispositions 11/13/14/19/20/21 identified from `IDS_mapping.csv` and **excluded (2,423 rows)** — their observed <30-day readmit rates (0%, 4.8%, 6.5%…) confirm the logic |
| 4 | **Patients repeat** (101,766 encounters, 71,518 patients) | Kept only each patient's **first encounter** → **69,987 patients**, preventing the same patient landing in both train and test. This also drops the baseline rate from 11.2% to a cleaner **9.0%** (frequent-flyer encounters removed) |

**On PCA:** deliberately *not* used. A VIF check found max VIF = **1.68** — no meaningful
multicollinearity — so PCA would only trade away the interpretability that is the entire
point of a clinical risk model.

---

## Detailed findings

### 1. The accuracy trap

| "Model" | Accuracy | Readmissions caught (recall) |
|---|---|---|
| Predict "no readmission" for everyone | **91.0%** | **0%** |
| Logistic regression (top-20% operating point) | lower | **~36%** |

At a 9% base rate, a do-nothing classifier is right 91% of the time and clinically
worthless. This is why **accuracy is not reported as a headline** — the rest of the
analysis uses metrics that reward finding at-risk patients.

### 2. Discrimination: a modest, honest ranker

| Metric | Value |
|---|---|
| Test ROC-AUC | **0.642** |
| 5-fold CV ROC-AUC (train) | 0.633 ± 0.014 |
| Prevalence (positive rate) | 8.98% |

AUC 0.64 is modest — and consistent with the published literature on this dataset.
Readmission from discharge-time data alone is hard. The honest framing is that the model
**ranks** well enough to be operationally useful, not that it "predicts readmission."

### 3. The threshold is its own trap → tune for recall

Because probabilities are calibrated to the true ~9% prevalence, **almost nothing clears
the default 0.5 cutoff** — at 0.5 the model flags just 13 of 17,497 patients (recall
0.2%). The costs are asymmetric: a **false negative** (a patient sent home without
follow-up who returns) is costly and CMS-penalized; a **false positive** (an unnecessary
phone call) is cheap. So the threshold is lowered on purpose to match follow-up capacity.

**Operating point — flag the top 20% of discharges (threshold ≈ 0.117):**

|  | Predicted NO | Predicted YES |
|---|---|---|
| **Actual NO** | 12,990 | 2,936 |
| **Actual YES** | 1,008 | 563 |

- **Recall 35.8% (≈36%)** — the model catches over a third of readmissions…
- **Precision 16.1%** — …at the cost of ~5 calls per true readmission caught, which is
  acceptable when a call is cheap and a missed readmission is not.
- **Flagged 20.0%** of discharges — matched to a realistic capacity constraint.

### 4. Risk deciles — does the model actually separate risk?

| Decile (9 = highest risk) | Patients | Readmit rate | Cumulative % of readmits captured |
|---|---|---|---|
| 9 | 1,750 | **17.9%** | 19.9% |
| 8 | 1,750 | 14.3% | 35.9% |
| 7 | 1,749 | 11.3% | 48.5% |
| 6 | 1,750 | 10.1% | 59.8% |
| 5 | 1,749 | 6.7% | 67.2% |
| 4 | 1,750 | 8.6% | 76.8% |
| 3 | 1,750 | 5.7% | 83.1% |
| 2 | 1,749 | 5.9% | 89.7% |
| 1 | 1,750 | 5.7% | 96.1% |
| 0 | 1,750 | **3.5%** | 100.0% |

Risk rises cleanly from **3.5% to 17.9%** across deciles — a **2.0× lift** in the top
decile over the 9.0% baseline. This monotonic separation is what makes the ranking usable
even though raw AUC is modest.

### 5. Patient risk tiers — the actionable segmentation

Grouping the test set into three tiers by predicted risk:

| Tier | Patients | Readmit rate |
|---|---|---|
| **High** (top 20%) | 3,500 | **16.1%** |
| Medium | 5,249 | 9.4% |
| Low | 8,748 | **5.9%** |

The High tier readmits at nearly **3× the Low tier's rate**. This is the segment that
justifies intervention: *"the High tier gets a 48-hour post-discharge follow-up call."*

### 6. What drives readmission — odds ratios

From the unscaled logistic model (all below significant at p < 0.05; the top four at
p < 0.001):

| Predictor | Odds ratio | Reading |
|---|---|---|
| Discharged not to home (SNF/transfer) | **1.84** | Sicker disposition → +84% odds |
| Prior inpatient visits (per visit) | **1.40** | Strongest utilization signal |
| On diabetes medication | 1.22 | |
| Prior emergency visits (per visit) | 1.10 | |
| Age (per band) | 1.04 | Older patients, higher risk |
| Number of diagnoses | 1.03 | Comorbidity burden |
| Time in hospital (per day) | 1.03 | Longer stay, sicker patient |
| **A1C tested** | **0.90** | *Protective* — proxies attentive diabetes management |
| Primary dx: Respiratory | 0.73 | *Protective* vs the diabetes-primary reference |

**Prior utilization and discharge disposition dominate** — exactly the factors a care
manager can read off the chart at discharge. That the model's strongest levers are
interpretable is the argument for logistic regression over a black box here.

### 7. Gains curve — the efficiency argument

Sorting patients by predicted risk and walking down the list:

| Contact the top… | …and you capture this share of readmissions |
|---|---|
| 10% | 19.9% |
| **20%** | **35.9%** |
| 30% | 48.5% |
| 50% | 67.2% |

Against an untargeted baseline where contacting X% catches X% of readmissions, the model
is **~1.8× more efficient** at the 20% operating point. This is the single chart a
hospital actually decides on: *how much of the problem you catch for how much effort.*

---

## Recommendations

1. **Use the model to rank, not to label.** Work down the predicted-risk list until
   follow-up capacity is full. Do not deploy a yes/no classifier at the default threshold —
   it flags almost no one.
2. **Set the operating threshold from capacity, and tune for recall.** With capacity for
   ~20% of discharges, the top-20% cut catches ~36% of readmissions. If capacity grows,
   lower the threshold; the gains curve shows the exact trade.
3. **Give the High tier a 48-hour follow-up call.** The top-20% segment readmits at 16.1%
   vs 5.9% in the Low tier — the clearest place to spend limited outreach.
4. **Prioritize the interpretable levers at discharge.** Patients discharged to SNF/transfer,
   or with prior inpatient/emergency visits, are the model's strongest flags and are
   visible without any model at all — useful as a manual backstop.
5. **Don't over-promise on accuracy.** Report recall and lift, not accuracy, to stakeholders.
   The value proposition is targeting efficiency, and it should be sold as such.

---

## Caveats

- **AUC 0.64 is modest.** The model is a useful ranker, not a precise predictor; discharge
  data has limited signal for 30-day readmission, and this is consistent with published work.
- **All findings are correlational.** Odds ratios describe associations in observational
  data, not causal effects; a follow-up program's impact would need a controlled evaluation.
- **The binarization is a modeling choice.** Collapsing ">30 days" into "not readmitted" is
  standard and penalty-aligned, but a different question (any-time readmission) would label
  the data differently.
- **Vintage data (1999–2008).** Coding practices and readmission patterns have shifted since;
  the *method* transfers cleanly to current data even if the specific coefficients would move.
