-- Builds the order-level table used by every analysis query.
-- Raw tables (loaded from the three CSVs): orders, order_payments, customers.
--
-- One row per order. Payment fields are summarised per order because an order can be paid with
-- several payments (96,479 of 99,440 paid orders have one; the rest split across methods).
--   payment_group      the single method used, or 'mixed' when an order combined methods
--   order_value_brl    total paid across all payments, in Brazilian reais
--   max_installments   highest installment count on any payment of the order

DROP VIEW IF EXISTS scope;
DROP TABLE IF EXISTS order_level;

CREATE TABLE order_level AS
WITH pay AS (
    SELECT order_id,
           COUNT(*)                       AS n_payments,
           COUNT(DISTINCT payment_type)   AS n_types,
           MIN(payment_type)              AS one_type,
           SUM(payment_value)             AS order_value_brl,
           MAX(payment_installments)      AS max_installments
    FROM order_payments
    GROUP BY order_id
)
SELECT o.order_id,
       c.customer_state,
       o.order_status,
       CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END           AS canceled,
       SUBSTR(o.order_purchase_timestamp, 1, 7)                          AS purchase_month,
       p.n_payments,
       CASE WHEN p.n_types = 1 THEN p.one_type ELSE 'mixed' END          AS payment_group,
       p.order_value_brl,
       p.max_installments,
       (julianday(o.order_approved_at) - julianday(o.order_purchase_timestamp)) * 24
                                                                         AS approval_hours,
       julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)
                                                                         AS delivery_days
FROM orders o
JOIN pay p       ON p.order_id = o.order_id
JOIN customers c ON c.customer_id = o.customer_id;

-- Analysis scope: orders bought January 2017 to August 2018 that reached a final outcome
-- (delivered or canceled). Earlier months have only a few hundred orders; later months are
-- cut off by the end of the data and contain mostly early cancellations, which would
-- overstate the cancellation rate. In-flight statuses and 'unavailable' (stock problems at the
-- seller, not a payment matter) are excluded.
CREATE VIEW scope AS
SELECT *
FROM order_level
WHERE purchase_month BETWEEN '2017-01' AND '2018-08'
  AND order_status IN ('delivered', 'canceled');
