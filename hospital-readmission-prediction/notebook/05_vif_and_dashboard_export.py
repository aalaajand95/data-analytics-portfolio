"""
(a) VIF check — substantiates skipping PCA (no serious multicollinearity).
(b) Export BI-friendly tables + a scored patient table for Power BI.
Re-fits the same model/split as 03 (RANDOM_STATE=42) so numbers match exactly.
"""
import numpy as np, pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.pipeline import Pipeline
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, recall_score, precision_score
from statsmodels.stats.outliers_influence import variance_inflation_factor
import statsmodels.api as sm

RANDOM_STATE = 42
df = pd.read_csv("../data/analytic_table.csv")
y = df["readmitted_30"].astype(int)

NUMERIC = ["age_ordinal", "number_outpatient", "number_emergency", "number_inpatient",
           "time_in_hospital", "num_lab_procedures", "num_procedures", "num_medications",
           "number_diagnoses", "a1c_tested", "glucose_tested", "med_changed",
           "on_diabetes_med", "on_insulin"]
CATEGORICAL = ["race", "gender", "diag1_group", "discharge_group", "admission_type_grp"]
X = df[NUMERIC + CATEGORICAL].copy()

# ---------- (a) VIF on the numeric predictors ----------
print("=" * 60)
print("VIF — multicollinearity check (rule of thumb: >5 concerning, >10 severe)")
print("=" * 60)
Xv = sm.add_constant(df[NUMERIC].astype(float))
vif = pd.DataFrame({
    "feature": Xv.columns,
    "VIF": [variance_inflation_factor(Xv.values, i) for i in range(Xv.shape[1])],
}).query("feature != 'const'").sort_values("VIF", ascending=False)
print(vif.to_string(index=False, float_format=lambda v: f"{v:.2f}"))
print(f"\nMax VIF = {vif['VIF'].max():.2f} -> "
      f"{'no serious multicollinearity; PCA not needed' if vif['VIF'].max() < 5 else 'review'}")

# ---------- refit model (identical to 03) ----------
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, stratify=y, random_state=RANDOM_STATE)
pre = ColumnTransformer([
    ("num", StandardScaler(), NUMERIC),
    ("cat", OneHotEncoder(drop="first", handle_unknown="ignore"), CATEGORICAL),
])
clf = Pipeline([("pre", pre), ("lr", LogisticRegression(max_iter=2000,
                random_state=RANDOM_STATE))]).fit(X_train, y_train)
proba = clf.predict_proba(X_test)[:, 1]
auc = roc_auc_score(y_test, proba)

# ---------- (b) scored patient table (held-out test set + dimensions) ----------
CAPACITY_HI, CAPACITY_MED = 0.20, 0.50   # top 20% High, next 30% Medium, rest Low
thr_hi = np.quantile(proba, 1 - CAPACITY_HI)
thr_med = np.quantile(proba, 1 - CAPACITY_MED)
scored = X_test.copy()
scored["age_band"] = df.loc[X_test.index, "age_band"].values
scored["predicted_prob"] = proba.round(4)
scored["actual_readmit"] = y_test.values
scored["risk_decile"] = pd.qcut(proba, 10, labels=False, duplicates="drop")
scored["risk_tier"] = np.where(proba >= thr_hi, "High",
                       np.where(proba >= thr_med, "Medium", "Low"))
scored.to_csv("../dashboard/scored_patients.csv", index=False)

# ---------- decile table ----------
d = pd.DataFrame({"y": y_test.values, "p": proba})
d["decile"] = pd.qcut(d["p"], 10, labels=False, duplicates="drop")
dt = d.groupby("decile").agg(patients=("y","size"), readmits=("y","sum"),
                             readmit_rate=("y","mean")).sort_index(ascending=False)
dt["readmit_rate_pct"] = (dt["readmit_rate"]*100).round(2)
dt["pct_of_readmits_captured"] = (dt["readmits"].cumsum()/dt["readmits"].sum()*100).round(1)
dt["pct_of_patients_contacted"] = (dt["patients"].cumsum()/dt["patients"].sum()*100).round(1)
dt.reset_index().to_csv("../dashboard/decile_summary.csv", index=False)

# ---------- odds-ratio table (tidy for a bar chart) ----------
odds = pd.read_csv("../charts/odds_ratios.csv", index_col=0).reset_index()
odds.columns = ["predictor", "odds_ratio", "p_value", "signif"]
odds["direction"] = np.where(odds["odds_ratio"] > 1, "Increases risk", "Decreases risk")
odds["significant"] = odds["p_value"] < 0.05
odds.to_csv("../dashboard/odds_ratios.csv", index=False)

# ---------- KPI strip (single row) ----------
tier_hi = scored[scored["risk_tier"] == "High"]
kpis = pd.DataFrame([{
    "total_encounters": len(df),
    "test_patients": len(y_test),
    "baseline_readmit_rate_pct": round(y.mean()*100, 2),
    "model_auc": round(auc, 3),
    "high_tier_share_pct": round(len(tier_hi)/len(scored)*100, 1),
    "high_tier_readmit_rate_pct": round(tier_hi["actual_readmit"].mean()*100, 1),
    "recall_at_high_tier_pct": round(recall_score(y_test, (proba>=thr_hi).astype(int))*100, 1),
    "precision_at_high_tier_pct": round(precision_score(y_test, (proba>=thr_hi).astype(int))*100, 1),
    "lift_top_decile": round(dt.iloc[0]["readmit_rate"]/y.mean(), 2),
}])
kpis.to_csv("../dashboard/kpi_summary.csv", index=False)

print("\nExported to dashboard/:")
for f in ["scored_patients.csv","decile_summary.csv","odds_ratios.csv","kpi_summary.csv"]:
    print("  -", f)
print("\nKPI summary:")
print(kpis.T.to_string(header=False))
