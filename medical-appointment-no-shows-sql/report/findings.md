# Medical Appointment No-Shows — Findings & Recommendations

**Analyst:** Aalaa Jandali
**Dataset:** [Medical Appointment No Shows (Kaggle)](https://www.kaggle.com/datasets/joniarroba/noshowappointments) — 110,527 appointments, public clinics in Vitória, Brazil, 29 Apr – 8 Jun 2016
**Tools:** SQLite (all loading, cleaning, and analysis done in SQL)

---

## Executive summary

Across ~110K appointments, **20.2% were missed**. Missed appointments waste clinical capacity and delay care for other patients, so even a small reduction is valuable.

The analysis set out to answer one question: **what predicts a no-show?** The answer is clear and, in one case, counter-intuitive:

1. **When a patient books matters most.** Same-day appointments are almost always kept (4.6% missed); risk rises steadily to ~33% for appointments booked a month or more ahead.
2. **A patient's own history is the most actionable predictor.** No-show risk climbs from 19% (no prior misses) to 38% (three or more prior misses).
3. **SMS reminders do *not* backfire.** The raw data appears to show reminders making things worse — but that is a statistical illusion caused by lead time. Compared like-for-like, reminders slightly *help*.
4. Age, welfare status, and neighbourhood have real but smaller effects. Gender and day of week have essentially none.

**Bottom line:** the clinic should target its limited outreach resources at *advance* bookings and at patients with a *history of missing*, and should keep sending SMS reminders.

---

## Method

All work was done in SQL, in five stages (see [`../sql/`](../sql/)):

1. **Load** the raw CSV into a TEXT staging table, untouched.
2. **Profile** the data to surface quality issues before trusting it.
3. **Clean & transform** into a typed analysis table — dropping 6 impossible rows (1 negative age, 5 appointments "scheduled" after they happened), fixing misspelled columns, and flipping the confusingly-named target so `no_show = 1` means the patient missed. Derived columns (booking lead time, age bands, day of week, lead-time buckets) were added here.
4. **Analyse** the drivers of no-shows with aggregation, conditional averages, and confounder control.
5. **Model behaviour over time** with window functions across each patient's history.

The final analysis table holds **110,521 appointments** for **62,298 patients**.

---

## Detailed findings

### 1. Baseline: 1 in 5 appointments is missed

| Metric | Value |
|---|---|
| Appointments | 110,521 |
| Missed (no-show) | 22,314 |
| **No-show rate** | **20.2%** |

Every finding below is compared against this 20.2% baseline.

### 2. Booking lead time is the strongest single driver

| Lead time | Appointments | No-show rate |
|---|---|---|
| Same day | 38,562 | **4.6%** |
| 1–3 days | 14,675 | 22.9% |
| 4–7 days | 17,510 | 25.2% |
| 8–14 days | 12,025 | 30.5% |
| 15–30 days | 17,371 | 32.6% |
| 31+ days | 10,378 | **33.0%** |

The pattern is stark and monotonic. A patient who books and is seen the same day almost never misses. Every week of waiting adds risk, plateauing around one-in-three for the longest waits. **The further out an appointment is booked, the more likely it is to be forgotten or superseded by life.**

### 3. The SMS paradox — the analytical centrepiece

At first glance, reminders look *harmful*:

| Received SMS? | Appointments | No-show rate |
|---|---|---|
| No | 75,039 | 16.7% |
| Yes | 35,482 | **27.6%** |

Taken alone, this says patients who got a reminder missed *far more often*. That would be a bizarre — and wrong — conclusion.

The cause is a **confounder**: the clinic only sends an SMS when an appointment is booked in advance. Same-day appointments (35% of all volume, and 95% reliable) *never* get an SMS, so they pile into the "No SMS" group and make it look artificially reliable.

Removing same-day appointments and comparing like-for-like — advance bookings only — the effect **reverses**:

| Received SMS? (advance bookings only) | Appointments | No-show rate |
|---|---|---|
| No | 36,477 | 29.4% |
| Yes | 35,482 | **27.6%** |

Among comparable appointments, **patients who got a reminder missed *less* often, not more.** The raw result was an artifact of *when* reminders are sent, not evidence that they fail. **Recommendation: keep the SMS program — and extend it to the advance bookings that currently don't receive one.**

### 4. A patient's own history is the most actionable predictor

Using a window function to count each patient's *prior* no-shows before each appointment:

| Prior no-shows | Appointments | No-show rate |
|---|---|---|
| 0 | 93,025 | 19.0% |
| 1 | 12,864 | 25.1% |
| 2 | 2,995 | 27.0% |
| 3+ | 1,637 | **38.0%** |

Risk rises monotonically with history. A patient with three or more past misses is **twice as likely** to miss again as a clean-history patient. Unlike age or neighbourhood, this is something the clinic can act on per-patient: **flag repeat no-showers and give them higher-touch outreach.**

Related history findings:
- **New patients are riskier.** First-ever appointments are missed 20.8% of the time vs 19.4% for returning ones — a patient who has shown up once tends to keep showing up.
- **Chronic no-showers exist.** Most misses are isolated, but streaks run up to one patient with **18 consecutive** missed appointments. These patients will keep ignoring SMS; they need a phone call.

### 5. Demographics: age matters, gender doesn't

| Age band | No-show rate |
|---|---|
| 0–11 | 20.2% |
| 12–17 | **26.4%** |
| 18–34 | 24.0% |
| 35–49 | 20.5% |
| 50–64 | 16.7% |
| 65+ | **15.5%** |

Teenagers and young adults are the least reliable; patients 65+ are the most reliable. **Gender has no meaningful effect** — women book ~65% of appointments but miss at the same ~20% rate as men.

### 6. Secondary factors (small effects)

| Factor | No-show rate |
|---|---|
| Welfare enrolled (Bolsa Família) | 23.7% vs 19.8% |
| Hypertension | 17.3% vs 20.9% |
| Diabetes | 18.0% vs 20.4% |

Welfare-enrolled patients miss somewhat more. Patients with chronic conditions miss *less* — largely because they skew older (see finding 5). **Neighbourhood** no-show rates range from ~16% to ~29% among clinics with 500+ appointments — a real but far narrower spread than lead time. **Day of week** is essentially flat across weekdays.

---

## Recommendations

1. **Prioritise outreach by lead time.** Same-day appointments barely need reminders. Concentrate reminder and confirmation effort on appointments booked 8+ days out, where a third go unattended.
2. **Keep and expand the SMS program.** The "reminders backfire" reading is a confound; like-for-like, they help. Ensure *every* advance booking gets one — not just some.
3. **Build a per-patient risk flag from history.** Patients with 2+ prior no-shows (and especially active streaks) warrant a personal phone call, not another SMS.
4. **Consider light overbooking for high-risk slots** — long-lead-time appointments for young-adult and repeat-no-show patients — to recover otherwise-wasted capacity.
5. **Don't waste effort on non-signals.** Gender and day of week don't predict attendance; targeting on them would spend resources for no return.

---

## Caveats

- The data covers a **single 6-week window** in 2016, so seasonal effects and the day-of-week read (very few Saturday appointments, no Sundays) are limited.
- All findings are **correlational**. The SMS analysis controls for the one obvious confounder (lead time) but is not a randomised trial; a controlled A/B test would confirm the reminder effect.
- `AppointmentDay` has no time-of-day component, so within-day timing could not be studied.
