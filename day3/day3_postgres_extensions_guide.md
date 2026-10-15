> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [⏮️ Day 2 Coursebook](../day2/day2_master_coursebook.md) | [📘 Day 3 Coursebook](day3_master_coursebook.md) | [⏭️ Day 4 Coursebook](../day4/day4_master_coursebook.md)

# PostgreSQL Essential Extensions: Production Engineering, Meteorological Telemetry & Storage Forensics Guide

**Target Audience:** Weather Forecast & Meteorological Data Engineers, Systems & Database Administrators  
**Companion to:** [day3_master_coursebook.md](./day3_master_coursebook.md) & [day3_postgres_advanced_cheatsheet.md](./day3_postgres_advanced_cheatsheet.md)

---

## Executive Summary for Systems & Database Engineers

PostgreSQL's pluggable C-extension architecture is one of its primary engineering differentiators. Extensions in PostgreSQL are not simple user-defined functions or stored procedures; they hook directly into the database engine's core lifecycle:

* **Executor & Planner Hooks:** Intercepting query planning to measure wall-clock latency, log execution trees, or substitute custom access paths (`pg_stat_statements`, `auto_explain`, `timescaledb`).
* **Storage Engine & Buffer Pool Introspection:** Inspecting raw binary $8\text{ KB}$ disk blocks (`pageinspect`), reading Free Space Maps (`_fsm`), checking Visibility Maps (`_vm` via `pg_visibility`), measuring dead-tuple bloat (`pgstattuple`), and profiling memory allocations in `shared_buffers` (`pg_buffercache`, `pg_prewarm`).
* **Custom Index Access Methods & Data Types:** Adding spherical geodetic indexing (`PostGIS` GiST), temporal exclusion constraints (`btree_gist`), trigram fuzzy search (`pg_trgm`), and vector embeddings (`pgvector`).
* **Background Workers & Online Maintenance:** Automating partition lifecycle management (`pg_partman`), running scheduled jobs inside the database (`pg_cron`), and performing lock-free table compaction (`pg_repack`).
* **Foreign Data Wrappers (FDW):** Abstracting flat files (`file_fdw`), remote PostgreSQL clusters (`postgres_fdw`), and archived Apache Parquet files (`parquet_fdw`) as native relational tables.

```
                          PostgreSQL Extension Hook Architecture
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ Client Application Query Execution Pipeline                                 │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼ Executor & Planner Hooks
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ OBSERVABILITY & DIAGNOSTICS HOOKS                                           │
 │ • pg_stat_statements : Captures normalized SQL execution timings & I/O      │
 │ • auto_explain        : Intercepts queries exceeding threshold; logs trees  │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼ Catalog / Background Workers
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ TIME-SERIES, SPATIAL & ONLINE MAINTENANCE                                   │
 │ • postgis / raster    : Spherical GEOGRAPHY, GEOMETRY, GiST & raster grids  │
 │ • timescaledb         : Hypertables, 90%+ columnar compression, time_bucket │
 │ • pg_partman + pg_cron: Automates temporal partition creation and scheduled │
 │                         concurrent materialized view refreshes              │
 │ • pg_repack           : Executes zero-downtime, lock-free table compactions │
 │ • pg_prewarm          : Restores hot tables/indexes into RAM after restarts │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼ Disk & Memory Internals
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ STORAGE & BUFFER POOL FORENSICS                                             │
 │ • pg_buffercache      : Reads RAM shared_buffers block by block             │
 │ • pageinspect         : Decodes binary 8 KB page headers and tuple CTIDs    │
 │ • pgstattuple         : Measures physical dead bloat without locking        │
 │ • pg_visibility       : Audits Visibility Map (_vm) for Index-Only Scans    │
 └─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Extension Installation & Loading Lifecycle

PostgreSQL extensions fall into two distinct mechanical categories based on how they load into the database engine:

| Extension Category | Requires `shared_preload_libraries`? | Requires Database Restart? | Enablement Mechanism | Example Extensions |
| :--- | :--- | :--- | :--- | :--- |
| **Dynamic Extensions** | **No** | **No** | Dynamic library load via `CREATE EXTENSION <name>;` per database. | `postgis`, `postgis_raster`, `btree_gist`, `pageinspect`, `pgstattuple`, `pg_visibility`, `pg_buffercache`, `pg_prewarm`, `pg_repack`, `pg_trgm`, `unaccent`, `file_fdw`, `postgres_fdw` |
| **Hook & Background Worker Extensions** | **Yes** (Must be in `postgresql.conf`) | **Yes** (Shared memory & bgworkers allocated at boot) | Preloaded at daemon start; registered per DB via `CREATE EXTENSION`. | `pg_stat_statements`, `auto_explain`, `pg_cron`, `pg_partman_bgw`, `timescaledb` |

### 1.1 Configuring Shared Preload Libraries (`postgresql.conf`)

Extensions that allocate shared memory or spawn background workers must be declared before PostgreSQL boots:

```ini
# /etc/postgresql/16/main/postgresql.conf
shared_preload_libraries = 'pg_stat_statements,auto_explain,pg_cron'

