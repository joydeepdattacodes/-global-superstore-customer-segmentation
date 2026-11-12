-- ======================================================================
-- Phase 8 - Geography & Service Economics
-- Project : Global Superstore - Customer Segmentation & Behavioral Analytics
-- Purpose : Market performance, segment mix per market, low-value countries, shipping-mode economics, ship duration, discount vs margin by market.
-- Depends : retail_raw
-- Engine  : PostgreSQL (run statements one at a time: select + F5 in pgAdmin)
-- NOTE: 'segment' in this phase = business segment column of the dataset (Consumer / Corporate / Home Office).
-- ======================================================================

----------------------------------------------------------------------------
--Market-Level Commercial Performance

--Compare customer counts, sales, profit and aggregate profit margin across markets
----------------------------------------------------------------------------


SELECT
	market AS market_name,
	COUNT(DISTINCT customer_id) AS total_distinct_customers,
	SUM(sales) AS total_sales,
	SUM(profit) AS total_profit,
	ROUND(
		(SUM(profit)::numeric/NULLIF(SUM(sales),0))*100,
		2
	) AS profit_margin,
	ROUND(
		SUM(sales)::numeric/NULLIF(count(DISTINCT customer_id),0),
		2
	) AS avg_customer_sales
FROM retail_raw
GROUP BY market



---------------------------------------------------------------------------------
--Customer Segment Composition Across Markets

--Which customer segments contribute the most customers and sales within each market?

--------------------------------------------------------------------------------------
WITH segment_level_analysis AS (
SELECT
	market,
	segment,
	COUNT(DISTINCT customer_id) AS total_customers_in_segment,
	SUM(sales) AS total_segment_sales
FROM retail_raw
GROUP BY market,segment
),


market_level_analysis AS (
SELECT
	market,
	COUNT(DISTINCT customer_id) AS total_customers_in_market,
    SUM(sales) AS total_market_sales
FROM retail_raw
GROUP BY market
)


SELECT
	s.market AS market_name,
	s.segment AS segment_name,
	s.total_customers_in_segment,
	ROUND(
		(s.total_customers_in_segment::numeric/m.total_customers_in_market)*100,
		2
	) AS customers_pct,
	s.total_segment_sales,
	ROUND(
		(s.total_segment_sales::numeric/m.total_market_sales)*100,
		2
	) AS sales_pct

FROM segment_level_analysis s
JOIN market_level_analysis m
	on s.market=m.market


--------------------------------------------------------------------------
--Identify High-Customer Countries with Below-Average Sales per Customer

--------------------------------------------------------------------------
WITH country_level_analysis AS (
SELECT
	country,
	COUNT(DISTINCT customer_id) AS total_customers,
	ROUND(
		SUM(sales)::numeric/COUNT(DISTINCT customer_id),
		2
	) AS avg_customer_sales
FROM retail_raw
GROUP BY country
),

overall_matrics AS(
	SELECT
		ROUND(
			SUM(sales)::numeric/COUNT(DISTINCT customer_id),
			2
		) AS overall_avg_sales
	FROM retail_raw
)

SELECT
	c.country AS country_name,
	c.total_customers,
	c.avg_customer_sales,
	r.overall_avg_sales,
	ROUND(
		(
			(c.avg_customer_sales-r.overall_avg_sales)::numeric
			/
			r.overall_avg_sales
		)*100,
	2
	)AS value_gap_pct
FROM country_level_analysis c
CROSS jOIN overall_matrics r
WHERE c.avg_customer_sales < r.overall_avg_sales
ORDER BY c.avg_customer_sales ASC;
	

--Negative gap: Below-average sales per customer.
--Positive gap: Above-average sales per customer.
--Zero gap: Equal to the overall average.


-----------------------------------------------------------------------------
--Shipping-Mode Economics by Customer Segment

--Different customer segments may use different shipping modes, and each mode 
--may have different sales, profitability, and shipping costs
--------------------------------------------------------------------------


SELECT
	segment,
	ship_mode,
	COUNT(distinct order_id) AS number_of_orders,
	SUM(sales) AS total_sales,
	SUM(profit) AS total_profit,
	ROUND(
		AVG(shipping_cost),
		2
	) AS avg_shipping_cost
FROM retail_raw
GROUP BY segment,ship_mode
ORDER BY segment, ship_mode;


-------------------------------------------------------------------------
--Shipping Duration Analysis

-------------------------------------------------------------------------

SELECT
	market,
	Ship_mode,
	order_priority,
	ROUND(
		AVG(ship_date-order_date),
		2
	) AS avg_ship_days,
	COUNT(DISTINCT order_id) AS number_of_orders
FROM retail_raw
GROUP BY market,ship_mode,order_priority
ORDER BY market, ship_mode, order_priority;


-----------------------------------------------------------------------------
--High Discounts and Weak Profit Margins

--Some markets may offer comparatively high discounts while generating
--relatively weak profit margin

-----------------------------------------------------------------------------


SELECT
    market AS "Market",
    ROUND(AVG(discount) * 100, 2) AS "Avg_Discount",
    ROUND(SUM(sales)::NUMERIC, 2) AS "Sales",
    ROUND(SUM(profit)::NUMERIC, 2) AS "Profit",
    ROUND(
        SUM(profit)::NUMERIC
        / NULLIF(SUM(sales), 0) * 100,
        2
    ) AS "Profit_Margin"
FROM retail_raw
GROUP BY market
ORDER BY "Profit_Margin" ASC;
