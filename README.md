# 5-Day Master Bootcamp: Database, Columnar Lakehouse & Polyglot Telemetry Engineering for Weather Forecast Engineers

> [!IMPORTANT]
> **Architected & Synthesized with Gemini 4 Argon**  
> This repository is the unified, zero-duplication **"Best of Both"** master edition (`70 files`, `30,000+ lines` of coursebooks, SQL/MongoDB course walkthroughs, reference cards, interactive simulators, and runnable SQL/MQL/Python/Docker labs).
> - 💿 **VMware Ubuntu 24.04 Blank Lab From-Scratch Installation Guide:** Read **[VM_BLANK_LAB_FROM_SCRATCH_GUIDE.md](./VM_BLANK_LAB_FROM_SCRATCH_GUIDE.md)** to create the blank Ubuntu VM in VMware and install every database, CLI tool, Python environment, and GUI client from scratch (Native + Docker alternative).
> - 🛠️ **Attendee Tooling & Day-0 Setup Guide (Windows, macOS & Linux):** Read **[ATTENDEE_SETUP_GUIDE.md](./ATTENDEE_SETUP_GUIDE.md)** for step-by-step instructions on reading coursebooks, setting up **DB Browser for SQLite**, **DBeaver Community** & **MongoDB Compass**, and launching the Docker Compose database stacks.
> - 🌐 **Interactive Web Command Center, Built-In Coursebook Reader & Simulators:** Run `python3 start_bootcamp.py` (or open [bootcamp_portal.html](./bootcamp_portal.html)) to launch the **Built-In Dark-Mode Markdown/Code Reader**, **PostgreSQL Tuple Tetris 8-Byte Alignment Visualizer**, **`-9999.0` Hardware Sentinel & 3VL Simulator**, **Multi-Engine Scaling Calculator**, **Polyglot Architecture Map**, and **15-Question Live Certification Quiz** at `http://127.0.0.1:8088/bootcamp_portal.html`.
> - ✅ **1-Command Pre-Flight Verification:** Run [`./verify_bootcamp.sh`](./verify_bootcamp.sh) to execute automated integrity, SQLite seed, 250,000-row telemetry generation, Python AST compilation, and Docker Compose checks.

**Curriculum Scope:** 5 Intensive Modules / Days (Comprehensive Architecture Theory + Hands-On Production Labs)  
**Target Audience:** Meteorological Software Engineers, Weather Forecast Systems Administrators, & Environmental Data Scientists  
**Core Engine Progression:** `CSV & Hardware Sentinels` $\rightarrow$ `SQLite 3 (OLTP Foundations)` $\rightarrow$ `PostgreSQL 16 & PostGIS 3.4 (Storage Internals, Partitioning & Geodesy)` $\rightarrow$ `MongoDB 7.0 (BSON, Time-Series, 2dsphere & Sharding)` $\rightarrow$ `DuckDB, Apache Parquet, GRIB2/NetCDF4/Zarr, dbt, Ceph S3 & Polyglot Streaming Lakehouse`

---

## 1. Repository Architecture & Complete File Navigator (`70 Files`)

```text
alternative B/
├── README.md                                                      # Master Syllabus, File Navigator & Quick-Start Runbook
├── VM_BLANK_LAB_FROM_SCRATCH_GUIDE.md                             # Blank Ubuntu 24.04 VM in VMware & From-Scratch Install Guide
├── ATTENDEE_SETUP_GUIDE.md                                        # Attendee Tooling & Day-0 Setup Guide (Windows, macOS & Linux)
├── start_bootcamp.py                                              # Zero-Dependency HTTP Server & Browser Launcher (Port 8088)
├── bootcamp_portal.html                                           # Interactive Command Center, Built-In Reader, 3 Simulators & Quiz
├── verify_bootcamp.sh                                             # Automated Pre-Flight & Live SQL/Python/Docker Verification Suite
├── day1/                                                          # Day 1: SQL Foundations, 1NF-3NF vs Denormalization, All 7 JOINs, Sentinels (-9999), 3VL & Window Functions
├── day2/                                                          # Day 2: PostgreSQL 8KB Internals, Tuple Tetris, MVCC, WAL, VACUUM & EXPLAIN
├── day3/                                                          # Day 3: Production PostgreSQL: Partitioning, BRIN, PostGIS Geodesy, Extensions & Patroni HA
├── day4/                                                          # Day 4: MongoDB: BSON/WiredTiger, Time-Series, 2dsphere Storm Polygons, Aggregations & Sharding
├── day5/                                                          # Day 5: Vectorized DuckDB, Parquet Lakehouse, GRIB2/NetCDF4/Zarr, Polyglot Streaming & Capstone
├── reference_cards/                                               # 14 Deep-Dive Engineering Reference Cards + 21-Symptom Diagnostic Index (README.md)
└── docker/                                                        # Turnkey Docker Compose Topologies (3-Node HA Replica Set & 6-Service Polyglot Lakehouse)
```

---

## 2. Day-by-Day Curriculum & Executable Labs

