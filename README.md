# 5-Day Master Bootcamp: Database, Columnar Lakehouse & Polyglot Telemetry Engineering for Weather Forecast Engineers

> [!IMPORTANT]
> **Architected & Synthesized with Gemini 4 Argon**  
> This repository is the unified, zero-duplication **"Best of Both"** master edition (`67 files`, `28,000+ lines` of coursebooks, SQL/MongoDB course walkthroughs, reference cards, interactive simulators, and runnable SQL/MQL/Python/Docker labs).
> - 🛠️ **Attendee Tooling & Day-0 Setup Guide (Windows, macOS & Linux):** Read **[ATTENDEE_SETUP_GUIDE.md](./ATTENDEE_SETUP_GUIDE.md)** for step-by-step instructions on reading coursebooks, setting up **DBeaver Community** & **MongoDB Compass**, and launching the Docker Compose database stacks.
> - 🌐 **Interactive Web Command Center, Built-In Coursebook Reader & Simulators:** Run `python3 start_bootcamp.py` (or open [bootcamp_portal.html](./bootcamp_portal.html)) to launch the **Built-In Dark-Mode Markdown/Code Reader**, **PostgreSQL Tuple Tetris 8-Byte Alignment Visualizer**, **`-9999.0` Hardware Sentinel & 3VL Simulator**, **Multi-Engine Scaling Calculator**, **Polyglot Architecture Map**, and **15-Question Live Certification Quiz** at `http://127.0.0.1:8088/bootcamp_portal.html`.
> - ✅ **1-Command Pre-Flight Verification:** Run [`./verify_bootcamp.sh`](./verify_bootcamp.sh) to execute automated integrity, SQLite seed, 250,000-row telemetry generation, Python AST compilation, and Docker Compose checks.

**Curriculum Scope:** 5 Intensive Modules / Days (Comprehensive Architecture Theory + Hands-On Production Labs)  
**Target Audience:** Meteorological Software Engineers, Weather Forecast Systems Administrators, & Environmental Data Scientists  
**Core Engine Progression:** `CSV & Hardware Sentinels` $\rightarrow$ `SQLite 3 (OLTP Foundations)` $\rightarrow$ `PostgreSQL 16 & PostGIS 3.4 (Storage Internals, Partitioning & Geodesy)` $\rightarrow$ `MongoDB 7.0 (BSON, Time-Series, 2dsphere & Sharding)` $\rightarrow$ `DuckDB, Apache Parquet, GRIB2/NetCDF4/Zarr, dbt, Ceph S3 & Polyglot Streaming Lakehouse`

---

## 1. Repository Architecture & Complete File Navigator (`67 Files`)

```text
alternative B/
├── README.md                                                      # Master Syllabus, File Navigator & Quick-Start Runbook
├── ATTENDEE_SETUP_GUIDE.md                                        # Attendee Tooling & Day-0 Setup Guide (Windows, macOS & Linux)
├── start_bootcamp.py                                              # Zero-Dependency HTTP Server & Browser Launcher (Port 8088)
├── bootcamp_portal.html                                           # Interactive Command Center, Built-In Reader, 3 Simulators & Quiz
├── verify_bootcamp.sh                                             # Automated Pre-Flight & Live SQL/Python/Docker Verification Suite
├── day1/                                                          # Day 1: SQL Foundations, Hardware Sentinels (-9999), 3VL & Window Functions (SQLite)
├── day2/                                                          # Day 2: PostgreSQL 8KB Internals, Tuple Tetris, MVCC, WAL, VACUUM & EXPLAIN
├── day3/                                                          # Day 3: Production PostgreSQL: Partitioning, BRIN, PostGIS Geodesy, Extensions & Patroni HA
├── day4/                                                          # Day 4: MongoDB: BSON/WiredTiger, Time-Series, 2dsphere Storm Polygons, Aggregations & Sharding
├── day5/                                                          # Day 5: Vectorized DuckDB, Parquet Lakehouse, GRIB2/NetCDF4/Zarr, Polyglot Streaming & Capstone
├── reference_cards/                                               # 13 Deep-Dive Engineering Reference Cards + 20-Symptom Diagnostic Index (README.md)
└── docker/                                                        # Turnkey Docker Compose Topologies (3-Node HA Replica Set & 6-Service Polyglot Lakehouse)
```

---

