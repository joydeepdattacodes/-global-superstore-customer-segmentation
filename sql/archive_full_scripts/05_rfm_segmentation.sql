-- ======================================================================
-- Phase 5 - Rule-Based Segmentation
-- Project : Global Superstore - Customer Segmentation & Behavioral Analytics
-- Purpose : Six mutually exclusive RFM segments (view customer_rfm_segments), contribution, profiles, margin/discount, within-segment ranking.
-- Depends : retail_raw -> creates VIEW customer_rfm_segments
-- Engine  : PostgreSQL (run statements one at a time: select + F5 in pgAdmin)
-- ======================================================================

-------------------------------------------------------------------------
--****************Rule-Based Customer Segmentation***********************

-------------------------------------------------------------------------

WITH rfm_matrics AS (
SELECT
customer_id,
DATE '2015-01-01' - MAX(order_date) AS recency,
COUNT(DISTINCT order_id) AS frequency,
SUM(sales) AS monetary_value
FROM retail_raw
GROUP BY customer_id
),

scores AS (
SELECT
customer_id,
6 - NTILE(5) OVER (ORDER BY recency ASC) AS r_score,
NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score
FROM rfm_matrics
),

rfm_scores AS (
SELECT
customer_id,
r_score,
f_score,
m_score,
r_score + f_score + m_score AS rfm_score
FROM scores
)

SELECT
customer_id,
r_score,
f_score,
m_score,
rfm_score,


CASE
    WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
        THEN 'CHAMPIONS'

    WHEN f_score >= 4 AND r_score >= 3 AND m_score >= 3
        THEN 'LOYAL CUSTOMER'

    WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
        THEN 'AT-RISK VALUABLE CUSTOMER'

    WHEN r_score >= 4 AND f_score >= 2 AND m_score >= 2
        THEN 'POTENTIAL LOYALIST'

    WHEN rfm_score BETWEEN 7 AND 9
        THEN 'NEEDS ATTENTION'

    ELSE 'LOW ENGAGEMENT CUSTOMER'
END AS segment,

CASE
    WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
        THEN 'R >= 4, F >= 4, M >= 4'

    WHEN f_score >= 4 AND r_score >= 3 AND m_score >= 3
        THEN 'F >= 4, R >= 3, M >= 3; excluding Champions'

    WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
        THEN 'R <= 2, F >= 3, M >= 3'

    WHEN r_score >= 4 AND f_score >= 2 AND m_score >= 2
        THEN 'R >= 4, F >= 2, M >= 2; excluding earlier segments'

    WHEN rfm_score BETWEEN 7 AND 9
        THEN 'RFM score between 7 and 9; excluding earlier segments'

    ELSE 'Does not meet any previous segment rule'
END AS segment_rule


FROM rfm_scores
ORDER BY rfm_score DESC, customer_id;



---------------------------------------------------------------------------
--cretaing customer rfm segmentation view
---------------------------------------------------------------------------
CREATE OR REPLACE VIEW customer_rfm_segments AS

WITH rfm_metrics AS (
    SELECT
        customer_id,
        DATE '2015-01-01' - MAX(order_date) AS recency,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(sales) AS monetary_value
    FROM retail_raw
    GROUP BY customer_id
),

