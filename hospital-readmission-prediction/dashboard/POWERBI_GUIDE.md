# Power BI Dashboard — Build & Reference Guide

`readmission_dashboard.pbix` in this folder **already contains all four required
views plus the bonus gains curve**, built on the four import-ready tables in this
folder. Open it in **Power BI Desktop** (Windows) and you'll land on a single
`Readmission Dashboard` page laid out like this:

```
┌───────────────────────────────────────────────────────────────────────────┐
│              Diabetic 30-Day Readmission Risk — Targeting Model             │  title
├───────────┬───────────┬───────────┬───────────┬───────────────────────────┤
│ Encounters│ Baseline %│ Model AUC │ Recall@20%│  Top-decile lift          │  KPI strip (View 4)
├───────────────────────────────┬───────────────────────────────────────────┤
│  Readmit rate by risk decile  │        Gains curve (bonus)                 │  middle row
│         (View 1)              │                                            │
├───────────────────────────────┼───────────────────────────────────────────┤
│  Top predictors by odds ratio │      Readmit rate by risk tier             │  bottom row
│         (View 2)              │             (View 3)                       │
└───────────────────────────────┴───────────────────────────────────────────┘
```

Every visual reads from a table already loaded in the model, so it should render
on open with no extra steps. The rest of this guide documents **what each view
shows, how it was configured, and how to rebuild or tweak it** — useful if you
want to restyle, or to reproduce the dashboard from scratch on another machine.

> **Note on View 3/4 wiring.** The views use Power BI's built-in (implicit)
> aggregations rather than the four named DAX measures the original draft
> suggested — e.g. View 3 plots `Average(actual_readmit)` directly, and the KPI
> cards read the single-row `kpi_summary` fields. That keeps the file
> self-contained (no measures to recreate). If you'd rather have reusable
> measures, section 2 below still lists them.

---

## 0. Get the tool

**Power BI Desktop** is free and Windows-only. Install from the **Microsoft Store**
(search "Power BI Desktop") — the Store version auto-updates. No account is needed
to *build*; you only need to sign in to *publish* to the Power BI Service later. For
a portfolio piece you can build locally and export screenshots / the `.pbix` file.

---

## 1. The data being imported

Four CSVs, each purpose-built so you don't have to reshape anything:

| File | Grain | Used by |
|---|---|---|
| `scored_patients.csv` | one row per held-out **test patient** (17,497) | risk-tier view, slicers, rate measures |
| `decile_summary.csv` | one row per **risk decile** (10) | decile bar chart, gains curve |
| `odds_ratios.csv` | one row per **predictor** (33) | top-predictors bar chart |
| `kpi_summary.csv` | **single row** of headline numbers | KPI strip |

> **Why the test set only?** Every number on the dashboard then reflects *held-out*
> performance — what the model does on patients it never saw. That's the honest,
> defensible choice, and it's worth a sentence on the dashboard itself.

### Import them (only needed if rebuilding from scratch)
1. Open Power BI Desktop → **Home → Get data → Text/CSV**.
2. Pick a file → **Load** (not Transform — they're already clean). Repeat for all four.
3. They appear in the **Data** pane on the right.

> **Do NOT create relationships between these four tables.** They're at different
> grains and each visual reads from exactly one table. In **Model view**, if Power BI
> auto-detected any relationship lines, delete them. (This is the #1 first-timer
> confusion — leave the tables independent. The shipped file already has none.)

---

## 2. Optional DAX measures

The shipped file doesn't need these, but if you want reusable measures, right-click
`scored_patients` in the Data pane → **New measure**, paste, Enter:

```DAX
Total Patients = COUNTROWS(scored_patients)
```
```DAX
Readmissions = SUM(scored_patients[actual_readmit])
```
```DAX
Readmit Rate = DIVIDE([Readmissions], [Total Patients])
```
```DAX
Avg Predicted Risk = AVERAGE(scored_patients[predicted_prob])
```

Format `Readmit Rate` and `Avg Predicted Risk` as **Percentage** (Measure tools →
Format → % ).

---

## 3. The four views (what ships, and how to rebuild)

### View 1 — Readmission rate by risk decile *(does the model separate risk?)*
- Visual: **Clustered column chart**, from `decile_summary`.
- **X-axis:** `decile`  ·  **Y-axis:** `readmit_rate_pct`.
- Sorted by `decile` ascending. Decile 9 = highest risk.
- Baseline: **Analytics → Constant line** at **9** ("Baseline 9.0%").
- *What it shows:* bars climb left→right; top decile **17.9%** vs **9.0%** baseline (2.0× lift).

### View 2 — Top predictors by odds ratio
- Visual: **Clustered bar chart** (horizontal), from `odds_ratios`.
- **Y-axis:** `predictor`  ·  **X-axis:** `odds_ratio`.
- Filtered to `significant = True` (12 of 33 predictors survive), sorted by `odds_ratio` descending.
- Constant line at **1** ("No effect (OR=1)").
- *What it shows:* discharge-not-to-home **1.84** and prior inpatient visits **1.40** lead;
  A1C tested **0.90** and respiratory primary dx **0.73** are protective.

### View 3 — Readmit rate by risk tier
- Visual: **Clustered column chart**, from `scored_patients`.
- **Axis:** `risk_tier` (High / Medium / Low)  ·  **Values:** `Average of actual_readmit` (shown as %).
- Sorted High → Low.
- *What it shows:* **High 16.1% · Medium 9.4% · Low 5.9%.** This is the actionable one —
  "the High tier (top 20%) gets a 48-hour follow-up call."
- *Optional:* drag `Total Patients` (or count of any column) into the tooltip to show tier size
  (High 3,500 · Medium 5,249 · Low 8,748).

### View 4 — KPI strip
- Five **Card** visuals across the top, each from `kpi_summary`:
  - `total_encounters` → "Encounters" (69,987)
  - `baseline_readmit_rate_pct` → "Baseline rate (%)" (9.0)
  - `model_auc` → "Model AUC" (0.642)
  - `recall_at_high_tier_pct` → "Recall @ top 20% (%)" (35.9)
  - `lift_top_decile` → "Top-decile lift" (1.99)

### Bonus — Gains curve (the money chart)
- Visual: **Line chart**, from `decile_summary`.
- **X-axis:** `pct_of_patients_contacted`  ·  **Y-axis:** `pct_of_readmits_captured`.
- *What it shows:* contact the top 20% by risk → catch **~36%** of readmissions.

---

## 4. Optional polish

- **Slicers:** add a **Slicer** visual with `age_band`, another with `diag1_group`
  or `discharge_group`. Because Views 1(decile is pre-aggregated) — note only the
  `scored_patients`-backed visuals (View 3) cross-filter live; the decile/odds/kpi
  tables are pre-aggregated summaries and won't filter. That's expected.
- **Theme:** View → Themes → pick a clean, calm one (healthcare audience).
- **Title:** already added as a text box across the top; edit the wording in place.

---

## 5. Save & show it off
- **Save** keeps it as `dashboard/readmission_dashboard.pbix`.
- For the portfolio: **File → Export → Export to PDF**, and take a PNG screenshot
  of the full canvas for the README.
- If you want it live: **Publish** (needs a free Power BI account) → embed the link.

---

### One honest caption to put on the dashboard
> *Model AUC 0.64 — modest, and consistent with published models on this dataset;
> readmission is genuinely hard to predict from discharge data. The value is in
> **ranking**: contacting the top 20% of patients by risk reaches 36% of eventual
> readmissions, 1.8× better than untargeted outreach.*

That sentence is what separates an analyst who understands the model from one who
just built it.