## 2. Day-by-Day Curriculum & Executable Labs

### Day 1: Advanced SQL Foundations, Telemetry Wrangling & Hardware Sentinels (`day1/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day1/day1_master_coursebook.md](./day1/day1_master_coursebook.md) | **Master Coursebook (963 lines)** | Declarative 8-step query execution order, Three-Valued Logic (`3VL`), `-9999.0` hardware sentinel hygiene (`NULLIF`, `CASE WHEN`), WMO `CHECK` constraints, multi-model NWP verification `JOIN`s (`ECMWF-HRES`, `GFS`, `AROME`), CTE pipelines, `WITH RECURSIVE` gap detection, and `LAG`/`AVG OVER` window functions. |
| [day1/weather_ops_seed_sql_course_walkthrough.md](./day1/weather_ops_seed_sql_course_walkthrough.md) | **SQL Course Walkthrough** | Complete line-by-line Markdown course explaining every pragma, DDL constraint, 3VL check guard, and planted sensor anomaly in `weather_ops_seed.sql`. |
| [day1/day1_sqlite_and_sql_cheatsheet.md](./day1/day1_sqlite_and_sql_cheatsheet.md) | **Cheatsheet (583 lines)** | Complete `sqlite3` CLI dot-commands (`.headers`, `.mode box`, `.timer on`, `~/.sqliterc`), 3VL truth tables, temporal bucketing, and window function recipes. |
| [day1/day1_hardware_sentinels_and_qc_guide.md](./day1/day1_hardware_sentinels_and_qc_guide.md) | **Deep-Dive Guide (393 lines)** | Physics of RS-485/Modbus/SDI-12 & Pt100 ADC open/short-circuit `-9999.0` sentinels, WMO Code 306 flags, 3VL mean/variance contamination math, and ELT QC architecture. |
| [day1/weather_ops_seed.sql](./day1/weather_ops_seed.sql) | **SQL Seed Script** | Builds `weather_ops.db` with WMO stations, synoptic observations (with `NULL` dropouts, `-9999.0` sentinels, and `68.5°C` spikes), NWP forecasts, and alerts. |
| [day1/weather_ops.db](./day1/weather_ops.db) | **SQLite Database** | Pre-built WMO operational SQLite database ready for immediate CLI or DBeaver inspection. |
| [day1/generate_weather_db.py](./day1/generate_weather_db.py) | **Python Generator** | Zero-dependency Python script synthesizing `weather_telemetry.db` (**250,000 rows** across 50 AWS stations in ~2 seconds). |
| [day1/weather_telemetry.db](./day1/weather_telemetry.db) | **SQLite Database (250k rows)** | Pre-generated 250,000-row AWS telemetry database with injected `-999.0` sentinels, frontal pressure drops, and `AWS-033` 6-hour communications blackout. |

---

