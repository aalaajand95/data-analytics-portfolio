"""
Phase 3 + 4 — Logistic regression, odds ratios, and the accuracy trap.
  - statsmodels Logit (unscaled) -> interpretable odds ratios for the clinical audience
  - sklearn pipeline            -> honest predictive metrics (AUC, recall, PR), threshold tuning
  - risk deciles                -> the operational "who do we call" recommendation
"""
import numpy as np
import pandas as pd
import statsmodels.api as sm
from sklearn.model_selection import train_test_split, cross_val_score, StratifiedKFold
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.pipeline import Pipeline
from sklearn.linear_model import LogisticRegression
from sklearn.dummy import DummyClassifier
from sklearn.metrics import (roc_auc_score, average_precision_score, confusion_matrix,
                             classification_report, precision_score, recall_score,
                             f1_score, roc_curve, precision_recall_curve)

RANDOM_STATE = 42
pd.set_option("display.width", 160)
pd.set_option("display.max_columns", 60)

df = pd.read_csv("../data/analytic_table.csv")
y = df["readmitted_30"].astype(int)

NUMERIC = ["age_ordinal", "number_outpatient", "number_emergency", "number_inpatient",
           "time_in_hospital", "num_lab_procedures", "num_procedures", "num_medications",
           "number_diagnoses", "a1c_tested", "glucose_tested", "med_changed",
           "on_diabetes_med", "on_insulin"]
CATEGORICAL = ["race", "gender", "diag1_group", "discharge_group", "admission_type_grp"]
X = df[NUMERIC + CATEGORICAL].copy()

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, stratify=y, random_state=RANDOM_STATE)
print(f"Train {X_train.shape}  Test {X_test.shape}")
print(f"Train positive rate {y_train.mean()*100:.2f}%  Test {y_test.mean()*100:.2f}%")

# ============================================================================
# PHASE 4a — THE ACCURACY TRAP
# ============================================================================
print("\n" + "=" * 70)
print("THE ACCURACY TRAP")
print("=" * 70)
dummy = DummyClassifier(strategy="most_frequent").fit(X_train, y_train)
acc = dummy.score(X_test, y_test)
print(f'Model = "predict NO readmission for everyone"')
print(f"  Accuracy: {acc*100:.2f}%   <-- looks great")
print(f"  Recall (at-risk patients caught): "
      f"{recall_score(y_test, dummy.predict(X_test), zero_division=0)*100:.2f}%   <-- useless")

# ============================================================================
# PHASE 3 — LOGISTIC REGRESSION (predictive pipeline)
# ============================================================================
pre = ColumnTransformer([
    ("num", StandardScaler(), NUMERIC),
    ("cat", OneHotEncoder(drop="first", handle_unknown="ignore"), CATEGORICAL),
])
# Unweighted: probabilities stay calibrated to the true ~9% prevalence, so the
# classification THRESHOLD is our explicit tuning lever (Phase 4 asymmetric costs).
clf = Pipeline([
    ("pre", pre),
    ("lr", LogisticRegression(max_iter=2000, random_state=RANDOM_STATE)),
])
clf.fit(X_train, y_train)

proba = clf.predict_proba(X_test)[:, 1]
auc = roc_auc_score(y_test, proba)
ap = average_precision_score(y_test, proba)

cv_auc = cross_val_score(clf, X_train, y_train, cv=StratifiedKFold(5, shuffle=True,
                         random_state=RANDOM_STATE), scoring="roc_auc")

print("\n" + "=" * 70)
print("LOGISTIC REGRESSION — DISCRIMINATION")
print("=" * 70)
print(f"  Test ROC-AUC:              {auc:.3f}")
print(f"  5-fold CV ROC-AUC (train): {cv_auc.mean():.3f} +/- {cv_auc.std():.3f}")
print(f"  Avg precision (PR-AUC):    {ap:.3f}   (baseline = prevalence {y_test.mean():.3f})")

# ============================================================================
# PHASE 4b — ASYMMETRIC COSTS: the default threshold is its OWN trap
# ============================================================================
print("\n" + "=" * 70)
print("THRESHOLD CHOICE (false negative >> false positive in cost)")
print("=" * 70)
pred_05 = (proba >= 0.5).astype(int)
print(f"At the default 0.5 cutoff: recall {recall_score(y_test,pred_05)*100:.1f}%, "
      f"flags {pred_05.mean()*100:.1f}% of discharges -- calibrated to 9% prevalence,")
