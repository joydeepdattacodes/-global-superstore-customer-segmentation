-- ======================================================================
-- Phase 1 - Data Audit
-- Project : Global Superstore - Customer Segmentation & Behavioral Analytics
-- Purpose : Row/customer/order/product counts, key uniqueness, nulls, duplicates, date window, numeric sanity checks.
-- Depends : retail_raw
-- Engine  : PostgreSQL (run statements one at a time: select + F5 in pgAdmin)
-- ======================================================================

--------------------------------------------------------------------
--BASIC DATA AUDIT
--------------------------------------------------------------------


SELECT
	COUNT(*) AS total_rows,
	COUNT (DISTINCT customer_id) AS distinct_customer_count,
	COUNT (DISTINCT order_id) AS distinct_orders,
	COUNT (DISTINCT product_id) AS distincts_products
FROM retail_raw



--------------------------------------------------------------------
--DATA INTEGRITY AUDIT
--------------------------------------------------------------------

SELECT
	COUNT(DISTINCT row_id)
from retail_raw

--all row id are unique

SELECT
	order_id,
	COUNT(*) AS total_orders
FROM retail_raw
GROUP BY order_id
ORDER BY total_orders DESC
LIMIT(10)

--SINGLE ORDER CAN CONTAIN MULTIPLE ORDER IN IT

SELECT
	customer_id,
	COUNT( DISTINCT order_id) AS total_orders
FROM retail_raw
GROUP BY customer_id
ORDER BY total_orders DESC
LIMIT(10)

--SINGLE CUSTOMER CAN MAKE MULTIPLE ORDERS




---------------------------------------------------------------------
--checking missing value in important columns
---------------------------------------------------------------------

SELECT
	COUNT(*) FILTER(where row_id IS NULL) AS row_id_nulls,
	COUNT(*) FILTER(where order_id IS NULL) AS order_id_nulls,
	COUNT(*) FILTER(where product_id IS NULL) AS product_id_nulls,
	COUNT(*) FILTER(where customer_id IS NULL) AS customer_id_nulls,
	COUNT(*) FILTER(where order_date IS NULL) AS order_date_nulls,
	COUNT(*) FILTER(where ship_date IS NULL) AS ship_date_nulls,
	COUNT(*) FILTER(where sales IS NULL) AS sales_nulls,
	COUNT(*) FILTER(where quantity IS NULL) AS quantity_nulls,
	COUNT(*) FILTER(where profit IS NULL) AS profit_nulls
FROm retail_raw

-- NO NULl present

--Check for duplicates


SELECT COUNT(*) AS duplicate_record_groups
FROM (
    SELECT
        category, city, country, customer_id, customer_name,
        discount, market, record_count, order_date, order_id,
        order_priority, product_id, product_name, profit,
        quantity, region, sales, segment, ship_date, ship_mode,
        shipping_cost, state, sub_category, year, market2, week_num
    FROM retail_raw
    GROUP BY
        category, city, country, customer_id, customer_name,
        discount, market, record_count, order_date, order_id,
        order_priority, product_id, product_name, profit,
        quantity, region, sales, segment, ship_date, ship_mode,
        shipping_cost, state, sub_category, year, market2, week_num
    HAVING COUNT(*) > 1
) AS duplicates;



---- 0 duplicate rows,


-----------------------------------------------------
-- Confirm the observation window and inspect order
--date and ship-date ranges.
-----------------------------------------------------
SELECT
	DATE_TRUNC('MONTH',MIN(order_date)) AS min_order_date,
	DATE_TRUNC('MONTH',MAX(order_date)) AS max_order_date,
	DATE_TRUNC('MONTH',MIN(ship_date)) AS min_ship_date,
	DATE_TRUNC('MONTH',MAX(ship_date)) AS max_ship_date
FROM retail_raw

-- order_date range  2011/01/01 - 2014/12/01
--ship_date range    2011/01/01 - 2015/01/01


------------------------------------------------------
--checking validity of quantity sales and other numeric
-- columns

------------------------------------------------------

SELECT 
	MIN(quantity) as min_qunatity,
	MAX(quantity) as max_quantity,
	MIN(sales) as min_sales,
	MAX(sales) as max_sales,
	MIN(profit) as min_profit,
	MAX(profit) as max_profit,
	MIN(discount) as min_discount,
	MAX(discount) as max_discount,
	MIN(shipping_cost) as min_shiipingcost,
	MAX(shipping_cost) as max_shippingcost
FROM retail_raw

--- * no such unusal values
---	* the negative value in profit indicates normalli loss suffered




-----------------------------------------------------------------
-- checking if numerical value are within range
-----------------------------------------------------------------


SELECT
    COUNT(*) FILTER (WHERE quantity <= 0) AS invalid_quantity,
    COUNT(*) FILTER (WHERE sales < 0) AS negative_sales,
    COUNT(*) FILTER (WHERE discount < 0 OR discount > 1) AS invalid_discount,
    COUNT(*) FILTER (WHERE shipping_cost < 0) AS negative_shipping_cost,
    COUNT(*) FILTER (WHERE profit < 0) AS loss_transactions
FROM retail_raw;


-- there is no numerical value out of range 


-------------------------------------------------------------
