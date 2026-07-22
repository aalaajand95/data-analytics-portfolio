"""
Phase 1 — Profile the raw diabetic_data.csv before trusting anything.
Checks every data-quality landmine from the project guide.
"""
import pandas as pd
import numpy as np

pd.set_option("display.width", 160)
pd.set_option("display.max_columns", 60)

DATA = "../data/diabetic_data.csv"

# Read everything as string first so '?' and numeric-coded IDs are preserved verbatim.
df = pd.read_csv(DATA, dtype=str)

print("=" * 70)
print("SHAPE & KEYS")
print("=" * 70)
print(f"Rows (encounters):        {len(df):,}")
print(f"Distinct encounter_id:    {df['encounter_id'].nunique():,}")
print(f"Distinct patient_nbr:     {df['patient_nbr'].nunique():,}")
print(f"Columns:                  {df.shape[1]}")

print("\n" + "=" * 70)
print("TARGET: readmitted (3 classes)")
print("=" * 70)
vc = df["readmitted"].value_counts(dropna=False)
for k, v in vc.items():
    print(f"  {k:>6}: {v:>7,}  ({v/len(df)*100:5.2f}%)")
print(f"\n  <30 day readmit rate (the CMS-penalized outcome): "
      f"{(df['readmitted']=='<30').mean()*100:.2f}%")

print("\n" + "=" * 70)
print("MISSING VALUES ENCODED AS '?' (per column, only where present)")
print("=" * 70)
q = (df == "?").sum()
q = q[q > 0].sort_values(ascending=False)
for col, n in q.items():
    print(f"  {col:<22} {n:>7,}  ({n/len(df)*100:5.2f}%)")

print("\n" + "=" * 70)
print("PATIENT DUPLICATION (leakage risk)")
print("=" * 70)
per_patient = df.groupby("patient_nbr").size()
print(f"  Patients with 1 encounter:   {(per_patient==1).sum():,}")
print(f"  Patients with >1 encounter:  {(per_patient>1).sum():,}")
print(f"  Max encounters for a patient: {per_patient.max()}")
print(f"  Extra rows lost if we keep first-only: "
      f"{len(df) - df['patient_nbr'].nunique():,}")

print("\n" + "=" * 70)
print("DISCHARGE DISPOSITION (death / hospice cannot be readmitted)")
print("=" * 70)
# Map from IDS_mapping.csv, discharge section.
disp = df["discharge_disposition_id"].value_counts().sort_index(key=lambda x: x.astype(int))
# IDs that mean death or hospice per the mapping file:
#   11 Expired | 13 Hospice/home | 14 Hospice/medical facility
#   19,20,21 Expired (hospice, Medicaid)
death_hospice = {"11", "13", "14", "19", "20", "21"}
print("  disposition_id : count : <30 readmit rate within that group")
for k, v in disp.items():
    grp = df[df["discharge_disposition_id"] == k]
    r = (grp["readmitted"] == "<30").mean() * 100
    flag = "  <-- DEATH/HOSPICE" if k in death_hospice else ""
    print(f"  {k:>3} : {v:>6,} : {r:5.2f}%{flag}")
n_dh = df["discharge_disposition_id"].isin(death_hospice).sum()
print(f"\n  Rows in death/hospice dispositions (to EXCLUDE): {n_dh:,} "
      f"({n_dh/len(df)*100:.2f}%)")

print("\n" + "=" * 70)
print("CANDIDATE NUMERIC PREDICTORS — ranges & sanity")
print("=" * 70)
num_cols = ["time_in_hospital", "num_lab_procedures", "num_procedures",
            "num_medications", "number_outpatient", "number_emergency",
            "number_inpatient", "number_diagnoses"]
for c in num_cols:
    s = pd.to_numeric(df[c], errors="coerce")
    print(f"  {c:<20} min={s.min():>4.0f} med={s.median():>5.1f} "
          f"mean={s.mean():>6.2f} max={s.max():>5.0f}")

print("\n" + "=" * 70)
print("KEY CATEGORICALS")
print("=" * 70)
for c in ["gender", "age", "A1Cresult", "max_glu_serum", "change", "diabetesMed"]:
    print(f"\n  {c}:")
    for k, v in df[c].value_counts(dropna=False).items():
        print(f"      {str(k):<12} {v:>7,}  ({v/len(df)*100:5.2f}%)")