# 1. pg_stat_statements tuning
pg_stat_statements.max = 10000
pg_stat_statements.track = all
pg_stat_statements.track_utility = off
pg_stat_statements.save = on

# 2. auto_explain tuning (automatically logs plans of slow queries >= 500ms)
auto_explain.log_min_duration = '500ms'
auto_explain.log_analyze = true
auto_explain.log_buffers = true
auto_explain.log_timing = true
auto_explain.log_format = text

# 3. pg_cron database target
cron.database_name = 'weather_ops'
```

---

## 2. Master Extensions Directory & Comparison Matrix

| Extension Name | Category | Primary Weather / Engineering Function | Requires Preload? | Overhead Profile | Production Recommendation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`postgis` & `postgis_raster`** | **Spatial / GIS** | Spherical station coordinates (`GEOGRAPHY`), storm polygons (`GEOMETRY`), GiST indexing, and gridded rasters | No | Memory per spatial op | **Mandatory** for all meteorological databases |
| **`timescaledb`** | **Time-Series Engine** | Self-partitioning **Hypertables**, **90%+ native columnar compression**, `time_bucket()`, and Continuous Aggregates | **Yes** | Low background worker | Ideal when you want automated columnar compression inside PG |
| **`pg_partman`** | **Partition Automation** | Pre-creates future monthly partitions (`obs_y2026m11`, `m12`) and detaches/drops expired partitions | Optional (`pg_partman_bgw`) | Negligible | **Mandatory** for native declarative partitioned tables |
| **`pg_cron`** | **In-DB Scheduler** | Runs scheduled SQL jobs inside PG (`REFRESH MATERIALIZED VIEW CONCURRENTLY`, nightly `partman` maintenance) | **Yes** | 1 background worker | **Highly Recommended** for self-contained DB automation |
| **`pg_stat_statements`** | **Query Observability** | Tracks execution count, total/mean latency, and 8 KB buffer hits/reads for every normalized SQL query | **Yes** | Very Low ($< 1\%$ CPU) | **Mandatory** across all production nodes |
| **`auto_explain`** | **Query Observability** | Automatically logs `EXPLAIN (ANALYZE, BUFFERS)` trees for slow queries exceeding `log_min_duration` | **Yes** | Low (triggers only on slow SQL) | **Mandatory** with threshold $\ge 500\text{ ms}$ |
| **`pg_buffercache`** | **Memory Forensics** | Real-time inspection of which tables/indexes occupy `shared_buffers` RAM | No | Momentary buffer lock | **Diagnostic only**; do not run in high-frequency loops |
| **`pg_prewarm`** | **Memory Forensics** | Pre-loads critical B-Tree/GiST indexes and hot partitions into `shared_buffers` after a restart | No | I/O-bound during warm | **Highly Recommended** post-restart or post-failover |
| **`pageinspect`** | **Disk Forensics** | Decodes raw binary 8 KB heap pages, line pointers (`lp`), tuple headers (`t_xmin`, `t_xmax`, `t_ctid`), and index pages | No | Negligible | Essential for DBA forensics & verifying tuple alignment |
| **`pgstattuple`** | **Bloat Forensics** | Non-locking scan reporting exact live tuples, dead tuples (`dead_tuple_percent`), and free space | No | Sequential page read | Run during off-peak audit windows to decide if `pg_repack` is needed |
| **`pg_visibility`** | **Bloat Forensics** | Audits the Visibility Map (`_vm`) fork to verify if blocks are marked `all_visible` for Index-Only Scans | No | Fast fork scan | Ideal for diagnosing why `Heap Fetches` $> 0$ |
| **`pg_repack`** | **Zero-Downtime Ops** | Reorganizes bloated tables and rebuilds indexes **online** to return disk space to Linux without `VACUUM FULL` locks | No | Moderate write I/O during copy | **Essential** operational tool for high-update tables |
| **`btree_gist`** | **Temporal Constraints** | Combines scalar equality (`station_id WITH =`) and range overlaps (`valid_period WITH &&`) in `EXCLUDE USING GIST` | No | GiST index maintenance | **Essential** for preventing overlapping calibration or alert windows |
| **`file_fdw` / `postgres_fdw` / `parquet_fdw`** | **Data Federation** | Queries local CSV datalogger dumps, remote PG regional servers, or archived Parquet files directly via SQL | No | I/O / Network bound | Excellent for zero-ETL federation and lakehouse queries |
| **`pg_trgm` & `unaccent` / `pgvector`** | **Search & AI Analogs** | TrigramGIN index for fast `%substring%` & typo-tolerant station search (`pg_trgm`); vector similarity for weather regime analogs (`pgvector`) | No | Higher index write tax | Essential for station registries, METAR text remarks, and AI analogs |

---

## 3. Deep Dive #1: Spatial Intelligence — `PostGIS` & `postgis_raster`

### 3.1 Installing & Enabling PostGIS
```bash
# Ubuntu / Debian (for PostgreSQL 16):
sudo apt-get update
sudo apt-get install -y postgresql-16-postgis-3 postgresql-16-postgis-3-scripts
```

```sql
-- Run inside psql on your weather database:
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- Verify PostGIS version, GEOS, PROJ, and GDAL libraries:
SELECT PostGIS_Full_Version();
```

### 3.2 Crucial PostGIS Rule for Weather Engineers: `GEOGRAPHY` vs. `GEOMETRY`

| Type | Coordinate System | Units of Distance / Area | When to Use in Meteorology |
| :--- | :--- | :--- | :--- |
| **`GEOGRAPHY(Point, 4326)`** | Spherical / Ellipsoidal Earth (WGS 84 `lon, lat`) | **Meters** (and square meters) automatically across the globe! | Global or national WMO station networks, cyclone radius searches (`ST_DWithin`), great-circle distances |
| **`GEOMETRY(Polygon, 4326)`** *(or local UTM SRID)* | Flat Cartesian plane | Degrees (if SRID 4326) or Meters (if projected SRID like UTM) | Fast polygon clipping, complex topological operations, local radar grids (or cast `geom::geography` for meter distances) |

> **Coordinate Order Warning:** Just like GeoJSON in MongoDB, `ST_MakePoint(longitude, latitude)` always takes **`(X, Y)` = `(longitude, latitude)`**!

### 3.3 Essential PostGIS Patterns for Weather Operations

```sql
-- 1. Add a spherical GEOGRAPHY column to synoptic.stations & populate from (longitude, latitude)
ALTER TABLE synoptic.stations
    ADD COLUMN IF NOT EXISTS geog GEOGRAPHY(Point, 4326);

