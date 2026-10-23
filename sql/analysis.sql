-- Payments decline analysis (SQLite; works on PostgreSQL with minor date-function changes)
-- Table: transactions(transaction_id, created_at, user_id, payment_method, currency,
--        provider, amount_eur, three_ds_required, three_ds_outcome, status,
--        decline_code, retry_of, is_retry)
-- "First attempts" = is_retry = 0. Retries are analysed separately in Q7 and Q8.

-- Q1. Authorization rate by payment method (first attempts only)
-- name: q1_auth_rate_by_method
SELECT payment_method,
       COUNT(*)                                                    AS attempts,
       SUM(status = 'approved')                                    AS approved,
       ROUND(100.0 * SUM(status = 'approved') / COUNT(*), 2)       AS auth_rate_pct
FROM transactions
WHERE is_retry = 0
GROUP BY payment_method
ORDER BY auth_rate_pct;

-- Q2. Authorization rate by provider and currency, cards only,
--     flagging cells that sit well below the provider's own average
-- name: q2_provider_currency_cards
WITH cell AS (
    SELECT provider,
           currency,
           COUNT(*)                                              AS attempts,
           100.0 * SUM(status = 'approved') / COUNT(*)           AS auth_rate_pct
    FROM transactions
    WHERE is_retry = 0 AND payment_method = 'card'
    GROUP BY provider, currency
),
provider_avg AS (
    SELECT provider,
           100.0 * SUM(status = 'approved') / COUNT(*)           AS provider_avg_pct
    FROM transactions
    WHERE is_retry = 0 AND payment_method = 'card'
    GROUP BY provider
)
SELECT c.provider,
       c.currency,
       c.attempts,
       ROUND(c.auth_rate_pct, 2)                                 AS auth_rate_pct,
       ROUND(p.provider_avg_pct, 2)                              AS provider_avg_pct,
       ROUND(c.auth_rate_pct - p.provider_avg_pct, 2)            AS gap_vs_provider_avg
FROM cell c
JOIN provider_avg p USING (provider)
ORDER BY gap_vs_provider_avg;

-- Q3. Decline reasons ranked, with share of all declines and running total
-- name: q3_decline_reasons
WITH declines AS (
    SELECT decline_code, COUNT(*) AS n, SUM(amount_eur) AS value_eur
    FROM transactions
    WHERE is_retry = 0 AND status = 'declined'
    GROUP BY decline_code
)
SELECT decline_code,
       n                                                          AS declines,
       ROUND(100.0 * n / SUM(n) OVER (), 2)                       AS share_pct,
       ROUND(100.0 * SUM(n) OVER (ORDER BY n DESC) / SUM(n) OVER (), 2)
                                                                  AS cumulative_pct,
       ROUND(value_eur, 0)                                        AS declined_value_eur
FROM declines
ORDER BY n DESC;

-- Q4. Month-over-month authorization rate by provider, using LAG
-- name: q4_monthly_auth_by_provider
WITH monthly AS (
    SELECT provider,
           SUBSTR(created_at, 1, 7)                               AS month,
           100.0 * SUM(status = 'approved') / COUNT(*)            AS auth_rate_pct
    FROM transactions
    WHERE is_retry = 0
    GROUP BY provider, SUBSTR(created_at, 1, 7)
)
SELECT provider,
       month,
       ROUND(auth_rate_pct, 2)                                    AS auth_rate_pct,
       ROUND(auth_rate_pct - LAG(auth_rate_pct) OVER (PARTITION BY provider ORDER BY month), 2)
                                                                  AS change_vs_prev_month
FROM monthly
ORDER BY provider, month;

-- Q5. Issuer-unavailable declines by provider and month
--     (isolates a possible provider-side incident from customer behaviour)
-- name: q5_issuer_unavailable
SELECT provider,
       SUBSTR(created_at, 1, 7)                                   AS month,
       SUM(decline_code = 'issuer_unavailable')                   AS issuer_unavailable,
       COUNT(*)                                                   AS attempts,
       ROUND(100.0 * SUM(decline_code = 'issuer_unavailable') / COUNT(*), 2)
                                                                  AS pct_of_attempts
FROM transactions
WHERE is_retry = 0
GROUP BY provider, SUBSTR(created_at, 1, 7)
ORDER BY pct_of_attempts DESC
LIMIT 12;

-- Q6. 3-D Secure funnel for card payments that required it (CTE chain)
-- name: q6_three_ds_funnel
WITH required AS (
    SELECT *, CASE WHEN amount_eur >= 200 THEN '>= EUR 200' ELSE '< EUR 200' END AS band
    FROM transactions
    WHERE is_retry = 0 AND three_ds_required = 1
),
steps AS (
    SELECT band,
           COUNT(*)                                               AS required,
           SUM(three_ds_outcome = 'frictionless')                 AS frictionless,
           SUM(three_ds_outcome = 'challenge_passed')             AS challenge_passed,
           SUM(three_ds_outcome = 'challenge_failed')             AS challenge_failed,
           SUM(status = 'approved')                               AS approved
    FROM required
    GROUP BY band
)
SELECT band,
       required,
       frictionless,
       challenge_passed,
       challenge_failed,
       ROUND(100.0 * challenge_failed / (challenge_passed + challenge_failed), 2)
                                                                  AS challenge_fail_rate_pct,
       ROUND(100.0 * approved / required, 2)                      AS end_to_end_approval_pct
FROM steps
ORDER BY band;

-- Q7. Do retries work? Recovery rate by original decline code (self-join)
-- name: q7_retry_recovery
SELECT o.decline_code,
       COUNT(*)                                                   AS retried,
       SUM(r.status = 'approved')                                 AS recovered,
       ROUND(100.0 * SUM(r.status = 'approved') / COUNT(*), 2)    AS recovery_pct
FROM transactions o
JOIN transactions r ON r.retry_of = o.transaction_id
WHERE o.status = 'declined'
GROUP BY o.decline_code
ORDER BY recovery_pct DESC;

-- Q8. Revenue at risk: declined value by month and the share later recovered by a retry
-- name: q8_value_lost_and_recovered
WITH first_declines AS (
    SELECT o.transaction_id,
           SUBSTR(o.created_at, 1, 7)                             AS month,
           o.amount_eur,
           MAX(CASE WHEN r.status = 'approved' THEN 1 ELSE 0 END) AS recovered
    FROM transactions o
    LEFT JOIN transactions r ON r.retry_of = o.transaction_id
    WHERE o.is_retry = 0 AND o.status = 'declined'
    GROUP BY o.transaction_id, SUBSTR(o.created_at, 1, 7), o.amount_eur
)
SELECT month,
       COUNT(*)                                                   AS declined_attempts,
       ROUND(SUM(amount_eur), 0)                                  AS declined_value_eur,
       ROUND(SUM(CASE WHEN recovered = 1 THEN amount_eur ELSE 0 END), 0)
                                                                  AS recovered_value_eur,
       ROUND(SUM(CASE WHEN recovered = 1 THEN amount_eur ELSE 0 END)
             / SUM(amount_eur) * 100, 2)                          AS recovered_pct_of_value
FROM first_declines
GROUP BY month
ORDER BY month;
