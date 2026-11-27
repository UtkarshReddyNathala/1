-- Creates the Silver tables for cleaned data, including the hash and SCD columns used to track changes.
-- Running it again empties Silver and resets the watermarks, so the next load starts from the beginning.

-- Customers from the CRM (name, marital status, gender) - cleaned values
IF OBJECT_ID('silver.crm_cust_info', 'U') IS NOT NULL
    DROP TABLE silver.crm_cust_info;
GO

CREATE TABLE silver.crm_cust_info (
    cst_id             INT,
    cst_key            NVARCHAR(50),
    cst_firstname      NVARCHAR(50),
    cst_lastname       NVARCHAR(50),
    cst_marital_status NVARCHAR(50),
    cst_gndr           NVARCHAR(50),
    cst_create_date    DATE,
    cst_hash           VARBINARY(32),               -- SHA2_256 fingerprint of the customer columns, to find changes
    dwh_create_date    DATETIME2 DEFAULT GETDATE()  -- When the row was loaded into the warehouse
);
GO

-- Products from the CRM (name, cost, product line, start and end date) - cleaned values
IF OBJECT_ID('silver.crm_prd_info', 'U') IS NOT NULL
    DROP TABLE silver.crm_prd_info;
GO

CREATE TABLE silver.crm_prd_info (
    prd_id          INT,
    cat_id          NVARCHAR(50),
    prd_key         NVARCHAR(50),
    prd_nm          NVARCHAR(50),
    prd_cost        INT,
    prd_line        NVARCHAR(50),
    prd_start_dt    DATE,
    prd_end_dt      DATE,                           -- SCD Type 2: last day this version was valid (NULL = still current)
    is_current      BIT,                            -- SCD Type 2: 1 = current version, 0 = old version (history)
    prd_hash        VARBINARY(32),                  -- SHA2_256 fingerprint of the product columns, to find changes
    dwh_create_date DATETIME2 DEFAULT GETDATE()
);
GO

-- Sales order lines from the CRM (order, ship and due dates, quantity, price) - cleaned values
IF OBJECT_ID('silver.crm_sales_details', 'U') IS NOT NULL
    DROP TABLE silver.crm_sales_details;
GO

CREATE TABLE silver.crm_sales_details (
    sls_ord_num     NVARCHAR(50),
    sls_prd_key     NVARCHAR(50),
    sls_cust_id     INT,
    sls_order_dt    DATE,
    sls_ship_dt     DATE,
    sls_due_dt      DATE,
    sls_sales       INT,
    sls_quantity    INT,
    sls_price       INT,
    dwh_create_date DATETIME2 DEFAULT GETDATE()
);
GO

-- Customer country from the ERP - cleaned values
IF OBJECT_ID('silver.erp_loc_a101', 'U') IS NOT NULL
    DROP TABLE silver.erp_loc_a101;
GO

CREATE TABLE silver.erp_loc_a101 (
    cid             NVARCHAR(50),
    cntry           NVARCHAR(50),
    dwh_create_date DATETIME2 DEFAULT GETDATE()
);
GO

-- Customer birthdate and gender from the ERP - cleaned values
IF OBJECT_ID('silver.erp_cust_az12', 'U') IS NOT NULL
    DROP TABLE silver.erp_cust_az12;
GO

CREATE TABLE silver.erp_cust_az12 (
    cid             NVARCHAR(50),
    bdate           DATE,
    gen             NVARCHAR(50),
    dwh_create_date DATETIME2 DEFAULT GETDATE()
);
GO

-- Product category, subcategory and maintenance flag from the ERP - cleaned values
IF OBJECT_ID('silver.erp_px_cat_g1v2', 'U') IS NOT NULL
    DROP TABLE silver.erp_px_cat_g1v2;
GO

CREATE TABLE silver.erp_px_cat_g1v2 (
    id              NVARCHAR(50),
    cat             NVARCHAR(50),
    subcat          NVARCHAR(50),
    maintenance     NVARCHAR(50),
    dwh_create_date DATETIME2 DEFAULT GETDATE()
);
GO

-- Reset the watermarks, because the Silver tables above are now empty and must be loaded from the beginning
IF OBJECT_ID('audit.watermark_control', 'U') IS NOT NULL
    UPDATE audit.watermark_control
    SET
        last_watermark_value = '1900-01-01',
        last_updated         = GETDATE();
GO
