-- =====================================================================
-- 01_data_audit.sql : what is wrong with this data BEFORE analysing it?
-- Read-only checks. Every finding here drives a decision in 02.
-- =====================================================================

-- name: row_counts
SELECT 'customers' AS tbl, count(*) AS n FROM customers
UNION ALL SELECT 'orders',         count(*) FROM orders
UNION ALL SELECT 'order_items',    count(*) FROM order_items
UNION ALL SELECT 'order_payments', count(*) FROM order_payments
UNION ALL SELECT 'order_reviews',  count(*) FROM order_reviews
UNION ALL SELECT 'products',       count(*) FROM products
UNION ALL SELECT 'sellers',        count(*) FROM sellers;

-- name: orphan_keys
-- Referential integrity: rows whose foreign key points at nothing.
SELECT 'items -> orders' AS check_name, count(*) AS orphans
FROM order_items i WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = i.order_id)
UNION ALL
SELECT 'items -> products', count(*)
FROM order_items i WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = i.product_id)
UNION ALL
SELECT 'items -> sellers', count(*)
FROM order_items i WHERE NOT EXISTS (SELECT 1 FROM sellers s WHERE s.seller_id = i.seller_id)
UNION ALL
SELECT 'orders -> customers', count(*)
FROM orders o WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id)
UNION ALL
SELECT 'payments -> orders', count(*)
FROM order_payments p WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = p.order_id)
UNION ALL
SELECT 'reviews -> orders', count(*)
FROM order_reviews r WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = r.order_id);

-- name: customer_id_vs_unique_id
-- GOTCHA: customer_id is generated per order. Counting it as "customers"
-- would overstate the customer base and make everyone look like a one-timer.
SELECT count(*)                           AS customer_id_rows,
       count(DISTINCT customer_unique_id) AS real_customers
FROM customers;

-- name: duplicate_reviews
-- GOTCHA: review_id is not unique, and an order can have several reviews.
SELECT count(*)                    AS review_rows,
       count(DISTINCT review_id)   AS distinct_review_ids,
       count(DISTINCT order_id)    AS orders_reviewed,
       (SELECT count(*) FROM (SELECT order_id FROM order_reviews
                              GROUP BY order_id HAVING count(*) > 1) t) AS orders_with_multiple_reviews
FROM order_reviews;

-- name: order_status_mix
SELECT order_status,
       count(*)                                   AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct,
       count(order_delivered_customer_date)       AS with_delivery_date
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- name: timestamp_logic_errors
SELECT
  count(*) FILTER (WHERE order_approved_at < order_purchase_timestamp)              AS approved_before_purchase,
  count(*) FILTER (WHERE order_delivered_carrier_date < order_purchase_timestamp)   AS carrier_before_purchase,
  count(*) FILTER (WHERE order_delivered_customer_date < order_delivered_carrier_date) AS customer_before_carrier,
  count(*) FILTER (WHERE order_status = 'delivered'
                    AND order_delivered_customer_date IS NULL)                      AS delivered_but_no_date,
  count(*) FILTER (WHERE order_status <> 'delivered'
                    AND order_delivered_customer_date IS NOT NULL)                  AS not_delivered_but_has_date
FROM orders;

-- name: orders_by_month
-- Which months are complete enough to analyse?
SELECT date_trunc('month', order_purchase_timestamp)::date AS month,
       count(*) AS orders
FROM orders
GROUP BY 1
ORDER BY 1;

-- name: category_gaps
SELECT count(*) FILTER (WHERE product_category_name IS NULL)  AS products_without_category,
       count(*) FILTER (WHERE product_category_name IS NOT NULL
                          AND product_category_name NOT IN
                              (SELECT product_category_name FROM category_translation))
                                                              AS category_without_translation
FROM products;

-- name: payment_oddities
SELECT count(*) FILTER (WHERE payment_value = 0)             AS zero_value_payments,
       count(*) FILTER (WHERE payment_type = 'not_defined')  AS undefined_payment_type,
       (SELECT count(*) FROM orders o WHERE NOT EXISTS
            (SELECT 1 FROM order_payments p WHERE p.order_id = o.order_id)) AS orders_without_payment
FROM order_payments;

-- name: orders_without_items
-- These can never contribute revenue; they are almost all cancelled/unavailable.
SELECT o.order_status, count(*) AS orders
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)
GROUP BY o.order_status
ORDER BY orders DESC;
