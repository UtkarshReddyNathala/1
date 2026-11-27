-- Creates the audit objects: a log of every ETL run and a watermark table that remembers where each load stopped.
-- Run once after 01_init_database.sql. Running it again clears all ETL history and watermarks.

-- =============================================================================
-- Create Sequence: audit.batch_id_seq
-- =============================================================================
IF OBJECT_ID('audit.batch_id_seq', 'SO') IS NOT NULL
    DROP SEQUENCE audit.batch_id_seq;
GO

-- Gives every ETL run its own number (batch ID), so all logs of one run can be found together
CREATE SEQUENCE audit.batch_id_seq
    AS INT
    START WITH 1
    INCREMENT BY 1;
GO

-- =============================================================================
-- Create Table: audit.etl_log
-- =============================================================================
IF OBJECT_ID('audit.etl_log', 'U') IS NOT NULL
    DROP TABLE audit.etl_log;
GO

-- AUDIT LOG: one row for every table load, with its status, duration, row count and error message
CREATE TABLE audit.etl_log (
    log_id          INT IDENTITY(1, 1) PRIMARY KEY,
    batch_id        INT,
    layer           NVARCHAR(50),
    table_name      NVARCHAR(100),
    start_time      DATETIME2,
    end_time        DATETIME2,
    rows_processed  INT,            -- Rows inserted or updated
    status          NVARCHAR(20),   -- SUCCESS or FAILED
    error_message   NVARCHAR(MAX)
);
GO

-- =============================================================================
-- Create Table: audit.watermark_control
-- =============================================================================
IF OBJECT_ID('audit.watermark_control', 'U') IS NOT NULL
    DROP TABLE audit.watermark_control;
GO

-- WATERMARK TABLE: the last loaded value of each incremental table.
-- The next run reads only the rows on or after this value, instead of reloading everything.
CREATE TABLE audit.watermark_control (
    table_name            NVARCHAR(100) PRIMARY KEY,
    watermark_column      NVARCHAR(100),
    last_watermark_value  DATETIME2,
    last_updated          DATETIME2 DEFAULT GETDATE()
);
GO

-- Initial watermarks: '1900-01-01' means "nothing loaded yet", so the first run loads everything
INSERT INTO audit.watermark_control (table_name, watermark_column, last_watermark_value)
VALUES
    ('crm_cust_info',     'cst_create_date', '1900-01-01'),
    ('crm_prd_info',      'prd_start_dt',    '1900-01-01'),
    ('crm_sales_details', 'sls_ship_dt',     '1900-01-01');
GO
