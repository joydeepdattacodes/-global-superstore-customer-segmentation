-- =====================================================================================
-- 03 | EXPLAINABLE RFM SEGMENTATION                          (roadmap Phase 5)
-- Reads    : customer_features, customer_rfm_scores   (script 02)
-- Creates  : VIEW customer_rfm_segments   (read by Python notebooks 02 and 03)
--
-- BUSINESS QUESTION
--   Which groups of customers deserve which treatment (reward, win back, nurture,
--   ignore) - and how much of the business does each group carry?
--
-- DESIGN
--   Rules are evaluated TOP-DOWN in a CASE expression: the first rule that matches wins,
--   so every customer lands in exactly ONE segment (mutually exclusive, fully covering).
--   Segments are analytical descriptions, not validated predictions of future behavior.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 3.1  Segment definition
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW customer_rfm_segments AS
SELECT
    customer_id,
    r_score,
    f_score,
    m_score,
    r_score + f_score + m_score AS rfm_score,

    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'CHAMPIONS'            -- recent, frequent, big spenders
        WHEN f_score >= 4 AND r_score >= 3 AND m_score >= 3 THEN 'LOYAL CUSTOMER'       -- frequent and still active
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'AT-RISK VALUABLE CUSTOMER' -- good history, gone quiet
        WHEN r_score >= 4 AND f_score >= 2 AND m_score >= 2 THEN 'POTENTIAL LOYALIST'   -- recent, can grow
        WHEN r_score + f_score + m_score BETWEEN 7 AND 9    THEN 'NEEDS ATTENTION'      -- middle of the pack
        ELSE 'LOW ENGAGEMENT CUSTOMER'                                                  -- catch-all (see limitation below)
    END AS segment,

    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'R>=4, F>=4, M>=4'
        WHEN f_score >= 4 AND r_score >= 3 AND m_score >= 3 THEN 'F>=4, R>=3, M>=3; excluding Champions'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'R<=2, F>=3, M>=3'
        WHEN r_score >= 4 AND f_score >= 2 AND m_score >= 2 THEN 'R>=4, F>=2, M>=2; excluding earlier segments'
        WHEN r_score + f_score + m_score BETWEEN 7 AND 9    THEN 'RFM score 7-9; excluding earlier segments'
        ELSE 'No earlier rule matched'
    END AS segment_rule
FROM customer_rfm_scores;

-- LIMITATION: the ELSE bucket mixes very different customers (e.g. R=3,F=3,M=5 lands here
-- although they spend a lot). A sensitivity test / extra rule is a planned improvement.

-- Coverage check: every customer in exactly one segment (total must equal 4,873)
SELECT COUNT(*) AS customers_in_view, COUNT(DISTINCT customer_id) AS distinct_customers
FROM customer_rfm_segments;


-- -------------------------------------------------------------------------------------
-- 3.2  Segment size and commercial contribution
--      Q: Which segments carry the customers, the sales and the PROFIT?
--      Joins customer_features (1 row/customer), so no sales are duplicated.
-- -------------------------------------------------------------------------------------
SELECT
    s.segment,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_pct,
    ROUND(SUM(f.total_sales)::numeric, 0) AS sales,
    ROUND((100.0 * SUM(f.total_sales)  / SUM(SUM(f.total_sales))  OVER ())::numeric, 2) AS sales_pct,
    ROUND(SUM(f.total_profit)::numeric, 0) AS profit,
    ROUND((100.0 * SUM(f.total_profit) / SUM(SUM(f.total_profit)) OVER ())::numeric, 2) AS profit_pct
FROM customer_rfm_segments s
JOIN customer_features f USING (customer_id)
GROUP BY s.segment
ORDER BY sales DESC;
-- READ IT AS: a segment whose profit_pct is below its customer_pct costs more than it earns.


-- -------------------------------------------------------------------------------------
-- 3.3  Segment behavior profile
--      Q: How do segments differ in recency, frequency, value and basket size?
-- -------------------------------------------------------------------------------------
SELECT
    s.segment,
    ROUND(AVG(DATE '2015-01-01' - f.last_order_date), 1)  AS avg_recency_days,
    ROUND(AVG(f.total_orders), 2) AS avg_orders,
    ROUND(AVG(f.total_sales)::numeric, 0) AS avg_sales,
    ROUND(AVG(f.total_profit)::numeric, 0)  AS avg_profit,
    ROUND(AVG(f.avg_order_value)::numeric, 0) AS avg_order_value
FROM customer_rfm_segments s
JOIN customer_features f USING (customer_id)
GROUP BY s.segment
ORDER BY avg_sales DESC;


-- -------------------------------------------------------------------------------------
-- 3.4  Which segments sell a lot but earn little? (margin + discount exposure)
--      Margin = SUM(profit)/SUM(sales) per segment (weighted). Discount is line-level.
-- -------------------------------------------------------------------------------------
SELECT
    s.segment,
    ROUND(SUM(r.sales)::numeric, 0)                                      AS sales,
    ROUND(SUM(r.profit)::numeric, 0)                                     AS profit,
    ROUND((100.0 * SUM(r.profit) / SUM(r.sales))::numeric, 2)            AS profit_margin_pct,
    ROUND((100.0 * AVG(r.discount))::numeric, 1)                         AS avg_discount_pct
FROM retail_raw r
JOIN customer_rfm_segments s USING (customer_id)
GROUP BY s.segment
ORDER BY profit_margin_pct ASC;


-- -------------------------------------------------------------------------------------
-- 3.5  Top customers inside each segment (action lists for the business)
--      RANK() gives ties the same rank (and skips numbers); use ROW_NUMBER() if you need
--      exactly N rows per segment.
-- -------------------------------------------------------------------------------------
WITH ranked AS (
    SELECT
        s.segment,
        f.customer_id,
        ROUND(f.total_sales::numeric, 0)   AS sales,
        ROUND(f.total_profit::numeric, 0)  AS profit,
        RANK() OVER (PARTITION BY s.segment ORDER BY f.total_sales  DESC) AS sales_rank,
        RANK() OVER (PARTITION BY s.segment ORDER BY f.total_profit DESC) AS profit_rank
    FROM customer_rfm_segments s
    JOIN customer_features f USING (customer_id)
)
SELECT *
FROM ranked
WHERE sales_rank <= 3
ORDER BY segment, sales_rank;
