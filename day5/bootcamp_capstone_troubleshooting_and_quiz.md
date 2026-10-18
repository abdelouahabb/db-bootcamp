> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [⬅️ Day 5 (Part 1): Analytical OLAP & DuckDB](day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | [📘 Day 5 (Part 2): Polyglot Lakehouse & Capstone](day5_part2_enterprise_polyglot_lakehouse_and_capstone_coursebook.md) | [📚 Reference Cards](../reference_cards/README.md)

# 5-Day Bootcamp Final Assessment Quiz & 15 Real-World Weather Database Troubleshooting Scenarios

**Target Audience:** Weather Forecast & Meteorological Data Engineers  
**Purpose:** Production incident diagnostics reference and final certification self-assessment

> [!TIP]
> **Operational Incident Runbook:**  
> Part 1 catalogs 15 high-frequency production failure modes across SQLite, PostgreSQL/PostGIS, MongoDB, Apache Parquet, DuckDB, and Ceph S3 object storage, pairing each symptom directly with its physical root cause and exact SQL, MQL, or Python remediation command.

---

## Part 1: 15 Real-World Meteorological Troubleshooting Scenarios ("What Went Wrong?")

Each operational scenario below details the observed production symptom, the underlying database storage or query engine root cause, and the exact remediation pattern:

### Scenario 1: The `-1,648 mm` Monthly Rainfall Anomaly (Day 1 — SQLite / SQL Basics)
- **Symptom:** A forecaster runs `SELECT station_id, AVG(precip_1h_mm) FROM observations GROUP BY station_id;` on raw WMO data and gets `-1665.2 mm` for Constantine (`60419`).
- **Diagnostic Question:** Why did this happen, and what are two ways (one in `SELECT`, one via `UPDATE`) to fix it?
- **Root Cause & Fix:** Legacy WMO/Fortran loggers write `-9999.0` (or `-999.0`) for missing rain gauge readings. SQL treats `-9999.0` as a valid number unless converted to `NULL` (which `AVG()` ignores).
  - **Fix 1 (In Query):** `AVG(NULLIF(precip_1h_mm, -9999.0))`
  - **Fix 2 (Permanent):** `UPDATE observations SET precip_1h_mm = NULL WHERE precip_1h_mm = -9999.0;`

### Scenario 2: The Silent 3VL `NOT IN` Trap on Faulty Sensors (Day 1 — Three-Valued Logic & Sentinels)
- **Symptom:** An engineer sanitizes `-9999.0` sentinels into `NULL` inside a temporary table `flagged_stations(station_id INT)`. One row in `flagged_stations` accidentally has `station_id = NULL`. When they run:
  ```sql
  SELECT * FROM stations WHERE station_id NOT IN (SELECT station_id FROM flagged_stations);
  ```
  The query returns **0 rows**, wiping out the entire national station map!
- **Diagnostic Question:** Why did a single `NULL` inside `NOT IN (...)` cause 0 rows to return, and what SQL operator is immune to this 3VL trap?
- **Root Cause & Fix:** Under SQL **Three-Valued Logic (3VL)**, `x NOT IN (60390, NULL)` expands to `x <> 60390 AND x <> NULL`. Since `x <> NULL` evaluates to `UNKNOWN`, and `TRUE AND UNKNOWN` is `UNKNOWN`, the `WHERE` clause rejects every single row!
  - **Fix:** Use `NOT EXISTS` (which uses two-valued boolean existence checks) or filter `WHERE station_id IS NOT NULL` inside the subquery.

### Scenario 3: The Vanishing Silent Weather Station & Cross-Engine `JOIN` Trap (Day 1 — `3NF` & `JOIN` Compatibility)
- **Symptom:** Because `stations` (`7` rows) and `observations` (`36` rows) are normalized into **Third Normal Form (`3NF`)** to prevent insertion/update/deletion anomalies, an engineer queries all stations and their valid observation counts using:
  ```sql
  SELECT s.station_id, COUNT(o.obs_id)
  FROM stations s
  LEFT JOIN observations o ON s.station_id = o.station_id
  WHERE o.qc_flag = 'VALID'
  GROUP BY s.station_id;
  ```
  Station `60402` (`Bejaia`, which has `0` observations) completely disappears! Worse, when they try `FULL OUTER JOIN` to reconcile `forecasts` and `weather_alerts` on an edge SQLite `< 3.39` datalogger or a MySQL `8.0` server, the query crashes with a syntax error!
- **Diagnostic Question:** Why did `WHERE o.qc_flag = 'VALID'` turn the `LEFT JOIN` into an `INNER JOIN`, and how do you write a portable `FULL OUTER JOIN` across SQLite `< 3.39` and MySQL `8.0/8.4`?
- **Root Cause & Fix:**
  1. For a station with `0` observations, all `o.*` columns after `LEFT JOIN` are `NULL`. Filtering `WHERE o.qc_flag = 'VALID'` evaluates to `UNKNOWN` and eliminates the preserved row! Move the filter into the `ON` clause: `LEFT JOIN observations o ON s.station_id = o.station_id AND o.qc_flag = 'VALID'`.
  2. Neither **SQLite `< 3.39.0`** nor **MySQL `8.0/8.4`** supports native `FULL OUTER JOIN`. Emulate it portably using `A LEFT JOIN B UNION ALL B LEFT JOIN A WHERE A.id IS NULL` (see [Day 1 Master Coursebook Section 6.2](../day1/day1_master_coursebook.md#62-the-complete-taxonomy-of-sql-joins--sqlite-compatibility-matrix) and [Reference Card 14 Section 7.1](../reference_cards/14_mysql_and_mariadb_innodb_complete_engineering_guide.md#71-mysql-80--84-join-capabilities--4-engine-compatibility-matrix)).

### Scenario 4: The 24 GB "Tuple Tetris" Alignment Tax (Day 2 — PostgreSQL Physical Byte Alignment)
- **Symptom:** A database architect designs a 1-billion-row telemetry table with columns ordered as:
  `(flag1 BOOLEAN, obs_time TIMESTAMPTZ, flag2 BOOLEAN, station_uuid UUID, flag3 BOOLEAN, pressure_pa BIGINT)`.
  Even before adding indexes, the table consumes **21 GB more disk space** than calculated from the raw column type sizes!
- **Diagnostic Question:** Why did alternating 1-byte `BOOLEAN` columns with 8-byte/16-byte columns waste 21 bytes per row, and how should the columns be ordered?
- **Root Cause & Fix:** 64-bit CPUs require 8-byte types (`TIMESTAMPTZ`, `BIGINT`) to sit at memory offsets divisible by 8. Placing a 1-byte `BOOLEAN` before an 8-byte column forces PostgreSQL to insert **7 bytes of zero-padding** after each boolean ($3 \times 7 = 21\text{ wasted bytes/row} = 21\text{ GB}$ across 1B rows!).
  - **Fix ("Tuple Tetris" Rule):** Order columns from largest alignment requirement to smallest: `(station_uuid UUID, obs_time TIMESTAMPTZ, pressure_pa BIGINT, flag1 BOOLEAN, flag2 BOOLEAN, flag3 BOOLEAN)`.

### Scenario 5: The Bloated Synoptic Table After QC Scripts (Day 2 — PostgreSQL Heap MVCC vs. MySQL InnoDB Undo MVCC)
- **Symptom:** Your `synoptic.observations` table has 40 million rows (~4 GB). A quality-control script runs 5 times a day updating `qc_flag` on millions of rows. Within two weeks, the table size on disk balloons to **28 GB** and queries slow down, even though `COUNT(*)` is still 40 million!
- **Diagnostic Question:** Why did `UPDATE` cause the PostgreSQL table to grow 7x on disk, what `ALTER TABLE` setting prevents this, and how does MySQL InnoDB handle high-frequency in-place `UPDATE`s differently?
- **Root Cause & Fix:** Under PostgreSQL **Heap MVCC**, every `UPDATE` marks the old tuple's `xmax` (creating a **Dead Tuple**) and appends a brand-new tuple version at a new `ctid`. Default `autovacuum_vacuum_scale_factor = 0.20` waits until 20% (8 million rows!) change before vacuuming.
  - **PostgreSQL Fix:** Run `VACUUM (ANALYZE) synoptic.observations;` and lower the table's scale factor: `ALTER TABLE synoptic.observations SET (autovacuum_vacuum_scale_factor = 0.01);`.
  - **MySQL InnoDB Comparison:** By contrast, MySQL InnoDB updates non-indexed columns **in place** inside its `16 KB` Clustered PK leaf page and writes the old image to the **Undo Log** (`History List Length`), making InnoDB ideal for 5-second `station_live_status` heartbeat tables (`ON DUPLICATE KEY UPDATE` — see [Reference Card 14](../reference_cards/14_mysql_and_mariadb_innodb_complete_engineering_guide.md)).

### Scenario 6: The 00Z ECMWF Ingestion I/O Freeze (Day 2 — PostgreSQL WAL & Checkpoints)
- **Symptom:** Every night at `02:00 UTC` when your pipeline loads 5 million ECMWF forecast rows, PostgreSQL logs `checkpoints are occurring too frequently (18 seconds apart)` and forecaster dashboards stall.
- **Diagnostic Question:** Which 4 `postgresql.conf` parameters should you tune, and how should the Python script load the rows?
- **Root Cause & Fix:** Default `max_wal_size = 1GB` is too small for bulk NWP loads. Set `max_wal_size = '16GB'`, `checkpoint_timeout = '15min'`, `checkpoint_completion_target = 0.9`, and `wal_compression = lz4`. In Python, use PostgreSQL's streaming `COPY` protocol instead of individual `INSERT` statements.

### Scenario 7: Deleting 2024 Observations Locks Up Disk I/O (Day 3 — Partitioning & BRIN)
- **Symptom:** To free disk space on the 1st of each month, an engineer runs `DELETE FROM synoptic.observations WHERE obs_time < NOW() - INTERVAL '1 year';`. The command runs for 45 minutes, generates 15 GB of WAL, and **does not shrink the file size on disk at all**!
- **Diagnostic Question:** Why didn't `DELETE` free OS disk space, and how should time-series retention be architected in PostgreSQL?
- **Root Cause & Fix:** `DELETE` only marks tuples as dead (`xmax` set) inside existing 8KB heap pages; it does not return file blocks to the OS. Instead, use **Declarative Range Partitioning (`PARTITION BY RANGE (obs_time)`)** with monthly child tables, detach old months via `ALTER TABLE ... DETACH PARTITION obs_y2025m06 CONCURRENTLY;`, archive to Parquet, and run `DROP TABLE obs_y2025m06;` (which frees 100% of disk space in milliseconds with zero dead tuples).

### Scenario 8: Station in the Indian Ocean! (Days 3–4 — PostGIS & MongoDB GeoJSON)
- **Symptom:** A weather engineer inserts Algiers (`Lat 36.6910°N, Lon 3.2154°E`) into MongoDB as `location: { type: "Point", coordinates: [36.6910, 3.2154] }` (or in PostGIS as `ST_MakePoint(36.6910, 3.2154)`). When they search for stations near Algiers, `0` results come back!
- **Diagnostic Question:** Why did the station end up off the coast of Somalia in the Indian Ocean?
- **Root Cause & Fix:** Both **GeoJSON (MongoDB)** and **PostGIS (`ST_MakePoint`)** strictly require **`[X, Y] = [longitude, latitude]`** order: `[3.2154, 36.6910]`!

### Scenario 9: The False-Positive 500 hPa Jet Stream Alert (Day 4 — MongoDB `$elemMatch`)
- **Symptom:** Each document in `db.radiosonde_soundings` has an array `vertical_levels: [ { pressure_hpa: 1000, wind_speed_kt: ... }, ..., { pressure_hpa: 300, wind_speed_kt: 95 } ]`. An engineer runs:
  ```javascript
  db.radiosonde_soundings.find({
    "vertical_levels.pressure_hpa": 850,
    "vertical_levels.wind_speed_kt": { $gte: 80 }
  })
  ```
  It returns almost every balloon launch, even when the `850 hPa` wind was only `15 kt`!
- **Diagnostic Question:** Why did this happen, and how do you fix the query?
- **Root Cause & Fix:** Dot-notation conditions on an array match if *any* element has `pressure_hpa: 850` and *any other* element (such as `300 hPa`!) has `wind_speed_kt >= 80`. Use **`$elemMatch`** so both conditions must match the **same** array element: `vertical_levels: { $elemMatch: { pressure_hpa: 850, wind_speed_kt: { $gte: 80 } } }`.

### Scenario 10: The 100 MB Blocking Sort Error in MongoDB (Day 4 — Indexing & ESR Rule)
- **Symptom:** A query `db.radiosonde_soundings.find({ station_id: 60390, cape_j_kg: { $gte: 500 } }).sort({ launch_time: -1 })` is slow and shows a `SORT` stage in `.explain("executionStats")`, even though an index exists on `{ station_id: 1, cape_j_kg: 1, launch_time: -1 }`.
- **Diagnostic Question:** Why couldn't MongoDB use the index to avoid sorting in memory, and how should the index keys be reordered?
- **Root Cause & Fix:** Because the range field (`cape_j_kg`) was placed *before* the sort field (`launch_time`)! Follow the **ESR Rule (Equality $\rightarrow$ Sort $\rightarrow$ Range)**: `{ station_id: 1, launch_time: -1, cape_j_kg: 1 }`.

### Scenario 11: The 10-Shard MongoDB Cluster Where Only 1 Shard Works (Day 4 — Sharding)
- **Symptom:** To scale writes for 5,000 automated weather stations, an administrator deploys a 10-shard MongoDB cluster and shards the `observations` collection on `{ obs_time: 1 }`. CPU utilization on Shard 10 hits 100%, while Shards 1–9 sit at 0% CPU during live ingestion!
- **Diagnostic Question:** Why did `{ obs_time: 1 }` create a hotspot on Shard 10, and what is the proper Shard Key?
- **Root Cause & Fix:** `obs_time` is monotonically increasing, so 100% of live observations fall into the newest `maxKey` chunk on a single shard. Prefix the shard key with a high-cardinality station identifier: **`{ "station_meta.station_id": 1, obs_time: 1 }`**.

### Scenario 12: The 12 GB CSV Laptop Freeze (Day 5 — Columnar Parquet & DuckDB)
- **Symptom:** A climate scientist has a 12 GB CSV file (`synoptic_2020_2026.csv`) with 55 columns. Every morning their Python script runs `pd.read_csv('synoptic_2020_2026.csv')` just to calculate daily mean `temp_c` for 3 desert stations, crashing their 16 GB RAM laptop.
- **Diagnostic Question:** How should they convert this file and run the query in < 0.3 seconds using < 200 MB of RAM?
- **Root Cause & Fix:** Convert the row-oriented CSV into a column-oriented ZSTD-compressed **Apache Parquet** file using **DuckDB**: `COPY (SELECT * FROM read_csv_auto('synoptic_2020_2026.csv')) TO 'synoptic.parquet' (FORMAT PARQUET, COMPRESSION ZSTD);` and query `'synoptic.parquet'` directly in DuckDB (which uses Projection Pushdown to read only `station_id`, `obs_time`, and `temp_c`, plus Predicate Pushdown to skip irrelevant Row Groups).

### Scenario 13: The 450,000 Tiny Parquet Files Disaster (Day 5 — Hive Partitioning & Small Files Problem)
- **Symptom:** An engineer modifies the MQTT stream router to write a brand-new Parquet file every 10 seconds partitioned by `year/month/day/hour/minute`. Within 2 months, querying `read_parquet('lake/**/*.parquet')` in DuckDB takes **4 minutes** just to scan 2 GB of data!
- **Diagnostic Question:** Why did writing 10-second Parquet files ruin DuckDB's performance, and what is the target file size and compaction strategy?
- **Root Cause & Fix:** This is the **"Small Files Problem"**: opening 450,000 tiny 4 KB files spends 99% of wall-clock time on OS inode lookups / S3 HTTP `GET` handshakes and Thrift footer parsing rather than vectorized SIMD execution.
  - **Fix:** Partition strictly by coarse temporal boundaries (`year=YYYY/month=MM`) and run a scheduled compaction job to merge files into **128 MB – 512 MB** Parquet blocks with 100k–250k rows per Row Group.

### Scenario 14: The S3 / Ceph RGW `GRIB2` Cloud Bottleneck (Day 5 — Gridded Data: `GRIB2` vs. `NetCDF4` vs. `Zarr`)
- **Symptom:** A machine learning team stores 50 TB of global NWP model grids on an on-premises **Ceph RGW (S3)** cluster as monolithic `NetCDF4` (`.nc`) and `GRIB2` files. When 64 Dask/PyTorch workers try to slice a 30-year time-series for a single grid cell over Algiers, network throughput maxes out while CPU sits idle.
- **Diagnostic Question:** Why do monolithic `NetCDF4` / `GRIB2` files struggle on S3 object storage, and how should the 4D arrays be stored and chunked?
- **Root Cause & Fix:** `NetCDF4` (HDF5) requires multiple sequential pointer seeks across internal B-trees, and `GRIB2` is a sequential message stream optimized for 2D horizontal maps—forcing workers to pull entire multi-megabyte horizontal slices just to read 1 coordinate.
  - **Fix:** Convert the archive to **Cloud-Native `Zarr`** stored on Ceph RGW S3, where each 4D chunk is an independent S3 object (`s3://bucket/temp/0.1.4`), and re-chunk along the time dimension for time-series training (or use `.idx` byte-range index sidecars for operational GRIB2).

### Scenario 15: Remote Saharan Stations Exhausting PostgreSQL Connections (Day 5 — Edge MQTT & Polyglot Routing)
- **Symptom:** 1,200 remote solar-powered weather stations over 2G/satellite modems are configured to connect directly to the central PostgreSQL server (`port 5432`) every minute to run `INSERT INTO observations...`. Whenever a sandstorm causes intermittent packet loss, PostgreSQL hits `FATAL: sorry, too many clients already` and crashes!
- **Diagnostic Question:** Why is direct SQL over unstable field links an architectural antipattern, and how does the Day 5 Edge-to-Core pipeline solve it?
- **Root Cause & Fix:** Each direct PostgreSQL connection requires a heavy TCP + TLS + auth handshake and spawns an OS backend process that hangs in `idle in transaction` when a satellite link drops.
  - **Fix:** Buffer observations locally in **SQLite (`WAL` mode)** on the station logger, publish lightweight 2-byte-header **MQTT (`QoS 1`)** packets to an edge **Mosquitto / Kafka** broker, and use a central **Polyglot Stream Router** to batch-insert (`execute_values` / `COPY` / `bulk_write`) into PostgreSQL and MongoDB using a fixed connection pool.

---

## Part 2: 15-Question Multiple-Choice Final Certification Quiz

1. **In SQLite, which command must you run on every new connection to enforce Foreign Key constraints?**
   - A) `SET foreign_keys = TRUE;`
   - B) `PRAGMA foreign_keys = ON;` ✅
   - C) `ALTER DATABASE ENABLE FOREIGN KEYS;`

