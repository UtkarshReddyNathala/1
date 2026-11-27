-- Rebuilds the Gold star schema from Silver after every load: first the two dimensions, then the fact table.
-- Runs as one transaction, so if anything fails Gold keeps its previous data. Run with: EXEC gold.load_gold;

CREATE OR ALTER PROCEDURE gold.load_gold
    @batch_id INT = NULL   -- ID of the ETL run; a new one is created when it is not given
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
    DECLARE @table_name NVARCHAR(100), @rows_processed INT;

    IF @batch_id IS NULL
        SET @batch_id = NEXT VALUE FOR audit.batch_id_seq;

    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Gold Layer (Batch ID: ' + CAST(@batch_id AS NVARCHAR) + ')';
        PRINT '================================================';

        -- One transaction for the whole rebuild: readers see either the old Gold data or the new one, never half
        BEGIN TRANSACTION;

        -- The fact table points to the dimension keys, so it is emptied first
        PRINT '>> Truncating Tables: gold.fact_sales, gold.dim_customers, gold.dim_products';
        TRUNCATE TABLE gold.fact_sales;
        TRUNCATE TABLE gold.dim_customers;
        TRUNCATE TABLE gold.dim_products;

        -- =====================================================================
        -- Loading gold.dim_customers
        -- =====================================================================
        SET @start_time = GETDATE();
        SET @table_name = 'gold.dim_customers';
        PRINT '>> Inserting Data Into: gold.dim_customers';
        INSERT INTO gold.dim_customers (
            customer_key,
            customer_id,
            customer_number,
            first_name,
            last_name,
            country,
            marital_status,
            gender,
            birthdate,
            create_date
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key, -- Surrogate key: a simple 1, 2, 3... ID made by the warehouse
            ci.cst_id,
            ci.cst_key,
            ci.cst_firstname,
            ci.cst_lastname,
            la.cntry,
            ci.cst_marital_status,
            CASE
                WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr -- CRM is the primary source for gender
                ELSE COALESCE(ca.gen, 'n/a')               -- Fallback to ERP data
            END,
            ca.bdate,
            ci.cst_create_date
        FROM silver.crm_cust_info ci            -- Join the CRM customer with its ERP birthdate/gender and country
        LEFT JOIN silver.erp_cust_az12 ca
            ON ci.cst_key = ca.cid
        LEFT JOIN silver.erp_loc_a101 la
            ON ci.cst_key = la.cid;
        SET @rows_processed = @@ROWCOUNT;
        SET @end_time = GETDATE();
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'gold', @table_name, @start_time, @end_time, @rows_processed, 'SUCCESS', NULL);
        PRINT '>> Rows Loaded: ' + CAST(@rows_processed AS NVARCHAR);
        PRINT '>> -------------';

        -- =====================================================================
        -- Loading gold.dim_products
        -- =====================================================================
        SET @start_time = GETDATE();
        SET @table_name = 'gold.dim_products';
        PRINT '>> Inserting Data Into: gold.dim_products';
        INSERT INTO gold.dim_products (
            product_key,
            product_id,
            product_number,
            product_name,
            category_id,
            category,
            subcategory,
            maintenance,
            cost,
            product_line,
            start_date
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key, -- Surrogate key: a simple 1, 2, 3... ID made by the warehouse
            pn.prd_id,
            pn.prd_key,
            pn.prd_nm,
            pn.cat_id,
            pc.cat,
            pc.subcat,
            pc.maintenance,
            pn.prd_cost,
            pn.prd_line,
            pn.prd_start_dt
        FROM silver.crm_prd_info pn
        LEFT JOIN silver.erp_px_cat_g1v2 pc
            ON pn.cat_id = pc.id
        WHERE pn.is_current = 1; -- Keep only the current version of each product (SCD Type 2 history stays in Silver)
        SET @rows_processed = @@ROWCOUNT;
        SET @end_time = GETDATE();
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'gold', @table_name, @start_time, @end_time, @rows_processed, 'SUCCESS', NULL);
        PRINT '>> Rows Loaded: ' + CAST(@rows_processed AS NVARCHAR);
        PRINT '>> -------------';

        -- =====================================================================
        -- Loading gold.fact_sales
        -- =====================================================================
        SET @start_time = GETDATE();
        SET @table_name = 'gold.fact_sales';

        -- PERFORMANCE: load the fact table without the columnstore index, then build the index once at the end.
        -- For fewer than 102,400 rows this is about twice as fast as inserting into the index directly.
        -- Step 1: remove the columnstore index, so the rows go into a plain table (fast insert)
        DROP INDEX cci_fact_sales ON gold.fact_sales;

        -- Step 2: insert the sales rows and look up the customer and product surrogate keys
        PRINT '>> Inserting Data Into: gold.fact_sales';
        INSERT INTO gold.fact_sales WITH (TABLOCK) (
            order_number,
            product_key,
            customer_key,
            order_date,
            shipping_date,
            due_date,
            sales_amount,
            quantity,
            price
        )
        SELECT
            sd.sls_ord_num  AS order_number,
            pr.product_key  AS product_key,
            cu.customer_key AS customer_key,
            sd.sls_order_dt AS order_date,
            sd.sls_ship_dt  AS shipping_date,
            sd.sls_due_dt   AS due_date,
            sd.sls_sales    AS sales_amount,
            sd.sls_quantity AS quantity,
            sd.sls_price    AS price
        FROM silver.crm_sales_details sd
        LEFT JOIN gold.dim_products pr
            ON sd.sls_prd_key = pr.product_number
        LEFT JOIN gold.dim_customers cu
            ON sd.sls_cust_id = cu.customer_id;
        SET @rows_processed = @@ROWCOUNT;

        -- Step 3 - COLUMNSTORE: build the index once on all rows. The data is stored compressed, column by column,
        -- so reports read only the columns they need and run in fast batch mode.
        PRINT '>> Building Columnstore Index: cci_fact_sales';
        CREATE CLUSTERED COLUMNSTORE INDEX cci_fact_sales ON gold.fact_sales;

        SET @end_time = GETDATE();
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'gold', @table_name, @start_time, @end_time, @rows_processed, 'SUCCESS', NULL);
        PRINT '>> Rows Loaded: ' + CAST(@rows_processed AS NVARCHAR);
        PRINT '>> -------------';

        COMMIT TRANSACTION;

        SET @batch_end_time = GETDATE();
        PRINT '==========================================';
        PRINT 'Loading Gold Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
        PRINT '==========================================';
    END TRY
    BEGIN CATCH
        -- ERROR HANDLING: undo the whole rebuild, so Gold keeps its previous data
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Log the failure for the table that was being loaded
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'gold', @table_name, @start_time, GETDATE(), 0, 'FAILED', ERROR_MESSAGE());

        PRINT '==========================================';
        PRINT 'ERROR OCCURRED DURING LOADING GOLD LAYER';
        PRINT 'Table: ' + ISNULL(@table_name, 'n/a');
        PRINT 'Error Message: ' + ERROR_MESSAGE();
        PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT 'Error State: ' + CAST(ERROR_STATE() AS NVARCHAR);
        PRINT '==========================================';

        -- Re-raise the error, so the caller knows the load failed
        THROW;
    END CATCH
END
