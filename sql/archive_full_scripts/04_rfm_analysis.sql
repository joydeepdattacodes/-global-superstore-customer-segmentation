-- ======================================================================
-- Phase 4 - RFM Analysis
-- Project : Global Superstore - Customer Segmentation & Behavioral Analytics
-- Purpose : Reference date, Recency/Frequency/Monetary, NTILE scoring, conflicting value signals.
-- Depends : retail_raw
-- Engine  : PostgreSQL (run statements one at a time: select + F5 in pgAdmin)
-- NOTE: F and M scores use ORDER BY ... ASC so that 5 = best (most frequent / highest spend),
--       consistent with R (5 = most recent) and with Phase 5. Hard-coded thresholds below
--       (269 days, 2.52 %) come from the percentile queries run just before them.
-- ======================================================================

SELECT
	MAX(order_date) as latest_purchase_date
FROM retail_raw

--LATEST ORDER DATE 2014-12-31

---ANALYSIS DATE

SELECT
	MAX(order_date)+1 as analysis_date
FROM retail_raw

--analysis date  2015-01-01

--Rationale
--sUsing the day after the latest order date makes
--the most recent purchase 1 day old.


--------------------------------------------------------------------------
--RECENCY 
--------------------------------------------------------------------------

SELECT 
	customer_id,
	DATE '2015-01-01'-MAX(order_date) AS recency
FROM retail_raw
GROUP BY customer_id
ORDER BY recency


-------------------------------------------------------------------------
--FREQUENCY
-------------------------------------------------------------------------

SELECT
	customer_id,
	COUNT(DISTINCT order_id) as frequency
FROM retail_raw
GROUP BY customer_id
ORDER BY frequency DESC



-------------------------------------------------------------------------
--MONETARY VALUE
-------------------------------------------------------------------------

SELECT
	customer_id,
	SUM(sales) AS monetary_value
FROM retail_raw
GROUP BY customer_id
ORDER BY monetary_value DESC



---------------------------------------------------------------------------
--COMBINE RFM MATRICS
---------------------------------------------------------------------------

WITH rfm_matrics as(
SELECT
	customer_id,
	DATE '2015-01-01'-MAX(order_date) AS recency,
	COUNT(DISTINCT order_id) as frequency,
	SUM(sales) AS monetary_value,
	SUM(profit) as total_profit,
	ROUND((SUM(profit)::numeric/NULLIF(SUM(sales),0))*100,2)AS profit_margin
FROM retail_raw
GROUP BY customer_id
),

scores as(
SELECT
	customer_id,
	6-NTILE(5) over(ORDER BY recency ASC) AS r_score,
	NTILE(5) OVER (ORDER BY frequency ASC)AS f_score,
	NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score,
	monetary_value AS total_sales,
	total_profit,
	profit_margin
FROM rfm_matrics
)

SELECT
	customer_id,
	r_score,
	f_score,
	m_score,
	r_score+f_score+m_score AS rfm_scores,
	total_sales,
	total_profit,
	profit_margin
FROM scores
	

------------------------------------------------------------------------
--Identify customers with conflicting value signals
------------------------------------------------------------------------


--**first conflicting signal: high sales but negative profit


WITH rfm_matrics as(
SELECT
	customer_id,
	DATE '2015-01-01'-MAX(order_date) AS recency,
	COUNT(DISTINCT order_id) as frequency,
	SUM(sales) AS monetary_value,
	SUM(profit) as total_profit	
FROM retail_raw
GROUP BY customer_id
),

scores as(
SELECT
	customer_id,
	6-NTILE(5) over(ORDER BY recency ASC) AS r_score,
	NTILE(5) OVER (ORDER BY frequency ASC)AS f_score,
	NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score,
	monetary_value AS total_sales,
	total_profit
FROM rfm_matrics
)

SELECT
	customer_id,
	r_score+f_score+m_score AS rfm_scores,
	total_sales,
	total_profit,
	'High sales but loss making' AS signal_type
FROM scores
WHERE total_profit<0 AND total_sales 
		>
		(SELECT
			SUM(sales)::numeric/COUNT(DISTINCT customer_id)
		FROM retail_raw)
ORDER BY total_sales

------------------------------------------------------------------------


--***2nd conflicting signal
--customers whose total sales exceed average customer sales but whose
--last purchase was a long time ago




--** considering recency days above 75 percentile as high recency days

WITH customer_recency AS (
    SELECT
        customer_id,
        DATE '2015-01-01' - MAX(order_date) AS recency_days
    FROM retail_raw
    GROUP BY customer_id
)
SELECT
    PERCENTILE_CONT(0.75)
        WITHIN GROUP (ORDER BY recency_days) AS recency_75th_percentile
FROM customer_recency;




------------------------------------------------
WITH rfm_matrics as(
SELECT
	customer_id,
	DATE '2015-01-01'-MAX(order_date) AS recency,
	COUNT(DISTINCT order_id) as frequency,
	SUM(sales) AS monetary_value,
	SUM(profit) as total_profit	
FROM retail_raw
GROUP BY customer_id
),

scores as(
SELECT
	customer_id,
	6-NTILE(5) over(ORDER BY recency ASC) AS r_score,
	NTILE(5) OVER (ORDER BY frequency ASC)AS f_score,
	NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score,
	recency as recency_days,
	monetary_value AS total_sales,
	total_profit
FROM rfm_matrics
)

SELECT
	customer_id,
	r_score+f_score+m_score AS rfm_scores,
	recency_days,
	total_sales,
	total_profit,
	'High sales but haven''t purchased recently' AS signal_type
FROM scores
WHERE recency_days > 269 AND total_sales 
		>
		(SELECT
			SUM(sales)::numeric/COUNT(DISTINCT customer_id)
		FROM retail_raw)
ORDER BY total_sales



-------------------------------------------------------------------------

--***customers with high RFM scores but low profit margins.

--High RFM score: RFM score ≥ 12.
--Low profit margin: Profit margin below the 25th percentile

WITH customer_metrics AS (
    SELECT
        customer_id,
        SUM(sales) AS total_sales,
        SUM(profit) AS total_profit,
        SUM(profit)::numeric
            / NULLIF(SUM(sales), 0) * 100 AS profit_margin
    FROM retail_raw
    GROUP BY customer_id
)
SELECT
    PERCENTILE_CONT(0.25)
        WITHIN GROUP (ORDER BY profit_margin)
        AS profit_margin_25th_percentile
FROM customer_metrics;

---------------------------------------------------------------------------


WITH rfm_matrics as(
SELECT
	customer_id,
	DATE '2015-01-01'-MAX(order_date) AS recency,
	COUNT(DISTINCT order_id) as frequency,
	SUM(sales) AS monetary_value,
	SUM(profit) as total_profit,
	ROUND((SUM(profit)::numeric/NULLIF(SUM(sales),0))*100,2)AS profit_margin
FROM retail_raw
GROUP BY customer_id
),

scores as(
SELECT
	customer_id,
	6-NTILE(5) over(ORDER BY recency ASC) AS r_score,
	NTILE(5) OVER (ORDER BY frequency ASC)AS f_score,
	NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score,
	monetary_value AS total_sales,
	total_profit,
	profit_margin
FROM rfm_matrics
)

SELECT
	customer_id,
	r_score+f_score+m_score AS rfm_score,
	total_sales,
	total_profit,
	profit_margin,
	'high RFM scores but low profit margins' AS signal_type
FROM scores
WHERE (r_score+f_score+m_score) >=12 AND profit_margin < 2.52
	
--**************************************************************************
