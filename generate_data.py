"""Generate a SYNTHETIC payments dataset for the decline-analysis project.

Everything here is invented. No real company, customer or transaction data is
used. Some patterns are deliberately built in (see PLANTED_PATTERNS in the
README) so the SQL analysis has something realistic to find. The numbers
therefore illustrate the method, not facts about any real payments business.

Run:  python3 generate_data.py
Out:  data/transactions.csv
"""
import numpy as np
import pandas as pd

SEED = 42
N_ORIGINAL = 88_000          # first attempts; retries are added on top
START = pd.Timestamp("2025-01-01")
DAYS = 365

rng = np.random.default_rng(SEED)

# ---------------------------------------------------------------- timestamps
# Mild growth through the year plus a weekend/evening skew.
day_weights = np.linspace(0.8, 1.25, DAYS)
dow = (START + pd.to_timedelta(np.arange(DAYS), unit="D")).dayofweek
day_weights = day_weights * np.where(dow >= 5, 1.15, 1.0)
day_weights = day_weights / day_weights.sum()
days = rng.choice(DAYS, size=N_ORIGINAL, p=day_weights)
hour_weights = np.array([1, 1, 1, 1, 1, 2, 3, 4, 5, 5, 5, 6,
                         6, 6, 6, 6, 6, 7, 8, 9, 9, 8, 5, 3], dtype=float)
hour_weights /= hour_weights.sum()
hours = rng.choice(24, size=N_ORIGINAL, p=hour_weights)
created = (START + pd.to_timedelta(days, unit="D")
           + pd.to_timedelta(hours, unit="h")
           + pd.to_timedelta(rng.integers(0, 3600, N_ORIGINAL), unit="s"))

# ------------------------------------------------------------------ attributes
n_users = 32_000
user_id = rng.zipf(1.6, N_ORIGINAL) % n_users + 1

method = rng.choice(["card", "ewallet", "bank_transfer"], N_ORIGINAL,
                    p=[0.62, 0.23, 0.15])
currency = rng.choice(["EUR", "GBP", "USD", "SGD", "IDR"], N_ORIGINAL,
                      p=[0.50, 0.16, 0.16, 0.10, 0.08])
provider = rng.choice(["Alpha", "Beta", "Gamma"], N_ORIGINAL, p=[0.45, 0.35, 0.20])

amount_eur = np.round(np.exp(rng.normal(3.7, 1.0, N_ORIGINAL)), 2)
amount_eur = np.clip(amount_eur, 2, 2500)

df = pd.DataFrame({
    "created_at": created,
    "user_id": user_id,
    "payment_method": method,
    "currency": currency,
    "provider": provider,
    "amount_eur": amount_eur,
})
df["month"] = df["created_at"].dt.month

# ------------------------------------------------------------------- 3-D Secure
# Cards above EUR 30 (and a share of smaller ones) go through 3DS.
is_card = df["payment_method"] == "card"
needs_3ds = is_card & ((df["amount_eur"] >= 30) | (rng.random(N_ORIGINAL) < 0.35))
df["three_ds_required"] = needs_3ds.astype(int)

# Frictionless vs challenge; larger amounts get challenged and abandoned more.
p_challenge = np.where(df["amount_eur"] >= 200, 0.55, 0.35)
challenged = needs_3ds & (rng.random(N_ORIGINAL) < p_challenge)
p_fail_given_challenge = np.where(df["amount_eur"] >= 200, 0.30, 0.17)
challenge_failed = challenged & (rng.random(N_ORIGINAL) < p_fail_given_challenge)

three_ds_outcome = np.full(N_ORIGINAL, "not_required", dtype=object)
three_ds_outcome[needs_3ds] = "frictionless"
three_ds_outcome[challenged] = "challenge_passed"
three_ds_outcome[challenge_failed] = "challenge_failed"
df["three_ds_outcome"] = three_ds_outcome

# ------------------------------------------------------- authorization outcome
base = df["payment_method"].map({"card": 0.90, "ewallet": 0.95, "bank_transfer": 0.965}).to_numpy()
p_ok = base.copy()

