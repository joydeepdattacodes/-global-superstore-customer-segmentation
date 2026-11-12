-- =====================================================================================
-- 04 | BUSINESS INSIGHTS: where does revenue fail to become profit?   (roadmap Phases 6-8)
-- Reads    : retail_raw, customer_features   (script 02)
--
-- Six questions a manager could act on. Each has: the question, why it matters,
-- the query, and how to read the result.
--
--   Q1  Do discounts destroy margin?                      -> discount policy
--   Q2  Which big customers lose money?                   -> account / pricing review
--   Q3  How concentrated is our business?                 -> dependence & retention risk
--   Q4  Which categories sell well but earn little?       -> product / pricing review
--   Q5  Which markets pair heavy discounting with weak margin? -> regional strategy
--   Q6  Which large markets have low-value customers?     -> growth targeting
--
-- NOTE: "segment" in the raw table = business segment (Consumer / Corporate / Home Office).
--       RFM segments live in the view customer_rfm_segments (script 03).
-- NOTE: discount comparisons are OBSERVATIONAL - they show association, not causation.
-- =====================================================================================


-- =====================================================================================
-- Q1. Do discounts destroy margin?
-- WHY : Discounts lift sales volume but may push lines below cost.
-- HOW : Group transaction lines into discount bands; compare aggregate margin per band.
--       (aggregate margin = SUM(profit)/SUM(sales); NULLIF guards divide-by-zero)
-- READ: a band with negative margin loses money on every dollar sold in it.
-- =====================================================================================
WITH banded AS (
    SELECT
        CASE
            WHEN discount = 0    THEN '1. No discount'
            WHEN discount <= 0.20 THEN '2. Low (0-20%]'
            WHEN discount <= 0.40 THEN '3. Medium (20-40%]'
            ELSE                       '4. High (>40%)'
        END AS discount_band,
        sales, profit, discount
    FROM retail_raw
)
SELECT
    discount_band,
    COUNT(*) AS transaction_lines,
    ROUND(SUM(sales)::numeric, 0) AS total_sales,
    ROUND(SUM(profit)::numeric, 0) AS total_profit,
    ROUND((100.0 * SUM(profit) / NULLIF(SUM(sales), 0))::numeric, 2) AS profit_margin_pct,
    ROUND((100.0 * AVG(discount))::numeric, 1) AS avg_discount_pct
FROM banded
GROUP BY discount_band
ORDER BY discount_band;

-- Q1b. Which categories drive the losses in the medium/high bands?
SELECT
    CASE WHEN discount <= 0.40 THEN 'Medium (20-40%]' ELSE 'High (>40%)' END AS discount_band,
    category,
    COUNT(*) AS transaction_lines,
    ROUND(SUM(sales)::numeric, 0) AS total_sales,
    ROUND(SUM(profit)::numeric, 0)  AS total_profit,
    ROUND((100.0 * SUM(profit) / NULLIF(SUM(sales), 0))::numeric, 2) AS profit_margin_pct
FROM retail_raw
WHERE discount > 0.20
GROUP BY 1, 2
ORDER BY total_profit ASC;                     -- biggest losses first


-- =====================================================================================
-- Q2. Which high-sales customers are loss-making or low-margin?
-- WHY : Ranking customers by sales alone rewards the wrong people.
-- HOW : "High sales" = top quartile of customer sales (75th percentile, computed, not guessed).
--       "Low margin" = under 5% aggregate margin (business benchmark - adjust as needed).
-- READ: these accounts need a pricing / discount review before more growth is chased.
-- =====================================================================================
WITH threshold AS (
    SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_sales) AS high_sales_cutoff
    FROM customer_features
)
SELECT
    f.customer_id,
    f.total_orders,
    ROUND(f.total_sales::numeric, 0)   AS total_sales,
    ROUND(f.total_profit::numeric, 0)  AS total_profit,
    f.profit_margin_pct,
    f.avg_discount,
    CASE WHEN f.total_profit < 0 THEN 'Loss-making'
         ELSE 'Low-margin (<5%)' END   AS status
FROM customer_features f
CROSS JOIN threshold t
WHERE f.total_sales >= t.high_sales_cutoff
  AND (f.total_profit < 0 OR f.profit_margin_pct < 5)
ORDER BY f.total_profit ASC;


