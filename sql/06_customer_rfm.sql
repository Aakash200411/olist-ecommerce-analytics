-- =====================================================================
-- 06_customer_rfm.sql : who are the customers and what are they worth?
-- Customer = customer_unique_id. Population: v_analysis_orders.
-- Snapshot date for recency = 2018-09-01 (day after the study window).
-- Techniques: NTILE scoring, CASE segmentation, ROW_NUMBER / LAG for
--             purchase sequences, cohort-style comparison.
-- NOTE: NTILE gets a customer_unique_id tie-breaker so ties (many customers share
-- the same recency/spend) split the same way on every run.
-- NOTE: ~97% of customers bought exactly once in this data, so classic
-- RFM is dominated by recency + monetary. Frequency is scored 1/2/3+.
-- =====================================================================

-- name: purchase_frequency
WITH per_customer AS (
    SELECT customer_unique_id, count(*) AS orders, sum(items_value) AS spend
    FROM v_analysis_orders
    GROUP BY 1
)
SELECT CASE WHEN orders >= 3 THEN '3+' ELSE CAST(orders AS VARCHAR) END AS orders_placed,
       count(*)                                           AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_customers,
       round(sum(spend), 0)                               AS total_spend,
       round(100.0 * sum(spend) / sum(sum(spend)) OVER (), 1) AS pct_of_revenue
FROM per_customer
GROUP BY 1
ORDER BY 1;

-- name: days_to_second_purchase
-- Among repeat customers, how long until the 2nd order?
WITH seq AS (
    SELECT customer_unique_id, purchased_at,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchased_at) AS n
    FROM v_analysis_orders
), gaps AS (
    SELECT a.customer_unique_id,
           extract(epoch FROM (b.purchased_at - a.purchased_at)) / 86400.0 AS days_gap
    FROM seq a JOIN seq b
      ON a.customer_unique_id = b.customer_unique_id AND a.n = 1 AND b.n = 2
)
SELECT count(*)                                          AS repeat_customers,
       round(avg(days_gap), 0)                           AS avg_days,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY days_gap)::numeric, 0) AS median_days,
       round(100.0 * avg(CASE WHEN days_gap < 1 THEN 1 ELSE 0 END), 1) AS pct_within_24h,
       round(100.0 * avg(CASE WHEN days_gap <= 30 THEN 1 ELSE 0 END), 1) AS pct_within_30d,
       round(100.0 * avg(CASE WHEN days_gap > 180 THEN 1 ELSE 0 END), 1) AS pct_after_180d
FROM gaps;

-- name: rfm_customer_scores
-- One row per customer with R, F, M scores (4 = best). Saved as a view
-- so later queries and the Python notebook can reuse it.
CREATE OR REPLACE VIEW rfm_scores AS
WITH base AS (
    SELECT customer_unique_id,
           CAST(DATE '2018-09-01' - CAST(max(purchased_at) AS DATE) AS INTEGER) AS recency_days,
           count(*)           AS frequency,
           sum(items_value)   AS monetary
    FROM v_analysis_orders
    GROUP BY 1
), scored AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY recency_days DESC, customer_unique_id) AS r_score,   -- low days = high score
           CASE WHEN frequency >= 3 THEN 3 WHEN frequency = 2 THEN 2 ELSE 1 END AS f_score,
           NTILE(4) OVER (ORDER BY monetary ASC, customer_unique_id) AS m_score
    FROM base
)
SELECT *,
       CASE
         WHEN f_score >= 2 AND r_score >= 3 THEN '1 Loyal repeat buyers'
         WHEN f_score >= 2 AND r_score <= 2 THEN '2 Lapsed repeat buyers'
         WHEN r_score >= 3 AND m_score >= 3 THEN '3 Recent big spenders'
         WHEN r_score >= 3                  THEN '4 Recent small spenders'
         WHEN m_score >= 3                  THEN '5 Lapsed big spenders (win-back)'
         ELSE                                    '6 Lapsed small spenders'
       END AS segment
