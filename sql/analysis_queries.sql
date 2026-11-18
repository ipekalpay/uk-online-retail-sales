-- UK Online Retail: sales and customer analysis (SQLite)
-- Table: sales (one row per invoice line, Dec 2009 - Dec 2011, cleaned by scripts/01_clean.py)

-- Q1 Monthly revenue, orders and average order value
-- export: monthly_sales.csv
SELECT month,
       ROUND(SUM(revenue), 0) AS revenue_gbp,
       COUNT(DISTINCT invoice) AS orders,
       COUNT(DISTINCT customer_id) AS customers,
       ROUND(SUM(revenue) / COUNT(DISTINCT invoice), 2) AS avg_order_value_gbp
FROM sales
WHERE month < '2011-12'            -- Dec 2011 only has 9 days of data
GROUP BY month
ORDER BY month;

-- Q2 Year-on-year growth: Jan-Nov 2011 vs Jan-Nov 2010
WITH yearly AS (
  SELECT substr(month, 1, 4) AS year, SUM(revenue) AS revenue, COUNT(DISTINCT invoice) AS orders
  FROM sales
  WHERE substr(month, 6, 2) <= '11' AND substr(month, 1, 4) IN ('2010', '2011')
  GROUP BY year
)
SELECT year,
       ROUND(revenue, 0) AS revenue_gbp,
       orders,
       ROUND(100.0 * (revenue / LAG(revenue) OVER (ORDER BY year) - 1), 1) AS revenue_growth_pct
FROM yearly;

-- Q3 Top 10 products by revenue
-- export: top_products.csv
SELECT description,
       SUM(quantity) AS units_sold,
       ROUND(SUM(revenue), 0) AS revenue_gbp,
       COUNT(DISTINCT invoice) AS orders
FROM sales
GROUP BY description
ORDER BY revenue_gbp DESC
LIMIT 10;

-- Q4 Revenue by country: UK vs international
-- export: country_sales.csv
SELECT country,
       ROUND(SUM(revenue), 0) AS revenue_gbp,
       ROUND(100.0 * SUM(revenue) / (SELECT SUM(revenue) FROM sales), 1) AS pct_of_revenue,
       COUNT(DISTINCT customer_id) AS customers
FROM sales
GROUP BY country
ORDER BY revenue_gbp DESC;

-- Q5 Busiest day of the week (orders and revenue)
SELECT CASE strftime('%w', invoice_date)
         WHEN '0' THEN 'Sun' WHEN '1' THEN 'Mon' WHEN '2' THEN 'Tue' WHEN '3' THEN 'Wed'
         WHEN '4' THEN 'Thu' WHEN '5' THEN 'Fri' ELSE 'Sat' END AS weekday,
       COUNT(DISTINCT invoice) AS orders,
       ROUND(SUM(revenue), 0) AS revenue_gbp
FROM sales
GROUP BY strftime('%w', invoice_date)
ORDER BY strftime('%w', invoice_date);

-- Q6 RFM customer segmentation (Recency, Frequency, Monetary) scored 1-5 with NTILE
-- Ties are broken by customer_id so every run gives the same segments.
-- export: customer_rfm.csv
WITH base AS (
  SELECT customer_id,
         julianday('2011-12-10') - julianday(MAX(invoice_date)) AS recency_days,
         COUNT(DISTINCT invoice) AS frequency,
         SUM(revenue) AS monetary
  FROM sales
  WHERE customer_id IS NOT NULL
  GROUP BY customer_id
),
scored AS (
  SELECT *,
         6 - NTILE(5) OVER (ORDER BY recency_days, customer_id) AS r_score,
         NTILE(5) OVER (ORDER BY frequency, customer_id) AS f_score,
         NTILE(5) OVER (ORDER BY monetary, customer_id) AS m_score
  FROM base
),
segmented AS (
  SELECT *,
         CASE
           WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal'
           WHEN r_score >= 4 AND f_score <= 2 THEN 'New / promising'
           WHEN r_score <= 2 AND f_score >= 3 THEN 'At risk'
           ELSE 'Lost / low value'
         END AS segment
  FROM scored
)
SELECT customer_id,
       CAST(recency_days AS INT) AS recency_days,
       frequency,
       ROUND(monetary, 2) AS monetary_gbp,
       r_score, f_score, m_score,
       segment
FROM segmented;

-- Q7 Segment summary: how much revenue does each segment bring? (same CTEs as Q6)
-- export: segment_summary.csv
WITH base AS (
  SELECT customer_id,
         julianday('2011-12-10') - julianday(MAX(invoice_date)) AS recency_days,
         COUNT(DISTINCT invoice) AS frequency,
         SUM(revenue) AS monetary
  FROM sales
  WHERE customer_id IS NOT NULL
  GROUP BY customer_id
),
scored AS (
  SELECT *,
         6 - NTILE(5) OVER (ORDER BY recency_days, customer_id) AS r_score,
         NTILE(5) OVER (ORDER BY frequency, customer_id) AS f_score,
         NTILE(5) OVER (ORDER BY monetary, customer_id) AS m_score
  FROM base
),
segmented AS (
  SELECT *,
         CASE
           WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal'
           WHEN r_score >= 4 AND f_score <= 2 THEN 'New / promising'
           WHEN r_score <= 2 AND f_score >= 3 THEN 'At risk'
           ELSE 'Lost / low value'
         END AS segment
  FROM scored
)
SELECT segment,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_customers,
       ROUND(SUM(monetary), 0) AS revenue_gbp,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue,
       ROUND(AVG(monetary), 0) AS avg_spend_gbp,
       CAST(AVG(recency_days) AS INT) AS avg_days_since_last_order
FROM segmented
GROUP BY segment
ORDER BY revenue_gbp DESC;

-- Q8 Customer concentration: share of revenue from the top 20% of customers
WITH c AS (
  SELECT customer_id, SUM(revenue) AS spend,
         NTILE(5) OVER (ORDER BY SUM(revenue) DESC, customer_id) AS quintile
  FROM sales
  WHERE customer_id IS NOT NULL
  GROUP BY customer_id
)
SELECT quintile AS customer_quintile,
       COUNT(*) AS customers,
       ROUND(100.0 * SUM(spend) / (SELECT SUM(spend) FROM c), 1) AS pct_revenue
FROM c
GROUP BY quintile
ORDER BY quintile;