### Day 1: Advanced SQL Foundations, Telemetry Wrangling & Hardware Sentinels (`day1/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day1/day1_master_coursebook.md](./day1/day1_master_coursebook.md) | **Master Coursebook (1,400 lines)** | CLI dot-commands vs. **SQLite `PRAGMA` engine directives** (`foreign_keys`, `journal_mode`, `synchronous`, `busy_timeout`, `wal_checkpoint` modes & `(busy, log, checkpointed)` return tuple, `journal_size_limit`, `cache_size`, `temp_store`, `table_info`), declarative 8-step query execution order, Three-Valued Logic (`3VL`), `-9999.0` hardware sentinel hygiene (`NULLIF`, `CASE WHEN`), **Black Box 1A (`NOT NULL` vs. `CHECK` vs. `NOT NULL CHECK` & 3VL Asymmetry)**, **`1NF`–`3NF` Normalization vs. Deliberate Denormalization**, **All 7 SQL `JOIN` Types & Black Box 1B (`LEFT JOIN ... ON` vs. `WHERE` silent `INNER JOIN` trap)**, `WITH RECURSIVE` gap detection, and **Black Box 1C (Window Frame `RANGE UNBOUNDED PRECEDING` default, `LAST_VALUE` trap & `ROWS` vs. `RANGE` on gappy streams)**. |
| [day1/weather_ops_seed_sql_course_walkthrough.md](./day1/weather_ops_seed_sql_course_walkthrough.md) | **SQL Course Walkthrough (641 lines)** | Complete line-by-line Markdown course explaining every `PRAGMA` category (per-connection vs. persistent `.db` header scope), DDL constraint, 3VL `NOT NULL` vs. `CHECK` decision matrix, planted sensor anomaly, `3NF` decomposition, and all 7 SQL `JOIN` recipes in `weather_ops_seed.sql`. |
| [day1/day1_sqlite_and_sql_cheatsheet.md](./day1/day1_sqlite_and_sql_cheatsheet.md) | **Cheatsheet (836 lines)** | Complete `sqlite3` CLI dot-commands (`.headers`, `.mode box`, `.timer on`, `~/.sqliterc`), **comprehensive SQLite `PRAGMA` & `WAL` Reference** (Integrity, `WAL` 4 checkpoint modes, `journal_mode` $\times$ `synchronous` `fsync` matrix, WAL Starvation & `BEGIN IMMEDIATE` `SQLITE_BUSY_SNAPSHOT`, Memory/Cache, `pragma_*` TVFs, and 3 Production Profiles), 3VL `WHERE` vs. `CHECK` truth tables, 4-Pattern Constraint Decision Matrix, Normalization vs. Denormalization matrix, SQL `JOIN` compatibility & `<3.39` portable rewrites, temporal bucketing, and window function recipes. |
| [day1/day1_hardware_sentinels_and_qc_guide.md](./day1/day1_hardware_sentinels_and_qc_guide.md) | **Deep-Dive Guide (393 lines)** | Physics of RS-485/Modbus/SDI-12 & Pt100 ADC open/short-circuit `-9999.0` sentinels, WMO Code 306 flags, 3VL mean/variance contamination math, and ELT QC architecture. |
| [day1/weather_ops_seed.sql](./day1/weather_ops_seed.sql) | **SQL Seed Script** | Builds `weather_ops.db` with WMO stations, synoptic observations (with `NULL` dropouts, `-9999.0` sentinels, and `68.5°C` spikes), NWP forecasts, and alerts. |
| [day1/weather_ops.db](./day1/weather_ops.db) | **SQLite Database** | Pre-built WMO operational SQLite database ready for immediate CLI or DBeaver inspection. |
| [day1/generate_weather_db.py](./day1/generate_weather_db.py) | **Python Generator** | Zero-dependency Python script synthesizing `weather_telemetry.db` (**250,000 rows** across 50 AWS stations in ~2 seconds). |
| [day1/weather_telemetry.db](./day1/weather_telemetry.db) | **SQLite Database (250k rows)** | Pre-generated 250,000-row AWS telemetry database with injected `-999.0` sentinels, frontal pressure drops, and `AWS-033` 6-hour communications blackout. |

---

### Day 2: PostgreSQL Storage Engine Internals, MVCC, WAL, `VACUUM` & Tuning (`day2/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day2/day2_master_coursebook.md](./day2/day2_master_coursebook.md) | **Master Coursebook (1,341 lines)** | Host NVMe storage topology (`pgdata` vs `pgwal`), `synoptic`/`nwp`/`alerts` schemas, **Black Box 2A (`TIMESTAMPTZ` vs. `TIMESTAMP` 8-byte UTC normalization & DST fallback collision)**, **Black Box 2B (`NUMERIC(p,s)` vs. `REAL`/`DOUBLE PRECISION` binary float trap)**, **Black Box 2C (`PRIMARY KEY` vs. `UNIQUE NOT NULL` vs. `NULLS DISTINCT`)**, **Black Box 2D (`BIGINT IDENTITY` vs. `UUIDv4` B-Tree/WAL FPW killer vs. RFC 9562 time-ordered `UUIDv7`)**, 8 KB Heap Pages (`PageHeaderData`, `ItemIdData`, 23-byte `HeapTupleHeaderData`), CPU Byte-Alignment Padding ("Tuple Tetris" saving 8–16 bytes/row), TOAST (`lz4`), Dual-Caching (`shared_buffers` vs OS Page Cache), Checkpoint Smoothing, `COPY` vs `INSERT`, **LLVM `JIT` latency traps, Parallel Bulk Index Builds, `plan_cache_mode`, and the 10-Layer Optimization Matrix**. |
| [day2/weather_ops_pg_sql_course_walkthrough.md](./day2/weather_ops_pg_sql_course_walkthrough.md) | **SQL Course Walkthrough (507 lines)** | Line-by-line Markdown course explaining `weather_ops_pg.sql`: multi-schema isolation, `NOT NULL` vs. `CHECK` 4-pattern matrix, `TOAST` out-of-line compression, `GENERATED ALWAYS AS ... STORED`, `generate_series()` diurnal/synoptic wave math, and per-table autovacuum tuning. |
| [day2/day2_pageinspect_and_storage_lab_course_walkthrough.md](./day2/day2_pageinspect_and_storage_lab_course_walkthrough.md) | **SQL Course Walkthrough (712 lines)** | Line-by-line Markdown course explaining `day2_pageinspect_and_storage_lab.sql`: Tuple Tetris byte offsets, `pageinspect` (`page_header`, `heap_page_items`), MVCC `t_xmin`/`t_xmax`/`t_ctid` chains, `pgstattuple` `VACUUM` vs `VACUUM FULL`, and 1M-row `EXPLAIN (ANALYZE, BUFFERS)`. |
| [day2/day2_two_terminal_acid_lab_course_walkthrough.md](./day2/day2_two_terminal_acid_lab_course_walkthrough.md) | **SQL Course Walkthrough (572 lines)** | Line-by-line Markdown course explaining `day2_two_terminal_acid_lab.sql`: Snapshot Isolation, row-lock queues, `pg_blocking_pids()` & `pg_locks` forensics, `40P01` deadlocks, `READ COMMITTED` vs `REPEATABLE READ`, and emergency DBA session termination. |
| [day2/day2_postgres_tuning_and_internals_cheatsheet.md](./day2/day2_postgres_tuning_and_internals_cheatsheet.md) | **Cheatsheet (406 lines)** | 32 GB RAM `postgresql.conf` weather profile, `pg_hba.conf`, `psql` commands, 8 KB page layout, Tuple Tetris alignment rules, **Black Box 2A–2D Data Type, Uniqueness & `UUIDv7` Decision Matrices**, `pg_locks` diagnostics, `EXPLAIN (ANALYZE, BUFFERS)` red flags, and the **10-Layer PostgreSQL Performance Optimization Master Checklist**. |
| [day2/day2_postgres_vs_mysql_mvcc_guide.md](./day2/day2_postgres_vs_mysql_mvcc_guide.md) | **Comparative Guide (309 lines)** | Head-to-head forensic comparison: PostgreSQL 8 KB Unclustered Heap (`ctid`, `t_xmin`/`t_xmax`, HOT updates, $O(1)$ rollback) vs. MySQL InnoDB 16 KB Clustered B+Tree (`DB_TRX_ID`, Undo Logs, Purge Lag, secondary index double-lookup penalty). |
| [day2/weather_ops_pg.sql](./day2/weather_ops_pg.sql) | **SQL Seed Script** | Multi-schema PostgreSQL seed script (`synoptic`, `nwp`, `alerts`) generating **18,000+ synoptic observations** and **9,000+ NWP model forecasts**. |
| [day2/day2_pageinspect_and_storage_lab.sql](./day2/day2_pageinspect_and_storage_lab.sql) | **SQL Forensics Lab** | Runnable lab proving Tuple Tetris byte savings (`pg_column_size`), `pageinspect` MVCC tuple version chains, `pgstattuple` bloat measurement, and 1,000,000-row `EXPLAIN (ANALYZE, BUFFERS)` row-store I/O amplification. |
| [day2/day2_two_terminal_acid_lab.sql](./day2/day2_two_terminal_acid_lab.sql) | **Two-Terminal ACID Lab (341 lines)** | Side-by-side `[TERM A]` vs. `[TERM B]` scripts for Snapshot Isolation, Row-Level Lock Contention (`FOR NO KEY UPDATE`), Circular Deadlock Detection (`40P01`), `READ COMMITTED` vs. `REPEATABLE READ`, and `pg_blocking_pids()` termination. |

