-- ======================================================================
-- Phase 2 - Data Validation
-- Project : Global Superstore - Customer Segmentation & Behavioral Analytics
-- Purpose : Column types, date consistency (ship vs order), record_count profiling, repeated order/product pairs.
-- Depends : retail_raw
-- Engine  : PostgreSQL (run statements one at a time: select + F5 in pgAdmin)
-- ======================================================================

SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_name = 'retail_raw'
ORDER BY ordinal_position;



--------------------------------------------------------------
-- checking date consistency 

--------------------------------------------------------------

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE ship_date < order_date
    ) AS shipped_before_order,
    COUNT(*) FILTER (
        WHERE ship_date = order_date
    ) AS same_day_shipping,
    COUNT(*) FILTER (
        WHERE ship_date > order_date
    ) AS shipped_after_order
FROM retail_raw;


--* no unusual dates

--------------------------------------------------------------
-- investigating record count column
--------------------------------------------------------------

SELECT
    record_count,
    COUNT(*) AS frequency
FROM retail_raw
GROUP BY record_count
ORDER BY record_count;




----------------------------------------------------------------
-- checking for duplicate buisness record

----------------------------------------------------------------

SELECT
    order_id,
    product_id,
    COUNT(*) AS occurrence_count
FROM retail_raw
GROUP BY order_id, product_id
HAVING COUNT(*) > 1
ORDER BY occurrence_count DESC;


SELECT *
FROM retail_raw
WHERE order_id = 'IN-2011-77892'
  AND product_id = 'TEC-PH-10001751'
ORDER BY row_id;