print("almost nothing clears 0.5. So we LOWER the threshold on purpose:\n")
print(f"{'thresh':>7} {'precision':>10} {'recall':>8} {'F1':>7} {'flagged%':>9}")
for t in [0.50, 0.30, 0.20, 0.15, 0.12, 0.10, 0.08]:
    pred = (proba >= t).astype(int)
    print(f"{t:>7.2f} {precision_score(y_test,pred,zero_division=0):>10.3f} "
          f"{recall_score(y_test,pred):>8.3f} {f1_score(y_test,pred):>7.3f} "
          f"{pred.mean()*100:>8.1f}%")

# Operating point: choose the threshold that flags ~20% of discharges — matching a
# realistic follow-up capacity — and report what share of readmits it catches.
CAPACITY = 0.20
thr = np.quantile(proba, 1 - CAPACITY)
pred_op = (proba >= thr).astype(int)
cm = confusion_matrix(y_test, pred_op)
tn, fp, fn, tp = cm.ravel()
print(f"\nOperating point = flag top {CAPACITY*100:.0f}% of discharges "
      f"(threshold {thr:.3f}):")
print(f"                 pred NO   pred YES")
print(f"  actual NO     {tn:>8,} {fp:>10,}")
print(f"  actual YES    {fn:>8,} {tp:>10,}")
print(f"  Recall {tp/(tp+fn)*100:.1f}%  Precision {tp/(tp+fp)*100:.1f}%  "
      f"Flagged {(tp+fp)/len(y_test)*100:.1f}% of discharges")

# ============================================================================
# PHASE 4c — RISK DECILES: the operational recommendation
# ============================================================================
print("\n" + "=" * 70)
print("RISK DECILES — model separation & targeting efficiency")
print("=" * 70)
dec = pd.DataFrame({"y": y_test.values, "p": proba})
dec["decile"] = pd.qcut(dec["p"], 10, labels=False, duplicates="drop")
tab = dec.groupby("decile").agg(n=("y","size"), readmits=("y","sum"),
                                rate=("y","mean"), avg_p=("p","mean")).sort_index(ascending=False)
tab["rate_pct"] = (tab["rate"]*100).round(1)
tab["capture_pct"] = (tab["readmits"].cumsum()/tab["readmits"].sum()*100).round(1)
tab["contacted_pct"] = (tab["n"].cumsum()/tab["n"].sum()*100).round(1)
print("  decile 9 = highest predicted risk")
print(tab[["n","readmits","rate_pct","capture_pct","contacted_pct"]].to_string())
top = tab.iloc[0]
base = y_test.mean()*100
print(f"\n  Top decile readmits at {top['rate_pct']}% vs {base:.1f}% baseline "
      f"({top['rate_pct']/base:.1f}x lift)")

# ============================================================================
# ODDS RATIOS via statsmodels (unscaled -> per-unit clinical interpretation)
# ============================================================================
print("\n" + "=" * 70)
print("ODDS RATIOS (statsmodels Logit, unscaled features)")
print("=" * 70)
Xtr_num = X_train[NUMERIC].reset_index(drop=True)
Xtr_cat = pd.get_dummies(X_train[CATEGORICAL].reset_index(drop=True),
                         drop_first=True, dtype=float)
Xsm = pd.concat([Xtr_num, Xtr_cat], axis=1)
Xsm = sm.add_constant(Xsm)
logit = sm.Logit(y_train.reset_index(drop=True), Xsm.astype(float)).fit(disp=False, maxiter=200)

odds = pd.DataFrame({
    "odds_ratio": np.exp(logit.params),
    "p_value": logit.pvalues,
})
odds = odds.drop("const")
odds["signif"] = np.where(odds["p_value"] < 0.001, "***",
                  np.where(odds["p_value"] < 0.01, "**",
                  np.where(odds["p_value"] < 0.05, "*", "")))
odds = odds.sort_values("odds_ratio", ascending=False)
print(odds.to_string(float_format=lambda v: f"{v:.3f}"))

# Save artifacts for the dashboard / report
tab.to_csv("../charts/risk_deciles.csv")
odds.to_csv("../charts/odds_ratios.csv")
pd.DataFrame({"y_test": y_test.values, "proba": proba}).to_csv(
    "../charts/test_predictions.csv", index=False)
print("\nSaved: risk_deciles.csv, odds_ratios.csv, test_predictions.csv -> charts/")