### Day 2: PostgreSQL Storage Engine Internals, MVCC, WAL, `VACUUM` & Tuning (`day2/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day2/day2_master_coursebook.md](./day2/day2_master_coursebook.md) | **Master Coursebook (1,067 lines)** | Host NVMe storage topology (`pgdata` vs `pgwal`), `synoptic`/`nwp`/`alerts` schemas, `TIMESTAMPTZ` vs `TIMESTAMP`, `NUMERIC` vs `REAL`, 8 KB Heap Pages (`PageHeaderData`, `ItemIdData`, 23-byte `HeapTupleHeaderData`), CPU Byte-Alignment Padding ("Tuple Tetris" saving 8–16 bytes/row), TOAST, Dual-Caching (`shared_buffers` vs OS Page Cache), Checkpoint Smoothing, and `COPY` vs `INSERT`. |
| [day2/weather_ops_pg_sql_course_walkthrough.md](./day2/weather_ops_pg_sql_course_walkthrough.md) | **SQL Course Walkthrough** | Line-by-line Markdown course explaining `weather_ops_pg.sql`: multi-schema isolation, `TOAST` out-of-line compression, `GENERATED ALWAYS AS ... STORED`, `generate_series()` diurnal/synoptic wave math, and per-table autovacuum tuning. |
| [day2/day2_pageinspect_and_storage_lab_course_walkthrough.md](./day2/day2_pageinspect_and_storage_lab_course_walkthrough.md) | **SQL Course Walkthrough** | Line-by-line Markdown course explaining `day2_pageinspect_and_storage_lab.sql`: Tuple Tetris byte offsets, `pageinspect` (`page_header`, `heap_page_items`), MVCC `t_xmin`/`t_xmax`/`t_ctid` chains, `pgstattuple` `VACUUM` vs `VACUUM FULL`, and 1M-row `EXPLAIN (ANALYZE, BUFFERS)`. |
| [day2/day2_two_terminal_acid_lab_course_walkthrough.md](./day2/day2_two_terminal_acid_lab_course_walkthrough.md) | **SQL Course Walkthrough** | Line-by-line Markdown course explaining `day2_two_terminal_acid_lab.sql`: Snapshot Isolation, row-lock queues, `pg_blocking_pids()` & `pg_locks` forensics, `40P01` deadlocks, `READ COMMITTED` vs `REPEATABLE READ`, and emergency DBA session termination. |
| [day2/day2_postgres_tuning_and_internals_cheatsheet.md](./day2/day2_postgres_tuning_and_internals_cheatsheet.md) | **Cheatsheet (345 lines)** | 32 GB RAM `postgresql.conf` weather profile, `pg_hba.conf`, `psql` commands, 8 KB page layout, Tuple Tetris alignment rules, `pg_locks` diagnostics, and `EXPLAIN (ANALYZE, BUFFERS)` red flags. |
| [day2/day2_postgres_vs_mysql_mvcc_guide.md](./day2/day2_postgres_vs_mysql_mvcc_guide.md) | **Comparative Guide (309 lines)** | Head-to-head forensic comparison: PostgreSQL 8 KB Unclustered Heap (`ctid`, `t_xmin`/`t_xmax`, HOT updates, $O(1)$ rollback) vs. MySQL InnoDB 16 KB Clustered B+Tree (`DB_TRX_ID`, Undo Logs, Purge Lag, secondary index double-lookup penalty). |
| [day2/weather_ops_pg.sql](./day2/weather_ops_pg.sql) | **SQL Seed Script** | Multi-schema PostgreSQL seed script (`synoptic`, `nwp`, `alerts`) generating **18,000+ synoptic observations** and **9,000+ NWP model forecasts**. |
| [day2/day2_pageinspect_and_storage_lab.sql](./day2/day2_pageinspect_and_storage_lab.sql) | **SQL Forensics Lab** | Runnable lab proving Tuple Tetris byte savings (`pg_column_size`), `pageinspect` MVCC tuple version chains, `pgstattuple` bloat measurement, and 1,000,000-row `EXPLAIN (ANALYZE, BUFFERS)` row-store I/O amplification. |
| [day2/day2_two_terminal_acid_lab.sql](./day2/day2_two_terminal_acid_lab.sql) | **Two-Terminal ACID Lab (341 lines)** | Side-by-side `[TERM A]` vs. `[TERM B]` scripts for Snapshot Isolation, Row-Level Lock Contention (`FOR NO KEY UPDATE`), Circular Deadlock Detection (`40P01`), `READ COMMITTED` vs. `REPEATABLE READ`, and `pg_blocking_pids()` termination. |

---

