-- =====================================================================
-- 04_delivery_performance.sql : how reliable is delivery, and where?
-- Population: v_analysis_orders. "Late" = delivered date after the
-- promised (estimated) date, compared at DATE level (see 02).
-- Techniques: percentile_cont, RANK, CTEs, conditional aggregation.
-- =====================================================================

-- name: overall_delivery
SELECT count(*)                                             AS orders,
       round(avg(delivery_days), 1)                         AS avg_delivery_days,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY delivery_days)::numeric, 1) AS median_delivery_days,
       round(percentile_cont(0.9) WITHIN GROUP (ORDER BY delivery_days)::numeric, 1) AS p90_delivery_days,
       round(avg(promised_days), 1)                         AS avg_promised_days,
       round(100.0 * avg(is_late), 2)                       AS late_pct,
       round(avg(days_late) FILTER (WHERE is_late = 1), 1)  AS avg_days_late_when_late,
       round(100.0 * avg(CASE WHEN days_late <= -7 THEN 1 ELSE 0 END), 1) AS pct_delivered_a_week_early
FROM v_analysis_orders;

-- name: monthly_late_rate
SELECT date_trunc('month', purchased_at)::date AS month,
       count(*)                                AS orders,
       round(avg(delivery_days), 1)            AS avg_delivery_days,
       round(100.0 * avg(is_late), 1)          AS late_pct
FROM v_analysis_orders
GROUP BY 1
ORDER BY 1;

-- name: delivery_stage_breakdown
-- Where do the days go? Seller handling vs carrier transit.
SELECT round(avg(extract(epoch FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400.0), 2)
           AS purchase_to_approval_days,
       round(avg(extract(epoch FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400.0), 2)
           AS approval_to_carrier_days,       -- seller handling time
       round(avg(extract(epoch FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400.0), 2)
           AS carrier_to_customer_days        -- logistics transit time
FROM orders o
JOIN v_analysis_orders a ON a.order_id = o.order_id
WHERE o.order_approved_at IS NOT NULL
  AND o.order_delivered_carrier_date >= o.order_approved_at
  AND o.order_delivered_customer_date >= o.order_delivered_carrier_date;

-- name: state_delivery_ranking
-- By customer state; states with fewer than 300 orders are excluded
-- as too small for a stable rate.
SELECT customer_state,
       count(*)                          AS orders,
       round(avg(delivery_days), 1)      AS avg_delivery_days,
       round(avg(promised_days), 1)      AS avg_promised_days,
       round(100.0 * avg(is_late), 1)    AS late_pct,
       round(avg(items_value), 0)        AS avg_order_value,
       round(avg(freight_value), 1)      AS avg_freight,
       RANK() OVER (ORDER BY avg(is_late) DESC) AS late_rank
FROM v_analysis_orders
GROUP BY customer_state
HAVING count(*) >= 300
ORDER BY late_pct DESC;

-- name: same_state_vs_cross_state
-- Single-seller orders only, so "seller state" is unambiguous.
WITH single AS (
    SELECT a.order_id, a.customer_state, a.delivery_days, a.is_late, a.freight_value, a.items_value,
           max(d.seller_state) AS seller_state
    FROM v_analysis_orders a
    JOIN v_item_detail d ON d.order_id = a.order_id
    WHERE a.n_sellers = 1
    GROUP BY a.order_id, a.customer_state, a.delivery_days, a.is_late, a.freight_value, a.items_value
)
SELECT CASE WHEN customer_state = seller_state THEN 'same state' ELSE 'cross-state' END AS route,
       count(*)                       AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_of_orders,
       round(avg(delivery_days), 1)   AS avg_delivery_days,
       round(100.0 * avg(is_late), 1) AS late_pct,
       round(avg(freight_value), 1)   AS avg_freight,
       round(100.0 * sum(freight_value) / sum(items_value), 1) AS freight_pct_of_item_value
FROM single
GROUP BY 1
ORDER BY 1;

-- name: seller_late_ranking
-- Sellers with 50+ delivered orders. An order with several sellers counts
-- once for each seller involved.
WITH seller_orders AS (
    SELECT DISTINCT d.seller_id, a.order_id, a.is_late, a.delivery_days
    FROM v_item_detail d
    JOIN v_analysis_orders a ON a.order_id = d.order_id
), seller_stats AS (
    SELECT seller_id,
           count(*)                       AS orders,
           round(100.0 * avg(is_late), 1) AS late_pct,
           round(avg(delivery_days), 1)   AS avg_delivery_days
    FROM seller_orders
    GROUP BY seller_id
    HAVING count(*) >= 50
)
SELECT RANK() OVER (ORDER BY late_pct DESC) AS late_rank,
       s.seller_id, st.seller_state, s.orders, s.late_pct, s.avg_delivery_days
FROM seller_stats s
JOIN sellers st ON st.seller_id = s.seller_id
ORDER BY late_rank, orders DESC
LIMIT 20;

-- name: seller_late_distribution
-- Is lateness concentrated in a few sellers, or spread across everyone?
WITH seller_orders AS (
    SELECT DISTINCT d.seller_id, a.order_id, a.is_late
    FROM v_item_detail d
    JOIN v_analysis_orders a ON a.order_id = d.order_id
), seller_stats AS (
    SELECT seller_id, count(*) AS orders, sum(is_late) AS late_orders,
           100.0 * avg(is_late) AS late_pct
    FROM seller_orders
    GROUP BY seller_id
    HAVING count(*) >= 50
)
SELECT CASE WHEN late_pct < 5  THEN '1) under 5% late'
            WHEN late_pct < 10 THEN '2) 5-10% late'
            WHEN late_pct < 20 THEN '3) 10-20% late'
            ELSE                    '4) 20%+ late' END AS seller_band,
       count(*)                            AS sellers,
       sum(orders)                         AS orders,
       sum(late_orders)                    AS late_orders,
       round(100.0 * sum(late_orders) / sum(sum(late_orders)) OVER (), 1) AS pct_of_all_late_orders
FROM seller_stats
GROUP BY 1
ORDER BY 1;
