-- Data quality checks. Run these BEFORE trusting any result in analysis.sql.
-- Each row is one rule; "violations" is the number of rows that break it.
-- Every rule should return 0. A non-zero result means the data must be fixed or explained first.

-- D1. Rule-by-rule data quality report
-- name: dq_checks
WITH retry_pairs AS (
    SELECT r.transaction_id AS retry_id, r.created_at AS retry_at, r.user_id AS retry_user,
           r.amount_eur AS retry_amount, r.provider AS retry_provider,
           r.payment_method AS retry_method, o.transaction_id AS orig_id,
           o.created_at AS orig_at, o.user_id AS orig_user, o.amount_eur AS orig_amount,
           o.provider AS orig_provider, o.payment_method AS orig_method, o.status AS orig_status
    FROM transactions r
    LEFT JOIN transactions o ON o.transaction_id = r.retry_of
    WHERE r.retry_of IS NOT NULL
),
checks AS (
    SELECT 'identifiers' AS area, 'duplicate transaction_id' AS rule,
           COUNT(*) - COUNT(DISTINCT transaction_id) AS violations
    FROM transactions
    UNION ALL
    SELECT 'completeness', 'null in a required column', COUNT(*)
    FROM transactions
    WHERE transaction_id IS NULL OR created_at IS NULL OR user_id IS NULL
       OR payment_method IS NULL OR currency IS NULL OR provider IS NULL
       OR amount_eur IS NULL OR status IS NULL
    UNION ALL
    SELECT 'validity', 'amount outside 0 to 2,500 EUR', COUNT(*)
    FROM transactions WHERE amount_eur <= 0 OR amount_eur > 2500
    UNION ALL
    SELECT 'validity', 'timestamp outside 2025', COUNT(*)
    FROM transactions WHERE created_at < '2025-01-01' OR created_at >= '2026-01-01'
    UNION ALL
    SELECT 'validity', 'status not approved or declined', COUNT(*)
    FROM transactions WHERE status NOT IN ('approved', 'declined')
    UNION ALL
    SELECT 'consistency', 'approved row carries a decline_code', COUNT(*)
    FROM transactions WHERE status = 'approved' AND decline_code IS NOT NULL
    UNION ALL
    SELECT 'consistency', 'declined row has no decline_code', COUNT(*)
    FROM transactions WHERE status = 'declined' AND decline_code IS NULL
    UNION ALL
    SELECT 'consistency', 'is_retry flag disagrees with retry_of', COUNT(*)
    FROM transactions
    WHERE (is_retry = 1 AND retry_of IS NULL) OR (is_retry = 0 AND retry_of IS NOT NULL)
    UNION ALL
    SELECT 'referential', 'retry_of points to a missing transaction', COUNT(*)
    FROM retry_pairs WHERE orig_id IS NULL
    UNION ALL
    SELECT 'referential', 'retry timestamp earlier than its original', COUNT(*)
    FROM retry_pairs WHERE retry_at < orig_at
    UNION ALL
    SELECT 'referential', 'retry of an attempt that was approved', COUNT(*)
    FROM retry_pairs WHERE orig_status = 'approved'
    UNION ALL
    SELECT 'referential', 'retry differs from original in customer, amount, provider or method', COUNT(*)
    FROM retry_pairs
    WHERE retry_user <> orig_user OR retry_amount <> orig_amount
       OR retry_provider <> orig_provider OR retry_method <> orig_method
    UNION ALL
    SELECT '3-D Secure', '3DS required on a non-card payment', COUNT(*)
    FROM transactions WHERE payment_method <> 'card' AND three_ds_required = 1
    UNION ALL
    SELECT '3-D Secure', '3DS outcome contradicts three_ds_required', COUNT(*)
    FROM transactions
    WHERE (three_ds_required = 0 AND three_ds_outcome <> 'not_required')
       OR (three_ds_required = 1 AND three_ds_outcome = 'not_required')
    UNION ALL
    SELECT '3-D Secure', 'failed challenge on an approved payment', COUNT(*)
    FROM transactions WHERE three_ds_outcome = 'challenge_failed' AND status = 'approved'
    UNION ALL
    SELECT '3-D Secure', '3ds_failed code and challenge_failed outcome disagree', COUNT(*)
    FROM transactions
    WHERE status = 'declined'
      AND ((decline_code = '3ds_failed') <> (three_ds_outcome = 'challenge_failed'))
    UNION ALL
    SELECT 'duplicates', 'first attempts with same customer, amount and second', COUNT(*)
    FROM (
        SELECT 1
        FROM transactions
        WHERE is_retry = 0
        GROUP BY user_id, amount_eur, created_at
        HAVING COUNT(*) > 1
    )
)
SELECT area,
       rule,
       violations,
       CASE WHEN violations = 0 THEN 'pass' ELSE 'FAIL' END AS result
FROM checks;