### Day 3: Advanced Production PostgreSQL: Partitioning, BRIN, PostGIS Geodesy, Extensions & HA (`day3/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day3/day3_master_coursebook.md](./day3/day3_master_coursebook.md) | **Master Coursebook (969 lines)** | Declarative time-range partitioning (`PARTITION BY RANGE`), zero-bloat `DETACH PARTITION CONCURRENTLY`, Index Selection Matrix (B-Tree vs. `BRIN` `28 MB` vs `32 KB`, Partial, Covering `INCLUDE`, `GIN`), PostGIS Geodesy (`GEOGRAPHY(Point, 4326)` vs `GEOMETRY`, `ST_DWithin`, `ST_Distance`), meteorological window functions ($\Delta P_{3\text{h}}$), idempotent `UPSERT` (`IS DISTINCT FROM`), `JSONB`, and `REFRESH MATERIALIZED VIEW CONCURRENTLY`. |
| [day3/day3_weather_advanced_pg_sql_course_walkthrough.md](./day3/day3_weather_advanced_pg_sql_course_walkthrough.md) | **SQL Course Walkthrough** | Line-by-line Markdown course explaining `day3_weather_advanced_pg.sql`: `PARTITION BY RANGE`, `PRIMARY KEY` partition rules, `jsonb_build_object`, the 5 specialized indexes (`BRIN`, `BTREE`, Partial, Covering `INCLUDE`, `GIN`), concurrent materialized views, and PostGIS `GEOGRAPHY`. |
| [day3/day3_postgis_5m_benchmark_sql_course_walkthrough.md](./day3/day3_postgis_5m_benchmark_sql_course_walkthrough.md) | **SQL Course Walkthrough** | Line-by-line Markdown course explaining `day3_postgis_5m_benchmark.sql`: `\gexec`, WGS-84 Haversine great-circle spherical trigonometry, `GiST` spatial indexes, 5,000,000-row partitioned ingestion, `pg_inherits` catalog forensics, B-Tree vs BRIN size benchmarks, and `ST_DWithin` joins. |
| [day3/day3_postgres_advanced_cheatsheet.md](./day3/day3_postgres_advanced_cheatsheet.md) | **Cheatsheet (212 lines)** | Quick reference for declarative partitioning, B-Tree vs. BRIN vs. Partial vs. GIN index selection, PostGIS spatial functions, window frames, `UPSERT`, and `JSONB` operators. |
| [day3/day3_postgres_extensions_guide.md](./day3/day3_postgres_extensions_guide.md) | **Deep-Dive Guide (574 lines)** | Complete guide to 15 essential extensions: `PostGIS`, `postgis_raster`, `TimescaleDB`, `pg_partman`, `pg_cron`, `pg_stat_statements`, `auto_explain`, `pg_buffercache`, `pg_prewarm`, `pageinspect`, `pgstattuple`, `pg_visibility`, `pg_repack`, and `btree_gist`. |
| [day3/day3_postgres_ha_patroni_and_ops_guide.md](./day3/day3_postgres_ha_patroni_and_ops_guide.md) | **Deep-Dive Guide (787 lines)** | CAP & PACELC theorems in weather networks, Physical vs. Logical Replication, Split-Brain prevention, `Patroni` + 3-node `etcd` + `HAProxy` Docker blueprint, `patronictl` runbook, `PgBouncer` transaction pooling, RBAC security, and `pg_dump`/`pg_basebackup` PITR backups. |
| [day3/day3_weather_advanced_pg.sql](./day3/day3_weather_advanced_pg.sql) | **SQL Lab Script** | Monthly range partitions, BRIN/Partial/Covering/GIN indexes, `nwp.mv_daily_model_verification` materialized view, and PostGIS `GEOGRAPHY` proximity queries. |
| [day3/day3_postgis_5m_benchmark.sql](./day3/day3_postgis_5m_benchmark.sql) | **SQL Benchmark Script** | Seeds **5,000,000 partitioned telemetry rows** across 50 PostGIS stations and benchmarks B-Tree (`28 MB`) vs. BRIN (`32 KB`) index scans and geodesic `ST_DWithin` joins. |

---