UPDATE synoptic.stations
SET geog = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::GEOGRAPHY;

-- MANDATORY: Create a GiST (Generalized Search Tree) Spatial Index!
CREATE INDEX IF NOT EXISTS idx_stations_geog_gist
ON synoptic.stations USING GIST (geog);

-- 2. Radius Search (ST_DWithin): Find all stations within 250 km (250,000 meters) of an offshore cyclone eye [3.30E, 36.80N]
-- Note: Always use ST_DWithin instead of ST_Distance(...) < 250000 because ST_DWithin uses the GiST spatial index!
SELECT
    station_id,
    station_name,
    climate_zone,
    ROUND((ST_Distance(
        geog,
        ST_SetSRID(ST_MakePoint(3.30, 36.80), 4326)::GEOGRAPHY
    ) / 1000.0)::NUMERIC, 1) AS distance_km
FROM synoptic.stations
WHERE ST_DWithin(
    geog,
    ST_SetSRID(ST_MakePoint(3.30, 36.80), 4326)::GEOGRAPHY,
    250000.0 -- Distance in meters!
)
ORDER BY distance_km ASC;

-- 3. Storm Polygon / River Basin Containment (ST_Intersects):
-- Find all stations inside a severe thunderstorm warning polygon
WITH storm_polygon AS (
    SELECT ST_GeogFromText(
        'SRID=4326;POLYGON((2.5 35.8, 7.2 35.8, 7.2 37.1, 2.5 37.1, 2.5 35.8))'
    ) AS footprint
)
SELECT
    s.station_id,
    s.station_name,
    s.elevation_m