# PLANTED 1: Gamma struggles with cross-currency cards.
p_ok -= np.where((df["provider"] == "Gamma") & is_card & (df["currency"] != "EUR"), 0.13, 0.0)
# PLANTED 2: Beta has an issuer-availability problem in July.
beta_july = (df["provider"] == "Beta") & (df["month"] == 7)
p_ok -= np.where(beta_july, 0.10, 0.0)
# PLANTED 3: very large baskets are declined more often.
p_ok -= np.where(df["amount_eur"] >= 500, 0.06, 0.0)

approved = rng.random(N_ORIGINAL) < np.clip(p_ok, 0.5, 0.995)
approved &= ~challenge_failed        # a failed challenge is always a decline

# ----------------------------------------------------------------- decline codes
card_codes = ["insufficient_funds", "do_not_honor", "issuer_unavailable",
              "expired_card", "suspected_fraud", "invalid_cvv", "limit_exceeded"]
card_p = np.array([0.34, 0.25, 0.10, 0.08, 0.07, 0.09, 0.07])
alt_codes = ["insufficient_funds", "timeout", "limit_exceeded"]
alt_p = np.array([0.55, 0.25, 0.20])

decline_code = np.full(N_ORIGINAL, None, dtype=object)
declined_idx = np.where(~approved)[0]
for i in declined_idx:
    if challenge_failed[i]:
        decline_code[i] = "3ds_failed"
    elif is_card.iloc[i]:
        p = card_p.copy()
        if beta_july.iloc[i]:
            p[2] += 0.30            # issuer_unavailable spike
            p /= p.sum()
        decline_code[i] = rng.choice(card_codes, p=p)
    else:
        decline_code[i] = rng.choice(alt_codes, p=alt_p)

df["status"] = np.where(approved, "approved", "declined")
df["decline_code"] = decline_code
df["retry_of"] = pd.NA
df["is_retry"] = 0

# ----------------------------------------------------------------------- retries
RETRY_SUCCESS = {"issuer_unavailable": 0.55, "timeout": 0.55, "do_not_honor": 0.35,
                 "insufficient_funds": 0.15, "invalid_cvv": 0.60}
RETRY_SHARE = 0.40       # share of retryable declines the customer tries again
df = df.sort_values("created_at").reset_index(drop=True)
df.insert(0, "transaction_id", ["T" + str(i + 1).zfill(7) for i in range(len(df))])

retry_rows = []
for row in df[df["status"] == "declined"].itertuples():
    code = row.decline_code
    if code in RETRY_SUCCESS and rng.random() < RETRY_SHARE:
        ok = rng.random() < RETRY_SUCCESS[code]
        retry_rows.append({
            "transaction_id": "R" + str(len(retry_rows) + 1),
            "created_at": row.created_at + pd.Timedelta(minutes=int(rng.integers(1, 61))),
            "user_id": row.user_id,
            "payment_method": row.payment_method,
            "currency": row.currency,
            "provider": row.provider,
            "amount_eur": row.amount_eur,
            "month": row.month,
            "three_ds_required": row.three_ds_required,
            "three_ds_outcome": "frictionless" if row.three_ds_required == 1 else "not_required",
            "status": "approved" if ok else "declined",
            "decline_code": None if ok else code,
            "retry_of": row.transaction_id,
            "is_retry": 1,
        })

all_df = pd.concat([df, pd.DataFrame(retry_rows)], ignore_index=True)
all_df = all_df.sort_values("created_at", kind="stable").reset_index(drop=True)

# Final IDs follow time order; retry_of is remapped to the final IDs.
final_ids = ["T" + str(i + 1).zfill(7) for i in range(len(all_df))]
id_map = dict(zip(all_df["transaction_id"], final_ids))
all_df["retry_of"] = all_df["retry_of"].map(id_map)
all_df["transaction_id"] = final_ids

all_df["created_at"] = all_df["created_at"].dt.strftime("%Y-%m-%d %H:%M:%S")
cols = ["transaction_id", "created_at", "user_id", "payment_method", "currency",
        "provider", "amount_eur", "three_ds_required", "three_ds_outcome",
        "status", "decline_code", "retry_of", "is_retry"]
all_df[cols].to_csv("data/transactions.csv", index=False)
print(f"{len(all_df):,} rows written to data/transactions.csv "
      f"({int(all_df['is_retry'].sum()):,} are retries)")
