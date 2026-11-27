-- Runs seven Gold queries and shows how many pages each one reads and how long it takes.
-- Read the results in the SSMS Messages tab. Press Ctrl + M first to also see the execution plans.

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- ====================================================================
-- Query 1: Customer report
-- ====================================================================
SELECT * FROM gold.report_customers;

-- ====================================================================
-- Query 2: Product report
-- ====================================================================
SELECT * FROM gold.report_products;

-- ====================================================================
-- Query 3: Revenue by category
-- ====================================================================
SELECT
    p.category,
    SUM(f.sales_amount) AS total_revenue
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
    ON p.product_key = f.product_key
GROUP BY p.category
ORDER BY total_revenue DESC;

-- ====================================================================
-- Query 4: Monthly sales trend
-- ====================================================================
SELECT
    DATETRUNC(month, order_date) AS order_date,
    SUM(sales_amount)            AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity)                AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month, order_date)
ORDER BY DATETRUNC(month, order_date);

-- ====================================================================
-- Query 5: Top 10 customers by revenue
-- ====================================================================
SELECT TOP 10
    c.customer_key,
    c.first_name,
    c.last_name,
    SUM(f.sales_amount) AS total_revenue
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
    ON c.customer_key = f.customer_key
GROUP BY
    c.customer_key,
    c.first_name,
    c.last_name
ORDER BY total_revenue DESC;

-- ====================================================================
-- Query 6: Orders of one customer (lookup by customer number)
-- ====================================================================
SELECT
    f.order_number,
    f.order_date,
    p.product_name,
    f.sales_amount
FROM gold.fact_sales f
INNER JOIN gold.dim_customers c
    ON c.customer_key = f.customer_key
INNER JOIN gold.dim_products p
    ON p.product_key = f.product_key
WHERE c.customer_number = 'AW00011000';

-- ====================================================================
-- Query 7: Sales by category for one quarter
-- ====================================================================
SELECT
    p.category,
    COUNT(DISTINCT f.order_number) AS orders,
    SUM(f.sales_amount)            AS revenue
FROM gold.fact_sales f
INNER JOIN gold.dim_products p
    ON p.product_key = f.product_key
WHERE f.order_date >= '2013-10-01'
  AND f.order_date <  '2014-01-01'
GROUP BY p.category;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