FROM synoptic.stations s
CROSS JOIN storm_polygon sp
WHERE ST_Intersects(s.geog, sp.footprint);

-- 4. Export Station + Metadata directly as a GeoJSON Feature for Leaflet/Mapbox web maps!
SELECT jsonb_build_object(
    'type', 'Feature',
    'geometry', ST_AsGeoJSON(s.geog)::JSONB,
    'properties', jsonb_build_object(
        'station_id', s.station_id,
        'station_name', s.station_name,
        'elevation_m', s.elevation_m
    )
) AS geojson_feature
FROM synoptic.stations s;
```

---

## 4. Deep Dive #2: Time-Series Automation — `TimescaleDB`, `pg_partman` & `pg_cron`

### 4.1 `TimescaleDB`: Hypertables & Native Columnar Compression Inside PostgreSQL
If your team wants automated time-partitioning plus **90%+ native columnar compression** inside PostgreSQL:

```sql
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- 1. Convert a normal PostgreSQL table into a self-partitioning Hypertable (7-day chunks):
SELECT create_hypertable(
    'synoptic.observations',
    by_range('obs_time', INTERVAL '7 days'),
    migrate_data => TRUE
);

-- 2. Enable Native Columnar Compression inside PostgreSQL for chunks older than 14 days!
-- Compresses 8KB row pages into columnar arrays (saving 90%+ disk space, similar to Parquet!)
ALTER TABLE synoptic.observations SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'station_id',
    timescaledb.compress_orderby = 'obs_time DESC'
);

SELECT add_compression_policy('synoptic.observations', INTERVAL '14 days');

-- 3. Use time_bucket() for arbitrary synoptic intervals (e.g., 3-hour windows):
SELECT
    station_id,
    time_bucket('3 hours', obs_time) AS synoptic_3h_window,
    ROUND(AVG(temp_c), 1)            AS avg_temp_c,
    MAX(wind_speed_kt)               AS max_wind_kt
FROM synoptic.observations
WHERE obs_time >= NOW() - INTERVAL '7 days'
GROUP BY station_id, synoptic_3h_window
ORDER BY synoptic_3h_window DESC;
```

### 4.2 `pg_partman` + `pg_cron`: Native Declarative Partition & Job Automation
If you use native PostgreSQL Declarative Partitioning (`PARTITION BY RANGE`), combine **`pg_partman`** and **`pg_cron`** so PostgreSQL automatically pre-creates future monthly partitions and refreshes Materialized Views on schedule:

```sql
-- Requires in postgresql.conf: shared_preload_libraries = 'pg_stat_statements,pg_cron'
CREATE SCHEMA IF NOT EXISTS partman;
CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 1. Tell pg_partman to manage monthly partitions on synoptic.observations_part
-- (or public.raw_telemetry_partitioned) and always pre-create 3 future months ahead of time!
SELECT partman.create_parent(
    p_parent_table := 'synoptic.observations_part',
    p_control      := 'obs_time',
    p_interval     := '1 month',
    p_premake      := 3
);

-- 2. Schedule pg_partman maintenance to run every night at 01:00 UTC via pg_cron:
SELECT cron.schedule(
    'nightly-partition-maintenance',
    '0 1 * * *',
    $$CALL partman.run_maintenance_proc()$$
);

-- 3. Schedule NWP Verification Materialized View refresh 30 mins after 00Z and 12Z model runs!
SELECT cron.schedule(
    'refresh-nwp-verification-00z-12z',
    '30 2,14 * * *',
    $$REFRESH MATERIALIZED VIEW CONCURRENTLY nwp.mv_daily_model_verification$$
);

-- View all scheduled jobs and their execution history:
SELECT * FROM cron.job;
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

---

## 5. Deep Dive #3: Query Observability — `pg_stat_statements` & `auto_explain`

