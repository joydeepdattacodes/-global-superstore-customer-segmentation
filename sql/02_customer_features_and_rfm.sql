-- =====================================================================================
-- 02 | CUSTOMER FEATURES & RFM SCORING                      (roadmap Phases 3-4)
-- Reads    : retail_raw
-- Creates  : VIEW customer_features   (exactly 1 row per customer)
--            VIEW customer_rfm_scores (R, F, M scores, 5 = best)
--
-- BUSINESS QUESTION
--   Who are our customers in terms of value (how much), loyalty (how often) and
--   activity (how recently) - and which ones send conflicting signals?
--
-- WHY ONE VIEW INSTEAD OF MANY QUERIES
--   Every later step (segments, notebooks, insights) needs the same customer metrics.
--   Building them once, at the correct grain, avoids copy-paste drift and avoids
--   multiplying sales through joins.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 2.1  Customer feature table
--      Order-level measures divide by DISTINCT orders (not rows).
--      Margin = SUM(profit) / SUM(sales)  (weighted) - never an average of line margins.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW customer_features AS
WITH base AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(sales)  AS total_sales,
        SUM(profit) AS total_profit,
        SUM(quantity)  AS total_quantity,
        MIN(order_date) AS first_order_date,
        MAX(order_date)  AS last_order_date,
        COUNT(DISTINCT DATE_TRUNC('month', order_date))  AS active_months,
        AVG(discount)  AS avg_discount,
        COUNT(DISTINCT product_id) AS unique_products,
        COUNT(DISTINCT category) AS unique_categories,
        COUNT(DISTINCT sub_category) AS unique_sub_categories
    FROM retail_raw
    GROUP BY customer_id
),
category_sales AS (                       -- sales per customer per category
    SELECT customer_id,
		category,
		SUM(sales) AS category_sales
    FROM retail_raw
    GROUP BY customer_id, category
),
dominant AS (                             -- top category per customer
    SELECT DISTINCT ON (customer_id)      -- keeps the first row per customer after ORDER BY
           customer_id, category AS dominant_category, category_sales
    FROM category_sales
    ORDER BY customer_id, category_sales DESC, category ASC   -- category ASC = deterministic tie rule
)
SELECT
    b.customer_id,
    b.total_orders,
    b.total_sales,
    b.total_profit,
    b.total_quantity,
    ROUND((b.total_sales  / b.total_orders)::numeric, 2) AS avg_order_value,
    ROUND((b.total_profit / b.total_orders)::numeric, 2)AS avg_profit_per_order,
    ROUND(b.total_quantity::numeric / b.total_orders, 2) AS avg_items_per_order,
    ROUND((100.0 * b.total_profit / NULLIF(b.total_sales, 0))::numeric, 2) AS profit_margin_pct,
    ROUND(b.avg_discount::numeric, 3) AS avg_discount,
    b.first_order_date,
    b.last_order_date,
    b.last_order_date - b.first_order_date AS observed_span_days,   -- span, NOT lifetime
    b.active_months,
    ROUND(b.total_orders::numeric / b.active_months, 2) AS orders_per_active_month,
    b.unique_products,
    b.unique_categories,
    b.unique_sub_categories,
    d.dominant_category,
    ROUND((100.0 * d.category_sales / NULLIF(b.total_sales, 0))::numeric, 2)   AS dominant_category_pct
FROM base b
JOIN dominant d USING (customer_id);

-- Validation: must return one row per customer (4,873) with no duplicates
SELECT
	COUNT(*) AS rows_in_view,
	COUNT(DISTINCT customer_id) AS distinct_customers
FROM customer_features;

SELECT * FROM customer_features ORDER BY total_sales DESC LIMIT 10;


-- -------------------------------------------------------------------------------------
-- 2.2  RFM reference date
--      Day AFTER the latest order => the most recent buyer has recency = 1 day.
--      This is a reproducible convention, not proof customers were observed in 2015.
-- -------------------------------------------------------------------------------------
SELECT MAX(order_date) AS latest_order_date, MAX(order_date) + 1 AS rfm_analysis_date
FROM retail_raw;                                   -- expected: 2014-12-31 / 2015-01-01


-- -------------------------------------------------------------------------------------
-- 2.3  RFM scores
--      Recency   = days since last order      (smaller is better)
--      Frequency = distinct orders            (bigger  is better)
--      Monetary  = total sales                (bigger  is better)
--      NTILE(5) cuts customers into 5 equal groups. Every score is oriented so 5 = BEST:
--        R: 6 - NTILE over recency ASC   (lowest recency -> NTILE 1 -> score 5)
--        F, M: NTILE over ... ASC        (highest value  -> NTILE 5 -> score 5)
--      Limitation: NTILE splits tied values arbitrarily (many customers share the same
--      order count), so group boundaries are approximate for tied customers.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW customer_rfm_scores AS
WITH rfm AS (
    SELECT
        customer_id,
        DATE '2015-01-01' - last_order_date AS recency_days,
        total_orders AS frequency,
        total_sales  AS monetary_value,
        total_profit,
        profit_margin_pct
    FROM customer_features
)
SELECT
    customer_id,
    6 - NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
    NTILE(5)     OVER (ORDER BY frequency  ASC) AS f_score,
    NTILE(5)     OVER (ORDER BY monetary_value  ASC) AS m_score,
    recency_days,
    frequency,
    monetary_value,
    total_profit,
    profit_margin_pct
FROM rfm;