2. **Which file format stores data column-by-column with Row Group `min`/`max` statistics in its footer?**
   - A) CSV
   - B) Apache Parquet ✅
   - C) JSON Lines

3. **Why is DuckDB 20–50x faster than SQLite or PostgreSQL when calculating `AVG(temp_c)` over 50 million synoptic rows?**
   - A) DuckDB uses columnar storage and multi-core vectorized SIMD execution (processing 2,048-value vectors in AVX registers), reading only the `temp_c` column ✅
   - B) DuckDB skips ACID transactions
   - C) SQLite cannot store floating-point numbers

4. **In PostgreSQL physical storage, what does `ctid = (4, 12)` represent?**
   - A) CPU Core 4, Thread 12
   - B) Physical 8KB Heap Page 4, Tuple Slot 12 ✅
   - C) Schema 4, Table 12

5. **In PostgreSQL, which hidden tuple header field holds the Transaction ID that deleted or updated a row?**
   - A) `xmin`
   - B) `xmax` ✅
   - C) `cmin`

6. **How many bytes is the fixed PostgreSQL MVCC tuple header (`HeapTupleHeaderData`) before alignment padding and column data?**
   - A) 8 bytes
   - B) 23 bytes (padded to 24 bytes) ✅
   - C) 64 bytes

