"""Generate the portfolio charts from saved model artifacts."""
import numpy as np, pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.metrics import roc_curve, roc_auc_score, precision_recall_curve

plt.rcParams.update({"figure.dpi": 130, "font.size": 10, "axes.grid": True,
                     "grid.alpha": 0.3, "axes.spines.top": False, "axes.spines.right": False})
BLUE, GRAY = "#2166ac", "#9aa0a6"

pred = pd.read_csv("../charts/test_predictions.csv")
y, p = pred["y_test"].values, pred["proba"].values
dec = pd.read_csv("../charts/risk_deciles.csv")
odds = pd.read_csv("../charts/odds_ratios.csv", index_col=0)

# 1) ROC curve
fpr, tpr, _ = roc_curve(y, p)
auc = roc_auc_score(y, p)
fig, ax = plt.subplots(figsize=(5, 4.2))
ax.plot(fpr, tpr, color=BLUE, lw=2, label=f"Logistic regression (AUC = {auc:.3f})")
ax.plot([0, 1], [0, 1], "--", color=GRAY, label="Random (AUC = 0.50)")
ax.set(xlabel="False positive rate", ylabel="True positive rate (recall)",
       title="ROC — 30-day readmission model")
ax.legend(loc="lower right", fontsize=9)
fig.tight_layout(); fig.savefig("../charts/roc_curve.png"); plt.close(fig)

# 2) Risk-decile lift
dec = dec.sort_values("decile")
fig, ax = plt.subplots(figsize=(6, 4.2))
bars = ax.bar(dec["decile"], dec["rate_pct"], color=BLUE)
bars[dec["rate_pct"].idxmax() if False else len(bars)-1].set_color("#b2182b")
ax.axhline(9.0, color=GRAY, ls="--", lw=1.5, label="Baseline 9.0%")
ax.set(xlabel="Predicted-risk decile (9 = highest)", ylabel="Actual 30-day readmit rate (%)",
       title="Model separates high- from low-risk patients")
ax.legend(fontsize=9)
fig.tight_layout(); fig.savefig("../charts/risk_deciles.png"); plt.close(fig)

# 3) Cumulative capture (gains) curve
dec2 = dec.sort_values("decile", ascending=False)
x = np.concatenate([[0], dec2["contacted_pct"].values])
ycap = np.concatenate([[0], dec2["capture_pct"].values])
fig, ax = plt.subplots(figsize=(5.2, 4.2))
ax.plot(x, ycap, marker="o", color=BLUE, lw=2, label="Model targeting")
ax.plot([0, 100], [0, 100], "--", color=GRAY, label="Random outreach")
ax.set(xlabel="% of discharges contacted (by risk rank)",
       ylabel="% of eventual readmissions caught",
       title="Targeting efficiency (gains curve)")
ax.legend(loc="lower right", fontsize=9)
fig.tight_layout(); fig.savefig("../charts/gains_curve.png"); plt.close(fig)

# 4) Top odds ratios (significant, p<0.05), sorted by distance from 1
sig = odds[odds["p_value"] < 0.05].copy()
sig["dist"] = (sig["odds_ratio"] - 1).abs()
sig = sig.sort_values("odds_ratio")
fig, ax = plt.subplots(figsize=(6.5, 5))
colors = [BLUE if v > 1 else "#4d9221" for v in sig["odds_ratio"]]
ax.barh(sig.index, sig["odds_ratio"], color=colors)
ax.axvline(1.0, color="black", lw=1)
ax.set(xlabel="Odds ratio (>1 raises risk, <1 lowers)", title="Significant predictors (p < 0.05)")
fig.tight_layout(); fig.savefig("../charts/odds_ratios.png"); plt.close(fig)

print("Saved 4 charts to charts/: roc_curve, risk_deciles, gains_curve, odds_ratios")
