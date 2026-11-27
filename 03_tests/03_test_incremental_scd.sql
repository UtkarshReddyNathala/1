-- Tests incremental loading, hash checks, SCD Type 1 and Type 2, watermarks and error logging (10 tests).
-- Shows PASS or FAIL for each test. All test data is rolled back, so the real data does not change.

SET NOCOUNT ON;

DECLARE @results TABLE (test_name NVARCHAR(200), result NVARCHAR(10));
DECLARE @batch_id INT, @cust_count INT, @prd_count INT, @sales_count INT;
DECLARE @wm_cust DATETIME2, @wm_prd DATETIME2, @wm_sales DATETIME2;

-- ====================================================================
-- Test 1: Re-running the load with no new data changes nothing
-- ====================================================================
SELECT @cust_count  = COUNT(*) FROM silver.crm_cust_info;
SELECT @prd_count   = COUNT(*) FROM silver.crm_prd_info;
SELECT @sales_count = COUNT(*) FROM silver.crm_sales_details;

EXEC dbo.load_all;

SELECT @batch_id = MAX(batch_id) FROM audit.etl_log;

INSERT INTO @results
SELECT
    'Test 1: Re-run without new data inserts and updates nothing',
    CASE
        WHEN (SELECT SUM(rows_processed)
              FROM audit.etl_log
              WHERE batch_id = @batch_id
                AND table_name IN ('silver.crm_cust_info', 'silver.crm_prd_info', 'silver.crm_sales_details')) = 0
         AND (SELECT COUNT(*) FROM silver.crm_cust_info)     = @cust_count
         AND (SELECT COUNT(*) FROM silver.crm_prd_info)      = @prd_count
         AND (SELECT COUNT(*) FROM silver.crm_sales_details) = @sales_count
        THEN 'PASS' ELSE 'FAIL'
    END;

-- ====================================================================
-- Test 2-9: Load new and changed records (rolled back at the end)
-- ====================================================================
BEGIN TRANSACTION;

-- New customer
INSERT INTO bronze.crm_cust_info (cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date)
VALUES (99001, 'AW00099001', 'Test', 'Customer', 'S', 'F', '2026-12-01');

-- Changed customer: new last name for customer 11000
INSERT INTO bronze.crm_cust_info (cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date)
VALUES (11000, 'AW00011000', 'Jon', 'Yang-Smith', 'M', 'M', '2026-12-01');

-- Unchanged customer: customer 11001 is sent again with the same attributes
INSERT INTO bronze.crm_cust_info (cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date)
VALUES (11001, 'AW00011001', 'Eugene', 'Huang', 'S', 'M', '2026-12-01');

-- Changed product: new cost for product HL-U509-R
INSERT INTO bronze.crm_prd_info (prd_id, prd_key, prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt)
VALUES (9001, 'AC-HE-HL-U509-R', 'Sport-100 Helmet- Red', 15, 'S', '2014-07-01', NULL);

-- Unchanged product: the current version of product HL-U509 is sent again with a newer start date
INSERT INTO bronze.crm_prd_info (prd_id, prd_key, prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt)
SELECT TOP 1 9002, prd_key, prd_nm, prd_cost, prd_line, '2014-07-01', NULL
FROM bronze.crm_prd_info
WHERE prd_key = 'AC-HE-HL-U509'
ORDER BY prd_start_dt DESC;

-- New sales row
INSERT INTO bronze.crm_sales_details (sls_ord_num, sls_prd_key, sls_cust_id, sls_order_dt, sls_ship_dt, sls_due_dt, sls_sales, sls_quantity, sls_price)
VALUES ('SO99999', 'BK-R93R-62', 21768, 20140301, 20140308, 20140313, 3578, 1, 3578);

SELECT @cust_count  = COUNT(*) FROM silver.crm_cust_info;
SELECT @sales_count = COUNT(*) FROM silver.crm_sales_details;

EXEC silver.load_silver;
EXEC gold.load_gold;

INSERT INTO @results
SELECT
    'Test 2: New customer is inserted',
    CASE
        WHEN EXISTS (SELECT 1 FROM silver.crm_cust_info WHERE cst_id = 99001)
         AND (SELECT COUNT(*) FROM silver.crm_cust_info) = @cust_count + 1
        THEN 'PASS' ELSE 'FAIL'
    END;

INSERT INTO @results
SELECT
    'Test 3: SCD Type 1 overwrites the changed customer (no new row)',
    CASE
        WHEN (SELECT COUNT(*) FROM silver.crm_cust_info WHERE cst_id = 11000) = 1
         AND (SELECT cst_lastname FROM silver.crm_cust_info WHERE cst_id = 11000) = 'Yang-Smith'
        THEN 'PASS' ELSE 'FAIL'
    END;

INSERT INTO @results
SELECT
    'Test 4: Hash check skips the unchanged customer',
    CASE
        WHEN (SELECT cst_create_date FROM silver.crm_cust_info WHERE cst_id = 11001) < '2026-12-01'
        THEN 'PASS' ELSE 'FAIL'
    END;

