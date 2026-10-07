-- =====================================================================
-- 05_category_seller_analysis.sql : where does the money come from?
-- Population: items belonging to v_analysis_orders.
-- Techniques: RANK, NTILE, cumulative SUM() OVER (Pareto), self-join
--             for growth, HAVING thresholds to avoid tiny-sample noise.
-- =====================================================================

-- name: category_performance
-- GMV = sum(item price). Orders with items in several categories count once
-- per category (so category order counts can add to more than total orders).
WITH cat AS (
    SELECT d.category,
           count(DISTINCT d.order_id)              AS orders,
           count(*)                                AS items_sold,
           sum(d.price)                            AS gmv,
           avg(d.price)                            AS avg_price,
           100.0 * sum(d.freight_value) / sum(d.price) AS freight_pct_of_price,
           avg(a.review_score)                     AS avg_review,
           100.0 * avg(a.is_late)                  AS late_pct
    FROM v_item_detail d
    JOIN v_analysis_orders a ON a.order_id = d.order_id
    GROUP BY d.category
)
SELECT RANK() OVER (ORDER BY gmv DESC)                         AS gmv_rank,
       category, orders, items_sold,
       round(gmv, 0)                                           AS gmv,
       round(100.0 * gmv / sum(gmv) OVER (), 1)                AS pct_of_gmv,
       round(100.0 * sum(gmv) OVER (ORDER BY gmv DESC) / sum(gmv) OVER (), 1) AS cumulative_pct,
       round(avg_price, 0)                                     AS avg_price,
       round(freight_pct_of_price, 1)                          AS freight_pct_of_price,
       round(avg_review, 2)                                    AS avg_review,
       round(late_pct, 1)                                      AS late_pct
FROM cat
ORDER BY gmv DESC;

-- name: pareto_summary
-- How concentrated is revenue across categories?
WITH cat AS (
    SELECT d.category, sum(d.price) AS gmv
    FROM v_item_detail d
    JOIN v_analysis_orders a ON a.order_id = d.order_id
    GROUP BY d.category
), ranked AS (
    SELECT category, gmv,
           sum(gmv) OVER (ORDER BY gmv DESC) / sum(gmv) OVER () AS cum_share,
           ROW_NUMBER() OVER (ORDER BY gmv DESC)               AS rn,
           count(*) OVER ()                                    AS n_categories
    FROM cat
)
SELECT max(n_categories)                                  AS total_categories,
       min(rn) FILTER (WHERE cum_share >= 0.50)           AS categories_for_50pct_gmv,
       min(rn) FILTER (WHERE cum_share >= 0.80)           AS categories_for_80pct_gmv,
       round(100.0 * min(rn) FILTER (WHERE cum_share >= 0.80) / max(n_categories), 1) AS pct_of_categories_for_80pct
FROM ranked;

-- name: category_growth_jan_aug
-- Jan-Aug 2018 vs Jan-Aug 2017 GMV, for categories with >= 100k GMV in 2018.
WITH x AS (
    SELECT d.category,
           extract(year FROM a.purchased_at) AS yr,
           sum(d.price) AS gmv
    FROM v_item_detail d
    JOIN v_analysis_orders a ON a.order_id = d.order_id
    WHERE extract(month FROM a.purchased_at) BETWEEN 1 AND 8
    GROUP BY 1, 2
)
SELECT n.category,
       round(o.gmv, 0) AS gmv_2017,
       round(n.gmv, 0) AS gmv_2018,
       round(100.0 * (n.gmv - o.gmv) / o.gmv, 0) AS growth_pct,
       RANK() OVER (ORDER BY (n.gmv - o.gmv) DESC) AS abs_growth_rank
FROM x n
JOIN x o ON o.category = n.category AND o.yr = 2017 AND n.yr = 2018
WHERE n.gmv >= 100000
ORDER BY growth_pct DESC;

-- name: seller_concentration_deciles
-- Rank all sellers by GMV, cut into 10 equal-sized groups (NTILE).
WITH seller_gmv AS (
    SELECT d.seller_id, sum(d.price) AS gmv, count(DISTINCT d.order_id) AS orders
    FROM v_item_detail d
    JOIN v_analysis_orders a ON a.order_id = d.order_id
    GROUP BY d.seller_id
), tiled AS (
    SELECT *, NTILE(10) OVER (ORDER BY gmv DESC) AS decile FROM seller_gmv
)
SELECT decile,
       count(*)                                         AS sellers,
       round(sum(gmv), 0)                               AS gmv,
       round(100.0 * sum(gmv) / sum(sum(gmv)) OVER (), 1) AS pct_of_gmv,
       round(avg(orders), 1)                            AS avg_orders_per_seller
FROM tiled
GROUP BY decile
ORDER BY decile;

-- name: top_sellers
WITH seller_gmv AS (
    SELECT d.seller_id, s.seller_state,
           sum(d.price) AS gmv, count(DISTINCT d.order_id) AS orders,
           avg(a.review_score) AS avg_review, 100.0 * avg(a.is_late) AS late_pct
    FROM v_item_detail d
    JOIN v_analysis_orders a ON a.order_id = d.order_id
    JOIN sellers s ON s.seller_id = d.seller_id
    GROUP BY d.seller_id, s.seller_state
)
SELECT RANK() OVER (ORDER BY gmv DESC) AS gmv_rank,
       seller_id, seller_state, orders,
       round(gmv, 0) AS gmv,
       round(100.0 * gmv / sum(gmv) OVER (), 2) AS pct_of_total_gmv,
       round(avg_review, 2) AS avg_review,
       round(late_pct, 1)   AS late_pct
FROM seller_gmv
ORDER BY gmv DESC
LIMIT 15;

-- name: seller_geography
-- Supply is concentrated where? Compare share of sellers vs share of GMV.
WITH s AS (
    SELECT d.seller_state, count(DISTINCT d.seller_id) AS sellers, sum(d.price) AS gmv
    FROM v_item_detail d
    JOIN v_analysis_orders a ON a.order_id = d.order_id
    GROUP BY d.seller_state
)
SELECT seller_state, sellers,
       round(100.0 * sellers / sum(sellers) OVER (), 1) AS pct_of_sellers,
       round(gmv, 0) AS gmv,
       round(100.0 * gmv / sum(gmv) OVER (), 1)         AS pct_of_gmv
FROM s
ORDER BY gmv DESC
LIMIT 10;

-- name: problem_categories
-- High-volume categories with the weakest customer reviews.
-- (>= 500 orders so averages are stable.)
WITH cat AS (
    SELECT d.category,
           count(DISTINCT d.order_id) AS orders,
           avg(a.review_score)        AS avg_review,
           100.0 * avg(CASE WHEN a.review_score <= 2 THEN 1 ELSE 0 END) AS pct_1_2_star,
           100.0 * avg(a.is_late)     AS late_pct,
           sum(d.price)               AS gmv
    FROM v_item_detail d
    JOIN v_analysis_orders a ON a.order_id = d.order_id
    WHERE a.review_score IS NOT NULL
    GROUP BY d.category
    HAVING count(DISTINCT d.order_id) >= 500
)
SELECT category, orders,
       round(avg_review, 2)   AS avg_review,
       round(pct_1_2_star, 1) AS pct_1_2_star,
       round(late_pct, 1)     AS late_pct,
       round(gmv, 0)          AS gmv,
       RANK() OVER (ORDER BY avg_review ASC) AS worst_rank
FROM cat
ORDER BY avg_review ASC
LIMIT 10;