7. **Which PostgreSQL index type is 99% smaller than a B-Tree index for chronological append-only `obs_time` columns?**
   - A) `GIN`
   - B) `BRIN` (Block Range Index) ✅
   - C) `Hash`

8. **Which PostgreSQL Window Function computes the 3-hour barometric pressure tendency ($P_t - P_{t-3\text{h}}$) without a self-join?**
   - A) `RANK() OVER (...)`
   - B) `pressure_hpa - LAG(pressure_hpa, 3) OVER (PARTITION BY station_id ORDER BY obs_time)` ✅
   - C) `GROUP BY CUBE(pressure_hpa)`

9. **Why can't MySQL's 4-byte `TIMESTAMP` data type store historical 1955 WMO synoptic observations?**
   - A) MySQL `TIMESTAMP` only supports dates from `1970-01-01` to `2038-01-19` (32-bit Unix epoch limit) ✅
   - B) MySQL does not support hours and minutes
   - C) MySQL stores timestamps as plain strings

10. **In MongoDB, which update operator updates `max_observed_gust_kt` ONLY if the new wind gust is higher than the current stored value?**
    - A) `$inc`
    - B) `$max` ✅
    - C) `$push`

11. **In MongoDB Aggregation Pipelines, which stage flattens an array of upper-air radiosonde `vertical_levels` into individual documents per pressure level?**
    - A) `$unwind` ✅
    - B) `$lookup`
    - C) `$bucket`