-- =====================================================================================
-- Q3. How concentrated are sales and profit in the top customers?  (Pareto check)
-- WHY : If a few customers carry the business, losing them is a major risk.
-- HOW : Rank customers by sales (customer_id breaks ties so results are repeatable),
--       then sum the top 1 / 5 / 10 / 20 percent.
-- READ: compare sales_pct with profit_pct - if profit is MORE concentrated than sales,
--       the top customers matter even more than revenue suggests.
-- =====================================================================================
WITH ranked AS (
    SELECT
        customer_id, total_sales, total_profit,
        ROW_NUMBER() OVER (ORDER BY total_sales DESC, customer_id) AS rn,
        COUNT(*)          OVER ()  AS n_customers,
        SUM(total_sales)  OVER () AS all_sales,
        SUM(total_profit) OVER ()  AS all_profit
    FROM customer_features
),
cutoffs (label, pct) AS (
    VALUES ('Top 1%', 0.01), ('Top 5%', 0.05), ('Top 10%', 0.10), ('Top 20%', 0.20)
)
SELECT
    c.label AS customer_group,
    COUNT(*) AS customers,
    ROUND(SUM(r.total_sales)::numeric, 0)  AS sales,
    ROUND((100.0 * SUM(r.total_sales)  / MAX(r.all_sales))::numeric, 2)  AS sales_pct,
    ROUND(SUM(r.total_profit)::numeric, 0)   AS profit,
    ROUND((100.0 * SUM(r.total_profit) / MAX(r.all_profit))::numeric, 2) AS profit_pct
FROM cutoffs c
JOIN ranked r ON r.rn <= CEIL(c.pct * r.n_customers)
GROUP BY c.label, c.pct
ORDER BY c.pct;


-- =====================================================================================
-- Q4. Which categories sell a lot but earn little (or lose money)?
-- WHY : Revenue leaders are not always profit leaders.
-- HOW : Aggregate margin and average discount per category; then drill into sub-categories.
-- READ: high sales + low margin + high avg discount = a pricing problem, not a demand problem.
-- =====================================================================================
SELECT
    category,
    ROUND(SUM(sales)::numeric, 0)   AS total_sales,
    ROUND(SUM(profit)::numeric, 0)  AS total_profit,
    ROUND((100.0 * SUM(profit) / NULLIF(SUM(sales), 0))::numeric, 2) AS profit_margin_pct,
    ROUND((100.0 * AVG(discount))::numeric, 1) AS avg_discount_pct
FROM retail_raw
GROUP BY category
ORDER BY profit_margin_pct ASC;

-- Q4b. The 10 weakest sub-categories by total profit (where to look first)
SELECT
    category, sub_category,
    ROUND(SUM(sales)::numeric, 0) AS total_sales,
    ROUND(SUM(profit)::numeric, 0) AS total_profit,
    ROUND((100.0 * SUM(profit) / NULLIF(SUM(sales), 0))::numeric, 2) AS profit_margin_pct,
    ROUND((100.0 * AVG(discount))::numeric, 1) AS avg_discount_pct
FROM retail_raw
GROUP BY category, sub_category
ORDER BY total_profit ASC
LIMIT 10;


-- =====================================================================================
-- Q5. Which markets combine heavy discounting with weak margins?
-- WHY : A market-level discount habit can quietly erode profit.
-- HOW : One row per market: customers, sales, profit, margin, discount intensity,
--       and sales per customer (market value per customer).
-- READ: sort by margin; markets at the top with a high avg_discount_pct are the targets.
-- =====================================================================================
SELECT
    market,
    COUNT(DISTINCT customer_id)  AS customers,
    ROUND(SUM(sales)::numeric, 0) AS total_sales,
    ROUND(SUM(profit)::numeric, 0) AS total_profit,
    ROUND((100.0 * SUM(profit) / NULLIF(SUM(sales), 0))::numeric, 2)  AS profit_margin_pct,
    ROUND((100.0 * AVG(discount))::numeric, 1) AS avg_discount_pct,
    ROUND((SUM(sales) / COUNT(DISTINCT customer_id))::numeric, 0) AS sales_per_customer
FROM retail_raw
GROUP BY market
ORDER BY profit_margin_pct ASC;


-- =====================================================================================
-- Q6. Which large-customer countries have below-average value per customer?
-- WHY : Many customers + low spend each = growth opportunity (upsell / basket building).
-- HOW : Benchmark = overall sales per customer. "Large" = country customer count at or
--       above the median country. Value gap % = how far below the benchmark.
-- NOTE: a customer who bought in several countries is counted in each of them.
-- =====================================================================================
WITH country AS (
    SELECT
        country,
        COUNT(DISTINCT customer_id) AS customers,
        SUM(sales) / COUNT(DISTINCT customer_id) AS sales_per_customer
    FROM retail_raw
    GROUP BY country
),
benchmark AS (
    SELECT
        SUM(sales) / COUNT(DISTINCT customer_id) AS overall_sales_per_customer
    FROM retail_raw
),
size_cutoff AS (
    SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY customers) AS median_customers
    FROM country
)
SELECT
    c.country,
    c.customers,
    ROUND(c.sales_per_customer::numeric, 0) AS sales_per_customer,
    ROUND(b.overall_sales_per_customer::numeric, 0) AS overall_benchmark,
    ROUND((100.0 * (c.sales_per_customer - b.overall_sales_per_customer)
           / b.overall_sales_per_customer)::numeric, 1) AS value_gap_pct     -- negative = below average
FROM country c
CROSS JOIN benchmark b
CROSS JOIN size_cutoff s
WHERE c.customers >= s.median_customers
  AND c.sales_per_customer < b.overall_sales_per_customer
ORDER BY value_gap_pct ASC;