---

### Day 3: Advanced Production PostgreSQL: Partitioning, BRIN, PostGIS Geodesy, Extensions & HA (`day3/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day3/day3_master_coursebook.md](./day3/day3_master_coursebook.md) | **Master Coursebook (1,019 lines)** | Declarative time-range partitioning (`PARTITION BY RANGE`), **Black Box 3A (Why Partitioned `PRIMARY KEY` requires the partition key & why `FOR VALUES FROM (A) TO (B)` is half-open $[A, B)$)**, zero-bloat `DETACH PARTITION CONCURRENTLY`, **Black Box 3B (Why `BRIN` always uses `Bitmap Heap Scan + Recheck Cond` & 6-Index Decision Matrix)**, PostGIS Geodesy (`GEOGRAPHY(Point, 4326)` vs `GEOMETRY`, `ST_DWithin`, `ST_Distance`), meteorological window functions ($\Delta P_{3\text{h}}$), idempotent `UPSERT` (`IS DISTINCT FROM`), `JSONB`, and `REFRESH MATERIALIZED VIEW CONCURRENTLY`. |
| [day3/day3_weather_advanced_pg_sql_course_walkthrough.md](./day3/day3_weather_advanced_pg_sql_course_walkthrough.md) | **SQL Course Walkthrough (603 lines)** | Line-by-line Markdown course explaining `day3_weather_advanced_pg.sql`: `PARTITION BY RANGE`, `PRIMARY KEY` partition rules, `jsonb_build_object`, the 5 specialized indexes (`BRIN`, `BTREE`, Partial, Covering `INCLUDE`, `GIN`), concurrent materialized views, and PostGIS `GEOGRAPHY`. |
| [day3/day3_postgis_5m_benchmark_sql_course_walkthrough.md](./day3/day3_postgis_5m_benchmark_sql_course_walkthrough.md) | **SQL Course Walkthrough (735 lines)** | Line-by-line Markdown course explaining `day3_postgis_5m_benchmark.sql`: `\gexec`, WGS-84 Haversine great-circle spherical trigonometry, `GiST` spatial indexes, 5,000,000-row partitioned ingestion, `pg_inherits` catalog forensics, B-Tree vs BRIN size benchmarks, and `ST_DWithin` joins. |
| [day3/day3_postgres_advanced_cheatsheet.md](./day3/day3_postgres_advanced_cheatsheet.md) | **Cheatsheet (220 lines)** | Quick reference for declarative partitioning & $[A, B)$ bounds, B-Tree vs. BRIN (`Bitmap Heap Scan + Recheck Cond`) vs. Partial vs. GIN index selection, PostGIS spatial functions, window frames, `UPSERT`, and `JSONB` operators. |
| [day3/day3_postgres_extensions_guide.md](./day3/day3_postgres_extensions_guide.md) | **Deep-Dive Guide (574 lines)** | Complete guide to 15 essential extensions: `PostGIS`, `postgis_raster`, `TimescaleDB`, `pg_partman`, `pg_cron`, `pg_stat_statements`, `auto_explain`, `pg_buffercache`, `pg_prewarm`, `pageinspect`, `pgstattuple`, `pg_visibility`, `pg_repack`, and `btree_gist`. |
| [day3/day3_postgres_ha_patroni_and_ops_guide.md](./day3/day3_postgres_ha_patroni_and_ops_guide.md) | **Deep-Dive Guide (787 lines)** | CAP & PACELC theorems in weather networks, Physical vs. Logical Replication, Split-Brain prevention, `Patroni` + 3-node `etcd` + `HAProxy` Docker blueprint, `patronictl` runbook, `PgBouncer` transaction pooling, RBAC security, and `pg_dump`/`pg_basebackup` PITR backups. |
| [day3/day3_weather_advanced_pg.sql](./day3/day3_weather_advanced_pg.sql) | **SQL Lab Script** | Monthly range partitions, BRIN/Partial/Covering/GIN indexes, `nwp.mv_daily_model_verification` materialized view, and PostGIS `GEOGRAPHY` proximity queries. |
| [day3/day3_postgis_5m_benchmark.sql](./day3/day3_postgis_5m_benchmark.sql) | **SQL Benchmark Script** | Seeds **5,000,000 partitioned telemetry rows** across 50 PostGIS stations and benchmarks B-Tree (`28 MB`) vs. BRIN (`32 KB`) index scans and geodesic `ST_DWithin` joins. |

---