### Day 4: MongoDB & Polymorphic Telemetry: BSON, Time-Series, `2dsphere`, Aggregations & Sharding (`day4/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day4/day4_master_coursebook.md](./day4/day4_master_coursebook.md) | **Master Coursebook (1,084 lines)** | Polymorphic station metadata (`$jsonSchema`), BSON binary encoding & WiredTiger storage internals, upper-air radiosonde soundings (`$elemMatch`), Native Time-Series collections (`system.buckets.*` + TTL) vs. the Manual Bucket Pattern, multi-stage Aggregation Pipelines (`$match` $\rightarrow$ `$unwind` $\rightarrow$ `$group`), `2dsphere` GeoJSON storm polygons (`$geoIntersects`, `$nearSphere`), the `ESR` Indexing Rule, 3-node Replica Sets, Tunable CAP/PACELC, GridFS, and Sharding (`mongos`). |
| [day4/day4_weather_ops_mongo_js_course_walkthrough.md](./day4/day4_weather_ops_mongo_js_course_walkthrough.md) | **MongoDB Course Walkthrough** | Line-by-line Markdown course explaining `day4_weather_ops_mongo.js`: `$jsonSchema` validation rules, polymorphic stations, bounded `vertical_levels` radiosonde arrays, native Time-Series collections (`system.buckets.*`), and CAP storm alerts. |
| [day4/day4_weather_ops_mongo_advanced_js_course_walkthrough.md](./day4/day4_weather_ops_mongo_advanced_js_course_walkthrough.md) | **MongoDB Course Walkthrough** | Line-by-line Markdown course explaining `day4_weather_ops_mongo_advanced.js`: `2dsphere` spherical indexes, GeoJSON closed-ring `Polygon` rules, `ESR` compound indexing (`idx_sonde_esr`), and isobaric `$unwind` aggregation stages. |
| [day4/day4_mongo_50k_polymorphic_benchmark_js_course_walkthrough.md](./day4/day4_mongo_50k_polymorphic_benchmark_js_course_walkthrough.md) | **MongoDB Course Walkthrough** | Line-by-line Markdown course explaining `day4_mongo_50k_polymorphic_benchmark.js`: 50,000-document batch ingestion (`{ ordered: false }`), 4 polymorphic instrument schemas, Manual Bucket Pattern atomic upserts, Road Safety & `$unwind` Fault Diagnostics, and WiredTiger vs Columnar `stats()`. |
| [day4/day4_mongodb_complete_cheatsheet.md](./day4/day4_mongodb_complete_cheatsheet.md) | **Cheatsheet (268 lines)** | `mongod.conf` weather tuning, SQL-to-MQL translator, Time-Series & Bucket Pattern syntax, Aggregation stages, `2dsphere` GeoJSON operators, and the `ESR` compound index rule. |
| [day4/day4_mongodb_architecture_ha_and_sharding_guide.md](./day4/day4_mongodb_architecture_ha_and_sharding_guide.md) | **Deep-Dive Guide (571 lines)** | WiredTiger cache & checkpoint mechanics, 3-node Replica Set deployment (`rs.initiate`, priority/tag sets), PyMongo `SecondaryPreferred` analytics routing, Tunable CAP (`w: "majority"` vs `w: 1`), GridFS vs. S3, and Sharded Cluster (`sh.*`) administration. |
| [day4/day4_weather_ops_mongo.js](./day4/day4_weather_ops_mongo.js) | **`mongosh` Seed Script** | Creates polymorphic `stations` (`$jsonSchema`), `radiosonde_soundings`, `synoptic_timeseries` (native Time-Series + 90-day TTL), and `cap_alerts`. |
| [day4/day4_weather_ops_mongo_advanced.js](./day4/day4_weather_ops_mongo_advanced.js) | **`mongosh` Lab Script** | Builds `2dsphere` spatial indexes, `storm_polygons` (convective & haboob warning polygons), `idx_sonde_esr` compound index, and isobaric aggregation views. |
| [day4/day4_mongo_50k_polymorphic_benchmark.js](./day4/day4_mongo_50k_polymorphic_benchmark.js) | **`mongosh` Benchmark** | Generates **50,000 polymorphic sensor documents** (`METAR_STANDARD`, `ULTRASONIC_3D`, `PRESENT_WEATHER_OPTICAL`, `ROAD_SURFACE_RADAR`), benchmarks Manual Bucket Pattern upserts, and runs `$unwind` hardware fault diagnostics. |

---

### Day 5: Vectorized OLAP (`DuckDB` & `Parquet`), Gridded Data (`GRIB2`/`NetCDF4`/`Zarr`) & Enterprise Polyglot Lakehouse Capstone (`day5/`)

