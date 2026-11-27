# Data Warehouse and Analytics System

A SQL Server data warehouse that combines **116K+ records** from two source systems (CRM and ERP) into a **star schema**, loads only new and changed data, and makes analytical queries **up to 98x faster** with columnstore storage.

| 116,292 | 98x | 156,483 → 380 | 0 rows | 10 / 10 |
|:--:|:--:|:--:|:--:|:--:|
| source records integrated | fastest query speed-up | pages read by the customer report | processed when nothing changed | automated tests passed |

---

## Problem Statement

- Sales data is split across two systems: the **CRM** (customers, products, sales) and the **ERP** (birthdates, countries, categories). Their keys do not match.
- The raw data has duplicates, extra spaces, codes instead of names, invalid dates and wrong sales amounts.
- Reloading everything on every run wastes time and loses the history of changes.
- Reports built on views recalculate every join on every run, so they are slow.

---

## Key Features

| Feature | What it does |
|:--|:--|
| **Medallion architecture** | Bronze (raw) → Silver (clean) → Gold (business-ready), built with SQL stored procedures |
| **Star schema data model** | One fact table (`fact_sales`) and two dimensions (`dim_customers`, `dim_products`) |
| **Incremental loading** | A **watermark** per table remembers where the last load stopped; only newer rows are read |
| **Change detection** | A **SHA2_256 hash** of each row shows in one comparison whether anything changed |
| **SCD Type 1 and Type 2** | Changed customers are overwritten (Type 1); changed products get a new version and keep their history (Type 2) |
| **Query performance** | Gold stored as tables, with a **clustered columnstore index** on the fact table |
| **Audit logging and error handling** | Every table load is logged (status, rows, time, error); a failed load is rolled back and the watermark does not move |
| **Analytics and reports** | 13 SQL scripts: exploration, trends, rankings, segmentation, plus customer and product report views |

---

## Architecture

![Data Architecture](04_docs/data_architecture.png)

### Data Flow

![Data Flow](04_docs/data_flow.png)

---

## Data Model

A **star schema** in the Gold layer: `fact_sales` holds one row per order line and links to `dim_customers` and `dim_products` through surrogate keys.

![Data Model](04_docs/data_model.png)

---

## Results

### Query performance

Gold built as views compared with Gold built as tables plus a clustered columnstore index. Measured on SQL Server 2022 with the project data; median of 10 runs.

| Query | Pages read (before → after) | Time (before → after) | Speed-up |
|:--|--:|--:|--:|
| Customer report | 156,483 → 380 | 638 ms → 164 ms | **3.9x** |
| Product report | 168,535 → 109 | 619 ms → 35 ms | **17.9x** |
| Revenue by category | 1,774 → 17 | 79 ms → 3 ms | **26.3x** |
| Orders of one customer | 1,759 → 107 | 99 ms → 1 ms | **98.5x** |

**How:** with views, every query rebuilt the keys and joins and used temporary worktables (spools). Storing Gold as tables does that work once per load, and the columnstore index lets queries read compressed columns in fast batch mode. The customer report plan went from **30+ steps to 7** (execution plans in `04_docs/execution_plans/`).

Also tested and not used, because they gave no gain: extra indexes on Silver, rowstore indexes on the fact table, and partitioning by year.

### Data loading

| Check | Result |
|:--|:--|
| First load | 18,484 customers, 295 products (397 versions with history), 60,398 sales |
| Second load with no new data | 0 rows inserted or updated |
| Gold tables compared with the original view-based model | identical data |

---

## Tech Stack

**SQL Server 2022** · **T-SQL** (stored procedures, window functions, `HASHBYTES`, columnstore indexes) · **SSMS** · CSV source files

---

## Getting Started

