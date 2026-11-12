-- ======================================================================
-- Phase 6 - Profitability, Discount & Loyalty
-- Project : Global Superstore - Customer Segmentation & Behavioral Analytics
-- Purpose : Discount bands, loss drivers by category, loss-making high-sales customers, repeat vs one-time, Pareto concentration, frequent-low-value buyers.
-- Depends : retail_raw
-- Engine  : PostgreSQL (run statements one at a time: select + F5 in pgAdmin)
-- ======================================================================

--deciding discount bands

SELECT
    discount,
    COUNT(*) AS transaction_lines,
    ROUND(SUM(sales)::numeric, 2) AS total_sales,
    ROUND(SUM(profit)::numeric, 2) AS total_profit,
	ROUND((SUM(profit)::numeric/SUM(sales))*100,2) AS profit_margin
FROM retail_raw
GROUP BY discount
ORDER BY discount;

---------------------------------------------------------------------------------------
--How does the discount offered on products relate to sales, profit, and profit margin?

---------------------------------------------------------------------------------------

SELECT
	CASE 
		WHEN discount = 0 then 'no discount'
		WHEN discount > 0 AND discount <= 0.20 then 'low discount'
		WHEN discount > 0.20 AND discount <= 0.40 then 'medium discount'
		ELSE 'high discount'
	END AS discount_level,
	COUNT(*) AS transaction_lines,
	SUM(sales) AS total_sales,
	SUM(profit) AS total_profit,
	ROUND(
		(SUM(profit)::numeric/NULLIF(SUM(sales),0))*100,
		2
	) AS profit_margin,
	
	ROUND(
		AVG(discount),2) AS avg_discount

FROM retail_raw
GROUP BY CASE 
			WHEN discount = 0 then 'no discount'
			WHEN discount > 0 AND discount <= 0.20 then 'low discount'
			WHEN discount > 0.20 AND discount <= 0.40 then 'medium discount'
			ELSE 'high discount'
		END 
	
-- we observed that the High Discount and medium discount group has a negative profit margin.

---------------------------------------------------------------------------
--***
--  which categories contribute most to the losses associated with high discounts.


SELECT
	category,
	COUNT(*) AS total_transaction_lines,
	SUM(sales) AS total_sales,
	SUM(profit) AS total_profit,
	ROUND(
		(SUM(profit)::numeric/NULLIF(SUM(sales),0))*100,
		2
	) AS profit_margin
FROM retail_raw
WHERE discount > 0.40
GROUP BY category
ORDER BY total_profit ASC


--**
--which categories contribute most to the losses associated with medium discounts.


SELECT
	category,
	COUNT(*) AS total_transaction_lines,
	SUM(sales) AS total_sales,
	SUM(profit) AS total_profit,
	ROUND(
		(SUM(profit)::numeric/NULLIF(SUM(sales),0))*100,
		2
	) AS profit_margin
FROM retail_raw
WHERE 0.20 < discount and discount <= 0.40
GROUP BY category
ORDER BY total_profit ASC



-----------------------------------------------------------------------
--Analysing discount behavior at the customer level.
-----------------------------------------------------------------------


WITH customer_profitability AS (


SELECT
    customer_id,
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit,

    ROUND(
        SUM(profit)::NUMERIC
        / NULLIF(SUM(sales), 0) * 100,
        2
    ) AS profit_margin,

    ROUND(AVG(discount), 3) AS avg_discount

FROM retail_raw

GROUP BY
    customer_id


),

customer_threshold AS (


SELECT
    PERCENTILE_CONT(0.75)
        WITHIN GROUP (ORDER BY total_sales)
        AS high_sales_threshold

FROM customer_profitability


)

SELECT
c.customer_id,
c.total_orders,
ROUND(c.total_sales::NUMERIC, 2) AS total_sales,
ROUND(c.total_profit::NUMERIC, 2) AS total_profit,
c.profit_margin,
c.avg_discount,


CASE
    WHEN c.total_profit < 0
        THEN 'Loss-Making Customer'

    WHEN c.profit_margin < 5
        THEN 'Low-Margin Customer'

    ELSE 'Profitable Customer'
END AS profitability_status


FROM customer_profitability AS c

CROSS JOIN customer_threshold AS t

WHERE
c.total_sales >= t.high_sales_threshold
AND (
c.total_profit < 0
OR c.profit_margin < 5
)

ORDER BY
c.total_profit ASC;



-----------------------------------------------------------------------
--Customer Loyalty vs. Profitability

--Do repeat customers generate a larger share of total profit than 
--one-time customers?

-----------------------------------------------------------------------

WITH customer_segmentation AS (
SELECT 
	customer_id,
	SUM(sales) AS total_sales,
	SUM(profit) AS total_profit,
	ROUND(
		(SUM(profit)::numeric/NULLIF(SUM(sales),0))*100,
		2
	) AS profit_margin,
	CASE 
		WHEN COUNT(DISTINCT order_id) > 1 THEN 'Repeat customer'
		ELSE 'One time customer'
	END AS customer_type
FROM retail_raw
GROUP BY customer_id
)


