-- =====================================================================
-- 07_satisfaction_drivers.sql : what moves the review score?
-- Population: v_analysis_orders with a review (one review per order,
-- see v_reviews_dedup). Review score is 1 (worst) to 5 (best).
-- Techniques: CASE bucketing, conditional aggregation, cross-tabs.
-- =====================================================================

-- name: score_distribution
SELECT review_score,
       count(*)                                           AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM v_analysis_orders
WHERE review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- name: score_by_lateness
-- days_late: negative = delivered before the promised date.
SELECT CASE WHEN days_late <= -8 THEN '1) 8+ days early'
            WHEN days_late <= -1 THEN '2) 1-7 days early'
            WHEN days_late =   0 THEN '3) on promised day'
            WHEN days_late <=  3 THEN '4) 1-3 days late'
            WHEN days_late <=  7 THEN '5) 4-7 days late'
            WHEN days_late <= 14 THEN '6) 8-14 days late'
            ELSE                      '7) 15+ days late' END AS delivery_vs_promise,
       count(*)                                              AS orders,
       round(avg(review_score), 2)                           AS avg_score,
       round(100.0 * avg(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END), 1) AS pct_1_2_star,
       round(100.0 * avg(CASE WHEN review_score = 5  THEN 1 ELSE 0 END), 1) AS pct_5_star
FROM v_analysis_orders
WHERE review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- name: late_vs_on_time_summary
SELECT CASE WHEN is_late = 1 THEN 'late' ELSE 'on time / early' END AS delivery,
       count(*)                                  AS orders,
       round(avg(review_score), 2)               AS avg_score,
       round(100.0 * avg(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END), 1) AS pct_1_2_star,
       round(100.0 * avg(CASE WHEN review_score = 5 THEN 1 ELSE 0 END), 1)   AS pct_5_star
FROM v_analysis_orders
WHERE review_score IS NOT NULL
GROUP BY 1
ORDER BY 1 DESC;

-- name: score_by_delivery_speed
-- Is it speed itself, or broken promises? First look at raw speed...
SELECT CASE WHEN delivery_days < 7  THEN '1) under 1 week'
            WHEN delivery_days < 14 THEN '2) 1-2 weeks'
            WHEN delivery_days < 21 THEN '3) 2-3 weeks'
            WHEN delivery_days < 30 THEN '4) 3-4 weeks'
            ELSE                         '5) 30+ days' END AS actual_delivery_time,
       count(*)                                  AS orders,
       round(avg(review_score), 2)               AS avg_score,
       round(100.0 * avg(is_late), 1)            AS late_pct
FROM v_analysis_orders
WHERE review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- name: slow_but_on_time_vs_slow_and_late
-- ...then hold speed constant (orders that took 21+ days) and compare
-- those that still met the promise against those that did not.
SELECT CASE WHEN is_late = 1 THEN 'took 21+ days AND late'
            ELSE                  'took 21+ days but on time' END AS group_name,
       count(*)                    AS orders,
       round(avg(review_score), 2) AS avg_score,
       round(100.0 * avg(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END), 1) AS pct_1_2_star
FROM v_analysis_orders
WHERE review_score IS NOT NULL AND delivery_days >= 21
GROUP BY 1
ORDER BY 1;

-- name: late_pct_by_score
-- Reverse view: among orders at each score, how many were late?
SELECT review_score,
       count(*)                         AS orders,
       round(100.0 * avg(is_late), 1)   AS late_pct,
       round(avg(delivery_days), 1)     AS avg_delivery_days
FROM v_analysis_orders
WHERE review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- name: score_by_freight_burden
-- Freight as % of item value. High shipping cost relative to price.
SELECT CASE WHEN freight_value / NULLIF(items_value, 0) < 0.10 THEN '1) under 10%'
            WHEN freight_value / NULLIF(items_value, 0) < 0.20 THEN '2) 10-20%'
            WHEN freight_value / NULLIF(items_value, 0) < 0.40 THEN '3) 20-40%'
            WHEN freight_value / NULLIF(items_value, 0) < 0.80 THEN '4) 40-80%'
            ELSE                                                    '5) 80%+' END AS freight_to_price,
       count(*)                      AS orders,
       round(avg(review_score), 2)   AS avg_score,
       round(100.0 * avg(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END), 1) AS pct_1_2_star
FROM v_analysis_orders
WHERE review_score IS NOT NULL AND items_value > 0
GROUP BY 1
ORDER BY 1;

-- name: score_by_order_complexity
-- Orders fulfilled by several sellers must be split into several shipments.
SELECT CASE WHEN n_sellers = 1 THEN '1 seller' ELSE '2+ sellers' END AS sellers_in_order,
       count(*)                      AS orders,
       round(avg(review_score), 2)   AS avg_score,
       round(100.0 * avg(is_late), 1) AS late_pct
FROM v_analysis_orders
WHERE review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- name: monthly_score_vs_late
SELECT date_trunc('month', purchased_at)::date AS month,
       count(*)                         AS orders,
       round(avg(review_score), 2)      AS avg_score,
       round(100.0 * avg(is_late), 1)   AS late_pct
FROM v_analysis_orders
WHERE review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- name: comment_rate_by_score
-- Unhappy customers write more. (Text-mining the comments is a natural next step.)
SELECT r.review_score,
       count(*) AS reviews,
       round(100.0 * avg(CASE WHEN r.review_comment_message IS NOT NULL
                               AND length(trim(r.review_comment_message)) > 0 THEN 1 ELSE 0 END), 1) AS pct_with_comment
FROM v_reviews_dedup r
JOIN v_analysis_orders a ON a.order_id = r.order_id
GROUP BY 1
ORDER BY 1;
