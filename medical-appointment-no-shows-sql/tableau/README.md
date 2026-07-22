# Step 7 — Build the Tableau Dashboard

**▶️ Live dashboard:** <https://public.tableau.com/app/profile/aalaa.jandali/viz/Medical_No_Show_Dashboard/MedicalAppointmentNoShows>

This guide walks you through building a **No-Show Analysis** dashboard in
**Tableau Public** (the free version) from the extract this project produces.

The data feed is [`appointments_clean.csv`](appointments_clean.csv) —
110,521 rows, one per appointment, already cleaned and enriched by the SQL
pipeline. The key modelling trick: **`no_show` is stored as 0/1**, so a
no-show *rate* is just `AVG([no_show])` in Tableau. No pre-aggregation
needed — Tableau does the maths, and every chart comes from one source.

---

## 0. Prerequisites

- **Tableau Public Desktop** — free download: <https://public.tableau.com/en-us/s/download>
- A free **Tableau Public account** (required to save/publish).
- The file `appointments_clean.csv` from this folder. *(To regenerate it from
  scratch: `sqlite3 appointments.db < sql/06_export_for_tableau.sql`.)*

---

## 1. Connect the data

1. Open Tableau Public → **Connect → Text file** → choose `appointments_clean.csv`.
2. On the data-source screen, confirm Tableau read the types correctly:
   - `scheduled_date`, `appointment_date` → **Date**
   - `age`, `lead_time_days`, `prior_no_shows`, all the flag columns, `no_show` → **Number (whole)**
   - `no_show` should be a **Measure**. If Tableau files it under Dimensions, drag it to Measures (or right-click → *Convert to Measure*).
3. Click **Sheet 1** to start building.

---

## 2. Create three reusable calculated fields

Right-click in the Data pane → **Create Calculated Field** for each:

| Name | Formula | Why |
|---|---|---|
| **No-Show Rate** | `AVG([No Show])` | The core metric, reused on every chart. Format as Percentage, 1 decimal. |
| **Appointments** | `COUNT([Appointment Id])` | Volume, for context and tooltips. |
| **Prior Miss Group** | `IF [Prior No Shows] = 0 THEN "0" ELSEIF [Prior No Shows] = 1 THEN "1" ELSEIF [Prior No Shows] = 2 THEN "2" ELSE "3+" END` | Buckets the history column for chart 4. |

> Tip: format **No-Show Rate** once (right-click the field → *Default Properties → Number → Percentage*, 1 decimal) and every chart inherits it.

---

## 3. Build the worksheets

Build each as its own sheet, then assemble them in Section 4. For every
chart, drag **No-Show Rate** to the relevant shelf and label the bars.

### Sheet 1 — "No-Show Rate by Lead Time" (the headline)
- **Columns:** `Lead Time Bucket`   **Rows:** `No-Show Rate`
- Bar chart. The buckets already sort correctly (`0 same day` … `5 31+ days`).
- Add `Appointments` to Tooltip. Add a reference line at the overall rate (~20%).
- *This is your lead story: 4.6% → 33%.*

### Sheet 2 — "The SMS Paradox" (two side-by-side bars)
- Build a **parameter or filter** view. Simplest version:
  - **Columns:** `Sms Received`   **Rows:** `No-Show Rate`   → shows the *raw* 16.7% vs 27.6%.
  - Duplicate the sheet, drag `Lead Time Days` to Filters → set to **≥ 1** (advance bookings only) → now shows 29.4% vs 27.6%, the reversal.
- Title them "Raw" and "Advance bookings only" so the reversal is obvious side by side.

### Sheet 3 — "No-Show Rate by Age Band"
- **Columns:** `Age Band`   **Rows:** `No-Show Rate`   → bar chart, sorted by age band.

### Sheet 4 — "History Risk Curve"
- **Columns:** `Prior Miss Group`   **Rows:** `No-Show Rate`   → 19% → 25% → 27% → 38%.
- Add `Appointments` to Tooltip so viewers see the shrinking sample sizes.

### Sheet 5 — "Neighbourhood Leaderboard" (optional)
- **Rows:** `Neighbourhood`   **Columns:** `No-Show Rate`
- Sort descending; add a filter on `Appointments` ≥ 500 to hide tiny clinics.
- Show the **Top 10** with a Top-N filter.

### (Optional) KPI text tiles
- New sheet, drag **No-Show Rate** to Text → gives the big "20.2%" number.
- Repeat with **Appointments** for the "110,521" total.

---

## 4. Assemble the dashboard

1. **Dashboard → New Dashboard.** Set size to **Automatic** or a fixed 1200×900.
2. Drag sheets onto the canvas. Suggested layout:
   - Top row: the KPI tiles (20.2% no-show rate, 110K appointments).
   - Middle: **Lead Time** (left, largest) and **SMS Paradox** (right).
   - Bottom: **Age Band**, **History Risk Curve**, and the **Neighbourhood** leaderboard.
3. Add a **Dashboard Title**: *"Medical Appointment No-Shows — What Predicts a Missed Visit?"*
4. Add a text box with the one-line takeaway: *"Booking lead time and a patient's own history predict no-shows far better than demographics — and SMS reminders help once you control for lead time."*
5. Add a global **filter** (e.g. `Gender` or `Age Band`) and set it to *Apply to all worksheets using this data source* so the dashboard is interactive.

---

## 5. Publish & link it

1. **File → Save to Tableau Public As…** → sign in → name it
   `Medical_No_Show_Dashboard`.
2. Once it opens in the browser, copy the public URL.
3. Add the link to this project's README and your portfolio README, exactly
   like the Balaji project's Tableau link.

---

## Design tips for a portfolio-grade dashboard

- **One story per dashboard.** The lead-time and history charts *are* the
  story; don't crowd it with every variable.
- **Consistent colour.** Use a single accent colour for the bars; reserve a
  contrasting colour only for the SMS "reversal" so it pops.
- **Sort by value** (except lead time / age, which have a natural order) so
  the eye lands on the extremes.
- **Label the bars** with the percentage — reviewers shouldn't have to hover.
- **Title every sheet as a finding**, not a field name: "New patients miss
  more" beats "no_show by visit_number".