-- Sanity check: scores must point the right way (score 5 = best on every dimension)
SELECT 'R' AS dim, r_score AS score, MIN(recency_days) AS min_value, MAX(recency_days) AS max_value FROM customer_rfm_scores GROUP BY r_score
UNION ALL
SELECT 'F', f_score, MIN(frequency), MAX(frequency) FROM customer_rfm_scores GROUP BY f_score
UNION ALL
SELECT 'M', m_score, MIN(monetary_value), MAX(monetary_value) FROM customer_rfm_scores GROUP BY m_score
ORDER BY dim, score DESC;

-- Combined score vs. real money: do high-RFM customers actually earn more profit?
SELECT
    r_score + f_score + m_score AS rfm_score,
    COUNT(*)                    AS customers,
    ROUND(SUM(monetary_value)::numeric, 0)  AS sales,
    ROUND(SUM(total_profit)::numeric, 0)    AS profit,
    ROUND((100.0 * SUM(total_profit) / SUM(monetary_value))::numeric, 2) AS margin_pct
FROM customer_rfm_scores
GROUP BY 1
ORDER BY 1 DESC;


-- -------------------------------------------------------------------------------------
-- 2.4  Customers with CONFLICTING value signals
--      A high RFM score can hide a customer who costs money. Thresholds are computed
--      from the data (not hard-coded) so the logic stays reproducible.
--        Signal A: above-average sales but loss-making
--        Signal B: above-average sales but not seen for longer than the 75th-pct recency
--        Signal C: high RFM (>= 12) but margin below the 25th-percentile margin
-- -------------------------------------------------------------------------------------
WITH thresholds AS (
    SELECT
        AVG(monetary_value)                                            AS avg_sales,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY recency_days)     AS recency_p75,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY profit_margin_pct) AS margin_p25
    FROM customer_rfm_scores
)
SELECT s.customer_id, s.r_score + s.f_score + s.m_score AS rfm_score,
       s.monetary_value AS sales, s.total_profit AS profit,
       s.recency_days, s.profit_margin_pct,
       'A: high sales but loss-making' AS signal_type
FROM customer_rfm_scores s CROSS JOIN thresholds t
WHERE s.total_profit < 0 AND s.monetary_value > t.avg_sales

UNION ALL
SELECT s.customer_id, s.r_score + s.f_score + s.m_score,
       s.monetary_value, s.total_profit, s.recency_days, s.profit_margin_pct,
       'B: high sales but lapsed'
FROM customer_rfm_scores s CROSS JOIN thresholds t
WHERE s.recency_days > t.recency_p75 AND s.monetary_value > t.avg_sales

UNION ALL
SELECT s.customer_id, s.r_score + s.f_score + s.m_score,
       s.monetary_value, s.total_profit, s.recency_days, s.profit_margin_pct,
       'C: high RFM but low margin'
FROM customer_rfm_scores s CROSS JOIN thresholds t
WHERE s.r_score + s.f_score + s.m_score >= 12 AND s.profit_margin_pct < t.margin_p25

ORDER BY signal_type, sales DESC;

-- How many customers per signal? (a customer can appear in more than one)

WITH thresholds AS (
    SELECT
        AVG(monetary_value)                                            AS avg_sales,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY recency_days)     AS recency_p75,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY profit_margin_pct) AS margin_p25
    FROM customer_rfm_scores
),
signals AS(
SELECT s.customer_id, s.r_score + s.f_score + s.m_score AS rfm_score,
       s.monetary_value AS sales, s.total_profit AS profit,
       s.recency_days, s.profit_margin_pct,
       'A: high sales but loss-making' AS signal_type
FROM customer_rfm_scores s CROSS JOIN thresholds t
WHERE s.total_profit < 0 AND s.monetary_value > t.avg_sales

UNION ALL
SELECT s.customer_id, s.r_score + s.f_score + s.m_score,
       s.monetary_value, s.total_profit, s.recency_days, s.profit_margin_pct,
       'B: high sales but lapsed'
FROM customer_rfm_scores s CROSS JOIN thresholds t
WHERE s.recency_days > t.recency_p75 AND s.monetary_value > t.avg_sales

UNION ALL
SELECT s.customer_id, s.r_score + s.f_score + s.m_score,
       s.monetary_value, s.total_profit, s.recency_days, s.profit_margin_pct,
       'C: high RFM but low margin'
FROM customer_rfm_scores s CROSS JOIN thresholds t
WHERE s.r_score + s.f_score + s.m_score >= 12 AND s.profit_margin_pct < t.margin_p25
)

SELECT
    signal_type,
    COUNT(DISTINCT customer_id) AS customers,
    ROUND(SUM(sales)::numeric, 2) AS total_sales,
    ROUND(SUM(profit)::numeric, 2) AS total_profit
FROM signals
GROUP BY signal_type
ORDER BY signal_type;


-- ------------------------------------------------------------------------------------
-- RFM scores VS sales,profit,customers,profit margin
-- ------------------------------------------------------------------------------------
SELECT
    r_score + f_score + m_score AS rfm_score,
    COUNT(*) AS customers,
    ROUND(SUM(monetary_value)::numeric, 2) AS total_sales,
    ROUND(SUM(total_profit)::numeric, 2) AS total_profit,
    ROUND(
        100.0 * SUM(total_profit) /
        NULLIF(SUM(monetary_value), 0), 2
    ) AS profit_margin_pct
FROM customer_rfm_scores
GROUP BY 1
ORDER BY 1 DESC;