### Day 4: MongoDB & Polymorphic Telemetry: BSON, Time-Series, `2dsphere`, Aggregations & Sharding (`day4/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day4/day4_master_coursebook.md](./day4/day4_master_coursebook.md) | **Master Coursebook (1,116 lines)** | Polymorphic station metadata, **Black Box 4A (`$jsonSchema` `required` vs. `bsonType` & the `{ temp_c: null }` vs. `$type: 10` vs. `$exists: false` query trap)**, BSON binary encoding & WiredTiger storage internals, upper-air radiosonde soundings (`$elemMatch`), Native Time-Series collections (`system.buckets.*` + TTL) vs. the Manual Bucket Pattern, multi-stage Aggregation Pipelines & **Black Box 4B (`$unwind` silent empty-array drop vs. `preserveNullAndEmptyArrays: true`)**, `2dsphere` GeoJSON storm polygons, the `ESR` Indexing Rule, 3-node Replica Sets, Tunable CAP/PACELC, GridFS, and Sharding (`mongos`). |
| [day4/day4_weather_ops_mongo_js_course_walkthrough.md](./day4/day4_weather_ops_mongo_js_course_walkthrough.md) | **MongoDB Course Walkthrough (546 lines)** | Line-by-line Markdown course explaining `day4_weather_ops_mongo.js`: `$jsonSchema` validation rules, polymorphic stations, bounded `vertical_levels` radiosonde arrays, native Time-Series collections (`system.buckets.*`), and CAP storm alerts. |
| [day4/day4_weather_ops_mongo_advanced_js_course_walkthrough.md](./day4/day4_weather_ops_mongo_advanced_js_course_walkthrough.md) | **MongoDB Course Walkthrough (352 lines)** | Line-by-line Markdown course explaining `day4_weather_ops_mongo_advanced.js`: `2dsphere` spherical indexes, GeoJSON closed-ring `Polygon` rules, `ESR` compound indexing (`idx_sonde_esr`), and isobaric `$unwind` aggregation stages. |
| [day4/day4_mongo_50k_polymorphic_benchmark_js_course_walkthrough.md](./day4/day4_mongo_50k_polymorphic_benchmark_js_course_walkthrough.md) | **MongoDB Course Walkthrough (571 lines)** | Line-by-line Markdown course explaining `day4_mongo_50k_polymorphic_benchmark.js`: 50,000-document batch ingestion (`{ ordered: false }`), 4 polymorphic instrument schemas, Manual Bucket Pattern atomic upserts, Road Safety & `$unwind` Fault Diagnostics, and WiredTiger vs Columnar `stats()`. |
| [day4/day4_mongodb_complete_cheatsheet.md](./day4/day4_mongodb_complete_cheatsheet.md) | **Cheatsheet (285 lines)** | `mongod.conf` weather tuning, SQL-to-MQL translator, **Black Box 4A–4B Null/Missing & `$unwind` Decision Matrices**, Time-Series & Bucket Pattern syntax, Aggregation stages, `2dsphere` GeoJSON operators, and the `ESR` compound index rule. |
| [day4/day4_mongodb_architecture_ha_and_sharding_guide.md](./day4/day4_mongodb_architecture_ha_and_sharding_guide.md) | **Deep-Dive Guide (571 lines)** | WiredTiger cache & checkpoint mechanics, 3-node Replica Set deployment (`rs.initiate`, priority/tag sets), PyMongo `SecondaryPreferred` analytics routing, Tunable CAP (`w: "majority"` vs `w: 1`), GridFS vs. S3, and Sharded Cluster (`sh.*`) administration. |
| [day4/day4_weather_ops_mongo.js](./day4/day4_weather_ops_mongo.js) | **`mongosh` Seed Script** | Creates polymorphic `stations` (`$jsonSchema`), `radiosonde_soundings`, `synoptic_timeseries` (native Time-Series + 90-day TTL), and `cap_alerts`. |
| [day4/day4_weather_ops_mongo_advanced.js](./day4/day4_weather_ops_mongo_advanced.js) | **`mongosh` Lab Script** | Builds `2dsphere` spatial indexes, `storm_polygons` (convective & haboob warning polygons), `idx_sonde_esr` compound index, and isobaric aggregation views. |
| [day4/day4_mongo_50k_polymorphic_benchmark.js](./day4/day4_mongo_50k_polymorphic_benchmark.js) | **`mongosh` Benchmark** | Generates **50,000 polymorphic sensor documents** (`METAR_STANDARD`, `ULTRASONIC_3D`, `PRESENT_WEATHER_OPTICAL`, `ROAD_SURFACE_RADAR`), benchmarks Manual Bucket Pattern upserts, and runs `$unwind` hardware fault diagnostics. |

---

### Day 5: Vectorized OLAP (`DuckDB` & `Parquet`), Gridded Data (`GRIB2`/`NetCDF4`/`Zarr`) & Enterprise Polyglot Lakehouse Capstone (`day5/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md](./day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | **Master Coursebook Part 1 (988 lines)** | Volcano tuple-at-a-time vs. Vectorized SIMD (2,048-tuple vectors), Apache Parquet columnar layout & Hive partitioning, **Black Box 5A (How DuckDB scans 100M Parquet rows without B-Trees via 3-Gate Pruning & why unsorted exports ruin Row Group Zone Maps)**, **Black Box 5B (`NetCDF4`/`COG` `UInt16` quantization `scale_factor`/`add_offset` & masking `_FillValue` before unpacking)**, and PostgreSQL-to-Parquet archival pipelines. |
| [day5/day5_part2_enterprise_polyglot_lakehouse_and_capstone_coursebook.md](./day5/day5_part2_enterprise_polyglot_lakehouse_and_capstone_coursebook.md) | **Master Coursebook Part 2 (951 lines)** | Grand Unified National Weather Center Architecture, Hot/Warm/Cold storage SLAs, Edge MQTT & Kafka streaming, Dynamic Polyglot Stream Router, Hot-to-Cold Parquet Compactor + $O(1)$ Partition Detach, Sub-10ms Unified FastAPI Serving Tier, and the **Dellys Cape Mediterranean Squall Line Capstone Disaster Lab**. |
| [day5/bootcamp_capstone_troubleshooting_and_quiz.md](./day5/bootcamp_capstone_troubleshooting_and_quiz.md) | **Capstone Assessment (206 lines)** | **15 Real-World Weather Database Troubleshooting Scenarios** ("What Went Wrong?") + **15 Multiple-Choice Final Certification Quiz Questions** with full answer keys. |
| [day5/export_pg_to_parquet.py](./day5/export_pg_to_parquet.py) | **Python Pipeline** | Streams PostgreSQL observations via server-side cursor into ZSTD-compressed Apache Parquet (`psycopg` + `pyarrow`). |
| [day5/seed_olap_data.py](./day5/seed_olap_data.py) | **Python Generator** | Generates a **10,000,000-row Hive-partitioned Parquet climatology lake** and a **4D CF-1.8 compliant `NetCDF4` NWP grid**. |
| [day5/parquet_vs_csv_benchmark.py](./day5/parquet_vs_csv_benchmark.py) | **Python Benchmark** | Benchmarks 1,000,000 meteorological rows across Raw CSV, Uncompressed Parquet, Snappy Parquet, and ZSTD Dictionary-Encoded Parquet + DuckDB scan speed. |
| [day5/compact_small_parquet_files.py](./day5/compact_small_parquet_files.py) | **Python Compaction Lab** | Simulates the Lakehouse "Small Files Problem" (200 tiny Parquet files) and compacts them into optimal ZSTD Row Groups via PyArrow/DuckDB. |
| [day5/satellite_cog_int16_quantization.py](./day5/satellite_cog_int16_quantization.py) | **Python Raster Lab** | Quantizes 32-bit Float Kelvin (`200K–330K`) satellite rasters to `UInt16` (`0.01K` scale factor + horizontal predictor), achieving 50–75% petabyte storage reduction. |
| [day5/simulate_edge_sensors.py](./day5/simulate_edge_sensors.py) | **Python MQTT Simulator** | Publishes real-time `METAR_STANDARD` and 20Hz `ULTRASONIC_3D` telemetry (with `-999.0` sentinels) over MQTT. |
| [day5/stream_router.py](./day5/stream_router.py) | **Python Polyglot Router** | Subscribes to MQTT and dynamically routes structured METAR observations to PostgreSQL/PostGIS and polymorphic turbulence arrays to MongoDB. |
| [day5/compact_hot_to_cold.py](./day5/compact_hot_to_cold.py) | **Python Lake Compactor** | Offloads PostgreSQL partitions via zero-copy Arrow into Hive-partitioned ZSTD Parquet, strips `-999.0` sentinels, and verifies via DuckDB. |
| [day5/serving_api.py](./day5/serving_api.py) | **Python FastAPI Server** | Sub-10ms unified REST API querying PostGIS (`ST_DWithin`), MongoDB (`ULTRASONIC_3D` anomalies), and DuckDB (Parquet climatology). |