SELECT
	customer_type,
	COUNT(customer_type) AS total_customers,
	
	ROUND((COUNT(customer_type)::numeric
	/
	(SELECT COUNT(DISTINCT customer_id) FROM retail_raw)
	
	)*100,2) AS customer_pct,
	SUM(total_sales),
	
	ROUND((SUM(total_sales)::numeric
	/
	(SELECT SUM(sales) FROM retail_raw))*100,
	2
	) as sales_pct,
	SUM(total_profit) AS total_profit,
	ROUND(
		(SUM(total_profit)::numeric/SUM(total_sales))*100,
		2
	)AS profit_margin,
	AVG(total_profit) AS avg_customer_profit
	

	
FROM customer_segmentation
GROUP BY customer_type
	


-----------------------------------------------------------------------
--Sales and Profit Concentration

--What percentage of total sales and profit is generated by the top 1%, 
--5%, 10%, and 20% of customers ranked by total sales?
-----------------------------------------------------------------------
	

WITH customer_metrics AS (

    SELECT
        customer_id,
        SUM(sales) AS total_sales,
        SUM(profit) AS total_profit
    FROM retail_raw
    GROUP BY customer_id

),

ranked_customer AS (

    SELECT
        customer_id,

        ROW_NUMBER() OVER (
            ORDER BY total_sales DESC, customer_id ASC
        ) AS sales_rank,

        total_sales,
        total_profit

    FROM customer_metrics

),

customer_totals AS (

    SELECT
        COUNT(*) AS total_customers,
        SUM(total_sales) AS overall_sales,
        SUM(total_profit) AS overall_profit
    FROM ranked_customer

),

customer_groups AS (

    SELECT
        'Top 1%' AS customer_group,
        r.customer_id,
        r.total_sales,
        r.total_profit
    FROM ranked_customer r
    CROSS JOIN customer_totals t
    WHERE r.sales_rank <= CEIL(t.total_customers * 0.01)

    UNION ALL

    SELECT
        'Top 5%' AS customer_group,
        r.customer_id,
        r.total_sales,
        r.total_profit
    FROM ranked_customer r
    CROSS JOIN customer_totals t
    WHERE r.sales_rank <= CEIL(t.total_customers * 0.05)

    UNION ALL

    SELECT
        'Top 10%' AS customer_group,
        r.customer_id,
        r.total_sales,
        r.total_profit
    FROM ranked_customer r
    CROSS JOIN customer_totals t
    WHERE r.sales_rank <= CEIL(t.total_customers * 0.10)

    UNION ALL

    SELECT
        'Top 20%' AS customer_group,
        r.customer_id,
        r.total_sales,
        r.total_profit
    FROM ranked_customer r
    CROSS JOIN customer_totals t
    WHERE r.sales_rank <= CEIL(t.total_customers * 0.20)

)

SELECT
    g.customer_group,

    COUNT(*) AS customers,

    ROUND(SUM(g.total_sales)::NUMERIC, 2) AS sales,

    ROUND(
        SUM(g.total_sales)::NUMERIC
        / NULLIF(t.overall_sales, 0) * 100,
        2
    ) AS sales_pct,

    ROUND(SUM(g.total_profit)::NUMERIC, 2) AS profit,

    ROUND(
        SUM(g.total_profit)::NUMERIC
        / NULLIF(t.overall_profit, 0) * 100,
        2
    ) AS profit_pct

FROM customer_groups g

CROSS JOIN customer_totals t

GROUP BY
    g.customer_group,
    t.overall_sales,
    t.overall_profit

ORDER BY
    CASE g.customer_group
        WHEN 'Top 1%' THEN 1
        WHEN 'Top 5%' THEN 2
        WHEN 'Top 10%' THEN 3
        WHEN 'Top 20%' THEN 4
    END;





-----------------------------------------------------------------------
--Frequent Purchasers with Low Monetary Value

-----------------------------------------------------------------------



WITH customer_metrics AS (
	SELECT
		customer_id,
		COUNT(DISTINCT order_id) AS orders,
		SUM(sales) AS sales,
		ROUND(
			SUM(sales)::NUMERIC
			/ NULLIF(COUNT(DISTINCT order_id), 0),
			2
		) AS aov,
		SUM(profit) AS profit,
		COUNT(DISTINCT product_id) AS unique_products
	FROM retail_raw
	GROUP BY customer_id
),
customer_thresholds AS (
	SELECT
		PERCENTILE_CONT(0.75)
			WITHIN GROUP (ORDER BY orders) AS frequent_order_threshold,
		PERCENTILE_CONT(0.25)
			WITHIN GROUP (ORDER BY sales) AS low_sales_threshold
	FROM customer_metrics
)


SELECT
	c.customer_id AS "Customer.ID",
	c.orders AS "Orders",
	ROUND(c.sales::NUMERIC, 2) AS "Sales",
	c.aov AS "AOV",
		ROUND(c.profit::NUMERIC, 2) AS "Profit",
	c.unique_products AS "Unique_Products"
FROM customer_metrics c
CROSS JOIN customer_thresholds t
WHERE
c.orders >= t.frequent_order_threshold
AND c.sales <= t.low_sales_threshold
ORDER BY
c.sales ASC,
c.profit ASC;
