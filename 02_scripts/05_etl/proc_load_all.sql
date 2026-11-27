-- Runs the whole ETL in the right order (Bronze, then Silver, then Gold) under one batch ID.
-- This is the only command needed to refresh the warehouse: EXEC dbo.load_all;

CREATE OR ALTER PROCEDURE dbo.load_all AS
BEGIN
    SET NOCOUNT ON;
    -- One batch ID for the whole run, shared by all three layers in audit.etl_log
    DECLARE @batch_id INT = NEXT VALUE FOR audit.batch_id_seq;

    -- Each step stops the run if it fails, so a later layer never loads half-finished data

    EXEC bronze.load_bronze @batch_id = @batch_id;
    EXEC silver.load_silver @batch_id = @batch_id;
    EXEC gold.load_gold     @batch_id = @batch_id;

    PRINT 'Data Warehouse load is completed (Batch ID: ' + CAST(@batch_id AS NVARCHAR) + ')';
END
GO
