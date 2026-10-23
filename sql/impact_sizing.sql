-- Impact sizing: what is each recommendation worth, under stated assumptions?
-- All values are EUR per year on the (synthetic) first attempts, GROSS: before fees, margin,
-- refunds or fraud cost. Every scenario percentage is an assumption, not a measurement.
-- Each recommendation is sized with a low and a high scenario, so the answer is a range.

-- I1. Addressable value per recommendation
-- name: impact_sizing
WITH totals AS (
    SELECT SUM(amount_eur)                                            AS requested_eur,
           SUM(CASE WHEN status = 'declined' THEN amount_eur END)     AS declined_eur
    FROM transactions
    WHERE is_retry = 0
),
gamma AS (
    SELECT COUNT(*)                                                   AS n,
           1.0 * SUM(status = 'approved') / COUNT(*)                  AS rate,
           AVG(CASE WHEN status = 'declined' THEN amount_eur END)     AS avg_declined_eur
    FROM transactions
    WHERE is_retry = 0 AND payment_method = 'card' AND currency <> 'EUR' AND provider = 'Gamma'
),
peers AS (
    SELECT 1.0 * SUM(status = 'approved') / COUNT(*)                  AS rate
    FROM transactions
    WHERE is_retry = 0 AND payment_method = 'card' AND currency <> 'EUR' AND provider <> 'Gamma'
      AND NOT (provider = 'Beta' AND SUBSTR(created_at, 1, 7) = '2025-07')
),
big_3ds AS (
    SELECT COUNT(*)                                                   AS n,
           1.0 * SUM(three_ds_outcome = 'challenge_failed') / COUNT(*) AS fail_rate,
           AVG(CASE WHEN three_ds_outcome = 'challenge_failed' THEN amount_eur END) AS avg_failed_eur
    FROM transactions
    WHERE is_retry = 0 AND amount_eur >= 200
      AND three_ds_outcome IN ('challenge_passed', 'challenge_failed')
),
small_3ds AS (
    SELECT 1.0 * SUM(three_ds_outcome = 'challenge_failed') / COUNT(*) AS fail_rate
    FROM transactions
    WHERE is_retry = 0 AND amount_eur < 200
      AND three_ds_outcome IN ('challenge_passed', 'challenge_failed')
),
tech_declines AS (
    SELECT o.transaction_id,
           o.amount_eur,
           MAX(r.transaction_id IS NOT NULL)                          AS retried,
           MAX(CASE WHEN r.status = 'approved' THEN 1 ELSE 0 END)     AS recovered
    FROM transactions o
    LEFT JOIN transactions r ON r.retry_of = o.transaction_id
    WHERE o.is_retry = 0 AND o.status = 'declined'
      AND o.decline_code IN ('issuer_unavailable', 'timeout', 'invalid_cvv')
    GROUP BY o.transaction_id, o.amount_eur
),
tech AS (
    SELECT COUNT(*)                                                   AS n,
           1.0 * SUM(recovered) / SUM(retried)                        AS recovery_rate,
           AVG(amount_eur)                                            AS avg_eur
    FROM tech_declines
),
beta_july AS (
    SELECT COUNT(*)                                                   AS n,
           1.0 * SUM(status = 'approved') / COUNT(*)                  AS rate,
           AVG(CASE WHEN status = 'declined' THEN amount_eur END)     AS avg_declined_eur
    FROM transactions
    WHERE is_retry = 0 AND provider = 'Beta' AND SUBSTR(created_at, 1, 7) = '2025-07'
),
beta_base AS (
    SELECT 1.0 * SUM(status = 'approved') / COUNT(*)                  AS rate
    FROM transactions
    WHERE is_retry = 0 AND provider = 'Beta' AND SUBSTR(created_at, 1, 7) <> '2025-07'
),
sized AS (
    SELECT '1. Fix Gamma foreign-currency card routing' AS recommendation,
           'Low' AS scenario,
           'Half of the approval gap to Alpha/Beta on the same traffic is closed' AS assumption,
           g.n * (p.rate - g.rate) * 0.5 * g.avg_declined_eur AS value_eur
    FROM gamma g, peers p
    UNION ALL
    SELECT '1. Fix Gamma foreign-currency card routing', 'High',
           'The whole approval gap to Alpha/Beta on the same traffic is closed',
           g.n * (p.rate - g.rate) * 1.0 * g.avg_declined_eur
    FROM gamma g, peers p
    UNION ALL
    SELECT '2. Lower-friction 3DS for payments of EUR 200+', 'Low',
           'Half of the challenge-failure gap to payments under EUR 200 is closed',
           b.n * (b.fail_rate - s.fail_rate) * 0.5 * b.avg_failed_eur
    FROM big_3ds b, small_3ds s
    UNION ALL
    SELECT '2. Lower-friction 3DS for payments of EUR 200+', 'High',
           'The whole challenge-failure gap to payments under EUR 200 is closed',
           b.n * (b.fail_rate - s.fail_rate) * 1.0 * b.avg_failed_eur
    FROM big_3ds b, small_3ds s
    UNION ALL
    SELECT '3. Prompt retries after technical declines', 'Low',
           '10 more points of customers retry; they recover at the rate of those who already retry',
           t.n * 0.10 * t.recovery_rate * t.avg_eur
    FROM tech t
    UNION ALL
    SELECT '3. Prompt retries after technical declines', 'High',
           '20 more points of customers retry; they recover at the rate of those who already retry',
           t.n * 0.20 * t.recovery_rate * t.avg_eur
    FROM tech t
    UNION ALL
    SELECT '4. Alert on provider incidents (Beta July)', 'Low',
           'Incident is caught within 7 days instead of lasting the 31-day month',
           j.n * (b.rate - j.rate) * j.avg_declined_eur * (1 - 7 / 31.0)
    FROM beta_july j, beta_base b
    UNION ALL
    SELECT '4. Alert on provider incidents (Beta July)', 'High',
           'Incident is caught within 3 days instead of lasting the 31-day month',
           j.n * (b.rate - j.rate) * j.avg_declined_eur * (1 - 3 / 31.0)
    FROM beta_july j, beta_base b
)
SELECT recommendation,
       scenario,
       assumption,
       ROUND(value_eur, 0)                                            AS addressable_value_eur,
       ROUND(100.0 * value_eur / t.declined_eur, 2)                   AS pct_of_declined_value,
       ROUND(100.0 * value_eur / t.requested_eur, 3)                  AS pct_of_requested_value
FROM sized, totals t
ORDER BY recommendation, scenario DESC;
