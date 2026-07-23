# Power BI Dashboard — Build & Reference Guide

`readmission_dashboard.pbix` in this folder is the finished report, built in
**Power BI Desktop** on the four import-ready tables here. Open it and you'll find
**six pages**:

| Page | Visual | Answers |
|---|---|---|
| **Readmit Rate % by decile** | Clustered column | Does the model separate high from low risk? |
| **Odds ratio by predictor** | Clustered bar | What drives readmission, and how much? |
| **Patient Risk Segments** | Column + line combo | How big is each risk tier and how often does it readmit? |
| **KPI Strip** | 5 cards | The headline numbers at a glance |
| **Gains Curve** | Column + line combo | How much of the problem you catch for how much effort |
| **Dashboard** | All of the above, combined | One-page executive summary with title + honest caption |

The **Dashboard** page is the one to screenshot for the portfolio: a title text box,
the five KPI cards across the top, the decile / gains / odds-ratio / risk-segment
charts, and a caption text box reading —

> *Model AUC 0.64 is modest and consistent with published work — readmission is hard
> to predict. The value is in ranking: contacting the top 20% by risk reaches 36% of
> readmissions.*

The rest of this guide documents the data, the two DAX measures, and how each view is
wired — useful for restyling or rebuilding on another machine.

---

## 0. Get the tool

**Power BI Desktop** is free and Windows-only. Install from the **Microsoft Store**
(search "Power BI Desktop") — the Store version auto-updates. No account is needed to
*build*; you only need to sign in to *publish* to the Power BI Service later.

---

## 1. The data

Four CSVs, each purpose-built so nothing needs reshaping:

| File | Grain | Used by |
|---|---|---|
| `scored_patients.csv` | one row per held-out **test patient** (17,497) | Patient Risk Segments, rate/count measures |
| `decile_summary.csv` | one row per **risk decile** (10) | decile chart, gains curve |
| `odds_ratios.csv` | one row per **predictor** (33) | top-predictors bar chart |
| `kpi_summary.csv` | **single row** of headline numbers | KPI strip |

> **Why the test set only?** Every number then reflects *held-out* performance — what
> the model does on patients it never saw. That's the honest, defensible choice.

### Import (only if rebuilding from scratch)
1. **Home → Get data → Text/CSV** → pick a file → **Load** (not Transform — already clean).
   Repeat for all four.
2. **Do NOT create relationships between the four tables.** They're at different grains
   and each visual reads from exactly one. In **Model view**, delete any auto-detected
   relationship lines. The shipped file has none.

---

## 2. The two DAX measures

The Patient Risk Segments page uses these (right-click `scored_patients` → **New measure**):

```DAX
Total Patients = COUNTROWS(scored_patients)
```
```DAX
Readmit Rate = DIVIDE(SUM(scored_patients[actual_readmit]), COUNTROWS(scored_patients))
```

Format `Readmit Rate` as **Percentage** (Measure tools → Format → %). Everything else on
the dashboard reads columns directly (decile rates, odds ratios, and the single-row
`kpi_summary` fields), so no other measures are required.

---

## 3. How each view is wired

### Readmit Rate % by decile *(does the model separate risk?)*
- **Clustered column**, from `decile_summary`. **Axis:** `decile` · **Value:** `readmit_rate_pct`.
- Sort by `decile` ascending (decile 9 = highest risk). Analytics → **Constant line** at 9 ("Baseline 9.0%").
- *Shows:* 3.5% → **17.9%** across deciles vs 9.0% baseline (2.0× lift).

### Odds ratio by predictor
- **Clustered bar** (horizontal), from `odds_ratios`. **Axis:** `predictor` · **Value:** `odds_ratio`.
- Filter the visual to `significant = True` (12 of 33 survive); sort by `odds_ratio` desc; constant line at 1.
- *Shows:* discharge-not-home **1.84** and prior inpatient **1.40** lead; A1C tested **0.90** protective.

### Patient Risk Segments
- **Line + stacked/clustered column combo**, from `scored_patients`. **Axis:** `risk_tier`
  (High / Medium / Low) · **Column:** `[Total Patients]` · **Line:** `[Readmit Rate]`.
- *Shows:* High 3,500 patients @ **16.1%** · Medium 5,249 @ 9.4% · Low 8,748 @ 5.9%.
  The combo lets tier *size* (columns) and tier *risk* (line) share one frame without a
  broken dual scale.

### KPI Strip
- Five **Card** visuals, each from `kpi_summary`:
  `total_encounters` (69,987) · `baseline_readmit_rate_pct` (9.0) · `model_auc` (0.642) ·
  `recall_at_high_tier_pct` (35.9) · `lift_top_decile` (1.99).

### Gains Curve *(the money chart)*
- **Column + line combo**, from `decile_summary`. **Axis:** `pct_of_patients_contacted` ·
  **Line:** `pct_of_readmits_captured`.
- *Shows:* contact the top 20% by risk → capture **~36%** of readmissions (1.8× random).

### Dashboard (combined page)
- Title text box, the five KPI cards, all four charts, and the honest caption above.
  This is the export-to-PDF / screenshot page.

---

## 4. Polish already applied (and options)
- **Theme:** an accessible built-in theme is applied (calm, healthcare-appropriate).
- **Slicers (optional):** only `scored_patients`-backed visuals (Patient Risk Segments)
  would cross-filter live; the decile / odds / KPI tables are pre-aggregated summaries and
  won't filter. That's expected.

## 5. Save & show it off
- **File → Export → Export to PDF**, and take a PNG of the **Dashboard** page for the README.
- To go live: **Publish** (needs a free Power BI account) → embed the link.
