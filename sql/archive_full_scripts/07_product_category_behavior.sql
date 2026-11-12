-- ======================================================================
-- Phase 7 - Product & Category Behavior
-- Project : Global Superstore - Customer Segmentation & Behavioral Analytics
-- Purpose : Category leaders by business segment, breadth, category margin, product concentration among top 20% customers, single-product dependence.
-- Depends : retail_raw
-- Engine  : PostgreSQL (run statements one at a time: select + F5 in pgAdmin)
-- NOTE: 'segment' in this phase = business segment column of the dataset (Consumer / Corporate / Home Office),
--       NOT the RFM segments from Phase 5.
-- ======================================================================

------------------------------------------------------------------------------
--Identify the leading categories by sales and profit within each customer segment.

------------------------------------------------------------------------------



SELECT
	segment,
	category,
	SUM(sales) AS total_sales,
	SUM(profit) AS total_profit,
	ROW_NUMBER() OVER(
		PARTITION BY segment ORDER BY SUM(sales) DESC
	) AS sales_rank
FROM retail_raw
GROUP BY segment,category
ORDER BY segment,sales_rank


--------------------------------------------------------------------------------
--Product and Category Breadth by Segment

--Do different customer segments purchase a wider variety of products and 
--categories, or do some segments tend to buy from a narrower range

--------------------------------------------------------------------------------
WITH customer_matrics AS(
SELECT
	customer_id,
	segment,
	COUNT(DISTINCT category) as unique_categories,
	COUNT(DISTINCT sub_category ) AS unique_subcategories,
	COUNT(DISTINCT product_id) AS unique_products
FROM retail_raw
GROUP BY customer_id,segment
)

SELECT 
	segment,
	AVG(unique_categories) AS avg_unique_categories,
	AVG(unique_subcategories) AS avg_unique_subcategories,
	AVG(unique_products) AS avg_unique_products
FROM customer_matrics
GROUP BY segment


----------------------------------------------------------------------------------
--Identify categories with high sales but weak or negative profit margins, 
--including discount exposure
----------------------------------------------------------------------------------

SELECT
	category,
	SUM(sales) AS total_sales,
	SUM(profit) AS total_profit,
	ROUND(
		(SUM(PROFIT)::NUMERIC/SUM(sales))*100,
		2
	) AS profit_margin,
	ROUND(
		AVG(discount),
		2
	)AS avg_discount
FROM retail_raw
GROUP BY category





-------------------------------------------------------------------------
--**Product Concentration Among High-Value Customers

--Are certain products disproportionately popular among high-valuea
--customers compared with the overall customer base?

-------------------------------------------------------------------------
	
WITH customer_sales AS(
SELECT
	customer_id,
	SUM(sales) AS total_sales
FROM retail_raw
GROUP BY customer_id
),	

customer_ranking AS (
SELECT
	customer_id,
	ROW_NUMBER () OVER (
	ORDER BY total_sales DESC
	) AS ranking,
	total_sales
FROM customer_sales

),

total_customers AS (
SELECT
	COUNT(ranking) AS total_customers
FrOM customer_ranking
),


high_value_customers AS(
SELECT
	r.customer_id,
	r.ranking
FROM customer_ranking r
cross join total_customers t
WHERE r.ranking <= CEIL(0.20*t.total_customers)
),


product_customer_counts AS (
SELECT
	r.product_id,
	r.product_name,
	COUNT(DISTINCT CASE
		WHEN h.customer_id IS NOT NULL THEN r.customer_id
	END) AS high_value_customers,
	COUNT(DISTINCT r.customer_id) AS overall_customers
FROM retail_raw AS r
LEFT JOIN high_value_customers AS h
	ON r.customer_id = h.customer_id
GROUP BY
r.product_id,
r.product_name
)

SELECT
	product_id,
	product_name,
	ROUND(
		high_value_customers::numeric
		/
		NULLIF((SELECT COUNT(*) FROM high_value_customers),0)*100,
		2
	) AS high_value_share,
	ROUND(
		overall_customers::numeric
		/
		NULLIF((SELECT COUNT(DISTINCT customer_id) FROM retail_raw),0)*100,
		2		
	) AS overall_share,
	
	ROUND(
		(high_value_customers::NUMERIC
		/ NULLIF((SELECT COUNT(*) FROM high_value_customers), 0))
		/
		NULLIF(
			overall_customers::NUMERIC
			/ (SELECT COUNT(DISTINCT customer_id) FROM retail_raw),
		0
		),
		2
	) AS concentration_ratio
FROM product_customer_counts
ORDER BY concentration_ratio DESC


	

---------------------------------------------------------------------------
--Customer Product Concentration

--Which customers depend heavily on a single product, and how much does 
--that product contribute to their total sales?

---------------------------------------------------------------------------

WITH customer_matrics AS (
SELECT
	customer_id,
	product_id,
	SUM(sales) AS product_sale
FROM retail_raw
GROUP BY customer_id,product_id

),

product_ranking AS(
SELECT
	customer_id,
	product_id,
	product_sale,
	ROW_NUMBER () OVER(
		PARTITION BY customer_id ORDER BY product_sale DESC,product_id ASC
	) AS ranking

FROM customer_matrics


),


dominant_product_matrics AS(
SELECT
	customer_id,
	product_id,
	product_sale AS dominant_product_sales
FROM product_ranking
WHERE ranking =1
)

SELECT
	d.customer_id,
	COUNT( DISTINCT c.product_id) AS total_unique_products,
	d.dominant_product_sales,
	SUM(c.product_sale) as total_sales,
	ROUND(
		(d.dominant_product_sales::numeric/NULLIF(SUM(c.product_sale),0))*100,
		2
	) AS concentration_pct
FROM customer_matrics c
JOIN dominant_product_matrics d
	ON c.customer_id = d.customer_id
GROUP BY d.customer_id,d.dominant_product_sales
ORDER BY concentration_pct DESC
