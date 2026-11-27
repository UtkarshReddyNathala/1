-- Cleans the Bronze data and loads it into Silver: only new or changed CRM rows (incremental), ERP tables in full.
-- Customers use SCD Type 1 (overwrite), products use SCD Type 2 (keep history). Run with: EXEC silver.load_silver;

CREATE OR ALTER PROCEDURE silver.load_silver
    @batch_id INT = NULL   -- ID of the ETL run; a new one is created when it is not given
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
    DECLARE @table_name NVARCHAR(100), @rows_inserted INT, @rows_updated INT;
    DECLARE @last_watermark DATETIME2, @new_watermark DATETIME2;

    IF @batch_id IS NULL
        SET @batch_id = NEXT VALUE FOR audit.batch_id_seq;

    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Silver Layer (Batch ID: ' + CAST(@batch_id AS NVARCHAR) + ')';
        PRINT '================================================';

        PRINT '------------------------------------------------';
        PRINT 'Loading CRM Tables';
        PRINT '------------------------------------------------';

        -- =====================================================================
        -- Loading silver.crm_cust_info (incremental load + SCD Type 1)
        -- =====================================================================
        SET @start_time = GETDATE();
        SET @table_name = 'silver.crm_cust_info';
        PRINT '>> Loading Table: silver.crm_cust_info';

        -- WATERMARK: read the date where the last customer load stopped.
        -- A new or corrected customer always arrives as a row with a newer cst_create_date.
        SELECT @last_watermark = last_watermark_value
        FROM audit.watermark_control
        WHERE table_name = 'crm_cust_info';

        -- Step 1 - INCREMENTAL LOAD: copy only the Bronze rows on or after the watermark into a temp table, and clean them.
        -- '>=' reads the last loaded day again, in case more rows arrived for it; the hash check skips the unchanged ones.
        IF OBJECT_ID('tempdb..#stg_cust_info') IS NOT NULL
            DROP TABLE #stg_cust_info;

        SELECT
            cst_id,
            cst_key,
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname)  AS cst_lastname,
            CASE
                WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
                WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
                ELSE 'n/a'
            END                 AS cst_marital_status, -- Turn 'S' / 'M' into 'Single' / 'Married'
            CASE
                WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
                WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
                ELSE 'n/a'
            END                 AS cst_gndr,           -- Turn 'F' / 'M' into 'Female' / 'Male'
            cst_create_date,
            CAST(NULL AS VARBINARY(32)) AS cst_hash
        INTO #stg_cust_info
        FROM (
            SELECT
                *,
                ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
            FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL
              AND cst_create_date >= @last_watermark
        ) t
        WHERE flag_last = 1; -- Keep only the newest row of each customer (removes duplicates)

        -- Step 2 - HASH: turn the customer columns into one SHA2_256 fingerprint.
        -- If any column changes, the fingerprint changes, so one comparison finds every change.
        UPDATE #stg_cust_info
        SET cst_hash = HASHBYTES(
            'SHA2_256',
            CONCAT(
                ISNULL(cst_key, ''),            '|',
                ISNULL(cst_firstname, ''),      '|',
                ISNULL(cst_lastname, ''),       '|',
                ISNULL(cst_marital_status, ''), '|',
                ISNULL(cst_gndr, '')
            )
        );

        SELECT @new_watermark = MAX(cst_create_date) FROM #stg_cust_info;

        BEGIN TRANSACTION;

        -- Step 3 - SCD TYPE 1: the customer exists but its hash is different, so overwrite the old values (no history kept)
        UPDATE s
        SET
            s.cst_key            = t.cst_key,
            s.cst_firstname      = t.cst_firstname,
            s.cst_lastname       = t.cst_lastname,
            s.cst_marital_status = t.cst_marital_status,
            s.cst_gndr           = t.cst_gndr,
            s.cst_create_date    = t.cst_create_date,
            s.cst_hash           = t.cst_hash
        FROM silver.crm_cust_info s
        INNER JOIN #stg_cust_info t
            ON s.cst_id = t.cst_id
        WHERE s.cst_hash <> t.cst_hash;
        SET @rows_updated = @@ROWCOUNT;

        -- Step 4: insert customers that are not in Silver yet
        INSERT INTO silver.crm_cust_info (
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date,
            cst_hash
        )
        SELECT
            t.cst_id,
            t.cst_key,
            t.cst_firstname,
            t.cst_lastname,
            t.cst_marital_status,
            t.cst_gndr,
            t.cst_create_date,
            t.cst_hash
        FROM #stg_cust_info t
        WHERE NOT EXISTS (
            SELECT 1
            FROM silver.crm_cust_info s
            WHERE s.cst_id = t.cst_id
        );
        SET @rows_inserted = @@ROWCOUNT;

        -- Step 5 - WATERMARK: save the newest date that was read, so the next run starts from there.
        -- This happens inside the same transaction as the load, so a failed load never moves the watermark.
        UPDATE audit.watermark_control
        SET
            last_watermark_value = @new_watermark,
            last_updated         = GETDATE()
        WHERE table_name = 'crm_cust_info'
          AND @new_watermark IS NOT NULL;

        SET @end_time = GETDATE();
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'silver', @table_name, @start_time, @end_time, @rows_inserted + @rows_updated, 'SUCCESS', NULL);

        COMMIT TRANSACTION;
        PRINT '>> Inserted: ' + CAST(@rows_inserted AS NVARCHAR) + ', Updated: ' + CAST(@rows_updated AS NVARCHAR);
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- =====================================================================
        -- Loading silver.crm_prd_info (incremental load + SCD Type 2)
        -- =====================================================================
        SET @start_time = GETDATE();
        SET @table_name = 'silver.crm_prd_info';
        PRINT '>> Loading Table: silver.crm_prd_info';

        -- WATERMARK: read the date where the last product load stopped.
        -- Every new version of a product arrives as a new row with a newer prd_start_dt.
        SELECT @last_watermark = last_watermark_value
        FROM audit.watermark_control
        WHERE table_name = 'crm_prd_info';

        -- Step 1 - INCREMENTAL LOAD: copy only the Bronze rows on or after the watermark into a temp table, and clean them
        IF OBJECT_ID('tempdb..#stg_prd_info') IS NOT NULL
            DROP TABLE #stg_prd_info;

        SELECT
            prd_id,
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,       -- First 5 characters = category ID (matches the ERP format)
            SUBSTRING(prd_key, 7, LEN(prd_key))         AS prd_key,      -- The rest = product key (matches the sales table)
            prd_nm,
            ISNULL(prd_cost, 0)                         AS prd_cost,
            CASE
                WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
                WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
                WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
                WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
                ELSE 'n/a'
            END                                         AS prd_line,     -- Turn product line codes into readable names
            CAST(prd_start_dt AS DATE)                  AS prd_start_dt,
            CAST(NULL AS VARBINARY(32))                 AS prd_hash,
            CAST(NULL AS VARBINARY(32))                 AS previous_hash
        INTO #stg_prd_info
        FROM bronze.crm_prd_info
        WHERE prd_start_dt >= @last_watermark;

        -- Step 2 - HASH: turn the product columns into one SHA2_256 fingerprint
        UPDATE #stg_prd_info
        SET prd_hash = HASHBYTES(
            'SHA2_256',
            CONCAT(
                ISNULL(cat_id, ''),   '|',
                ISNULL(prd_nm, ''),   '|',
                ISNULL(CAST(prd_cost AS NVARCHAR(20)), ''), '|',
                ISNULL(prd_line, '')
            )
        );

        SELECT @new_watermark = MAX(prd_start_dt) FROM #stg_prd_info;

        -- Step 3 - HASH CHECK: find the hash of the version that came before each new row.
        -- That is the earlier new row of the same product, or (for the first one) the current version in Silver.
        WITH previous_versions AS (
            SELECT
                previous_hash,
                LAG(prd_hash) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) AS lag_hash
            FROM #stg_prd_info
        )
        UPDATE previous_versions
        SET previous_hash = lag_hash;

        UPDATE t
        SET t.previous_hash = s.prd_hash
        FROM #stg_prd_info t
        INNER JOIN silver.crm_prd_info s
            ON  s.prd_key    = t.prd_key
            AND s.is_current = 1
        WHERE t.previous_hash IS NULL;

        -- Step 4: drop the rows whose hash did not change. What is left is a new product or a real change.
        DELETE FROM #stg_prd_info
        WHERE prd_hash = previous_hash;

        BEGIN TRANSACTION;

        -- Step 5 - SCD TYPE 2: close the current version of every changed product (keep it as history).
        -- The old version ends one day before the new version starts, and is no longer marked as current.
        UPDATE s
        SET
            s.prd_end_dt = DATEADD(day, -1, t.first_start_dt),
            s.is_current = 0
        FROM silver.crm_prd_info s
        INNER JOIN (
            SELECT
                prd_key,
                MIN(prd_start_dt) AS first_start_dt
            FROM #stg_prd_info
            GROUP BY prd_key
        ) t
            ON s.prd_key = t.prd_key
        WHERE s.is_current = 1;
        SET @rows_updated = @@ROWCOUNT;

        -- Step 6 - SCD TYPE 2: insert the new versions. Only the newest version of each product is marked as current.
        INSERT INTO silver.crm_prd_info (
            prd_id,
            cat_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt,
            is_current,
            prd_hash
        )
        SELECT
            prd_id,
            cat_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            DATEADD(
                day, -1,
                LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)
            ) AS prd_end_dt, -- Calculate end date as one day before the next start date
            CASE
                WHEN LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) IS NULL THEN 1
                ELSE 0
            END AS is_current, -- The version without a next version is the current one
            prd_hash
        FROM #stg_prd_info;
        SET @rows_inserted = @@ROWCOUNT;

        -- Step 7 - WATERMARK: save the newest date that was read, and write the result to the audit log
        UPDATE audit.watermark_control
        SET
            last_watermark_value = @new_watermark,
            last_updated         = GETDATE()
        WHERE table_name = 'crm_prd_info'
          AND @new_watermark IS NOT NULL;

        SET @end_time = GETDATE();
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'silver', @table_name, @start_time, @end_time, @rows_inserted + @rows_updated, 'SUCCESS', NULL);

        COMMIT TRANSACTION;
        PRINT '>> Inserted: ' + CAST(@rows_inserted AS NVARCHAR) + ', Expired: ' + CAST(@rows_updated AS NVARCHAR);
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- =====================================================================
        -- Loading silver.crm_sales_details (incremental load, insert only)
        -- =====================================================================
        SET @start_time = GETDATE();
        SET @table_name = 'silver.crm_sales_details';
        PRINT '>> Loading Table: silver.crm_sales_details';

        -- WATERMARK: read the ship date where the last sales load stopped.
        -- The ship date is used because every row has one, while some order dates are invalid.
        SELECT @last_watermark = last_watermark_value
        FROM audit.watermark_control
        WHERE table_name = 'crm_sales_details';

        -- Step 1 - INCREMENTAL LOAD: copy only the Bronze rows on or after the watermark into a temp table, and clean them
        IF OBJECT_ID('tempdb..#stg_sales_details') IS NOT NULL
            DROP TABLE #stg_sales_details;

        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            -- Dates arrive as numbers like 20131229. Invalid ones (0 or wrong length) become NULL.
            CASE
                WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
            END AS sls_order_dt,
            CASE
                WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
            END AS sls_ship_dt,
            CASE
                WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
            END AS sls_due_dt,
            CASE
                WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
                    THEN sls_quantity * ABS(sls_price)
                ELSE sls_sales
            END AS sls_sales,    -- If sales is missing or wrong, recalculate it as quantity * price
            sls_quantity,
            CASE
                WHEN sls_price IS NULL OR sls_price <= 0
                    THEN sls_sales / NULLIF(sls_quantity, 0)
                ELSE sls_price  -- If price is missing or negative, calculate it as sales / quantity
            END AS sls_price
        INTO #stg_sales_details
        FROM bronze.crm_sales_details
        WHERE sls_ship_dt >= CAST(CONVERT(CHAR(8), @last_watermark, 112) AS INT) -- Bronze stores dates as YYYYMMDD numbers
           OR sls_ship_dt = 0
           OR LEN(sls_ship_dt) != 8; -- Rows without a valid ship date are always read, so they are never skipped

        SELECT @new_watermark = MAX(sls_ship_dt) FROM #stg_sales_details;

        BEGIN TRANSACTION;

        -- Step 2: insert only the sales rows that are not in Silver yet (one order number + one product = one sales row).
        -- Sales are never changed after they happen, so they are only inserted, never updated.
        INSERT INTO silver.crm_sales_details (
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )
        SELECT
            t.sls_ord_num,
            t.sls_prd_key,
            t.sls_cust_id,
            t.sls_order_dt,
            t.sls_ship_dt,
            t.sls_due_dt,
            t.sls_sales,
            t.sls_quantity,
            t.sls_price
        FROM #stg_sales_details t
        WHERE NOT EXISTS (
            SELECT 1
            FROM silver.crm_sales_details s
            WHERE s.sls_ord_num = t.sls_ord_num
              AND s.sls_prd_key = t.sls_prd_key
        );
        SET @rows_inserted = @@ROWCOUNT;

        -- Step 3 - WATERMARK: save the newest ship date that was read, and write the result to the audit log
        UPDATE audit.watermark_control
        SET
            last_watermark_value = @new_watermark,
            last_updated         = GETDATE()
        WHERE table_name = 'crm_sales_details'
          AND @new_watermark IS NOT NULL;

        SET @end_time = GETDATE();
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'silver', @table_name, @start_time, @end_time, @rows_inserted, 'SUCCESS', NULL);

        COMMIT TRANSACTION;
        PRINT '>> Inserted: ' + CAST(@rows_inserted AS NVARCHAR);
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        PRINT '------------------------------------------------';
        PRINT 'Loading ERP Tables';
        PRINT '------------------------------------------------';

        -- =====================================================================
        -- Loading silver.erp_cust_az12 (full load: small lookup table, reloaded every run)
        -- =====================================================================
        SET @start_time = GETDATE();
        SET @table_name = 'silver.erp_cust_az12';
        BEGIN TRANSACTION;
        PRINT '>> Truncating Table: silver.erp_cust_az12';
        TRUNCATE TABLE silver.erp_cust_az12;
        PRINT '>> Inserting Data Into: silver.erp_cust_az12';
        INSERT INTO silver.erp_cust_az12 (
            cid,
            bdate,
            gen
        )
        SELECT
            CASE
                WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid)) -- Remove 'NAS' prefix if present
                ELSE cid
            END AS cid,
            CASE
                WHEN bdate > GETDATE() THEN NULL
                ELSE bdate
            END AS bdate, -- Set future birthdates to NULL
            CASE
                WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
                WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
                ELSE 'n/a'
            END AS gen    -- Turn gender codes into 'Female' / 'Male', and unknown values into 'n/a'
        FROM bronze.erp_cust_az12;
        SET @rows_inserted = @@ROWCOUNT;
        SET @end_time = GETDATE();
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'silver', @table_name, @start_time, @end_time, @rows_inserted, 'SUCCESS', NULL);
        COMMIT TRANSACTION;
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- =====================================================================
        -- Loading silver.erp_loc_a101 (full load: small lookup table, reloaded every run)
        -- =====================================================================
        SET @start_time = GETDATE();
        SET @table_name = 'silver.erp_loc_a101';
        BEGIN TRANSACTION;
        PRINT '>> Truncating Table: silver.erp_loc_a101';
        TRUNCATE TABLE silver.erp_loc_a101;
        PRINT '>> Inserting Data Into: silver.erp_loc_a101';
        INSERT INTO silver.erp_loc_a101 (
            cid,
            cntry
        )
        SELECT
            REPLACE(cid, '-', '') AS cid,
            CASE
                WHEN TRIM(cntry) = 'DE' THEN 'Germany'
                WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
                WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
                ELSE TRIM(cntry)
            END                   AS cntry -- Turn country codes into full names, and blanks into 'n/a'
        FROM bronze.erp_loc_a101;
        SET @rows_inserted = @@ROWCOUNT;
        SET @end_time = GETDATE();
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'silver', @table_name, @start_time, @end_time, @rows_inserted, 'SUCCESS', NULL);
        COMMIT TRANSACTION;
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- =====================================================================
        -- Loading silver.erp_px_cat_g1v2 (full load: small lookup table, reloaded every run)
        -- =====================================================================
        SET @start_time = GETDATE();
        SET @table_name = 'silver.erp_px_cat_g1v2';
        BEGIN TRANSACTION;
        PRINT '>> Truncating Table: silver.erp_px_cat_g1v2';
        TRUNCATE TABLE silver.erp_px_cat_g1v2;
        PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';
        INSERT INTO silver.erp_px_cat_g1v2 (
            id,
            cat,
            subcat,
            maintenance
        )
        SELECT
            id,
            cat,
            subcat,
            maintenance
        FROM bronze.erp_px_cat_g1v2;
        SET @rows_inserted = @@ROWCOUNT;
        SET @end_time = GETDATE();
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'silver', @table_name, @start_time, @end_time, @rows_inserted, 'SUCCESS', NULL);
        COMMIT TRANSACTION;
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @batch_end_time = GETDATE();
        PRINT '==========================================';
        PRINT 'Loading Silver Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
        PRINT '==========================================';

    END TRY
    BEGIN CATCH
        -- ERROR HANDLING: undo the unfinished table load. Its watermark did not move, so the next run simply tries again.
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Log the failure for the table that was being loaded
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'silver', @table_name, @start_time, GETDATE(), 0, 'FAILED', ERROR_MESSAGE());

        PRINT '==========================================';
        PRINT 'ERROR OCCURRED DURING LOADING SILVER LAYER';
        PRINT 'Table: ' + ISNULL(@table_name, 'n/a');
        PRINT 'Error Message: ' + ERROR_MESSAGE();
        PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT 'Error State: ' + CAST(ERROR_STATE() AS NVARCHAR);
        PRINT '==========================================';

        -- Re-raise the error, so the caller knows the load failed
        THROW;
    END CATCH
END