---

### 2.6 Master Directory of Demystified Engineering "Black Boxes" & Decision Matrices (Days 1–5)

Throughout all 5 days, every non-obvious database rule or silent query trap is demystified from first principles with a **Truth Table / Byte Map** and a **4-Pattern Engineering Decision Matrix**:

| Code | Demystified Engineering "Black Box" | Core First-Principles Mechanism | Master Coursebook & Cheatsheet Links |
| :-: | :--- | :--- | :--- |
| **1A** | **`NOT NULL` vs. `CHECK` vs. `NOT NULL CHECK`** | **3VL Asymmetry:** `WHERE` requires `TRUE` (rejects `UNKNOWN`), whereas `CHECK` only rejects `FALSE` (**accepts `UNKNOWN` when `NULL`!**). `NOT NULL` guards presence; `CHECK` guards domain range; `'' != NULL`. | [Day 1 Coursebook §4.1.2](./day1/day1_master_coursebook.md) • [Day 1 Cheatsheet](./day1/day1_sqlite_and_sql_cheatsheet.md) • [Day 1 Walkthrough](./day1/weather_ops_seed_sql_course_walkthrough.md) |
| **1B** | **`LEFT JOIN ... ON` vs. `LEFT JOIN ... WHERE`** | Placing a right-table filter (`o.obs_time >= ...`) in `WHERE` evaluates `NULL >= ...` $\rightarrow$ `UNKNOWN` *after* the join, silently destroying padded `NULL` rows and downgrading `LEFT JOIN` to `INNER JOIN`. | [Day 1 Coursebook §3.2.5](./day1/day1_master_coursebook.md) • [Day 1 Cheatsheet](./day1/day1_sqlite_and_sql_cheatsheet.md) |
| **1C** | **Window Frames (`OVER (...)` Default & `ROWS` vs. `RANGE`)** | Adding `ORDER BY` inside `OVER (...)` silently sets `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` (breaking `LAST_VALUE()`). `ROWS BETWEEN` counts rows (shifts across telemetry dropouts); `RANGE BETWEEN INTERVAL` measures true wall-clock time. | [Day 1 Coursebook §6.3](./day1/day1_master_coursebook.md) |
| **2A** | **`TIMESTAMPTZ` vs. `TIMESTAMP` (Both 8 Bytes!)** | Neither stores a timezone string on disk (`8-byte BIGINT` $\mu\text{s}$ since `2000-01-01`). `TIMESTAMPTZ` normalizes to UTC on `INSERT`; `TIMESTAMP` stores raw wall-clock numbers (causing 1-hour duplicate collisions on DST fallback). | [Day 2 Coursebook §4.2](./day2/day2_master_coursebook.md) • [Day 2 Cheatsheet §4.1](./day2/day2_postgres_tuning_and_internals_cheatsheet.md) |
| **2B** | **`NUMERIC(p, s)` vs. `REAL` / `DOUBLE PRECISION`** | Binary floats cannot represent $0.1_{10}$ (`0.1 + 0.2 = 0.30000000000000004`). In `NUMERIC(p,s)`, max integer digits = $p - s$ (`NUMERIC(4,1)` overflows at `1000.0`). | [Day 2 Coursebook §4.2](./day2/day2_master_coursebook.md) • [Day 2 Cheatsheet §4.1](./day2/day2_postgres_tuning_and_internals_cheatsheet.md) |
| **2C** | **`PRIMARY KEY` vs. `UNIQUE` (`NULLS DISTINCT`)** | `PRIMARY KEY` = `UNIQUE NOT NULL`. Standard SQL `UNIQUE` treats `NULL != NULL` (`NULLS DISTINCT`), allowing unlimited `NULL`s unless `NOT NULL` or `UNIQUE NULLS NOT DISTINCT` (PG 15+) is specified. | [Day 2 Coursebook §4.2](./day2/day2_master_coursebook.md) • [Day 2 Cheatsheet §4.1](./day2/day2_postgres_tuning_and_internals_cheatsheet.md) |
| **2D** | **Surrogate Primary Keys (`BIGINT IDENTITY` vs. `UUIDv4` vs. `UUIDv7` RFC 9562)** | Random `UUIDv4` (`gen_random_uuid()`) scatters inserts across all B-Tree leaf pages, causing 50/50 page splits and **$500\times$ `pg_wal` Full-Page Write (`FPW`) amplification**. **`UUIDv7` (RFC 9562)** places a 48-bit big-endian Unix ms timestamp in the top 6 bytes (`16B` native `UUID`, `typalign='c'`), restoring rightmost B-Tree leaf append locality for offline edge stations. | [Day 2 Coursebook §4.2](./day2/day2_master_coursebook.md) • [Day 2 Cheatsheet §4.1](./day2/day2_postgres_tuning_and_internals_cheatsheet.md) • [Reference Card 11 §5.5](./reference_cards/11_python_database_drivers_for_weather_engineers.md) |
| **2E** | **MySQL Dual-Log (`Redo` vs. `binlog`) `2PC`, 3-Thread `Relay Log` & 3-Engine Failover** | Why MySQL has **two logs** (`InnoDB Redo Log` for local crash recovery vs. Server `binlog` for replication) synced via Internal XA `2PC` (`Dual-1`), why `binlog_format = ROW` is mandatory, how the 3-thread pipeline (`Dump` $\rightarrow$ `I/O` $\rightarrow$ `Relay Log` $\rightarrow$ `WRITESET` Parallel Workers) works, and the **PostgreSQL vs. MySQL vs. MongoDB Failover Matrix**. | [Reference Card 14 §9](./reference_cards/14_mysql_and_mariadb_innodb_complete_engineering_guide.md#9-high-availability-gtid-replication-mysql-innodb-cluster-group-replication--proxysql) • [Day 2 PG vs. MySQL Guide §5.3](./day2/day2_postgres_vs_mysql_mvcc_guide.md#53-replication-high-availability--failover-mechanics-postgresql-vs-mysql-innodb) |
| **3A** | **Partitioned `PRIMARY KEY` & Half-Open Bounds $[A, B)$** | Partitioned tables have no global B-Tree (preserving $O(1)$ `DETACH PARTITION`), so `PRIMARY KEY` must include the partition key. `FOR VALUES FROM (A) TO (B)` is $[A, B)$ ($\ge A \land < B$) to prevent microsecond boundary gaps. | [Day 3 Coursebook Mod 1](./day3/day3_master_coursebook.md) • [Day 3 Cheatsheet §1.1](./day3/day3_postgres_advanced_cheatsheet.md) |
| **3B** | **Why `BRIN` Always Uses `Bitmap Heap Scan + Recheck Cond`** | `BRIN` stores zero `ctid` row pointers—only `[min, max]` per 8 KB block range (`32 KB` vs. `28 MB` B-Tree). PostgreSQL reads candidate blocks via `Bitmap Heap Scan` and filters individual tuples via `Recheck Cond`. | [Day 3 Coursebook Mod 2](./day3/day3_master_coursebook.md) • [Day 3 Cheatsheet §2.1](./day3/day3_postgres_advanced_cheatsheet.md) |
| **3C** | **PostgreSQL Split-Brain Fencing (`Patroni` + `etcd`) & `synchronous_commit`** | Why PostgreSQL has no built-in auto-failover (2-node network glitch = `Split-Brain`), how `Patroni` + 3-node `etcd` 10s TTL lease + `/dev/watchdog` fence old Primaries, and the 4-pattern `synchronous_commit` (`off` vs. `local` vs. `on` vs. `remote_apply`) matrix. | [Day 3 Coursebook §6.1](./day3/day3_master_coursebook.md) • [Day 3 HA Guide](./day3/day3_postgres_ha_patroni_and_ops_guide.md) • [Day 3 Cheatsheet §6.1](./day3/day3_postgres_advanced_cheatsheet.md) |
| **4A** | **MongoDB `$jsonSchema` & The `{ field: null }` Query Trap** | In `$jsonSchema`, `required` checks key existence while `bsonType` checks value type (`null` fails `bsonType: "double"`). In MQL, `{ temp_c: null }` matches **both** explicit `null` and missing keys; use `{ $type: 10 }` vs. `{ $exists: false }`. | [Day 4 Coursebook §1.4](./day4/day4_master_coursebook.md) • [Day 4 Cheatsheet §3.1](./day4/day4_mongodb_complete_cheatsheet.md) |
| **4B** | **MongoDB `$unwind` Silent Empty-Array Drop** | `{ $unwind: "$arr" }` acts like `INNER JOIN`, silently dropping documents with `[]` or `null` arrays. Use `preserveNullAndEmptyArrays: true` (`LEFT JOIN`) for fleet-wide health denominators. | [Day 4 Coursebook §3.3](./day4/day4_master_coursebook.md) • [Day 4 Cheatsheet §5.1](./day4/day4_mongodb_complete_cheatsheet.md) |
| **4C** | **PostgreSQL (`Patroni`) vs. MongoDB (`Replica Set`) Failover & `w: 1` Rollback Trap** | Head-to-head comparison of PostgreSQL physical WAL + external `Patroni`/`etcd`/`HAProxy` vs. MongoDB logical `oplog.rs` + built-in Raft election + smart driver, plus why `{ w: 1 }` writes suffer silent post-failover rollbacks (`rollback/` BSON files) vs. `{ w: "majority", j: true }`. | [Day 4 Coursebook §5.2](./day4/day4_master_coursebook.md) • [Day 4 HA & Sharding Guide](./day4/day4_mongodb_architecture_ha_and_sharding_guide.md) • [Day 4 Cheatsheet §8.1](./day4/day4_mongodb_complete_cheatsheet.md) |
| **4D** | **MongoDB Shard Key Selection (`MaxKey` Hotspot & Jumbo Chunks)** | Why monotonic `{ obs_time: 1 }` routes 100% of live writes to 1 shard (`MaxKey` hotspot), why low-cardinality `{ station_type: 1 }` creates unsplittable Jumbo Chunks, why `{ obs_time: "hashed" }` causes Scatter-Gather range scans, and why compound **`{ "station_meta.station_id": 1, obs_time: 1 }`** wins on both writes and targeted reads. | [Day 4 Coursebook §5.4](./day4/day4_master_coursebook.md) • [Day 4 HA & Sharding Guide](./day4/day4_mongodb_architecture_ha_and_sharding_guide.md) • [Day 4 Cheatsheet §8.2](./day4/day4_mongodb_complete_cheatsheet.md) |
| **5A** | **DuckDB 3-Gate Parquet Pruning Without B-Trees** | DuckDB skips 99%+ of I/O via (1) Hive Directory Pruning $\rightarrow$ (2) Parquet Footer Row Group `min`/`max` Zone Maps $\rightarrow$ (3) Column Chunk Projection. Unsorted exports ruin Gate 2 (`[min, max]` overlap across all Row Groups). | [Day 5 Part 1 Coursebook §3.2](./day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) |
| **5B** | **`NetCDF4`/`COG` `UInt16` Quantization & `_FillValue`** | Physical packing $P = \text{round}((V - \text{offset})/\text{scale})$ slashes 32-bit float rasters by 50–75%. Readers must mask `_FillValue = 65535` to `NaN` *before* unpacking, or missing space pixels become $+455.35^\circ\text{C}$. | [Day 5 Part 1 Coursebook §4.2](./day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) |

---

## 3. Deep-Dive Engineering Reference Cards Library (`reference_cards/`)

See **[reference_cards/README.md](./reference_cards/README.md)** for the **21-Scenario Symptom-to-Reference-Card Diagnostic Lookup Table**.

| # | Reference Card | Lines | Core Engineering Topics Covered |
| :-: | :--- | :---: | :--- |
| **01** | [01_apache_parquet_and_columnar_architecture.md](./reference_cards/01_apache_parquet_and_columnar_architecture.md) | 832 | Parquet binary anatomy (`PAR1`, Row Groups, Pages, Footer), Dictionary/RLE/Delta-of-Delta/Byte-Stream-Split encodings, Zone Maps, ZSTD compression, CSV vs. Parquet benchmarks, and Postgres-to-Parquet pipelines (`ConnectorX`, `DuckDB`, `pg_parquet`). |
| **02** | [02_duckdb_vectorized_olap_vs_sqlite.md](./reference_cards/02_duckdb_vectorized_olap_vs_sqlite.md) | 458 | DuckDB SIMD morsel-driven execution vs. SQLite row-store, zero-copy Apache Arrow bridge, `httpfs`/`spatial`/`sqlite`/`postgres` extensions, `ASOF JOIN`, and the 4-Engine Decision Matrix. |
| **03** | [03_hive_partitioning_and_lakehouse_compaction.md](./reference_cards/03_hive_partitioning_and_lakehouse_compaction.md) | 337 | Physical Hive directory layouts (`year=YYYY/month=MM`), directory pruning, the "Small Files Problem" I/O penalty, PyArrow/DuckDB compaction lab, and Apache Iceberg / Delta Lake metadata tables. |
| **04** | [04_meteorological_gridded_formats_cog_zarr_netcdf_grib_bufr.md](./reference_cards/04_meteorological_gridded_formats_cog_zarr_netcdf_grib_bufr.md) | 1,006 | Database BLOB anti-pattern vs. S3 Object Storage, Cloud-Optimized GeoTIFFs (`COG`), `Zarr`, `Kerchunk` (`GRIB2`/`NetCDF4` virtualization), `xarray` NWP extraction, WMO `BUFR` decoding (`pdbufr`), `STAC` + PostGIS catalog, `Int16` quantization (50–75% petabyte savings), and `TiTiler` HTTP byte-range serving. |
| **05** | [05_ceph_distributed_storage_and_proxmox_ve_architecture.md](./reference_cards/05_ceph_distributed_storage_and_proxmox_ve_architecture.md) | 950 | Sovereign on-premises Ceph (`MON`, `MGR`, `OSD`, `RGW`, `CRUSH`, `BlueStore` NVMe WAL/DB), Reed-Solomon Erasure Coding ($k=4, m=2$), Proxmox VE 5-node hyperconverged deployment (`pveceph`), HAProxy + Keepalived S3 load balancing, and `ceph` operational CLI runbook. |
| **06** | [06_dbt_for_meteorological_telemetry_engineering.md](./reference_cards/06_dbt_for_meteorological_telemetry_engineering.md) | 444 | `dbt-duckdb` and `dbt-postgres` Lakehouse transformations (`staging` $\rightarrow$ `intermediate` $\rightarrow$ `marts`), incremental Hive Parquet models, Jinja macros for sentinel cleaning & sea-level pressure reduction, and WMO physical contract tests. |
| **07** | [07_wal_crash_recovery_sqlite_postgres_mysql.md](./reference_cards/07_wal_crash_recovery_sqlite_postgres_mysql.md) | 714 | Comparative crash recovery & write-ahead logging: SQLite Rollback Journal vs. WAL (`-wal`/`-shm`, 4 `wal_checkpoint` modes, `(busy, log, checkpointed)` return tuple, `journal_size_limit`, WAL Starvation & `BEGIN IMMEDIATE`), PostgreSQL `XLogRecord` / Full-Page Writes (`FPW`) / Checkpoint Smoothing, and MySQL InnoDB Redo Log + Doublewrite Buffer. |
| **08** | [08_postgresql_vacuum_vs_vacuum_full_and_bloat.md](./reference_cards/08_postgresql_vacuum_vs_vacuum_full_and_bloat.md) | 407 | MVCC dead tuple accumulation, `FSM`/`VM` maps, standard concurrent `VACUUM` (`ShareUpdateExclusiveLock`) vs. blocking `VACUUM FULL` (`AccessExclusiveLock`), zero-downtime `pg_repack`, and per-table autovacuum tuning. |
| **09** | [09_acid_transactions_and_two_terminal_lock_debugging.md](./reference_cards/09_acid_transactions_and_two_terminal_lock_debugging.md) | 481 | Four interactive Two-Terminal concurrency labs: Snapshot Isolation, Row-Level Lock Contention (`FOR UPDATE`), Circular Deadlock Detection, `Read Committed` vs. `Repeatable Read`, and emergency `pg_blocking_pids()` lock termination. |
| **10** | [10_query_execution_plan_forensics_and_explain.md](./reference_cards/10_query_execution_plan_forensics_and_explain.md) | 764 | PostgreSQL planner cost formulas (`seq_page_cost`, `random_page_cost`, `cpu_tuple_cost`), `Seq Scan` vs. `Bitmap Heap Scan` vs. `Index Only Scan`, `Nested Loop` vs. `Hash Join` vs. `Merge Join`, `external merge Disk:` spills, and the **7 Deadly Sins of Execution Plans**. |
| **11** | [11_python_database_drivers_for_weather_engineers.md](./reference_cards/11_python_database_drivers_for_weather_engineers.md) | 727 | Deep-dive Python driver internals: **PEP 249 (`DB-API 2.0`)** object/exception hierarchy, `paramstyle` binding vs. `f-strings`, **`autocommit` vs. `sqlite3` `isolation_level` quirks**, **why `with sqlite3.connect() as conn:` does NOT close the connection** (`contextlib.closing` fix), **stdlib `sqlite3` vs. `APSW`** (`wal_hook`, nested savepoints, hot backup), **`psycopg` v3 vs. `psycopg2`** (server-side binding, pipeline `executemany`, binary `COPY`, Named Server-Side Cursors), **RFC 9562 `UUIDv7` generation & `16B` binary binding**, DuckDB Arrow Replacement Scans, `GeoPandas` (`read_postgis`), and `PyMongo` replica-set topology. |
| **12** | [12_dbeaver_and_mongodb_compass_gui_workflows.md](./reference_cards/12_dbeaver_and_mongodb_compass_gui_workflows.md) | 105 | Visual GUI workflows: DBeaver Spatial GIS Leaflet Map viewer for PostGIS `GEOGRAPHY`, ER diagrams, visual `EXPLAIN` (`Ctrl+Shift+E`), and MongoDB Compass visual aggregation pipeline builder. |
| **13** | [13_database_observability_prometheus_grafana_and_alerts.md](./reference_cards/13_database_observability_prometheus_grafana_and_alerts.md) | 167 | Golden observability signals for weather databases, `postgres_exporter` + `mongodb_exporter` + Prometheus + Grafana setup, and custom SQL monitors for silent weather stations and late NWP model runs. |
| **14** | [14_mysql_and_mariadb_innodb_complete_engineering_guide.md](./reference_cards/14_mysql_and_mariadb_innodb_complete_engineering_guide.md) | 826 | Dedicated MySQL 8.0/8.4 & MariaDB 10.11+ production engineering guide: where MySQL beats PostgreSQL (in-place heartbeat `UPDATE`s, Clustered PK range scans), Pluggable Engines (`InnoDB`, `MyRocks`, `Aria`, `ColumnStore`), 16 KB page anatomy, PK byte math (`UUID_TO_BIN`), Buffer Pool midpoint LRU & Change Buffer, Undo Log MVCC (`History List Length`), Gap & Next-Key Locks, 4-engine SQL/`JOIN` dialect (`ON DUPLICATE KEY UPDATE`, `LATERAL`, `JSON_TABLE`, `ST_Distance_Sphere`), **Dual-Log (`Redo` + `binlog`) `2PC`, 3-Thread `Relay Log` & `WRITESET` Parallel Replicas, 4-Pattern Failover (`AFTER_SYNC` / `InnoDB Cluster Paxos` / `ProxySQL`), 3-Engine PG vs. MySQL vs. MongoDB HA Matrix**, 32 GB `my.cnf`, and Top 10 DBA forensic queries. |

---

## 4. Turnkey Docker Compose Environments (`docker/`)

| File | Description |
| :--- | :--- |
| [docker/docker-compose.ha-replicaset.yml](./docker/docker-compose.ha-replicaset.yml) | **Stack 1 (Days 2–4 HA Lab):** Spins up `postgis/postgis:16-3.4` (`weather-pg-primary`) + a **3-Node MongoDB 7.0 Replica Set** (`mongo-node1`, `mongo-node2`, `mongo-node3`) for live primary failover testing. |
| [docker/docker-compose.polyglot-lakehouse.yml](./docker/docker-compose.polyglot-lakehouse.yml) | **Stack 2 (Day 5 Enterprise Polyglot Capstone):** Spins up **Eclipse Mosquitto MQTT Broker** (`1883`) + **Redpanda Kafka** (`9092`) + **PostgreSQL 16 / PostGIS 3.4** (`5432`) + **MongoDB 7.0** (`27017`) + **MinIO S3 Object Storage** (`9000`/`9001`) + **Adminer** (`8080`). |
| [docker/docker_lab_guide.md](./docker/docker_lab_guide.md) | Step-by-step launch commands, seed instructions, and Chaos Engineering live Primary crash & automatic election lab. |

---

## 5. Quick-Start Lab Execution Commands (Days 1–5)

### Day 0: Clone Repository, Launch Web Portal & Run Verification
```bash
# 0. Clone the bootcamp repository from GitHub
git clone https://github.com/abdelouahabb/db-bootcamp.git
cd db-bootcamp

# 1. Launch the Interactive Web Command Center & Built-In Coursebook Reader (http://127.0.0.1:8088/bootcamp_portal.html)
python3 start_bootcamp.py

# 2. Run the automated 89-check verification suite across all 5 days
./verify_bootcamp.sh
```

### Day 1: SQLite Operational & 250k-Row Telemetry Databases
```bash
cd "day1"

# 1. Inspect pre-built WMO operational database (or rebuild from weather_ops_seed.sql)
sqlite3 -header -box weather_ops.db < weather_ops_seed.sql
sqlite3 -header -box weather_ops.db

# 2. Generate or inspect the 250,000-row AWS telemetry database (with -999.0 sentinels & blackouts)
python3 generate_weather_db.py
sqlite3 -header -box weather_telemetry.db
```

### Day 2: PostgreSQL 16 Storage Internals, Tuple Tetris & Two-Terminal ACID Lab
```bash
cd "day2"

# 1. Load multi-schema operational dataset (18,000+ synoptic observations & 9,000+ NWP forecasts)
createdb weather_ops
psql -d weather_ops -f weather_ops_pg.sql

# 2. Run the 8KB Page Forensics, Tuple Tetris Byte-Alignment & EXPLAIN (ANALYZE, BUFFERS) Lab
psql -d weather_ops -f day2_pageinspect_and_storage_lab.sql

# 3. Follow the Two-Terminal Concurrency, Lock Contention & Deadlock Lab
less day2_two_terminal_acid_lab.sql
```

### Day 3: PostgreSQL Partitioning, BRIN vs. B-Tree & PostGIS 5M-Row Benchmark
```bash
cd "day3"

# 1. Load monthly range partitions, BRIN/Partial/Covering/GIN indexes & Materialized View
psql -d weather_ops -f day3_weather_advanced_pg.sql

# 2. Run the 5,000,000-row PostGIS & BRIN vs. B-Tree physical benchmark
psql -d postgres -f day3_postgis_5m_benchmark.sql
```

### Day 4: MongoDB 7 Polymorphic Stations, Radiosondes, `2dsphere` & 50k Benchmark
```bash
cd "day4"

# 1. Load $jsonSchema stations, upper-air radiosonde soundings & Native Time-Series collection
mongosh weather_nosql day4_weather_ops_mongo.js

# 2. Load 2dsphere storm warning polygons, ESR compound indexes & isobaric aggregations
mongosh weather_nosql day4_weather_ops_mongo_advanced.js

# 3. Run the 50,000-document polymorphic sensor ingestion, Bucket Pattern & $unwind fault lab
mongosh weather_nosql day4_mongo_50k_polymorphic_benchmark.js
```

### Day 5: DuckDB Vectorized OLAP, 10M-Row Parquet Lake, 4D NetCDF & Polyglot Streaming Capstone
```bash
cd "day5"

# 1. Generate 10,000,000-row Hive-partitioned Parquet lake & 4D CF-1.8 NetCDF4 NWP grid
python3 seed_olap_data.py

# 2. Run standalone Parquet, Small-Files Compaction & Satellite Int16 Quantization benchmarks
python3 parquet_vs_csv_benchmark.py
python3 compact_small_parquet_files.py
python3 satellite_cog_int16_quantization.py

# 3. Launch the Polyglot Lakehouse Docker Stack (MQTT + PostGIS + MongoDB + MinIO S3)
docker compose -f ../docker/docker-compose.polyglot-lakehouse.yml up -d

# 4. Run the Polyglot Stream Router, Edge MQTT Simulator, Cold Tier Compactor & FastAPI Gateway
python3 stream_router.py &
python3 simulate_edge_sensors.py &
python3 compact_hot_to_cold.py
uvicorn serving_api:app --host 0.0.0.0 --port 8000
```
