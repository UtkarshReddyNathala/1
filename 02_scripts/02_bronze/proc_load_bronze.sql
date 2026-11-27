-- Loads the six CSV files into the Bronze tables (full load: empty each table, then insert all rows).
-- Every table load is written to audit.etl_log. Run with: EXEC bronze.load_bronze;

CREATE OR ALTER PROCEDURE bronze.load_bronze
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
        PRINT 'Loading Bronze Layer (Batch ID: ' + CAST(@batch_id AS NVARCHAR) + ')';
        PRINT '================================================';

        -- FULL LOAD for every table: empty it, then copy all rows from its CSV file.
        -- Each table is loaded in its own transaction, so a failed load keeps the old data.
        -- Change the file paths below if the datasets are saved in another folder.
        PRINT '------------------------------------------------';
        PRINT 'Loading CRM Tables';
        PRINT '------------------------------------------------';

        SET @start_time = GETDATE();
        SET @table_name = 'bronze.crm_cust_info';
        BEGIN TRANSACTION;
        PRINT '>> Truncating Table: bronze.crm_cust_info';
        TRUNCATE TABLE bronze.crm_cust_info;
        PRINT '>> Inserting Data Into: bronze.crm_cust_info';
        BULK INSERT bronze.crm_cust_info
        FROM 'C:\sql\dwh_project\01_datasets\source_crm\cust_info.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @rows_processed = @@ROWCOUNT;
        SET @end_time = GETDATE();
        -- AUDIT: record the result of this table load
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'bronze', @table_name, @start_time, @end_time, @rows_processed, 'SUCCESS', NULL);
        COMMIT TRANSACTION;
        PRINT '>> Rows Loaded: ' + CAST(@rows_processed AS NVARCHAR);
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @start_time = GETDATE();
        SET @table_name = 'bronze.crm_prd_info';
        BEGIN TRANSACTION;
        PRINT '>> Truncating Table: bronze.crm_prd_info';
        TRUNCATE TABLE bronze.crm_prd_info;
        PRINT '>> Inserting Data Into: bronze.crm_prd_info';
        BULK INSERT bronze.crm_prd_info
        FROM 'C:\sql\dwh_project\01_datasets\source_crm\prd_info.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @rows_processed = @@ROWCOUNT;
        SET @end_time = GETDATE();
        -- AUDIT: record the result of this table load
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'bronze', @table_name, @start_time, @end_time, @rows_processed, 'SUCCESS', NULL);
        COMMIT TRANSACTION;
        PRINT '>> Rows Loaded: ' + CAST(@rows_processed AS NVARCHAR);
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @start_time = GETDATE();
        SET @table_name = 'bronze.crm_sales_details';
        BEGIN TRANSACTION;
        PRINT '>> Truncating Table: bronze.crm_sales_details';
        TRUNCATE TABLE bronze.crm_sales_details;
        PRINT '>> Inserting Data Into: bronze.crm_sales_details';
        BULK INSERT bronze.crm_sales_details
        FROM 'C:\sql\dwh_project\01_datasets\source_crm\sales_details.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @rows_processed = @@ROWCOUNT;
        SET @end_time = GETDATE();
        -- AUDIT: record the result of this table load
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'bronze', @table_name, @start_time, @end_time, @rows_processed, 'SUCCESS', NULL);
        COMMIT TRANSACTION;
        PRINT '>> Rows Loaded: ' + CAST(@rows_processed AS NVARCHAR);
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        PRINT '------------------------------------------------';
        PRINT 'Loading ERP Tables';
        PRINT '------------------------------------------------';

        SET @start_time = GETDATE();
        SET @table_name = 'bronze.erp_loc_a101';
        BEGIN TRANSACTION;
        PRINT '>> Truncating Table: bronze.erp_loc_a101';
        TRUNCATE TABLE bronze.erp_loc_a101;
        PRINT '>> Inserting Data Into: bronze.erp_loc_a101';
        BULK INSERT bronze.erp_loc_a101
        FROM 'C:\sql\dwh_project\01_datasets\source_erp\LOC_A101.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @rows_processed = @@ROWCOUNT;
        SET @end_time = GETDATE();
        -- AUDIT: record the result of this table load
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'bronze', @table_name, @start_time, @end_time, @rows_processed, 'SUCCESS', NULL);
        COMMIT TRANSACTION;
        PRINT '>> Rows Loaded: ' + CAST(@rows_processed AS NVARCHAR);
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @start_time = GETDATE();
        SET @table_name = 'bronze.erp_cust_az12';
        BEGIN TRANSACTION;
        PRINT '>> Truncating Table: bronze.erp_cust_az12';
        TRUNCATE TABLE bronze.erp_cust_az12;
        PRINT '>> Inserting Data Into: bronze.erp_cust_az12';
        BULK INSERT bronze.erp_cust_az12
        FROM 'C:\sql\dwh_project\01_datasets\source_erp\CUST_AZ12.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @rows_processed = @@ROWCOUNT;
        SET @end_time = GETDATE();
        -- AUDIT: record the result of this table load
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'bronze', @table_name, @start_time, @end_time, @rows_processed, 'SUCCESS', NULL);
        COMMIT TRANSACTION;
        PRINT '>> Rows Loaded: ' + CAST(@rows_processed AS NVARCHAR);
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @start_time = GETDATE();
        SET @table_name = 'bronze.erp_px_cat_g1v2';
        BEGIN TRANSACTION;
        PRINT '>> Truncating Table: bronze.erp_px_cat_g1v2';
        TRUNCATE TABLE bronze.erp_px_cat_g1v2;
        PRINT '>> Inserting Data Into: bronze.erp_px_cat_g1v2';
        BULK INSERT bronze.erp_px_cat_g1v2
        FROM 'C:\sql\dwh_project\01_datasets\source_erp\PX_CAT_G1V2.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
        SET @rows_processed = @@ROWCOUNT;
        SET @end_time = GETDATE();
        -- AUDIT: record the result of this table load
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'bronze', @table_name, @start_time, @end_time, @rows_processed, 'SUCCESS', NULL);
        COMMIT TRANSACTION;
        PRINT '>> Rows Loaded: ' + CAST(@rows_processed AS NVARCHAR);
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @batch_end_time = GETDATE();
        PRINT '==========================================';
        PRINT 'Loading Bronze Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
        PRINT '==========================================';
    END TRY
    BEGIN CATCH
        -- ERROR HANDLING: undo the unfinished table load, so the table keeps its previous data
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Log the failure for the table that was being loaded
        INSERT INTO audit.etl_log (batch_id, layer, table_name, start_time, end_time, rows_processed, status, error_message)
        VALUES (@batch_id, 'bronze', @table_name, @start_time, GETDATE(), 0, 'FAILED', ERROR_MESSAGE());

        PRINT '==========================================';
        PRINT 'ERROR OCCURRED DURING LOADING BRONZE LAYER';
        PRINT 'Table: ' + ISNULL(@table_name, 'n/a');
        PRINT 'Error Message: ' + ERROR_MESSAGE();
        PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT 'Error State: ' + CAST(ERROR_STATE() AS NVARCHAR);
        PRINT '==========================================';

        -- Re-raise the error, so the caller (dbo.load_all) stops and does not load Silver
        THROW;
    END CATCH
END