scores AS (
    SELECT
        customer_id,
        6 - NTILE(5) OVER (ORDER BY recency ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score
    FROM rfm_metrics
),

rfm_scores AS (
    SELECT
        customer_id,
        r_score,
        f_score,
        m_score,
        r_score + f_score + m_score AS rfm_score
    FROM scores
)

SELECT
    customer_id,
    r_score,
    f_score,
    m_score,
    rfm_score,

    CASE
        WHEN r_score >= 4
         AND f_score >= 4
         AND m_score >= 4
            THEN 'CHAMPIONS'

        WHEN f_score >= 4
         AND r_score >= 3
         AND m_score >= 3
            THEN 'LOYAL CUSTOMER'

        WHEN r_score <= 2
         AND f_score >= 3
         AND m_score >= 3
            THEN 'AT-RISK VALUABLE CUSTOMER'

        WHEN r_score >= 4
         AND f_score >= 2
         AND m_score >= 2
            THEN 'POTENTIAL LOYALIST'

        WHEN rfm_score BETWEEN 7 AND 9
            THEN 'NEEDS ATTENTION'

        ELSE 'LOW ENGAGEMENT CUSTOMER'
    END AS segment,

    CASE
        WHEN r_score >= 4
         AND f_score >= 4
         AND m_score >= 4
            THEN 'R >= 4, F >= 4, M >= 4'

        WHEN f_score >= 4
         AND r_score >= 3
         AND m_score >= 3
            THEN 'F >= 4, R >= 3, M >= 3; excluding Champions'

        WHEN r_score <= 2
         AND f_score >= 3
         AND m_score >= 3
            THEN 'R <= 2, F >= 3, M >= 3'

        WHEN r_score >= 4
         AND f_score >= 2
         AND m_score >= 2
            THEN 'R >= 4, F >= 2, M >= 2; excluding earlier segments'

        WHEN rfm_score BETWEEN 7 AND 9
            THEN 'RFM score between 7 and 9; excluding earlier segments'

        ELSE 'Does not meet any previous segment rule'
    END AS segment_rule

FROM rfm_scores;
--------------------------------------------------------------------------
--------------------------------------------------------------------------





-------------------------------------------------------------------------
--Segment Size and Commercial Contribution
-------------------------------------------------------------------------

--Which customer segments contribute the most customers,
--sales, and profit to the business


SELECT
	c.segment AS customer_segment,
	count(DISTINCT c.customer_id) AS total_customer,
	ROUND(
		 (count(DISTINCT c.customer_id)::numeric
		 /(SELECT COUNT(DISTINCT customer_id) FROM retail_raw))*100,
		2
	) AS customer_pct,
		
	
	SUM(r.sales) as total_sales,
	
	ROUND(
		(SUM(r.sales)::numeric
		/
		(SELECT SUM(sales) FROM retail_raw))*100,
		2
	) AS sales_pct,
	
	SUM(r.profit) as total_profit,
	
	ROUND(
		(SUM(r.profit)::numeric
		/
		(SELECT SUM(profit) FROM retail_raw))*100,
		2
	) AS profit_pct
FROM customer_rfm_segments c
JOIN retail_raw r
	ON c.customer_id = r.customer_id
GROUP BY c.segment




-----------------------------------------------------------------------
--How do customers in different segments behave, and how valuable is
--each segment on average?
-----------------------------------------------------------------------


WITH customer_matrics AS(
SELECT
	customer_id,
	DATE '2015-01-01' - MAX(order_date) AS recency,
	COUNT(DISTINCT order_id) AS total_orders,
	SUM(sales) AS total_sales,
	SUM(profit) AS total_profit,
	ROUND(
		SUM(sales)::numeric/COUNT(DISTINCT order_id),
		2
	) AS aov
FROM retail_raw
GROUP BY customer_id
)

SELECT
	s.segment,
	ROUND(AVG(c.recency),2) AS avg_recency,
	ROUND(AVG(c.total_orders),2) AS avg_orders,
	ROUND(AVG(c.total_sales),2) AS avg_sales,
	ROUND(AVG(c.total_profit),2) AS avg_profit,
	ROUND(AVG(c.aov),2) AS avg_aov
FROM customer_matrics c
JOIN customer_rfm_segments s
	ON c.customer_id = s.customer_id
GROUP BY s.segment

----------------------------------------------------------------------
--avg rfm scores accross segments
----------------------------------------------------------------------
SELECT
    segment,
    COUNT(*) AS customers,
    ROUND(AVG(r_score), 2) AS avg_r_score,
    ROUND(AVG(f_score), 2) AS avg_f_score,
    ROUND(AVG(m_score), 2) AS avg_m_score,
    ROUND(AVG(rfm_score), 2) AS avg_rfm_score
FROM customer_rfm_segments
GROUP BY segment
ORDER BY avg_rfm_score DESC



---------------------------------------------------------------------
WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders
    FROM retail_raw
    GROUP BY customer_id
)
SELECT
    s.f_score,
    COUNT(*) AS customers,
    ROUND(AVG(c.total_orders), 2) AS avg_orders,
    MIN(c.total_orders) AS min_orders,
    MAX(c.total_orders) AS max_orders
FROM customer_rfm_segments s
JOIN customer_orders c
    ON s.customer_id = c.customer_id
GROUP BY s.f_score
ORDER BY s.f_score DESC;



------------------------------------------------------------------------
--Which customer segments generate high sales but have relatively low profit 
--margins and higher discount exposure?

------------------------------------------------------------------------

SELECT
	c.segment,
	SUM(r.sales) AS total_sales,
	SUM(r.profit) AS total_profit,
	ROUND(
		 (SUM(r.profit)::numeric/SUM(r.sales))*100,
		 2
	)AS profit_margin,
	ROUND (
		AVG(r.discount),
		2
	) AS avg_discount
FROM retail_raw r
JOIN customer_rfm_segments c
	on r.customer_id=c.customer_id
GROUP BY c.segment
ORDER BY profit_margin ASC;	



------------------------------------------------------------------------
--Rank Customers Within Each Segment
------------------------------------------------------------------------
WITH segment_matrics as(
SELECT
	r.customer_id,
	s.segment,
	SUM(r.sales) AS total_sales,
	SUM(r.profit) AS total_profit
FROM retail_raw r
JOIN customer_rfm_segments s
	on r.customer_id = s.customer_id
GROUP BY r.customer_id,s.segment
)	

SELECT 
	customer_id,
	segment,
	total_sales,
	total_profit,
	RANK () OVER( 
		PARTITION BY segment ORDER BY total_sales DESC
	) AS sales_rank,
	RANK() OVER(
		partition by segment ORDER BY total_profit DESC
	) AS profit_rank
FROM segment_matrics
ORDER BY segment,sales_rank