12. **What is the correct key order according to MongoDB's ESR Compound Indexing Rule?**
    - A) Range $\rightarrow$ Sort $\rightarrow$ Equality
    - B) Equality $\rightarrow$ Sort $\rightarrow$ Range ✅
    - C) Sort $\rightarrow$ Equality $\rightarrow$ Range

13. **Which 4D meteorological gridded format breaks multidimensional arrays into independent chunk objects ideal for parallel reads/writes on S3 / Ceph RGW object storage?**
    - A) WMO `BUFR`
    - B) ASCII `SYNOP`
    - C) Cloud-Native `Zarr` ✅

14. **When streaming 50 million rows from PostgreSQL to Apache Parquet in Python, how do you prevent an `OutOfMemory` crash on the application server?**
    - A) Use `pandas.read_sql("SELECT * FROM observations")`
    - B) Use a PostgreSQL named **server-side cursor** (`itersize = 50000`) piped into `pyarrow.parquet.ParquetWriter.write_batch()` ✅
    - C) Convert all floats to strings first

15. **In the Day 5 Polyglot Streaming Architecture, why do we route `METAR_STANDARD` packets to PostgreSQL and `ULTRASONIC_3D` turbulence vectors to MongoDB?**
    - A) `METAR_STANDARD` has a strict relational schema joined with PostGIS stations, while `ULTRASONIC_3D` emits high-frequency polymorphic vector payloads suited for MongoDB native time-series bucketing ✅
    - B) PostgreSQL cannot store floating-point numbers
    - C) MongoDB does not support timestamps

---

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [⬅️ Day 5 (Part 1): Analytical OLAP & DuckDB](day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | [📘 Day 5 (Part 2): Polyglot Lakehouse & Capstone](day5_part2_enterprise_polyglot_lakehouse_and_capstone_coursebook.md) | [📚 Reference Cards](../reference_cards/README.md)
