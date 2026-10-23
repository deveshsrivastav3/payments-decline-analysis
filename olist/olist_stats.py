"""Are the differences in cancellation rate real? Tests and a regression on the Olist scope.

Cancellation is rare (about 0.6% of orders), and some groups have only a few dozen cancellations,
so this uses methods that behave well for rare events:
  - Fisher's exact test for each comparison (instead of a normal approximation)
  - Newcombe's interval (built from Wilson intervals) for the difference in rates
  - A logistic regression that adjusts for order value and installments together

Out: output/olist_tests.csv, output/olist_logit.csv
"""
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf
from scipy.stats import fisher_exact

from run_olist import ROOT, build_db

con = build_db()
df = pd.read_sql_query(
    "SELECT payment_group, purchase_month, canceled, order_value_brl, max_installments FROM scope", con)


def wilson(k, n, z=1.96):
    p = k / n
    denom = 1 + z**2 / n
    centre = (p + z**2 / (2 * n)) / denom
    half = z * np.sqrt(p * (1 - p) / n + z**2 / (4 * n**2)) / denom
    return centre - half, centre + half


def compare(test, label_a, a, label_b, b):
    """a, b: 0/1 Series (1 = canceled). Returns one row: rates, difference (a - b) with 95% CI, p."""
    ka, na, kb, nb = int(a.sum()), len(a), int(b.sum()), len(b)
    pa, pb = ka / na, kb / nb
    la, ua = wilson(ka, na)
    lb, ub = wilson(kb, nb)
    d = pa - pb
    lo = d - np.sqrt((pa - la) ** 2 + (ub - pb) ** 2)
    hi = d + np.sqrt((ua - pa) ** 2 + (pb - lb) ** 2)
    p = fisher_exact([[ka, na - ka], [kb, nb - kb]])[1]
    return {"test": test, "group_a": label_a, "orders_a": na, "canceled_a": ka,
            "rate_a_pct": round(100 * pa, 2), "group_b": label_b, "orders_b": nb, "canceled_b": kb,
            "rate_b_pct": round(100 * pb, 2), "diff_pts": round(100 * d, 2),
            "ci95_low": round(100 * lo, 2), "ci95_high": round(100 * hi, 2),
            "p_value": p, "verdict": "distinguishable from noise" if p < 0.05 else "not distinguishable from noise"}


g = df.payment_group
aug = df.purchase_month == "2018-08"
cc = df[g == "credit_card"]
rows = [
    compare("T1 boleto vs credit card, all months", "boleto", df[g == "boleto"].canceled,
            "credit card", df[g == "credit_card"].canceled),
    compare("T2 voucher-only vs credit card, all months", "voucher-only", df[g == "voucher"].canceled,
            "credit card", df[g == "credit_card"].canceled),
    compare("T3 voucher-only vs credit card, Aug 2018 removed", "voucher-only",
            df[(g == "voucher") & ~aug].canceled, "credit card", df[(g == "credit_card") & ~aug].canceled),
    compare("T4 voucher-only, Aug 2018 vs other months", "voucher-only, Aug 2018",
            df[(g == "voucher") & aug].canceled, "voucher-only, other months",
            df[(g == "voucher") & ~aug].canceled),
    compare("T5 credit card, 7+ installments vs 1", "7+ installments",
            cc[cc.max_installments >= 7].canceled, "1 installment", cc[cc.max_installments == 1].canceled),
    compare("T6 order value 500+ BRL vs under 500", "500 BRL and over",
            df[df.order_value_brl >= 500].canceled, "under 500 BRL", df[df.order_value_brl < 500].canceled),
]
tests = pd.DataFrame(rows)
tests.to_csv(ROOT / "output" / "olist_tests.csv", index=False)

# Logistic regression: cancellation on payment group, installments and log2(order value).
model_df = df[(g != "not_defined") & (df.order_value_brl > 0) & (df.max_installments >= 1)].copy()
model_df["log2_value"] = np.log2(model_df.order_value_brl)
formula = "canceled ~ C(payment_group, Treatment('credit_card')) + max_installments + log2_value"
labels = {"max_installments": "each extra installment", "log2_value": "each doubling of order value"}
out = []
for name, data in [("A: all months", model_df), ("B: August 2018 removed", model_df[model_df.purchase_month != "2018-08"])]:
    fit = smf.logit(formula, data).fit(disp=0)
    ci = fit.conf_int()
    for term in fit.params.index[1:]:
        label = labels.get(term, term.split("[T.")[-1].rstrip("]") + " vs credit card")
        out.append({"model": name, "term": label, "odds_ratio": round(float(np.exp(fit.params[term])), 2),
                    "ci95_low": round(float(np.exp(ci.loc[term, 0])), 2),
                    "ci95_high": round(float(np.exp(ci.loc[term, 1])), 2),
                    "p_value": float(fit.pvalues[term]), "orders": len(data), "cancellations": int(data.canceled.sum())})
logit = pd.DataFrame(out)
logit.to_csv(ROOT / "output" / "olist_logit.csv", index=False)

pd.set_option("display.width", 220)
print(tests.to_string(index=False, float_format=lambda x: f"{x:.4g}"))
print()
print(logit.to_string(index=False, float_format=lambda x: f"{x:.4g}"))