INSERT INTO @results
SELECT
    'Test 5: SCD Type 2 expires the old product version and adds the new one',
    CASE
        WHEN (SELECT COUNT(*) FROM silver.crm_prd_info WHERE prd_key = 'HL-U509-R') = 4
         AND (SELECT COUNT(*) FROM silver.crm_prd_info WHERE prd_key = 'HL-U509-R' AND is_current = 1) = 1
         AND EXISTS (SELECT 1 FROM silver.crm_prd_info
                     WHERE prd_key = 'HL-U509-R' AND is_current = 1
                       AND prd_cost = 15 AND prd_start_dt = '2014-07-01' AND prd_end_dt IS NULL)
         AND EXISTS (SELECT 1 FROM silver.crm_prd_info
                     WHERE prd_key = 'HL-U509-R' AND is_current = 0
                       AND prd_start_dt = '2013-07-01' AND prd_end_dt = '2014-06-30')
        THEN 'PASS' ELSE 'FAIL'
    END;

INSERT INTO @results
SELECT
    'Test 6: Hash check skips the unchanged product (no new version)',
    CASE
        WHEN NOT EXISTS (SELECT 1 FROM silver.crm_prd_info WHERE prd_key = 'HL-U509' AND prd_start_dt = '2014-07-01')
         AND (SELECT COUNT(*) FROM silver.crm_prd_info WHERE prd_key = 'HL-U509' AND is_current = 1) = 1
        THEN 'PASS' ELSE 'FAIL'
    END;

INSERT INTO @results
SELECT
    'Test 7: New sales row is inserted once',
    CASE
        WHEN (SELECT COUNT(*) FROM silver.crm_sales_details WHERE sls_ord_num = 'SO99999') = 1
         AND (SELECT COUNT(*) FROM silver.crm_sales_details) = @sales_count + 1
        THEN 'PASS' ELSE 'FAIL'
    END;

INSERT INTO @results
SELECT
    'Test 8: Watermarks move to the newest loaded values',
    CASE
        WHEN (SELECT last_watermark_value FROM audit.watermark_control WHERE table_name = 'crm_cust_info')     = '2026-12-01'
         AND (SELECT last_watermark_value FROM audit.watermark_control WHERE table_name = 'crm_prd_info')      = '2014-07-01'
         AND (SELECT last_watermark_value FROM audit.watermark_control WHERE table_name = 'crm_sales_details') = '2014-03-08'
        THEN 'PASS' ELSE 'FAIL'
    END;

INSERT INTO @results
SELECT
    'Test 9: Gold tables show the latest Silver data after gold.load_gold',
    CASE
        WHEN EXISTS (SELECT 1 FROM gold.dim_customers WHERE customer_id = 99001)
         AND (SELECT cost FROM gold.dim_products WHERE product_number = 'HL-U509-R') = 15
         AND EXISTS (SELECT 1 FROM gold.fact_sales
                     WHERE order_number = 'SO99999'
                       AND product_key IS NOT NULL
                       AND customer_key IS NOT NULL)
        THEN 'PASS' ELSE 'FAIL'
    END;

-- Undo all test records in Bronze, Silver, Gold and the watermarks
ROLLBACK TRANSACTION;

-- ====================================================================
-- Test 10: A failed load is logged and the watermark does not move
-- ====================================================================
SELECT @wm_sales    = last_watermark_value FROM audit.watermark_control WHERE table_name = 'crm_sales_details';
SELECT @sales_count = COUNT(*) FROM silver.crm_sales_details;

-- Broken record: 20991399 is not a real date, so the date conversion fails
INSERT INTO bronze.crm_sales_details (sls_ord_num, sls_prd_key, sls_cust_id, sls_order_dt, sls_ship_dt, sls_due_dt, sls_sales, sls_quantity, sls_price)
VALUES ('SO99998', 'BK-R93R-62', 21768, 20140301, 20991399, 20140313, 3578, 1, 3578);

BEGIN TRY
    EXEC silver.load_silver;
END TRY
BEGIN CATCH
    PRINT 'Expected failure: ' + ERROR_MESSAGE();
END CATCH

INSERT INTO @results
SELECT
    'Test 10: Failed load is logged and the watermark does not move',
    CASE
        WHEN (SELECT TOP 1 status
              FROM audit.etl_log
              WHERE table_name = 'silver.crm_sales_details'
              ORDER BY log_id DESC) = 'FAILED'
         AND (SELECT last_watermark_value FROM audit.watermark_control WHERE table_name = 'crm_sales_details') = @wm_sales
         AND (SELECT COUNT(*) FROM silver.crm_sales_details) = @sales_count
        THEN 'PASS' ELSE 'FAIL'
    END;

-- Remove the broken record from Bronze
DELETE FROM bronze.crm_sales_details
WHERE sls_ord_num = 'SO99998';

-- ====================================================================
-- Test Results
-- ====================================================================
SELECT test_name, result FROM @results;

SELECT
    COUNT(*)                                          AS total_tests,
    SUM(CASE WHEN result = 'PASS' THEN 1 ELSE 0 END) AS passed,
    SUM(CASE WHEN result = 'FAIL' THEN 1 ELSE 0 END) AS failed
FROM @results;