1. Install SQL Server 2022 (Express or Developer) and SSMS.
2. Copy the project to `C:\sql\dwh_project\`, so the CSV files are in `C:\sql\dwh_project\01_datasets\`.
3. In SSMS, run the scripts in this order:

```
02_scripts/01_setup/     01_init_database.sql   02_ddl_audit.sql
02_scripts/02_bronze/    ddl_bronze.sql         proc_load_bronze.sql
02_scripts/03_silver/    ddl_silver.sql         proc_load_silver.sql
02_scripts/04_gold/      ddl_gold.sql           proc_load_gold.sql
02_scripts/05_etl/       proc_load_all.sql
```

4. Load the warehouse (run this again whenever new data arrives):

```sql
EXEC dbo.load_all;
```

5. Run the analytics scripts in `02_scripts/06_analytics/` (01 to 13).

---

## Testing

All test scripts are in `03_tests/`. Run them after `EXEC dbo.load_all;`.

| Script | What it checks |
|:--|:--|
| `01_quality_checks_silver.sql` | Duplicates, missing keys, extra spaces, invalid values and dates in Silver |
| `02_quality_checks_gold.sql` | Unique keys and links between the fact table and the dimensions |
| `03_test_incremental_scd.sql` | 10 PASS / FAIL tests: incremental load, hash check, SCD Type 1 and 2, watermarks, error logging |
| `04_performance_benchmark.sql` | Pages read and time of the main Gold queries |

---

## Project Structure

```
├── 01_datasets/          CRM and ERP source files (CSV)
├── 02_scripts/
│   ├── 01_setup/         database, schemas, ETL log and watermark tables
│   ├── 02_bronze/        raw tables and full load
│   ├── 03_silver/        clean tables and incremental load (watermark, hash, SCD)
│   ├── 04_gold/          star schema tables and load (columnstore)
│   ├── 05_etl/           one procedure that runs the whole ETL
│   └── 06_analytics/     13 analysis and report scripts
├── 03_tests/             quality checks, incremental/SCD tests, performance benchmark
└── 04_docs/              diagrams and execution plans
```















# Data Warehouse and Analytics System

An end-to-end **SQL Server Data Warehouse** project that integrates data from multiple CRM and ERP source systems, processes it using **Medallion Architecture**, and prepares it for analytical reporting.

## Key Highlights

- **116,292 Records** integrated from 6 CRM and ERP source systems.
- **98.5× Maximum Query Speed-up** through performance optimization.
- **156,483 → 380 Page Reads** for the customer report.
- **0 Unchanged CRM Rows** inserted or updated when rerunning with unchanged source data.
- **10/10 Tests Passed** for incremental loading and SCD validation.

## Problem Statement

- **Scattered Data:** Information distributed across multiple CRM and ERP systems.
- **Poor Data Quality:** Duplicates, missing values, inconsistent formats, and invalid records.
- **Data Changes:** Need to identify new and modified records without reloading all CRM data.
- **Historical Tracking:** Need to maintain changes in customer and product information.
- **Reporting Requirements:** Need for clean, structured data for business analysis.

## Technologies Used

- **Database:** SQL Server 2022
- **Query Language:** T-SQL
- **Tools:** SQL Server Management Studio (SSMS)
- **Data Sources:** CRM and ERP CSV files
- **ETL:** Stored Procedures, BULK INSERT, Incremental Loading
- **Data Processing:** SHA2_256 Hashing, Watermarks, Window Functions
- **Data Modeling:** Star Schema, SCD Type 1 and Type 2
- **Performance Optimization:** Clustered Columnstore Index, Customer-Number Index

## Architecture

The project follows the **Medallion Architecture**, with data passing through Bronze, Silver, and Gold layers.

![Data Architecture](04_docs/data_architecture.png)

### Data Flow

![Data Flow](04_docs/data_flow.png)

## Data Processing

### 1. Bronze Layer

Stores raw data from the 6 CRM and ERP CSV source files.

- Loads source files using **BULK INSERT**.
- Performs full loading without applying transformations.
- Preserves the original source data.

### 2. Silver Layer

Cleans, standardizes, validates, and prepares data from the Bronze layer.

**Data Cleaning and Standardization**

| Transformation | Example |
|---|---|
| Gender code standardization | `m` → `Male`, `f` → `Female` |
| Marital status standardization | `S` → `Single`, `M` → `Married` |
| Product line standardization | `M` → `Mountain`, `R` → `Road` |
| Country standardization | `US` → `United States`, `DE` → `Germany` |
| Duplicate removal | Retain the latest customer record |
| Invalid date handling | Invalid dates → `NULL` |
| Sales validation | Recalculate incorrect sales using `quantity × price` |
| Missing value handling | Missing or invalid values → `NULL` or `n/a`, where applicable |

**Incremental Loading and Change Detection**

- **Watermarks:** Identify new and modified CRM records and track loading progress.
- **SHA2_256 Hashing:** Generate fingerprints to detect changes in customer and product records.
- **ROW_NUMBER():** Identify duplicate customer records and retain the latest record.
- **LAG():** Compare product hashes with previous product versions to identify changes.
- **LEAD():** Determine product version end dates and identify the current version.

**Historical Data Management**

- **SCD Type 1 – Customers:** Overwrite existing customer information when changes occur.
- **SCD Type 2 – Products:** Preserve historical product versions by closing old records and inserting new versions.
- **ERP Lookup Tables:** Fully reloaded during each ETL execution.

### 3. Gold Layer

Transforms the cleaned Silver data into a **Star Schema** for analytical queries and reporting.

**Star Schema Implementation**

- **Fact Table – `gold.fact_sales`:** Stores sales transactions, with one row per order line.
- **Dimension Table – `gold.dim_customers`:** Stores customer information.
- **Dimension Table – `gold.dim_products`:** Stores product information.
- **Surrogate Keys:** Generated using `ROW_NUMBER()` for customer and product dimensions.
- **Table Loading Order:** Loads customer and product dimensions first, followed by the sales fact table.

**Indexes Used**

- **Clustered Columnstore Index (CCI):** Applied to the fact table to improve analytical query performance.
- **Customer-Number Index:** Supports faster individual customer lookups.

**Transactional Loading**

- Rebuilds the Gold dimensions and fact table after Silver loading.
- Uses a single **transaction** for the complete Gold rebuild.
- Uses **COMMIT** when the complete load succeeds and **ROLLBACK** if an operation fails, preserving the previous Gold data.

## Data Model

A **star schema** in the Gold layer: `fact_sales` holds one row per order line and links to `dim_customers` and `dim_products` through surrogate keys.

![Data Model](04_docs/data_model.png)

## Data Analytics

Created 11 SQL analytics reports:

1. Database Exploration
2. Dimension Exploration
3. Date Exploration
4. Measures Exploration
5. Magnitude Analysis
6. Ranking Analysis
7. Change-over-Time Analysis
8. Cumulative Analysis
9. Performance Analysis
10. Part-to-Whole Analysis
11. Data Segmentation

## ETL Auditing and Error Handling

| Feature | Implementation |
|---|---|
| **Audit Logging** | Tracks batch IDs, execution times, processed rows, status, and error details. |
| **Watermark Tracking** | Maintains incremental loading progress. |
| **Error Handling** | Uses `TRY...CATCH` and `THROW` to capture and report failures. |
| **Transaction Management** | Uses `BEGIN TRANSACTION`, `COMMIT`, and `ROLLBACK`. |
| **Pipeline Orchestration** | `dbo.load_all` coordinates the Bronze → Silver → Gold loading process. |

## Performance Optimization

Compared the earlier **view-based implementation** with physical Gold tables using SQL Server 2022. Results represent the **median of 10 query executions**.

| Analytical Query | Pages Read (Before → After) | Time (Before → After) | Speed-up |
|---|---:|---:|---:|
| Customer Report | 156,483 → 380 | 638 ms → 164 ms | **3.9×** |
| Product Report | 168,535 → 109 | 619 ms → 35 ms | **17.9×** |
| Revenue by Category | 1,774 → 17 | 79 ms → 3 ms | **26.3×** |
| Monthly Sales Trend | 1,471 → 39 | 106 ms → 13 ms | **8.1×** |
| Top 10 Customers | 2,044 → 300 | 177 ms → 20 ms | **8.9×** |
| Orders of One Customer | 1,759 → 107 | 99 ms → 1 ms | **98.5×** |
| Sales by Category for One Quarter | 3,558 → 89 | 81 ms → 7 ms | **12.4×** |

**Key Optimization Techniques**

- Replaced the earlier view-based implementation with physical Gold tables.
- Used **Clustered Columnstore Indexing** and batch processing for analytical queries.
- Used the **Customer-Number Index** for faster individual customer lookups.
- Reduced unnecessary data reads through columnstore processing.

## How to Run

**Prerequisites:** SQL Server 2022, SSMS, and access to the CSV datasets.

1. Clone the repository and open the SQL scripts in SSMS.
2. Update the CSV paths in the Bronze loading procedure and provide SQL Server service account access.
3. Execute the scripts in order: `01_setup` → `02_bronze` → `03_silver` → `04_gold` → `05_etl`.
4. Run the complete pipeline:

```sql
EXEC dbo.load_all;
```

5. Run analytics from `02_scripts/06_analytics/` and tests from `03_tests/`.

**Note:** The initial setup script drops and recreates the `DataWarehouse` database. Run it only during initial setup or when intentionally resetting the database.

## Project Structure

```text
Data-Warehouse-and-Analytics-System/
│
├── 01_datasets/
├── 02_scripts/
│   ├── 01_setup/
│   ├── 02_bronze/
│   ├── 03_silver/
│   ├── 04_gold/
│   ├── 05_etl/
│   └── 06_analytics/
├── 03_tests/
├── 04_docs/
│   ├── data_architecture.png
│   ├── data_flow.png
│   └── data_model.png
└── README.md
```

---

## Acknowledgement

The base Bronze, Silver and Gold pipeline, the original diagrams and the analytics scripts started from the SQL Data Warehouse course project by Baraa Khatib Salkini (MIT License).
