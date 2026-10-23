"""Are the gaps found in analysis.sql real, or could they be noise?

For each headline finding this runs a two-proportion z-test and reports the size of the
gap with a 95% confidence interval. It also runs one CONTROL comparison that should show
nothing (two providers with no planted difference) and a multiple-comparison screen
across all provider x currency cells.

Out: output/significance_tests.csv, output/provider_currency_screen.csv
Method notes:
  - p-value: pooled-variance z-test, two-sided. CI: unpooled (Wald) interval on the difference.
  - Attempts are treated as independent. Customers repeat in this data, so real p-values
    would be somewhat larger; read the effect size and interval first, the p-value second.
"""
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import norm

root = Path(__file__).parent
df = pd.read_csv(root / "data" / "transactions.csv", parse_dates=["created_at"])
first = df[df.is_retry == 0].copy()
first["ok"] = (first.status == "approved").astype(int)
first["month"] = first.created_at.dt.month


def two_prop(a_success, a_n, b_success, b_n):
    """Difference in proportions (a - b) in percentage points, 95% CI, z, two-sided p."""
    pa, pb = a_success / a_n, b_success / b_n
    diff = pa - pb
    se_wald = np.sqrt(pa * (1 - pa) / a_n + pb * (1 - pb) / b_n)
    pooled = (a_success + b_success) / (a_n + b_n)
    se_pool = np.sqrt(pooled * (1 - pooled) * (1 / a_n + 1 / b_n))
    z = diff / se_pool
    p = 2 * norm.sf(abs(z))
    return pa, pb, 100 * diff, 100 * (diff - 1.96 * se_wald), 100 * (diff + 1.96 * se_wald), z, p


rows = []


def add(test, label_a, a, label_b, b, alpha=0.05, metric="approval rate"):
    """a, b are boolean-ish Series of outcomes (1 = success) for each group."""
    pa, pb, d, lo, hi, z, p = two_prop(a.sum(), len(a), b.sum(), len(b))
    rows.append({
        "test": test, "metric": metric,
        "group_a": label_a, "n_a": len(a), "rate_a_pct": round(100 * pa, 2),
        "group_b": label_b, "n_b": len(b), "rate_b_pct": round(100 * pb, 2),
        "diff_pts": round(d, 2), "ci95_low": round(lo, 2), "ci95_high": round(hi, 2),
        "z": round(z, 2), "p_value": p,
        "verdict": "distinguishable from noise" if p < alpha else "not distinguishable from noise",
    })


# S1. Cards vs e-wallets
card = first[first.payment_method == "card"]
ewal = first[first.payment_method == "ewallet"]
add("S1 card vs e-wallet", "card", card.ok, "e-wallet", ewal.ok)

# S2. Gamma non-EUR cards vs the same traffic at Alpha and Beta (Beta's July incident excluded)
cx = first[(first.payment_method == "card") & (first.currency != "EUR")]
gamma = cx[cx.provider == "Gamma"]
peers = cx[(cx.provider != "Gamma") & ~((cx.provider == "Beta") & (cx.month == 7))]
add("S2 Gamma non-EUR cards vs peers", "Gamma, non-EUR cards", gamma.ok,
    "Alpha+Beta, non-EUR cards (excl. Beta July)", peers.ok)

# S3. Beta in July vs Beta in other months, all payment methods
beta = first[first.provider == "Beta"]
add("S3 Beta July vs other months", "Beta, July", beta[beta.month == 7].ok,
    "Beta, other months", beta[beta.month != 7].ok)

# S3b. Same month, issuer_unavailable declines as the outcome
iu = (beta.decline_code == "issuer_unavailable").astype(int)
add("S3b Beta July issuer_unavailable share", "Beta, July", iu[beta.month == 7],
    "Beta, other months", iu[beta.month != 7], metric="share of attempts declined issuer_unavailable")

# S4. 3DS challenge failure: >= EUR 200 vs below (challenged payments only)
ch = first[first.three_ds_outcome.isin(["challenge_passed", "challenge_failed"])].copy()
ch["fail"] = (ch.three_ds_outcome == "challenge_failed").astype(int)
add("S4 3DS challenge failure, large vs small", "challenged, >= EUR 200", ch[ch.amount_eur >= 200].fail,
    "challenged, < EUR 200", ch[ch.amount_eur < 200].fail, metric="challenge failure rate")

# S5. Retry recovery: insufficient_funds vs technical declines
orig = df[["transaction_id", "decline_code"]].rename(columns={"transaction_id": "retry_of", "decline_code": "orig_code"})
rt = df[df.is_retry == 1].merge(orig, on="retry_of")
rt["ok"] = (rt.status == "approved").astype(int)
tech = rt[rt.orig_code.isin(["issuer_unavailable", "timeout", "invalid_cvv"])]
add("S5 retry recovery, technical vs insufficient_funds", "after technical declines", tech.ok,
    "after insufficient_funds", rt[rt.orig_code == "insufficient_funds"].ok, metric="retry recovery rate")

# C1. CONTROL: Alpha vs Beta on non-EUR cards, July excluded. No difference was planted.
alpha_c = cx[cx.provider == "Alpha"]
beta_c = cx[(cx.provider == "Beta") & (cx.month != 7)]
add("C1 control: Alpha vs Beta non-EUR cards (no planted gap)", "Alpha, non-EUR cards", alpha_c.ok,
    "Beta, non-EUR cards (excl. July)", beta_c.ok)

out = pd.DataFrame(rows)
out.to_csv(root / "output" / "significance_tests.csv", index=False)

# Screen: every provider x currency card cell against all other card attempts, Bonferroni-corrected.
cards = first[first.payment_method == "card"]
cells = cards.groupby(["provider", "currency"]).size().index.tolist()
alpha_bonf = 0.05 / len(cells)
screen = []
for prov, cur in cells:
    m = (cards.provider == prov) & (cards.currency == cur)
    pa, pb, d, lo, hi, z, p = two_prop(cards[m].ok.sum(), m.sum(), cards[~m].ok.sum(), (~m).sum())
    screen.append({"provider": prov, "currency": cur, "attempts": int(m.sum()),
                   "auth_rate_pct": round(100 * pa, 2), "rest_of_cards_pct": round(100 * pb, 2),
                   "diff_pts": round(d, 2), "p_value": p,
                   "flag_uncorrected": p < 0.05, f"flag_bonferroni_{len(cells)}": p < alpha_bonf})
screen = pd.DataFrame(screen).sort_values("diff_pts")
screen.to_csv(root / "output" / "provider_currency_screen.csv", index=False)

pd.set_option("display.width", 220)
print(out[["test", "n_a", "rate_a_pct", "n_b", "rate_b_pct", "diff_pts", "ci95_low", "ci95_high", "p_value", "verdict"]]
      .to_string(index=False, float_format=lambda x: f"{x:.4g}"))
print(f"\nProvider x currency screen (Bonferroni threshold {alpha_bonf:.4f}):")
print(screen.to_string(index=False, float_format=lambda x: f"{x:.4g}"))
