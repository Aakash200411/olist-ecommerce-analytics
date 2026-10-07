-- =====================================================================
-- 03_revenue_trends.sql : how is the business growing, and when?
-- Population: v_analysis_orders (delivered, Jan-2017 .. Aug-2018).
-- Revenue = GMV = sum of item prices (freight reported separately).
-- Techniques: date_trunc, LAG, running SUM() OVER, moving AVG, FILTER.
-- =====================================================================

-- name: monthly_revenue
WITH monthly AS (
    SELECT date_trunc('month', purchased_at)::date AS month,
           count(*)                       AS orders,
           count(DISTINCT customer_unique_id) AS customers,
           sum(items_value)               AS gmv,
           sum(freight_value)             AS freight,
           avg(items_value)               AS avg_order_value
    FROM v_analysis_orders
    GROUP BY 1
)
SELECT month,
       orders,
       customers,
       round(gmv, 0)                                   AS gmv,
       round(avg_order_value, 2)                       AS avg_order_value,
       round(100.0 * (gmv - LAG(gmv) OVER w) / NULLIF(LAG(gmv) OVER w, 0), 1) AS gmv_mom_pct,
       round(sum(gmv) OVER (ORDER BY month), 0)        AS gmv_running_total,
       round(avg(gmv) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0)
                                                       AS gmv_3m_moving_avg,
       round(100.0 * freight / NULLIF(gmv, 0), 1)      AS freight_pct_of_gmv
FROM monthly
WINDOW w AS (ORDER BY month)
ORDER BY month;

-- name: year_over_year_jan_aug
-- Like-for-like: Jan-Aug 2018 vs Jan-Aug 2017 (both full 8-month spans).
WITH x AS (
    SELECT extract(year FROM purchased_at) AS yr,
           count(*) AS orders, sum(items_value) AS gmv, avg(items_value) AS aov
    FROM v_analysis_orders
    WHERE extract(month FROM purchased_at) BETWEEN 1 AND 8
    GROUP BY 1
)
SELECT a.yr AS year_2018,
       a.orders AS orders_2018, b.orders AS orders_2017,
       round(100.0 * (a.orders - b.orders) / b.orders, 1) AS orders_growth_pct,
       round(a.gmv, 0) AS gmv_2018, round(b.gmv, 0) AS gmv_2017,
       round(100.0 * (a.gmv - b.gmv) / b.gmv, 1)          AS gmv_growth_pct,
       round(a.aov, 2) AS aov_2018, round(b.aov, 2) AS aov_2017
FROM x a JOIN x b ON a.yr = 2018 AND b.yr = 2017;

-- name: peak_days
-- Top 10 days by order count (expect Black Friday 2017).
SELECT CAST(purchased_at AS DATE) AS day,
       count(*)                   AS orders,
       round(sum(items_value), 0) AS gmv
FROM v_analysis_orders
GROUP BY 1
ORDER BY orders DESC
LIMIT 10;

-- name: day_of_week_pattern
-- 0 = Sunday ... 6 = Saturday
SELECT extract(dow FROM purchased_at)::int AS dow,
       count(*) AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_of_orders,
       round(avg(items_value), 2) AS avg_order_value
FROM v_analysis_orders
GROUP BY 1
ORDER BY 1;

-- name: hour_of_day_pattern
SELECT extract(hour FROM purchased_at)::int AS hour,
       count(*) AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_of_orders
FROM v_analysis_orders
GROUP BY 1
ORDER BY 1;

-- name: payment_mix
-- Payments of delivered analysis orders. Orders can be paid with several methods.
SELECT p.payment_type,
       count(*)                              AS payments,
       count(DISTINCT p.order_id)            AS orders,
       round(sum(p.payment_value), 0)        AS value,
       round(100.0 * sum(p.payment_value) / sum(sum(p.payment_value)) OVER (), 1) AS pct_of_value,
       round(avg(p.payment_installments), 1) AS avg_installments
FROM order_payments p
JOIN v_analysis_orders a ON a.order_id = p.order_id
GROUP BY p.payment_type
ORDER BY value DESC;

-- name: installments_vs_order_size
-- Do customers use installments (parcelas) more on bigger purchases?
SELECT CASE WHEN p.payment_installments = 1 THEN '1 (pay in full)'
            WHEN p.payment_installments BETWEEN 2 AND 4  THEN '2-4'
            WHEN p.payment_installments BETWEEN 5 AND 8  THEN '5-8'
            ELSE '9+' END                       AS installments,
       count(*)                                 AS credit_card_payments,
       round(avg(p.payment_value), 2)           AS avg_payment_value
FROM order_payments p
JOIN v_analysis_orders a ON a.order_id = p.order_id
WHERE p.payment_type = 'credit_card'
GROUP BY 1
ORDER BY avg_payment_value;
