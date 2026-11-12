-- ======================================================================
-- Phase 3 - Customer Feature Engineering
-- Project : Global Superstore - Customer Segmentation & Behavioral Analytics
-- Purpose : One-row-per-customer metrics: orders, sales, profit, AOV, frequency, breadth, discount exposure, dominant category.
-- Depends : retail_raw
-- Engine  : PostgreSQL (run statements one at a time: select + F5 in pgAdmin)
-- ======================================================================

-----------------------------------------------------------------
-- CUSTOMER FEATURE TABLE
-----------------------------------------------------------------

SELECT
	customer_id,
	SUM(sales) AS total_sales
FROM retail_raw
GROUP BY customer_id
ORDER BY total_sales DESC




------------------------------------------------------------------
-- TOTAL ORDERS PER CUSTOMER
------------------------------------------------------------------

SELECT
	customer_id,
	COUNT(DISTINCT order_id) AS total_orders
FROM retail_raw
GROUP BY customer_id
ORDER BY total_orders DESC



----------------------------------------------------------------
--CUSTOMER PROFITABILITY
----------------------------------------------------------------

SELECT 
	customer_id,
	SUM(sales) as total_sales,
	SUM(profit) as total_profit
FROM retail_raw
GROUP BY customer_id
ORDER BY total_profit DESC


---------------------------------------------------------------
--AVERAAGE ORDER VALUE
---------------------------------------------------------------

SELECT 
	customer_id,
	COUNT(DISTINCT order_id) AS total_orders,
	ROUND(SUM(quantity)::numeric/NULLIF(COUNT(DISTINCT order_id),0),2) AS avg_items_per_order,
	SUM(sales) as total_sales,
	ROUND(
	SUM(sales)::numeric/COUNT(DISTINCT order_id),
	2) AS avg_order_value,
	ROUND(
	SUM(profit)::numeric/COUNT(DISTINCT order_id),
	2) AS avg_profit_per_order
FROM retail_raw
GROUP BY customer_id
ORDER BY total_sales DESC


--------------------------------------------------------------
--Customer Purchase Frequency
--------------------------------------------------------------

WITH purchase_hist AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_purchase_date,
        MAX(order_date) AS last_purchase_date,
        COUNT(DISTINCT order_id) AS total_orders,
        MAX(order_date) - MIN(order_date)
            AS days_between_first_and_last_purchase
    FROM retail_raw
    GROUP BY customer_id
)

SELECT
    customer_id,
    first_purchase_date,
    last_purchase_date,
    total_orders,
    days_between_first_and_last_purchase,
    ROUND(
        total_orders::numeric /
        NULLIF(days_between_first_and_last_purchase, 0),
        4
    ) AS purchase_frequency
FROM purchase_hist
ORDER BY total_orders DESC;


---------------------------------------------------------------------
--CUSTOMER FETURE TABLE
---------------------------------------------------------------------


SELECT
	customer_id,
	COUNT(DISTINCT order_id) as total_orders,
	SUM(sales) as total_sales,
	SUM(profit) as total_profit,
	SUM(quantity) as total_quantities
FROM retail_raw
GROUP BY customer_id
ORDER BY total_sales DESC


------------------------------------------------------------------------
-- CUSTOMER PRODUCT AND CATEGORY BREADTH
------------------------------------------------------------------------


SELECT
	customer_id,
	COUNT(DISTINCT product_id) AS unique_products,
	COUNT(DISTINCT category) AS unique_category,
	COUNT(DISTINCT sub_category) AS unique_sub_category
FROM retail_raw
GROUP BY customer_id


-------------------------------------------------------------------------
--PURCHASE INTENSITY
-------------------------------------------------------------------------

SELECT
	customer_id,
	COUNT(DISTINCT(DATE_TRUNC('MONTH',order_date))) AS active_months,
	COUNT(DISTINCT order_id) as total_orders,
	ROUND(
	COUNT(DISTINCT order_id)::numeric/COUNT(DISTINCT(DATE_TRUNC('MONTH',order_date))),
	2) AS order_frequency
FROM retail_raw
GROUP BY customer_id

-------------------------------------------------------------------------
--DISCOUNT AND PROFITABILITY
-------------------------------------------------------------------------

SELECT
	customer_id,
	ROUND(
		AVG(discount),
		2
	 ) as avg_discount,
		
	SUM(sales) as total_sales,
	SUM(profit) as total_profit,
	ROUND(
		(SUM(profit)::numeric/NULLIF( SUM(sales),0))*100,
		2
	) AS profit_margin
FROM retail_raw
GROUP BY customer_id
ORDER BY total_sales DESC


------------------------------------------------------------------
--Dominant Category and Category Concentration
------------------------------------------------------------------
WITH category_analysis as(
SELECT
	customer_id,
	category,
	SUM(sales) as category_sales
	
FROM retail_raw
GROUP BY customer_id,category

),
rnk as(
SELECT
	customer_id,
	category,
	category_sales,
	ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY category_sales DESC
) as ranking
FROM category_analysis
),

fin_matrix as (
SELECT
	customer_id,
	category,
	category_sales,
	SUM(category_sales) OVER(partition by customer_id) AS total_sales,
	ranking
FROM rnk
)

SELECT
	customer_id,
	category AS dominant_category,
	category_sales AS dominant_category_sales,
	total_sales,
	ROUND
		((category_sales::numeric/NULLIF(total_sales,0))*100,
		2
	) AS concentration_pct
FROM fin_matrix
WHERE ranking=1 
	


------------------------------------------------------------------------