| File | Type | Description |
| :--- | :--- | :--- |
| [day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md](./day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | **Master Coursebook Part 1 (956 lines)** | Volcano tuple-at-a-time vs. Vectorized SIMD (2,048-tuple vectors), Apache Parquet columnar layout & Hive partitioning, DuckDB in-process OLAP & zero-copy Arrow scans, 4D meteorological grids (`GRIB2`, `NetCDF4`, `Zarr`, WMO `BUFR`), and PostgreSQL-to-Parquet archival pipelines. |
| [day5/day5_part2_enterprise_polyglot_lakehouse_and_capstone_coursebook.md](./day5/day5_part2_enterprise_polyglot_lakehouse_and_capstone_coursebook.md) | **Master Coursebook Part 2 (952 lines)** | Grand Unified National Weather Center Architecture, Hot/Warm/Cold storage SLAs, Edge MQTT & Kafka streaming, Dynamic Polyglot Stream Router, Hot-to-Cold Parquet Compactor + $O(1)$ Partition Detach, Sub-10ms Unified FastAPI Serving Tier, and the **Dellys Cape Mediterranean Squall Line Capstone Disaster Lab**. |
| [day5/bootcamp_capstone_troubleshooting_and_quiz.md](./day5/bootcamp_capstone_troubleshooting_and_quiz.md) | **Capstone Assessment (193 lines)** | **15 Real-World Weather Database Troubleshooting Scenarios** ("What Went Wrong?") + **15 Multiple-Choice Final Certification Quiz Questions** with full answer keys. |
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

## 3. Deep-Dive Engineering Reference Cards Library (`reference_cards/`)

See **[reference_cards/README.md](./reference_cards/README.md)** for the **20-Scenario Symptom-to-Reference-Card Diagnostic Lookup Table**.

| # | Reference Card | Lines | Core Engineering Topics Covered |
| :-: | :--- | :---: | :--- |
| **01** | [01_apache_parquet_and_columnar_architecture.md](./reference_cards/01_apache_parquet_and_columnar_architecture.md) | 832 | Parquet binary anatomy (`PAR1`, Row Groups, Pages, Footer), Dictionary/RLE/Delta-of-Delta/Byte-Stream-Split encodings, Zone Maps, ZSTD compression, CSV vs. Parquet benchmarks, and Postgres-to-Parquet pipelines (`ConnectorX`, `DuckDB`, `pg_parquet`). |
| **02** | [02_duckdb_vectorized_olap_vs_sqlite.md](./reference_cards/02_duckdb_vectorized_olap_vs_sqlite.md) | 458 | DuckDB SIMD morsel-driven execution vs. SQLite row-store, zero-copy Apache Arrow bridge, `httpfs`/`spatial`/`sqlite`/`postgres` extensions, `ASOF JOIN`, and the 4-Engine Decision Matrix. |
| **03** | [03_hive_partitioning_and_lakehouse_compaction.md](./reference_cards/03_hive_partitioning_and_lakehouse_compaction.md) | 337 | Physical Hive directory layouts (`year=YYYY/month=MM`), directory pruning, the "Small Files Problem" I/O penalty, PyArrow/DuckDB compaction lab, and Apache Iceberg / Delta Lake metadata tables. |
| **04** | [04_meteorological_gridded_formats_cog_zarr_netcdf_grib_bufr.md](./reference_cards/04_meteorological_gridded_formats_cog_zarr_netcdf_grib_bufr.md) | 1,006 | Database BLOB anti-pattern vs. S3 Object Storage, Cloud-Optimized GeoTIFFs (`COG`), `Zarr`, `Kerchunk` (`GRIB2`/`NetCDF4` virtualization), `xarray` NWP extraction, WMO `BUFR` decoding (`pdbufr`), `STAC` + PostGIS catalog, `Int16` quantization (50–75% petabyte savings), and `TiTiler` HTTP byte-range serving. |
| **05** | [05_ceph_distributed_storage_and_proxmox_ve_architecture.md](./reference_cards/05_ceph_distributed_storage_and_proxmox_ve_architecture.md) | 950 | Sovereign on-premises Ceph (`MON`, `MGR`, `OSD`, `RGW`, `CRUSH`, `BlueStore` NVMe WAL/DB), Reed-Solomon Erasure Coding ($k=4, m=2$), Proxmox VE 5-node hyperconverged deployment (`pveceph`), HAProxy + Keepalived S3 load balancing, and `ceph` operational CLI runbook. |
| **06** | [06_dbt_for_meteorological_telemetry_engineering.md](./reference_cards/06_dbt_for_meteorological_telemetry_engineering.md) | 444 | `dbt-duckdb` and `dbt-postgres` Lakehouse transformations (`staging` $\rightarrow$ `intermediate` $\rightarrow$ `marts`), incremental Hive Parquet models, Jinja macros for sentinel cleaning & sea-level pressure reduction, and WMO physical contract tests. |
| **07** | [07_wal_crash_recovery_sqlite_postgres_mysql.md](./reference_cards/07_wal_crash_recovery_sqlite_postgres_mysql.md) | 707 | Comparative crash recovery & write-ahead logging: SQLite Rollback Journal vs. WAL (`-wal`/`-shm`), PostgreSQL `XLogRecord` / Full-Page Writes (`FPW`) / Checkpoint Smoothing, and MySQL InnoDB Redo Log + Doublewrite Buffer. |
| **08** | [08_postgresql_vacuum_vs_vacuum_full_and_bloat.md](./reference_cards/08_postgresql_vacuum_vs_vacuum_full_and_bloat.md) | 407 | MVCC dead tuple accumulation, `FSM`/`VM` maps, standard concurrent `VACUUM` (`ShareUpdateExclusiveLock`) vs. blocking `VACUUM FULL` (`AccessExclusiveLock`), zero-downtime `pg_repack`, and per-table autovacuum tuning. |
| **09** | [09_acid_transactions_and_two_terminal_lock_debugging.md](./reference_cards/09_acid_transactions_and_two_terminal_lock_debugging.md) | 481 | Four interactive Two-Terminal concurrency labs: Snapshot Isolation, Row-Level Lock Contention (`FOR UPDATE`), Circular Deadlock Detection, `Read Committed` vs. `Repeatable Read`, and emergency `pg_blocking_pids()` lock termination. |
| **10** | [10_query_execution_plan_forensics_and_explain.md](./reference_cards/10_query_execution_plan_forensics_and_explain.md) | 764 | PostgreSQL planner cost formulas (`seq_page_cost`, `random_page_cost`, `cpu_tuple_cost`), `Seq Scan` vs. `Bitmap Heap Scan` vs. `Index Only Scan`, `Nested Loop` vs. `Hash Join` vs. `Merge Join`, `external merge Disk:` spills, and the **7 Deadly Sins of Execution Plans**. |
| **11** | [11_python_database_drivers_for_weather_engineers.md](./reference_cards/11_python_database_drivers_for_weather_engineers.md) | 225 | Production Python integration patterns: `sqlite3`, `duckdb` zero-copy DataFrame queries, `psycopg` v3 connection pools & binary `COPY`, `GeoPandas` + PostGIS (`read_postgis`), and `PyMongo` bulk writes. |
| **12** | [12_dbeaver_and_mongodb_compass_gui_workflows.md](./reference_cards/12_dbeaver_and_mongodb_compass_gui_workflows.md) | 105 | Visual GUI workflows: DBeaver Spatial GIS Leaflet Map viewer for PostGIS `GEOGRAPHY`, ER diagrams, visual `EXPLAIN` (`Ctrl+Shift+E`), and MongoDB Compass visual aggregation pipeline builder. |
| **13** | [13_database_observability_prometheus_grafana_and_alerts.md](./reference_cards/13_database_observability_prometheus_grafana_and_alerts.md) | 167 | Golden observability signals for weather databases, `postgres_exporter` + `mongodb_exporter` + Prometheus + Grafana setup, and custom SQL monitors for silent weather stations and late NWP model runs. |

---

## 4. Turnkey Docker Compose Environments (`docker/`)

| File | Description |
| :--- | :--- |
| [docker/docker-compose.ha-replicaset.yml](./docker/docker-compose.ha-replicaset.yml) | **Stack 1 (Days 2–4 HA Lab):** Spins up `postgis/postgis:16-3.4` (`weather-pg-primary`) + a **3-Node MongoDB 7.0 Replica Set** (`mongo-node1`, `mongo-node2`, `mongo-node3`) for live primary failover testing. |
| [docker/docker-compose.polyglot-lakehouse.yml](./docker/docker-compose.polyglot-lakehouse.yml) | **Stack 2 (Day 5 Enterprise Polyglot Capstone):** Spins up **Eclipse Mosquitto MQTT Broker** (`1883`) + **Redpanda Kafka** (`9092`) + **PostgreSQL 16 / PostGIS 3.4** (`5432`) + **MongoDB 7.0** (`27017`) + **MinIO S3 Object Storage** (`9000`/`9001`) + **Adminer** (`8080`). |
| [docker/docker_lab_guide.md](./docker/docker_lab_guide.md) | Step-by-step launch commands, seed instructions, and Chaos Engineering live Primary crash & automatic election lab. |

---

## 5. Quick-Start Lab Execution Commands (Days 1–5)

### Day 0: Web Portal Launcher & Pre-Bootcamp Verification
```bash
# 1. Launch the Interactive Web Command Center & Built-In Coursebook Reader (http://127.0.0.1:8088/bootcamp_portal.html)
python3 start_bootcamp.py

# 2. Run the automated 65+ check verification suite across all 5 days
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