### 5.1 `pg_stat_statements`: The Universal Performance Monitor
Normalizes incoming SQL queries, tracks total execution count, aggregate runtime, min/max/mean/stddev timings, and 8 KB buffer pool hits vs. disk reads. It immediately answers: *"Which 5 queries are consuming 80% of our server's CPU and disk I/O?"*

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Production Forensics Query: Top 5 queries by total execution time & buffer hit ratio
SELECT 
    calls,
    ROUND(total_exec_time::numeric, 2) AS total_time_ms,
    ROUND(mean_exec_time::numeric, 2)  AS mean_time_ms,
    shared_blks_hit,
    shared_blks_read                   AS disk_8kb_reads,
    ROUND((100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0))::numeric, 2) AS hit_ratio_pct,
    LEFT(query, 95)                    AS normalized_query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 5;
```

### 5.2 `auto_explain`: Zero-Code Slow Query Plan Logging
Automatically logs `EXPLAIN (ANALYZE, BUFFERS)` directly into the PostgreSQL server log whenever any query exceeds `auto_explain.log_min_duration`. Can also be enabled dynamically inside a single `psql` debugging session:

```sql
LOAD 'auto_explain';
SET auto_explain.log_min_duration = '500ms';
SET auto_explain.log_analyze = true;
SET auto_explain.log_buffers = true;
```

---

## 6. Deep Dive #4: Memory, Disk, Visibility & Online Compaction (`pg_buffercache`, `pg_prewarm`, `pageinspect`, `pgstattuple`, `pg_visibility`, `pg_repack`)

### 6.1 `pg_buffercache`: Real-Time RAM Buffer Inspection
Exposes a real-time view over PostgreSQL's `shared_buffers` array in RAM to reveal which tables and indexes are occupying memory and whether a large scan evicted hot operational indexes:

```sql
CREATE EXTENSION IF NOT EXISTS pg_buffercache;

SELECT 
    c.relname,
    pg_size_pretty(count(*) * 8192) AS buffered_size,
    ROUND((100.0 * count(*) / (SELECT setting FROM pg_settings WHERE name='shared_buffers')::integer)::numeric, 2) AS buffer_pool_pct,
    ROUND(avg(b.usagecount)::numeric, 2) AS avg_usage_tier
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
JOIN pg_database d ON (b.reldatabase = d.oid AND d.datname = current_database())
GROUP BY c.relname
ORDER BY count(*) DESC
LIMIT 10;
```

### 6.2 `pg_prewarm`: Eliminating the Cold-Cache Restart Penalty
Pre-loads critical indexes or hot partitions directly from disk into `shared_buffers` after a server reboot or replica promotion:

```sql
CREATE EXTENSION IF NOT EXISTS pg_prewarm;

-- Prewarm the active station covering index directly into shared_buffers RAM:
SELECT pg_prewarm('synoptic.idx_obs_station_time_covering', mode => 'buffer');
```

### 6.3 `pageinspect`: Binary 8 KB Page Anatomy Inspection
Exposes the raw byte structures of 8 KB heap pages, line pointers (`lp`), tuple headers (`t_xmin`, `t_xmax`, `t_ctid`), B-Tree pages, and BRIN ranges:

```sql
CREATE EXTENSION IF NOT EXISTS pageinspect;

-- Inspect the first 5 tuples on Heap Block 0 of raw_telemetry_partitioned (or telemetry_y2026m10):
SELECT lp, lp_off, lp_flags, lp_len, t_xmin, t_xmax, t_ctid 
FROM heap_page_items(get_raw_page('telemetry_y2026m10', 0))
LIMIT 5;
```

### 6.4 `pgstattuple`: Non-Locking Bloat Measurement
Scans relations and indexes to report exact live tuples, dead tuples (`dead_tuple_percent`), and free space without acquiring an `AccessExclusiveLock`:

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;

SELECT 
    table_len AS physical_bytes,
    pg_size_pretty(table_len) AS pretty_size,
    tuple_count AS live_tuples,
    dead_tuple_count AS dead_tuples,
    ROUND(dead_tuple_percent::numeric, 2) AS dead_pct,
    ROUND(free_percent::numeric, 2) AS free_space_pct
FROM pgstattuple('synoptic.observations');
```

### 6.5 `pg_visibility`: Visibility Map (`_vm`) Audits for Index-Only Scans
Verifies what percentage of 8 KB blocks in a relation are marked `all_visible` in the Visibility Map (`_vm`) fork so that Covering Indexes can execute with `Heap Fetches: 0`:

```sql
CREATE EXTENSION IF NOT EXISTS pg_visibility;

SELECT 
    count(*) AS total_blocks,
    count(*) FILTER (WHERE all_visible) AS all_visible_blocks,
    ROUND((100.0 * count(*) FILTER (WHERE all_visible) / NULLIF(count(*), 0))::numeric, 2) AS visibility_ratio_pct
FROM pg_visibility('synoptic.observations');
```

### 6.6 `pg_repack`: Lock-Free Online Table Reorganization
Standard `VACUUM FULL` acquires an `AccessExclusiveLock` and halts production reads and writes. **`pg_repack`** rebuilds bloated tables and indexes **online** using a shadow table and change-capture trigger, reclaiming physical disk space back to the Linux OS with only a `< 50 ms` metadata swap lock!

```bash
# 1. Install OS package:
sudo apt-get install -y postgresql-16-repack

# 2. Register extension inside database:
psql -U postgres -d weather_ops -c "CREATE EXTENSION IF NOT EXISTS pg_repack;"

# 3. Run online compaction from terminal without locking live weather ingestion:
pg_repack -h localhost -U postgres -d weather_ops -t synoptic.observations
```

---

## 7. Deep Dive #5: Temporal Integrity, Federation & Fuzzy Search (`btree_gist`, `file_fdw`, `postgres_fdw`, `pg_trgm`, `unaccent`)

### 7.1 `btree_gist`: Preventing Overlapping Sensor Calibration or Alert Windows
How do you guarantee in PostgreSQL that two technicians cannot accidentally enter **overlapping calibration validity periods (`TSTZRANGE`)** for the same `station_id`?
Standard B-Tree indexes only check equality (`=`), while `GiST` checks range overlaps (`&&`). **`btree_gist`** combines both inside a single `EXCLUDE USING GIST` constraint!

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE synoptic.sensor_calibration_windows (
    cal_id         SERIAL PRIMARY KEY,
    station_id     INTEGER      NOT NULL REFERENCES synoptic.stations(station_id),
    valid_period   TSTZRANGE    NOT NULL,
    temp_offset_c  NUMERIC(3,2) NOT NULL,
    -- For the same station_id (=), valid_period ranges MUST NOT overlap (&&)!
    EXCLUDE USING GIST (
        station_id WITH =,
        valid_period WITH &&
    )
);
```

### 7.2 `file_fdw` & `postgres_fdw`: Direct SQL Access to Datalogger CSVs & Remote Nodes
```sql
-- 1. Query raw datalogger CSV files directly from SQL via file_fdw:
CREATE EXTENSION IF NOT EXISTS file_fdw;
CREATE SERVER datalogger_files FOREIGN DATA WRAPPER file_fdw;

CREATE FOREIGN TABLE external_datalogger_dump (
    recorded_at TIMESTAMPTZ,
    station_id  VARCHAR(10),
    temperature REAL,
    wind_speed  REAL
) SERVER datalogger_files
OPTIONS (filename '/var/log/meteo/station_dump.csv', format 'csv', header 'true');

-- 2. Query remote regional PostgreSQL servers via postgres_fdw:
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE SERVER regional_node_oran FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host '10.10.30.50', port '5432', dbname 'oran_meteo_db');
```

### 7.3 `pg_trgm` & `unaccent`: Typo-Tolerant Station Search & METAR Substring Indexing
Standard B-Trees cannot accelerate `ILIKE '%THUNDER%'` or fuzzy spelling matches (`'Algirs Port Marin'` $\rightarrow$ `'Algiers Port Marine'`). **`pg_trgm`** slices text into 3-character trigrams indexed via `GIN`:

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Create GIN Trigram index on station_name:
CREATE INDEX IF NOT EXISTS idx_stations_trgm_name
ON stations USING GIN (station_name gin_trgm_ops);

-- Fuzzy search resilient to severe typos:
SELECT 
    station_id,
    station_name,
    ROUND(similarity(station_name, 'Algirs Port Marin')::numeric, 3) AS similarity_score
FROM stations
WHERE station_name % 'Algirs Port Marin'
ORDER BY similarity_score DESC
LIMIT 3;
```

---

## 8. Hands-On Forensics Lab: The DBA Diagnostic Toolkit

Execute this hands-on lab in `psql` against `weather_ops_db` (created in Module 0 / `day3_postgis_5m_benchmark.sql`) to install the diagnostic suite and run operational health audits.

