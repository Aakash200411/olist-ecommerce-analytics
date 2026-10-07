-- =====================================================================
-- 02_cleaning_views.sql : the cleaned layer every later query builds on.
-- Raw tables are never modified; cleaning rules live in views so every
-- decision is visible, reviewable and reversible.
--
-- Cleaning decisions (each one traces back to 01_data_audit.sql):
--  1. Reviews: keep ONE review per order (the most recently answered).
--  2. "Customer" = customer_unique_id, never customer_id.
--  3. Revenue (GMV) = sum of item price; freight is tracked separately.
--  4. Analysis set = delivered orders with a valid delivery timestamp
--     (drops 8 'delivered' orders with no date and any date-before-purchase).
--  5. Study window = Jan 2017 .. Aug 2018 (other months are near-empty).
--  6. Missing/untranslated categories are labelled 'unknown', not dropped.
--  7. "Late" compares DATES (delivered date > estimated date), because the
--     estimate is always stored at 00:00:00 and a same-day delivery is on time.
-- =====================================================================

-- name: v_reviews_dedup
CREATE OR REPLACE VIEW v_reviews_dedup AS
SELECT order_id, review_id, review_score, review_comment_message,
       review_creation_date, review_answer_timestamp
FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY review_answer_timestamp DESC, review_id) AS rn
    FROM order_reviews r
) t
WHERE rn = 1;

-- name: v_item_detail
CREATE OR REPLACE VIEW v_item_detail AS
SELECT i.order_id,
       i.order_item_id,
       i.product_id,
       i.seller_id,
       s.seller_state,
       i.price,
       i.freight_value,
       COALESCE(t.product_category_name_english,
                p.product_category_name,       -- untranslated: keep Portuguese name
                'unknown')                     AS category
FROM order_items i
JOIN products p  ON p.product_id = i.product_id
JOIN sellers  s  ON s.seller_id  = i.seller_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name;

-- name: v_order_summary
CREATE OR REPLACE VIEW v_order_summary AS
WITH item_totals AS (
    SELECT order_id,
           count(*)                  AS n_items,
           count(DISTINCT seller_id) AS n_sellers,
           sum(price)                AS items_value,
           sum(freight_value)        AS freight_value
    FROM order_items
    GROUP BY order_id
)
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       o.order_status,
       o.order_purchase_timestamp                        AS purchased_at,
       o.order_delivered_customer_date                   AS delivered_at,
       o.order_estimated_delivery_date                   AS estimated_at,
       it.n_items,
       it.n_sellers,
       it.items_value,
       it.freight_value,
       it.items_value + it.freight_value                 AS order_total,
       rv.review_score,
       -- delivery metrics (NULL unless the order was actually delivered)
       extract(epoch FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0
                                                         AS delivery_days,
       extract(epoch FROM (o.order_estimated_delivery_date - o.order_purchase_timestamp)) / 86400.0
                                                         AS promised_days,
       (CAST(o.order_delivered_customer_date AS DATE)
        - CAST(o.order_estimated_delivery_date AS DATE)) AS days_late,   -- negative = early
       CASE WHEN CAST(o.order_delivered_customer_date AS DATE)
                 > CAST(o.order_estimated_delivery_date AS DATE) THEN 1 ELSE 0 END AS is_late
FROM orders o
JOIN customers c           ON c.customer_id = o.customer_id
LEFT JOIN item_totals it   ON it.order_id   = o.order_id
LEFT JOIN v_reviews_dedup rv ON rv.order_id = o.order_id;

-- name: v_analysis_orders
CREATE OR REPLACE VIEW v_analysis_orders AS
SELECT *
FROM v_order_summary
WHERE order_status = 'delivered'
  AND delivered_at IS NOT NULL
  AND delivered_at >= purchased_at
  AND n_items IS NOT NULL
  AND purchased_at >= TIMESTAMP '2017-01-01'
  AND purchased_at <  TIMESTAMP '2018-09-01';

-- name: cleaning_impact
-- How many orders does each rule remove? (Transparency for the README.)
SELECT 'all orders'                              AS step, count(*) AS orders FROM orders
UNION ALL SELECT 'status = delivered',           count(*) FROM orders WHERE order_status = 'delivered'
UNION ALL SELECT '... with valid delivery date', count(*) FROM v_order_summary
          WHERE order_status = 'delivered' AND delivered_at IS NOT NULL AND delivered_at >= purchased_at AND n_items IS NOT NULL
UNION ALL SELECT '... within Jan-2017..Aug-2018 (analysis set)', count(*) FROM v_analysis_orders;
