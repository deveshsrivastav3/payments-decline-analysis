-- Does the way customers pay relate to whether an order is cancelled?
-- Real Olist data (Brazil, 2017-2018). Values are in Brazilian reais (BRL).
-- Population ("scope", defined in build.sql): orders bought Jan 2017 - Aug 2018 that were
-- either delivered or canceled. Cancellation is rare, so read every rate with its group size.

-- R1. What happens to orders in the period, and what is left out of the scope
-- name: r1_order_outcomes
SELECT order_status,
       COUNT(*)                                                       AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)             AS share_pct,
       CASE WHEN order_status IN ('delivered', 'canceled') THEN 'in scope' ELSE 'left out' END
                                                                      AS treatment
FROM order_level
WHERE purchase_month BETWEEN '2017-01' AND '2018-08'
GROUP BY order_status
ORDER BY orders DESC;

-- R2. Cancellation rate by how the order was paid
-- name: r2_cancel_by_payment_group
SELECT payment_group,
       COUNT(*)                                                       AS orders,
       SUM(canceled)                                                  AS canceled,
       ROUND(100.0 * SUM(canceled) / COUNT(*), 2)                     AS cancel_rate_pct,
       ROUND(AVG(order_value_brl), 0)                                 AS avg_order_value_brl
FROM scope
GROUP BY payment_group
ORDER BY orders DESC;

-- R3. Cancellation by number of installments (credit-card-only orders)
-- name: r3_cancel_by_installments
WITH banded AS (
    SELECT canceled,
           CASE WHEN max_installments = 1 THEN '1'
                WHEN max_installments <= 3 THEN '2-3'
                WHEN max_installments <= 6 THEN '4-6'
                WHEN max_installments <= 10 THEN '7-10'
                ELSE '11+' END AS installment_band
    FROM scope
    WHERE payment_group = 'credit_card' AND max_installments >= 1
)
SELECT installment_band,
       COUNT(*)                                                       AS orders,
       SUM(canceled)                                                  AS canceled,
       ROUND(100.0 * SUM(canceled) / COUNT(*), 2)                     AS cancel_rate_pct
FROM banded
GROUP BY installment_band
ORDER BY MIN(CASE installment_band WHEN '1' THEN 1 WHEN '2-3' THEN 2 WHEN '4-6' THEN 3
                                   WHEN '7-10' THEN 4 ELSE 5 END);

-- R4. Cancellation by order value
-- name: r4_cancel_by_value
WITH banded AS (
    SELECT canceled,
           CASE WHEN order_value_brl < 50 THEN '1. under 50'
                WHEN order_value_brl < 100 THEN '2. 50-99'
                WHEN order_value_brl < 200 THEN '3. 100-199'
                WHEN order_value_brl < 500 THEN '4. 200-499'
                ELSE '5. 500 and over' END AS value_band_brl
    FROM scope
)
SELECT value_band_brl,
       COUNT(*)                                                       AS orders,
       SUM(canceled)                                                  AS canceled,
       ROUND(100.0 * SUM(canceled) / COUNT(*), 2)                     AS cancel_rate_pct
FROM banded
GROUP BY value_band_brl
ORDER BY value_band_brl;

-- R5. Monthly cancellation rate against the previous three months (window function)
-- name: r5_monthly_cancel_rate
WITH monthly AS (
    SELECT purchase_month,
           COUNT(*)                                                   AS orders,
           SUM(canceled)                                              AS canceled,
           100.0 * SUM(canceled) / COUNT(*)                           AS cancel_rate_pct
    FROM scope
    GROUP BY purchase_month
)
SELECT purchase_month,
       orders,
       canceled,
       ROUND(cancel_rate_pct, 2)                                      AS cancel_rate_pct,
       ROUND(AVG(cancel_rate_pct) OVER (ORDER BY purchase_month ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING), 2)
                                                                      AS prev_3_month_avg_pct,
       ROUND(cancel_rate_pct
             - AVG(cancel_rate_pct) OVER (ORDER BY purchase_month ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING), 2)
                                                                      AS vs_prev_3_months
FROM monthly
ORDER BY purchase_month;

-- R6. Voucher-only orders look risky overall. Is that stable, or one episode?
--     Cancellation by payment group, August 2018 against every other month
-- name: r6_voucher_vs_period
SELECT payment_group,
       CASE WHEN purchase_month = '2018-08' THEN 'Aug 2018' ELSE 'all other months' END AS period,
       COUNT(*)                                                       AS orders,
       SUM(canceled)                                                  AS canceled,
       ROUND(100.0 * SUM(canceled) / COUNT(*), 2)                     AS cancel_rate_pct
FROM scope
WHERE payment_group IN ('credit_card', 'boleto', 'voucher')
GROUP BY payment_group, period
ORDER BY payment_group, period;

-- R7. Speed of payment approval by payment group (nearest-rank percentiles)
-- name: r7_approval_speed
WITH ranked AS (
    SELECT payment_group,
           approval_hours,
           ROW_NUMBER() OVER (PARTITION BY payment_group ORDER BY approval_hours) AS rn,
           COUNT(*)     OVER (PARTITION BY payment_group)                          AS n
    FROM scope
    WHERE approval_hours IS NOT NULL AND payment_group <> 'not_defined'
)
SELECT payment_group,
       MAX(n)                                                         AS orders,
       ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN approval_hours END), 2)
                                                                      AS median_hours,
       ROUND(MIN(CASE WHEN rn >= 0.9 * n THEN approval_hours END), 2) AS p90_hours,
       ROUND(100.0 * SUM(approval_hours <= 1) / MAX(n), 1)            AS approved_within_1h_pct
FROM ranked
GROUP BY payment_group
ORDER BY median_hours;

-- R8. Delivery time (purchase to delivery) by payment group, delivered orders only
-- name: r8_delivery_time
WITH ranked AS (
    SELECT payment_group,
           delivery_days,
           ROW_NUMBER() OVER (PARTITION BY payment_group ORDER BY delivery_days) AS rn,
           COUNT(*)     OVER (PARTITION BY payment_group)                        AS n
    FROM scope
    WHERE order_status = 'delivered' AND delivery_days IS NOT NULL AND payment_group <> 'not_defined'
)
SELECT payment_group,
       MAX(n)                                                         AS delivered_orders,
       ROUND(AVG(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN delivery_days END), 1)
                                                                      AS median_days,
       ROUND(AVG(delivery_days), 1)                                   AS mean_days
FROM ranked
GROUP BY payment_group
ORDER BY median_days;

-- R9. How much value is at stake? Cancelled value, with the voucher episode separated out
-- name: r9_cancelled_value
WITH tagged AS (
    SELECT canceled,
           order_value_brl,
           CASE WHEN payment_group = 'voucher' AND purchase_month = '2018-08'
                THEN 'voucher-only, Aug 2018' ELSE 'everything else' END AS segment
    FROM scope
)
SELECT segment,
       COUNT(*)                                                       AS orders,
       SUM(canceled)                                                  AS canceled_orders,
       ROUND(SUM(CASE WHEN canceled = 1 THEN order_value_brl ELSE 0 END), 0) AS canceled_value_brl,
       ROUND(100.0 * SUM(CASE WHEN canceled = 1 THEN order_value_brl ELSE 0 END)
             / SUM(order_value_brl), 2)                               AS pct_of_segment_value
FROM tagged
GROUP BY segment
ORDER BY segment;