### Step 1: Install and Enable Diagnostic Extensions
```sql
\c weather_ops_db

CREATE EXTENSION IF NOT EXISTS pg_buffercache;
CREATE EXTENSION IF NOT EXISTS pgstattuple;
CREATE EXTENSION IF NOT EXISTS pg_visibility;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Verify all installed extensions
\dx
```

#### Expected Terminal Output:
```text
                                  List of installed extensions
      Name      | Version |   Schema   |                            Description                            
----------------+---------+------------+-------------------------------------------------------------------
 plpgsql        | 1.0     | pg_catalog | PL/pgSQL procedural language
 postgis        | 3.4.2   | public     | PostGIS geometry and spatial types
 pg_buffercache | 1.4     | public     | examine the shared buffer cache
 pg_trgm        | 1.6     | public     | text similarity measurement and index searching based on trigrams
 pgstattuple    | 1.5     | public     | show tuple-level statistics
 pg_visibility  | 1.2     | public     | examine the visibility map (VM) and page-level visibility info
 unaccent       | 1.1     | public     | text search dictionary that removes accents
(7 rows)
```

### Step 2: Buffer Cache Forensics (`pg_buffercache`)
```sql
SELECT 
    CASE 
        WHEN c.relname IS NULL THEN '[Free Buffer Slots]'
        ELSE c.relname 
    END AS relation_name,
    c.relkind AS type,
    count(*) AS blocks_in_ram,
    pg_size_pretty(count(*) * 8192) AS ram_size,
    ROUND((100.0 * count(*) / sum(count(*)) OVER ())::numeric, 2) AS cache_share_pct
FROM pg_buffercache b
LEFT JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid) 
                     AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY c.relname, c.relkind
ORDER BY count(*) DESC
LIMIT 8;
```

### Step 3: Exact Bloat Audit on a Partition (`pgstattuple`)
```sql
SELECT 
    table_len AS total_file_bytes,
    pg_size_pretty(table_len) AS file_size_pretty,
    tuple_count AS active_tuples,
    dead_tuple_count AS defunct_tuples,
    dead_tuple_percent AS bloat_dead_pct,
    free_percent AS free_space_pct
FROM pgstattuple('telemetry_y2026m10');
```
- **Diagnostic Decision Rule:** If `bloat_dead_pct > 20%` and `free_space_pct > 25%`, and standard `VACUUM` cannot shrink the file because live tuples are scattered at the end of the heap, schedule an online compaction with `pg_repack`.

### Step 4: Trigram Fuzzy Search on Station Registries (`pg_trgm`)
```sql
CREATE INDEX IF NOT EXISTS idx_stations_trgm_name ON stations USING GIN (station_name gin_trgm_ops);

SELECT 
    station_id,
    station_name,
    ROUND(similarity(station_name, 'Algirs Port Marin')::numeric, 3) AS similarity_score
FROM stations
WHERE station_name % 'Algirs Port Marin'
ORDER BY similarity_score DESC
LIMIT 3;
```

---

## 9. Summary Checklist: Production Extensions Directives

```
================================================================================
               POSTGRESQL EXTENSIONS PRODUCTION DIRECTIVES
================================================================================
 1. Always Preload Observability : Add 'pg_stat_statements,auto_explain,pg_cron'
                                   to shared_preload_libraries in postgresql.conf.
 2. Enable Spatial Geodesy       : Install 'postgis' & 'postgis_raster'; index
                                   GEOGRAPHY(Point, 4326) columns with GiST.
 3. Automate Partition Builds    : Pair 'pg_partman' + 'pg_cron' (or 'timescaledb')
                                   to pre-create partitions before new months start.
 4. Enforce Temporal Integrity   : Use 'btree_gist' with EXCLUDE USING GIST to block
                                   overlapping station calibration or alert windows.
 5. Repack, Never VACUUM FULL    : Deploy 'pg_repack' for live, zero-downtime
                                   space reclamation on high-update tables.
 6. Audit RAM & Warm Caches      : Inspect 'pg_buffercache' during cache drops and
                                   run 'pg_prewarm' on critical indexes post-reboot.
 7. Clean Text at Database Gate  : Pair 'pg_trgm' with 'unaccent' to support fast,
                                   typo-tolerant station and METAR text searches.
================================================================================
```

---

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [⏮️ Day 2 Coursebook](../day2/day2_master_coursebook.md) | [📘 Day 3 Coursebook](day3_master_coursebook.md) | [⏭️ Day 4 Coursebook](../day4/day4_master_coursebook.md)

