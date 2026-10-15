# dbt (data build tool) & Modern Telemetry Lakehouse Architecture Reference Card

## Modular SQL Modeling, Incremental Materializations, Meteorological Quality Contracts, and `dbt-duckdb` Lakehouse Pipelines

---

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./05_ceph_distributed_storage_and_proxmox_ve_architecture.md) | **Card 06 of 13** | [Next Card ➡️](./07_wal_crash_recovery_sqlite_postgres_mysql.md)

## 🧭 Quick-Jump Table of Contents

- [Executive Summary for Weather & Systems Engineers](#executive-summary-for-weather--systems-engineers)
- [1. Where dbt Fits in the National Meteorological Architecture](#1-where-dbt-fits-in-the-national-meteorological-architecture)
  - [The Medallion Tier Progression in Meteorology](#the-medallion-tier-progression-in-meteorology)
- [2. Setting Up `dbt-duckdb` for Sovereign On-Premises Lakes](#2-setting-up-dbt-duckdb-for-sovereign-on-premises-lakes)
  - [2.1 Installation](#21-installation)
  - [2.2 Profile Configuration (`~/.dbt/profiles.yml`)](#22-profile-configuration-dbtprofilesyml)
- [3. Developing Meteorological dbt Models](#3-developing-meteorological-dbt-models)
  - [3.1 Bronze / Staging Model: Sentinel Sanitization (`models/staging/stg_weather_telemetry.sql`)](#31-bronze--staging-model-sentinel-sanitization-modelsstagingstg_weather_telemetrysql)
  - [3.2 Silver / Intermediate Model: Incremental Synoptic Hourly Aggregation (`models/intermediate/int_synoptic_hourly.sql`)](#32-silver--intermediate-model-incremental-synoptic-hourly-aggregation-modelsintermediateint_synoptic_hourlysql)
  - [3.3 Gold / Mart Model: Severe Squall & Rapid Pressure Drop Detector (`models/marts/fct_severe_weather_events.sql`)](#33-gold--mart-model-severe-squall--rapid-pressure-drop-detector-modelsmartsfct_severe_weather_eventssql)
- [4. Reusable Meteorological Jinja Macros](#4-reusable-meteorological-jinja-macros)
- [5. Automated Data Quality (QC) & Physical Contract Testing](#5-automated-data-quality-qc--physical-contract-testing)
  - [5.1 Out-of-the-Box Schema Validation (`models/schema.yml`)](#51-out-of-the-box-schema-validation-modelsschemayml)
  - [5.2 Singular Custom Physical Tests (`tests/assert_dewpoint_below_temp.sql`)](#52-singular-custom-physical-tests-testsassert_dewpoint_below_tempsql)
- [6. Execution Lifecycle & CI/CD Commands](#6-execution-lifecycle--cicd-commands)
- [7. Comparison: dbt vs. Plain SQL Views vs. Airflow/Prefect](#7-comparison-dbt-vs-plain-sql-views-vs-airflowprefect)
- [8. Summary Checklist: dbt Lakehouse Directives](#8-summary-checklist-dbt-lakehouse-directives)

---

### Executive Summary for Weather & Systems Engineers

Throughout Days 1 through 4, we engineered the physical foundations: raw sensor ingestion (MQTT/Kafka), relational spatial storage (PostgreSQL/PostGIS), polymorphic IoT buffering (MongoDB), and columnar analytical querying (DuckDB & Apache Parquet).

However, in production meteorological agencies, raw sensor streams are messy, inconsistent, and arrive at varying cadences. Ad-hoc Python scripts and unversioned SQL views quickly turn into an unmaintainable "spaghetti pipeline":
* Transformations are scattered across crontabs, airflow DAGs, and manual scripts.
* Business and physical logic (e.g., converting Kelvin to Celsius, barometric sea-level reduction, handling `-999.0` sentinels) is duplicated and drifts across teams.
* There are no automated regression tests to verify that physics rules hold (e.g., dew point temperature cannot exceed dry-bulb temperature).

**dbt (data build tool)** solves this by bringing software engineering best practices to data transformation (the **T** in **ELT**):
1. **Modularity & Lineage:** Transformations are written as modular `SELECT` statements; dbt handles compilation, dependencies, and Directed Acyclic Graph (DAG) resolution automatically via `ref()`.
2. **Version-Controlled Physics:** All meteorological algorithms (synoptic pressure reduction, moving averages, wind vector decomposition) are codified in Git.
3. **Automated Testing & Contracts:** Enforces schema validations, non-null guarantees, and physical boundary constraints before downstream forecaster dashboards consume data.
4. **Lakehouse Fit (`dbt-duckdb`):** Transforms Parquet files stored locally or in on-premises Ceph S3 without requiring expensive cloud data warehouses (Snowflake, BigQuery).

---

## 1. Where dbt Fits in the National Meteorological Architecture

```
                          The Production ELT Pipeline with dbt
                          
  EXTRACT & LOAD (Real-Time / Streaming)             TRANSFORM (dbt Batch Engine)
 ┌──────────────────────────────────────┐          ┌──────────────────────────────────────┐
 │ Remote Stations / Satellites / Radars│          │ MEDALLION LAKEHOUSE ARCHITECTURE     │
 └──────────────────┬───────────────────┘          │                                      │
                    │ MQTT / Kafka Stream          │ ┌──────────────────────────────────┐ │
                    ▼                              │ │ BRONZE (stg_): Raw & Untyped     │ │
 ┌──────────────────────────────────────┐          │ │ • Ingests raw Parquet / Postgres │ │
 │ Polyglot Ingestion Tier              │          │ │ • Eliminates sentinels (-999.0)  │ │
 │ • PostgreSQL 16 (Operational Rows)   │ ───────> │ └────────────────┬─────────────────┘ │
 │ • Ceph S3 / MinIO (Raw Parquet Lake) │          │                  │ ref('stg_...')    │
 └──────────────────────────────────────┘          │                  ▼                   │
                                                   │ ┌──────────────────────────────────┐ │
                                                   │ │ SILVER (int_): Cleansed & Aligned│ │
                                                   │ │ • Incremental hourly synoptics   │ │
                                                   │ │ • Barometric pressure reduction  │ │
                                                   │ └────────────────┬─────────────────┘ │
                                                   │                  │ ref('int_...')    │
                                                   │                  ▼                   │
                                                   │ ┌──────────────────────────────────┐ │
                                                   │ │ GOLD (fct_ / dim_): Climatology  │ │
                                                   │ │ • 30-year normals, storm indices │ │
                                                   │ └──────────────────────────────────┘ │
                                                   └──────────────────┬───────────────────┘
                                                                      │ Fast Vectorized Reads
                                                                      ▼
                                                   ┌──────────────────────────────────────┐
                                                   │ Forecaster Web APIs, GIS & Dashboards│
                                                   └──────────────────────────────────────┘
```

### The Medallion Tier Progression in Meteorology

| Layer | dbt Model Prefix | Materialization Strategy | Primary Meteorological Function |
| :--- | :--- | :--- | :--- |
| **Bronze** | `stg_` (Staging) | `view` (zero storage overhead) | Cleans column names, casts timestamps to UTC, and translates hardware sentinels (`-999.0`) to `NULL`. |
| **Silver** | `int_` (Intermediate) | `incremental` (ZSTD Parquet) | Downsamples raw pings into standardized 10-minute and 1-hour synoptic buckets; applies quality flags. |
| **Gold** | `fct_` / `dim_` (Marts) | `table` or partitioned Parquet | Serves climatological normals, severe storm track summaries, and regional weather indices. |

---

## 2. Setting Up `dbt-duckdb` for Sovereign On-Premises Lakes

You do not need a multi-node cloud warehouse to run dbt. With the **`dbt-duckdb`** adapter, dbt executes transformations directly inside DuckDB's in-process SIMD engine, reading and writing Parquet files directly to local NVMe storage or on-premises Ceph S3 buckets.

### 2.1 Installation
```bash
# In your Python virtual environment:
pip install dbt-core dbt-duckdb
```

### 2.2 Profile Configuration (`~/.dbt/profiles.yml`)
Configure dbt to attach to your local DuckDB lakehouse or connect to Ceph S3 via `httpfs`:

```yaml
weather_lakehouse:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: 'climatology_lake/duckdb_catalog.db'
      threads: 8
      settings:
        preserve_insertion_order: false
        memory_limit: '16GB'
      # Optional: Attach directly to on-premises Ceph S3
      extensions:
        - httpfs
        - parquet
      filesystems:
        - s3:
            endpoint: '10.10.20.100:80'
            key: 'METEO_ACCESS_KEY_2026'
            secret: 'METEO_SECRET_KEY_SUPER_SECURE_99'
            use_ssl: false
            url_style: 'path'
```

---

## 3. Developing Meteorological dbt Models

### 3.1 Bronze / Staging Model: Sentinel Sanitization (`models/staging/stg_weather_telemetry.sql`)

Staging models must never perform complex joins or multi-level aggregations. Their sole duty is **sanitizing and renaming raw inputs**.

```sql
{{ config(materialized='view') }}

WITH raw_source AS (
    -- Reads directly from raw Parquet files generated by Day 5 compactor
    SELECT * 
    FROM read_parquet('climatology_lake/**/*.parquet', hive_partitioning=true)
)

SELECT
    station_id,
    recorded_at::TIMESTAMPTZ AS recorded_at_utc,
    
    -- In-flight sentinel elimination (Day 1 Principle)
    NULLIF(temperature, -999.0)::REAL AS temperature_celsius,
    NULLIF(pressure, -999.0)::REAL    AS pressure_hpa,
    NULLIF(wind_speed, -999.0)::REAL  AS wind_speed_ms,
    
    -- Range-bound clamping for sensor short-circuits
    CASE 
        WHEN rain_accum_1m BETWEEN 0.0 AND 50.0 THEN rain_accum_1m 
        ELSE 0.0 
    END AS rain_accum_1m,
    
    -- Virtual partition columns
    year::INT  AS obs_year,
    month::INT AS obs_month

FROM raw_source
WHERE station_id IS NOT NULL
```

---

### 3.2 Silver / Intermediate Model: Incremental Synoptic Hourly Aggregation (`models/intermediate/int_synoptic_hourly.sql`)

Meteorological archives receive millions of records daily. Recomputing the entire historical table from scratch on every run is computationally wasteful.

dbt's **`incremental` materialization** ensures that only newly arrived observations are processed:

```sql
{{ config(
    materialized='incremental',
    unique_key=['station_id', 'synoptic_hour'],
    incremental_strategy='delete+insert',
    file_format='parquet',
    partition_by=['obs_year', 'obs_month']
) }}

WITH staged_telemetry AS (
    SELECT * FROM {{ ref('stg_weather_telemetry') }}
    
    {% if is_incremental() %}
        -- Only process observations newer than the latest recorded synoptic hour in our lake
        WHERE recorded_at_utc > (
            SELECT COALESCE(MAX(synoptic_hour), '1970-01-01'::TIMESTAMPTZ) 
            FROM {{ this }}
        ) - INTERVAL '2 hours' -- 2-hour lookback buffer to handle late-arriving telemetry!
    {% endif %}
),

hourly_buckets AS (
    SELECT
        station_id,
        date_trunc('hour', recorded_at_utc) AS synoptic_hour,
        
        -- High-Precision Aggregations
        ROUND(AVG(temperature_celsius), 2)  AS mean_temperature,
        ROUND(MIN(temperature_celsius), 2)  AS min_temperature,
        ROUND(MAX(temperature_celsius), 2)  AS max_temperature,
        ROUND(AVG(pressure_hpa), 2)         AS mean_pressure_hpa,
        ROUND(MAX(wind_speed_ms), 2)        AS peak_wind_gust,
        ROUND(SUM(rain_accum_1m), 2)        AS total_hourly_rainfall,
        
        COUNT(*) AS total_samples,
        
        -- Date partition metadata
        EXTRACT(YEAR FROM date_trunc('hour', recorded_at_utc))::INT  AS obs_year,
        EXTRACT(MONTH FROM date_trunc('hour', recorded_at_utc))::INT AS obs_month

    FROM staged_telemetry
    GROUP BY station_id, date_trunc('hour', recorded_at_utc)
)

SELECT * FROM hourly_buckets
```

---

### 3.3 Gold / Mart Model: Severe Squall & Rapid Pressure Drop Detector (`models/marts/fct_severe_weather_events.sql`)

```sql
{{ config(materialized='table') }}

WITH hourly_data AS (
    SELECT * FROM {{ ref('int_synoptic_hourly') }}
),

barometric_tendency AS (
    SELECT
        station_id,
        synoptic_hour,
        mean_pressure_hpa,
        peak_wind_gust,
        total_hourly_rainfall,
        
        -- Window function calculating 3-hour pressure plunge (Day 1 / Day 5 Recipe)
        LAG(mean_pressure_hpa, 3) OVER (
            PARTITION BY station_id 
            ORDER BY synoptic_hour
        ) AS pressure_3h_prior,
        
        ROUND(mean_pressure_hpa - LAG(mean_pressure_hpa, 3) OVER (
            PARTITION BY station_id 
            ORDER BY synoptic_hour
        ), 2) AS delta_p_3h_hpa

    FROM hourly_data
)

SELECT
    station_id,
    synoptic_hour,
    mean_pressure_hpa,
    pressure_3h_prior,
    delta_p_3h_hpa,
    peak_wind_gust,
    total_hourly_rainfall,
    
    -- Automated Classification of Convective Squall Line
    CASE 
        WHEN delta_p_3h_hpa <= -4.0 AND peak_wind_gust >= 20.0 THEN 'CRITICAL_GALE_SQUALL'
        WHEN delta_p_3h_hpa <= -4.0 THEN 'RAPID_PRESSURE_DROP'
        WHEN peak_wind_gust >= 25.0 THEN 'STORM_FORCE_GALE'
        ELSE 'STANDARD'
    END AS severity_alert_class

FROM barometric_tendency
WHERE delta_p_3h_hpa <= -4.0 OR peak_wind_gust >= 20.0
ORDER BY delta_p_3h_hpa ASC
```

---

## 4. Reusable Meteorological Jinja Macros

Instead of repeating complex unit conversions or psychrometric formulas across SQL files, encapsulate them inside **dbt macros** (`macros/meteorological_conversions.sql`).

```sql
{# Convert Kelvin to Celsius #}
{% macro kelvin_to_celsius(column_name) %}
    ROUND(({{ column_name }} - 273.15)::numeric, 2)
{% endmacro %}

{# Convert m/s to Knots #}
{% macro ms_to_knots(column_name) %}
    ROUND(({{ column_name }} * 1.94384)::numeric, 2)
{% endmacro %}

{# Estimate Sea-Level Pressure from Station Pressure using Barometric Formula #}
{% macro reduce_to_sea_level(pressure_col, elevation_col, temp_c_col) %}
    ROUND((
        {{ pressure_col }} * (1.0 - (0.0065 * {{ elevation_col }} / ({{ temp_c_col }} + 273.15 + (0.0065 * {{ elevation_col }})))) ** (-5.257)
    )::numeric, 2)
{% endmacro %}
```

#### Utilizing Macros inside Models:
```sql
SELECT
    station_id,
    {{ ms_to_knots('wind_speed_ms') }} AS wind_speed_knots,
    {{ reduce_to_sea_level('pressure_hpa', 'elevation_m', 'temperature_celsius') }} AS msl_pressure_hpa
FROM {{ ref('stg_weather_telemetry') }}
```

---

## 5. Automated Data Quality (QC) & Physical Contract Testing

In software engineering, unit tests prevent broken logic. In meteorological data engineering, **dbt tests** prevent physically impossible numbers from poisoning climatological records.

### 5.1 Out-of-the-Box Schema Validation (`models/schema.yml`)

```yaml
version: 2

models:
  - name: stg_weather_telemetry
    description: "Sanitized raw telemetry observations with sentinels removed."
    columns:
      - name: station_id
        tests:
          - not_null
      - name: recorded_at_utc
        tests:
          - not_null
      - name: temperature_celsius
        description: "Dry-bulb ambient temperature in Celsius."
        tests:
          # Verify physical limits on Earth (-90°C to +60°C)
          - dbt_utils.accepted_range:
              min_value: -90.0
              max_value: 60.0
      - name: pressure_hpa
        tests:
          - dbt_utils.accepted_range:
              min_value: 850.0
              max_value: 1090.0

  - name: int_synoptic_hourly
    description: "Hourly downsampled observations for synoptic meteorology."
    tests:
      - unique:
          column_name: "(station_id || '-' || synoptic_hour)"
      - not_null:
          columns: [station_id, synoptic_hour, mean_temperature]
```

### 5.2 Singular Custom Physical Tests (`tests/assert_dewpoint_below_temp.sql`)

A fundamental law of thermodynamics: **The Dew Point Temperature ($T_d$) can never exceed the Ambient Dry-Bulb Temperature ($T$).**

If $T_d > T$, the relative humidity exceeds $100\%$, indicating sensor calibration drift or an electrical short.

Create this test file in `tests/assert_dewpoint_below_temp.sql`:

```sql
-- dbt tests fail if the query returns ANY rows!
SELECT
    station_id,
    recorded_at_utc,
    temperature_celsius,
    dew_point_celsius,
    (dew_point_celsius - temperature_celsius) AS physical_violation_margin
FROM {{ ref('stg_weather_telemetry') }}
WHERE dew_point_celsius > temperature_celsius
```

When you execute `dbt test`, dbt runs this query. If a broken hygrometer reports $T_d = 24^\circ\text{C}$ while $T = 20^\circ\text{C}$, the pipeline halts and alerts the engineering team.

---

## 6. Execution Lifecycle & CI/CD Commands

```bash
# 1. Install dependent packages (e.g., dbt_utils)
dbt deps

# 2. Compile SQL models and verify DAG dependency graph
dbt compile

# 3. Execute all models (materializes Views, Incremental Parquet files, and Marts)
dbt run

# 4. Run incremental models only (processes latest batch of records)
dbt run --select int_synoptic_hourly

# 5. Run all automated schema validations and physical atmospheric sanity tests
dbt test

# 6. Generate interactive HTML documentation and lineage graph
dbt docs generate
dbt docs serve --port 8080
```

---

## 7. Comparison: dbt vs. Plain SQL Views vs. Airflow/Prefect

| Dimension | Plain SQL Views / Stored Procs | Python Airflow / Prefect | dbt (data build tool) |
| :--- | :--- | :--- | :--- |
| **Primary Domain** | Ad-hoc queries in DB engine | Workflow orchestration & scheduling | **In-database transformation logic (T)** |
| **Lineage & Dependencies** | None (Manual view order tracking) | Expressed procedurally in Python | **Automatic DAG compilation via `ref()`** |
| **Data Quality Testing** | Manual assertions | Custom Python assertions | **Built-in YAML contracts & test suites** |
| **Incremental Logic** | Complex procedural triggers / loops | Handcrafted SQL string formatting | **Automated `is_incremental()` macros** |
| **Environment Portability** | Locked to specific database dialect | Heavy (requires Airflow workers) | **Engine-agnostic (DuckDB, Postgres, S3)** |

---

## 8. Summary Checklist: dbt Lakehouse Directives

```text
================================================================================
                    dbt TELEMETRY LAKEHOUSE DIRECTIVES
================================================================================
 1. Never Transform in E : Extract and Load raw telemetry into Bronze as-is;
                           perform all cleaning, typing, and sentinel cuts in dbt.
 2. Incremental by Key   : For high-frequency time series, always use incremental
                           materialization with unique_key: [station_id, synoptic_hour].
 3. Use 2-Hour Buffers   : Always subtract a 2-hour buffer in is_incremental()
                           to gracefully ingest late-arriving remote cellular pings.
 4. Encode Physics Tests : Write singular tests enforcing atmospheric laws
                           (e.g., Dew Point <= Temperature, Pressure >= 870 hPa).
 5. Modularize Formulas  : Put unit conversions (Kelvin->Celsius, m/s->Knots) into
                           reusable Jinja macros; never hardcode formulas in models.
 6. Pair with DuckDB     : Use dbt-duckdb to transform Parquet lakehouses on-prem
                           with zero cloud database license costs.
================================================================================
```
---

### 🔗 Reference Library Navigation

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./05_ceph_distributed_storage_and_proxmox_ve_architecture.md) | **Card 06 of 13** | [Next Card ➡️](./07_wal_crash_recovery_sqlite_postgres_mysql.md) | [⬆️ Back to Top](#dbt-data-build-tool--modern-telemetry-lakehouse-architecture-reference-card)
