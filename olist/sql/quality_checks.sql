-- Data quality checks on the three raw Olist tables (orders, order_payments, customers).
-- Real data is rarely clean, so a non-zero result is not a failure by itself: each row says
-- how the issue is handled in the analysis. "REVIEW" means a human decided what to do.

-- D1. Rule-by-rule data quality report
-- name: dq_olist
WITH checks AS (
    SELECT 'keys' AS area, 'duplicate order_id in orders' AS rule,
           COUNT(*) - COUNT(DISTINCT order_id) AS violations,
           'none needed' AS handling
    FROM orders
    UNION ALL
    SELECT 'keys', 'duplicate customer_id in customers',
           COUNT(*) - COUNT(DISTINCT customer_id), 'none needed'
    FROM customers
    UNION ALL
    SELECT 'keys', 'duplicate (order_id, payment_sequential) in order_payments', COUNT(*), 'none needed'
    FROM (SELECT 1 FROM order_payments GROUP BY order_id, payment_sequential HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'referential', 'order without a customer row', COUNT(*), 'none needed'
    FROM orders o LEFT JOIN customers c ON c.customer_id = o.customer_id
    WHERE c.customer_id IS NULL
    UNION ALL
    SELECT 'referential', 'payment without an order', COUNT(*), 'none needed'
    FROM order_payments p LEFT JOIN orders o ON o.order_id = p.order_id
    WHERE o.order_id IS NULL
    UNION ALL
    SELECT 'referential', 'order without any payment row', COUNT(*),
           'dropped: payment method unknown'
    FROM orders o LEFT JOIN order_payments p ON p.order_id = o.order_id
    WHERE p.order_id IS NULL
    UNION ALL
    SELECT 'validity', 'payment_type = not_defined', COUNT(*),
           'kept as its own group; too small to compare, left out of the tests'
    FROM order_payments WHERE payment_type = 'not_defined'
    UNION ALL
    SELECT 'validity', 'payment_installments = 0', COUNT(*),
           'left out of the installment analysis'
    FROM order_payments WHERE payment_installments = 0
    UNION ALL
    SELECT 'validity', 'payment_value <= 0', COUNT(*),
           'kept; order value uses the sum, so these barely move it'
    FROM order_payments WHERE payment_value <= 0
    UNION ALL
    SELECT 'consistency', 'approved before it was purchased', COUNT(*), 'none needed'
    FROM orders WHERE order_approved_at < order_purchase_timestamp
    UNION ALL
    SELECT 'consistency', 'delivered before it was purchased', COUNT(*), 'none needed'
    FROM orders WHERE order_delivered_customer_date < order_purchase_timestamp
    UNION ALL
    SELECT 'consistency', 'delivered order with no delivery date', COUNT(*),
           'left out of delivery-time figures'
    FROM orders WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL
    UNION ALL
    SELECT 'consistency', 'delivered order with no approval time', COUNT(*),
           'left out of approval-speed figures'
    FROM orders WHERE order_status = 'delivered' AND order_approved_at IS NULL
    UNION ALL
    SELECT 'consistency', 'canceled order with a delivery date', COUNT(*),
           'kept as canceled; status is taken as the outcome'
    FROM orders WHERE order_status = 'canceled' AND order_delivered_customer_date IS NOT NULL
    UNION ALL
    SELECT 'coverage', 'purchases outside 2017-01 to 2018-08 (scope)', COUNT(*),
           'out of scope: sparse before 2017, cut off after Aug 2018'
    FROM orders WHERE SUBSTR(order_purchase_timestamp, 1, 7) NOT BETWEEN '2017-01' AND '2018-08'
)
SELECT area,
       rule,
       violations,
       CASE WHEN violations = 0 THEN 'pass' ELSE 'REVIEW' END AS result,
       handling
FROM checks;
