-- Creates the Gold star schema tables used for reporting: two dimension tables and one fact table.
-- The fact table is stored as a clustered columnstore index, which makes analytical queries much faster.

-- Remove the reports first, because they are built on top of the Gold tables
IF OBJECT_ID('gold.report_customers', 'V') IS NOT NULL
    DROP VIEW gold.report_customers;
GO

IF OBJECT_ID('gold.report_products', 'V') IS NOT NULL
    DROP VIEW gold.report_products;
GO

-- =============================================================================
-- Create Dimension: gold.dim_customers
-- =============================================================================
IF OBJECT_ID('gold.dim_customers', 'U') IS NOT NULL
    DROP TABLE gold.dim_customers;
GO

CREATE TABLE gold.dim_customers (
    customer_key     INT NOT NULL,   -- Surrogate key (warehouse ID, used by fact_sales)
    customer_id      INT,
    customer_number  NVARCHAR(50),
    first_name       NVARCHAR(50),
    last_name        NVARCHAR(50),
    country          NVARCHAR(50),
    marital_status   NVARCHAR(50),
    gender           NVARCHAR(50),
    birthdate        DATE,
    create_date      DATE,
    CONSTRAINT pk_dim_customers PRIMARY KEY CLUSTERED (customer_key)
);
GO

-- Index for fast lookups of one customer by customer number (for example 'AW00011000')
CREATE NONCLUSTERED INDEX ix_dim_customers_customer_number ON gold.dim_customers (customer_number);
GO

-- =============================================================================
-- Create Dimension: gold.dim_products
-- =============================================================================
IF OBJECT_ID('gold.dim_products', 'U') IS NOT NULL
    DROP TABLE gold.dim_products;
GO

CREATE TABLE gold.dim_products (
    product_key      INT NOT NULL,   -- Surrogate key (warehouse ID, used by fact_sales)
    product_id       INT,
    product_number   NVARCHAR(50),
    product_name     NVARCHAR(50),
    category_id      NVARCHAR(50),
    category         NVARCHAR(50),
    subcategory      NVARCHAR(50),
    maintenance      NVARCHAR(50),
    cost             INT,
    product_line     NVARCHAR(50),
    start_date       DATE,
    CONSTRAINT pk_dim_products PRIMARY KEY CLUSTERED (product_key)
);
GO

-- =============================================================================
-- Create Fact Table: gold.fact_sales
-- =============================================================================
IF OBJECT_ID('gold.fact_sales', 'U') IS NOT NULL
    DROP TABLE gold.fact_sales;
GO

CREATE TABLE gold.fact_sales (
    order_number   NVARCHAR(50),
    product_key    INT,            -- Links to gold.dim_products
    customer_key   INT,            -- Links to gold.dim_customers
    order_date     DATE,
    shipping_date  DATE,
    due_date       DATE,
    sales_amount   INT,
    quantity       INT,
    price          INT
);
GO

-- COLUMNSTORE: stores the sales data compressed and column by column.
-- Analytical queries (sums, counts, group by) read far less data and run in fast batch mode.
CREATE CLUSTERED COLUMNSTORE INDEX cci_fact_sales ON gold.fact_sales;
GO