FROM scored;

-- name: rfm_segment_summary
SELECT segment,
       count(*)                                              AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)    AS pct_customers,
       round(sum(monetary), 0)                               AS revenue,
       round(100.0 * sum(monetary) / sum(sum(monetary)) OVER (), 1) AS pct_revenue,
       round(avg(monetary), 0)                               AS avg_spend,
       round(avg(recency_days), 0)                           AS avg_recency_days,
       round(avg(frequency), 2)                              AS avg_orders
FROM rfm_scores
GROUP BY segment
ORDER BY segment;

-- name: new_vs_returning_revenue
-- Share of each month's revenue coming from customers who had ordered before.
WITH o AS (
    SELECT customer_unique_id, purchased_at, items_value,
           date_trunc('month', purchased_at)::date AS month,
           min(purchased_at) OVER (PARTITION BY customer_unique_id) AS first_purchase
    FROM v_analysis_orders
)
SELECT month,
       count(*)                                               AS orders,
       count(*) FILTER (WHERE purchased_at > first_purchase)  AS returning_orders,
       round(100.0 * count(*) FILTER (WHERE purchased_at > first_purchase) / count(*), 1) AS returning_order_pct,
       round(100.0 * sum(items_value) FILTER (WHERE purchased_at > first_purchase) / sum(items_value), 1) AS returning_revenue_pct
FROM o
GROUP BY month
ORDER BY month;

-- name: repeat_rate_by_first_category
-- Which first-purchase categories lead to a second order?
-- Fair comparison: only customers whose FIRST order was Jan-Jun 2017, so
-- every customer had 14+ months to come back.
WITH firsts AS (
    SELECT customer_unique_id, order_id, purchased_at,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchased_at) AS n
    FROM v_analysis_orders
), cohort AS (
    SELECT f.customer_unique_id, f.order_id
    FROM firsts f
    WHERE f.n = 1 AND f.purchased_at < TIMESTAMP '2017-07-01'
), cust_orders AS (
    SELECT customer_unique_id, count(*) AS total_orders
    FROM v_analysis_orders GROUP BY 1
)
SELECT d.category,
       count(*)                                         AS customers,
       round(100.0 * avg(CASE WHEN co.total_orders >= 2 THEN 1 ELSE 0 END), 2) AS repeat_rate_pct
FROM cohort c
JOIN v_item_detail d    ON d.order_id = c.order_id AND d.order_item_id = 1
JOIN cust_orders co     ON co.customer_unique_id = c.customer_unique_id
GROUP BY d.category
HAVING count(*) >= 100
ORDER BY repeat_rate_pct DESC;

-- name: repeat_rate_by_first_order_experience
-- Does a bad FIRST experience reduce the chance of a second order?
-- Same Jan-Jun 2017 first-order cohort (equal observation time).
WITH firsts AS (
    SELECT customer_unique_id, review_score, is_late, purchased_at,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchased_at) AS n
    FROM v_analysis_orders
), cohort AS (
    SELECT * FROM firsts WHERE n = 1 AND purchased_at < TIMESTAMP '2017-07-01'
), cust_orders AS (
    SELECT customer_unique_id, count(*) AS total_orders FROM v_analysis_orders GROUP BY 1
)
SELECT CASE WHEN c.review_score IS NULL THEN 'no review'
            WHEN c.review_score <= 2 THEN '1-2 stars'
            WHEN c.review_score = 3  THEN '3 stars'
            ELSE '4-5 stars' END                        AS first_order_review,
       count(*)                                         AS customers,
       round(100.0 * avg(CASE WHEN co.total_orders >= 2 THEN 1 ELSE 0 END), 2) AS repeat_rate_pct
FROM cohort c
JOIN cust_orders co ON co.customer_unique_id = c.customer_unique_id
GROUP BY 1
ORDER BY 1;
