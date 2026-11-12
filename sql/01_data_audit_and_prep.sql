-- =====================================================================================
-- 01 | DATA AUDIT & VALIDATION                               (roadmap Phases 1-2)
-- Project : Global Superstore - Customer Segmentation & Behavioral Analytics
-- Engine  : PostgreSQL. Run one statement at a time (select it, press F5 in pgAdmin).
-- Table   : retail_raw  (raw layer - NEVER modified; every later step reads from it)
--
-- BUSINESS QUESTION
--   Can we trust this data enough to segment customers and talk about profit?
--
-- GRAIN (decided here, used everywhere after)
--   row        = one transaction line      -> identified by row_id
--   order      = one distinct order_id     -> an order holds MANY lines
--   customer   = one distinct customer_id  -> a customer places MANY orders
--   => order counts must always use COUNT(DISTINCT order_id), never COUNT(*).
--
-- QUALITY RULES
--   * Negative profit is a business outcome (discount-driven loss), NOT an error -> keep it.
--   * Only remove/alter data with evidence that it is invalid. Nothing is deleted here.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1.1  Size of the dataset: rows, customers, orders, products, unique row ids
--      Expect distinct row_ids = total rows if row_id is a true key.
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT row_id) AS distinct_row_ids,
    COUNT(DISTINCT customer_id) AS distinct_customers,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT product_id) AS distinct_products
FROM retail_raw;


-- -------------------------------------------------------------------------------------
-- 1.2  Grain check: confirm one order = many lines, one customer = many orders
-- -------------------------------------------------------------------------------------
SELECT order_id, COUNT(*) AS lines_in_order
FROM retail_raw
GROUP BY order_id
ORDER BY lines_in_order DESC
LIMIT 10;

SELECT customer_id, COUNT(DISTINCT order_id) AS orders_placed
FROM retail_raw
GROUP BY customer_id
ORDER BY orders_placed DESC
LIMIT 10;


-- -------------------------------------------------------------------------------------
-- 1.3  Missing values in the columns every later analysis depends on
--      FILTER (WHERE ...) counts only matching rows - cleaner than SUM(CASE WHEN ...).
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE row_id IS NULL) AS row_id_nulls,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS order_id_nulls,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS customer_id_nulls,
    COUNT(*) FILTER (WHERE product_id  IS NULL) AS product_id_nulls,
    COUNT(*) FILTER (WHERE order_date  IS NULL) AS order_date_nulls,
    COUNT(*) FILTER (WHERE ship_date   IS NULL) AS ship_date_nulls,
    COUNT(*) FILTER (WHERE sales IS NULL) AS sales_nulls,
    COUNT(*) FILTER (WHERE quantity IS NULL) AS quantity_nulls,
    COUNT(*) FILTER (WHERE profit IS NULL) AS profit_nulls
FROM retail_raw;


-- -------------------------------------------------------------------------------------
-- 1.4  Exact duplicate rows (all business columns identical)
--      Result 0 = no fully duplicated records.
-- -------------------------------------------------------------------------------------
SELECT COUNT(*) AS duplicate_record_groups
FROM (
    SELECT 1
    FROM retail_raw
    GROUP BY
        category, city, country, customer_id, customer_name, discount, market,
        record_count, order_date, order_id, order_priority, product_id, product_name,
        profit, quantity, region, sales, segment, ship_date, ship_mode, shipping_cost,
        state, sub_category, year, market2, week_num
    HAVING COUNT(*) > 1
) AS dup;


-- -------------------------------------------------------------------------------------
-- 1.5  "Soft" duplicates: same order + same product on more than one line.
--      Repetition alone does NOT prove a duplicate (could be different sizes/prices),
--      so these are inspected, not deleted.
-- -------------------------------------------------------------------------------------
SELECT order_id, product_id, COUNT(*) AS occurrences
FROM retail_raw
GROUP BY order_id, product_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;

-- Inspect one example from the list above before deciding anything:
SELECT *
FROM retail_raw
WHERE order_id = 'IN-2011-77892' AND product_id = 'TEC-PH-10001751'
ORDER BY row_id;


-- -------------------------------------------------------------------------------------
-- 1.6  Observation window (drives the RFM reference date later)
-- -------------------------------------------------------------------------------------
SELECT
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,
    MIN(ship_date)  AS first_ship_date,
    MAX(ship_date)  AS last_ship_date
FROM retail_raw;


-- -------------------------------------------------------------------------------------
-- 1.7  Date logic: nothing should ship before it was ordered
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE ship_date <  order_date) AS shipped_before_order,   -- must be 0
    COUNT(*) FILTER (WHERE ship_date =  order_date) AS same_day_shipping,
    COUNT(*) FILTER (WHERE ship_date >  order_date) AS shipped_after_order,
    MIN(ship_date - order_date) AS min_days_to_ship,
    MAX(ship_date - order_date) AS max_days_to_ship
FROM retail_raw;


-- -------------------------------------------------------------------------------------
-- 1.8  Numeric sanity: impossible values vs. legitimate business outcomes
--      loss_lines is expected to be large - discount-driven losses are a finding, not a bug.
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE quantity <= 0)               AS invalid_quantity,
    COUNT(*) FILTER (WHERE sales <= 0)                  AS zero_or_negative_sales,
    COUNT(*) FILTER (WHERE discount < 0 OR discount > 1) AS invalid_discount,
    COUNT(*) FILTER (WHERE shipping_cost < 0)           AS negative_shipping_cost,
    COUNT(*) FILTER (WHERE profit < 0)                  AS loss_lines,
    ROUND(100.0 * COUNT(*) FILTER (WHERE profit < 0) / COUNT(*), 2) AS loss_lines_pct,
    COUNT(*) FILTER (WHERE profit = 0)                  AS zero_profit_lines
FROM retail_raw;

-- Ranges and tails (percentiles show whether extremes are errors or just big orders)
SELECT
    MIN(sales) AS min_sales,
    PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY sales) AS median_sales,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY sales) AS p99_sales,
    MAX(sales) AS max_sales,
    MIN(profit) AS min_profit,
    MAX(profit) AS max_profit,
    MAX(discount) AS max_discount,
    MAX(shipping_cost) AS max_shipping_cost
FROM retail_raw;


-- -------------------------------------------------------------------------------------
-- 1.9  record_count: a constant column carries no information -> exclude from analysis
-- -------------------------------------------------------------------------------------
SELECT record_count, COUNT(*) AS frequency
FROM retail_raw
GROUP BY record_count
ORDER BY record_count;

-- DECISIONS
--   * Raw table preserved; no rows removed. Loss-making and repeated order/product lines are kept.
--   * record_count is constant -> ignored.
--   * Zero-sales line(s) kept and documented (see notebook 01).


