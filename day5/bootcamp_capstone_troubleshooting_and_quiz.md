> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [⬅️ Day 5 (Part 1): Analytical OLAP & DuckDB](day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | [📘 Day 5 (Part 2): Polyglot Lakehouse & Capstone](day5_part2_enterprise_polyglot_lakehouse_and_capstone_coursebook.md) | [📚 Reference Cards](../reference_cards/README.md)

# 5-Day Bootcamp Final Assessment Quiz & 15 Real-World Weather Database Troubleshooting Scenarios

**Target Audience:** Weather Forecast & Meteorological Data Engineers  
**Purpose:** End-of-day knowledge checks, group discussions, and final certification assessment (with full Instructor Answer Key)

> [!TIP]
> **Instructor Live Demo Tip (War-Room Incident Drill):**  
> Split the class into 3 "Meteorological Operations Teams" for the last 45 minutes of Day 5. Assign 5 scenarios from Part 1 to each team and give them 10 minutes to diagnose the root cause and write the exact SQL, MQL, or DuckDB remediation command on the whiteboard!

---

## Part 1: 15 Real-World Meteorological Troubleshooting Scenarios ("What Went Wrong?")

Present these 15 operational scenarios to the weather engineers and ask them to diagnose the root cause and engineer the fix:

### Scenario 1: The `-1,648 mm` Monthly Rainfall Anomaly (Day 1 — SQLite / SQL Basics)
- **Symptom:** A forecaster runs `SELECT station_id, AVG(precip_1h_mm) FROM observations GROUP BY station_id;` on raw WMO data and gets `-1665.2 mm` for Constantine (`60419`).
- **Question:** Why did this happen, and what are two ways (one in `SELECT`, one via `UPDATE`) to fix it?
- <details><summary><strong>Answer</strong></summary>Legacy WMO/Fortran loggers write <code>-9999.0</code> (or <code>-999.0</code>) for missing rain gauge readings. SQL treats <code>-9999.0</code> as a valid number unless converted to <code>NULL</code> (which <code>AVG()</code> ignores).<br><strong>Fix 1 (In Query):</strong> <code>AVG(NULLIF(precip_1h_mm, -9999.0))</code><br><strong>Fix 2 (Permanent):</strong> <code>UPDATE observations SET precip_1h_mm = NULL WHERE precip_1h_mm = -9999.0;</code></details>

### Scenario 2: The Silent 3VL `NOT IN` Trap on Faulty Sensors (Day 1 — Three-Valued Logic & Sentinels)
- **Symptom:** An engineer sanitizes `-9999.0` sentinels into `NULL` inside a temporary table `flagged_stations(station_id INT)`. One row in `flagged_stations` accidentally has `station_id = NULL`. When they run:
  ```sql
  SELECT * FROM stations WHERE station_id NOT IN (SELECT station_id FROM flagged_stations);
  ```
  The query returns **0 rows**, wiping out the entire national station map!
- **Question:** Why did a single `NULL` inside `NOT IN (...)` cause 0 rows to return, and what SQL operator is immune to this 3VL trap?
- <details><summary><strong>Answer</strong></summary>Under SQL <strong>Three-Valued Logic (3VL)</strong>, <code>x NOT IN (60390, NULL)</code> expands to <code>x &lt;&gt; 60390 AND x &lt;&gt; NULL</code>. Since <code>x &lt;&gt; NULL</code> evaluates to <code>UNKNOWN</code>, and <code>TRUE AND UNKNOWN</code> is <code>UNKNOWN</code>, the <code>WHERE</code> clause rejects every single row!<br><strong>Fix:</strong> Use <code>NOT EXISTS</code> (which uses two-valued boolean existence checks) or filter <code>WHERE station_id IS NOT NULL</code> inside the subquery.</details>

### Scenario 3: The Vanishing Silent Weather Station (Day 1 — `JOIN`s)
- **Symptom:** An engineer wants a list of all stations and their observation counts, including stations under maintenance (`0` observations). They write:
  ```sql
  SELECT s.station_id, COUNT(o.obs_id)
  FROM stations s
  LEFT JOIN observations o ON s.station_id = o.station_id
  WHERE o.qc_flag = 'VALID'
  GROUP BY s.station_id;
  ```
  Station `60402` (`Bejaia`, which has `0` observations) completely disappears from the output!
- **Question:** Why did `WHERE o.qc_flag = 'VALID'` turn the `LEFT JOIN` into an `INNER JOIN`, and how do you fix it?
- <details><summary><strong>Answer</strong></summary>For a station with <code>0</code> observations, all <code>o.*</code> columns after the <code>LEFT JOIN</code> are <code>NULL</code>. Filtering <code>WHERE o.qc_flag = 'VALID'</code> eliminates those <code>NULL</code> rows! Move the condition into the <code>ON</code> clause: <code>LEFT JOIN observations o ON s.station_id = o.station_id AND o.qc_flag = 'VALID'</code>.</details>

### Scenario 4: The 24 GB "Tuple Tetris" Alignment Tax (Day 2 — PostgreSQL Physical Byte Alignment)
- **Symptom:** A database architect designs a 1-billion-row telemetry table with columns ordered as:
  `(flag1 BOOLEAN, obs_time TIMESTAMPTZ, flag2 BOOLEAN, station_uuid UUID, flag3 BOOLEAN, pressure_pa BIGINT)`.
  Even before adding indexes, the table consumes **21 GB more disk space** than calculated from the raw column type sizes!
- **Question:** Why did alternating 1-byte `BOOLEAN` columns with 8-byte/16-byte columns waste 21 bytes per row, and how should the columns be ordered?
- <details><summary><strong>Answer</strong></summary>64-bit CPUs require 8-byte types (<code>TIMESTAMPTZ</code>, <code>BIGINT</code>) to sit at memory offsets divisible by 8. Placing a 1-byte <code>BOOLEAN</code> before an 8-byte column forces PostgreSQL to insert <strong>7 bytes of zero-padding</strong> after each boolean (3 &times; 7 = 21 wasted bytes/row = 21 GB across 1B rows!).<br><strong>Fix ("Tuple Tetris" Rule):</strong> Order columns from largest alignment requirement to smallest: <code>(station_uuid UUID, obs_time TIMESTAMPTZ, pressure_pa BIGINT, flag1 BOOLEAN, flag2 BOOLEAN, flag3 BOOLEAN)</code>.</details>

### Scenario 5: The Bloated Synoptic Table After QC Scripts (Day 2 — PostgreSQL MVCC & Vacuum)
- **Symptom:** Your `synoptic.observations` table has 40 million rows (~4 GB). A quality-control script runs 5 times a day updating `qc_flag` on millions of rows. Within two weeks, the table size on disk balloons to **28 GB** and queries slow down, even though `COUNT(*)` is still 40 million!
- **Question:** Why did `UPDATE` cause the table to grow 7x on disk, and what `ALTER TABLE` setting prevents this?
- <details><summary><strong>Answer</strong></summary>Under PostgreSQL <strong>MVCC</strong>, every <code>UPDATE</code> marks the old tuple's <code>xmax</code> (creating a <strong>Dead Tuple</strong>) and inserts a brand-new tuple version at a new <code>ctid</code>. Default <code>autovacuum_vacuum_scale_factor = 0.20</code> waits until 20% (8 million rows!) change before vacuuming.<br><strong>Fix:</strong> Run <code>VACUUM (ANALYZE) synoptic.observations;</code> and lower the table's scale factor: <code>ALTER TABLE synoptic.observations SET (autovacuum_vacuum_scale_factor = 0.01);</code>.</details>

### Scenario 6: The 00Z ECMWF Ingestion I/O Freeze (Day 2 — PostgreSQL WAL & Checkpoints)
- **Symptom:** Every night at `02:00 UTC` when your pipeline loads 5 million ECMWF forecast rows, PostgreSQL logs `checkpoints are occurring too frequently (18 seconds apart)` and forecaster dashboards stall.
- **Question:** Which 4 `postgresql.conf` parameters should you tune, and how should the Python script load the rows?
- <details><summary><strong>Answer</strong></summary>Default <code>max_wal_size = 1GB</code> is too small for bulk NWP loads. Set <code>max_wal_size = '16GB'</code>, <code>checkpoint_timeout = '15min'</code>, <code>checkpoint_completion_target = 0.9</code>, and <code>wal_compression = lz4</code>. In Python, use PostgreSQL's streaming <code>COPY</code> protocol instead of individual <code>INSERT</code> statements.</details>

### Scenario 7: Deleting 2024 Observations Locks Up Disk I/O (Day 3 — Partitioning & BRIN)
- **Symptom:** To free disk space on the 1st of each month, an engineer runs `DELETE FROM synoptic.observations WHERE obs_time < NOW() - INTERVAL '1 year';`. The command runs for 45 minutes, generates 15 GB of WAL, and **does not shrink the file size on disk at all**!
- **Question:** Why didn't `DELETE` free OS disk space, and how should time-series retention be architected in PostgreSQL?
- <details><summary><strong>Answer</strong></summary><code>DELETE</code> only marks tuples as dead (<code>xmax</code> set) inside existing 8KB heap pages; it does not return file blocks to the OS. Instead, use <strong>Declarative Range Partitioning (<code>PARTITION BY RANGE (obs_time)</code>)</strong> with monthly child tables, detach old months via <code>ALTER TABLE ... DETACH PARTITION obs_y2025m06 CONCURRENTLY;</code>, archive to Parquet, and run <code>DROP TABLE obs_y2025m06;</code> (which frees 100% of disk space in milliseconds with zero dead tuples).</details>

### Scenario 8: Station in the Indian Ocean! (Days 3–4 — PostGIS & MongoDB GeoJSON)
- **Symptom:** A weather engineer inserts Algiers (`Lat 36.6910°N, Lon 3.2154°E`) into MongoDB as `location: { type: "Point", coordinates: [36.6910, 3.2154] }` (or in PostGIS as `ST_MakePoint(36.6910, 3.2154)`). When they search for stations near Algiers, `0` results come back!
- **Question:** Why did the station end up off the coast of Somalia in the Indian Ocean?
- <details><summary><strong>Answer</strong></summary>Both <strong>GeoJSON (MongoDB)</strong> and <strong>PostGIS (<code>ST_MakePoint</code>)</strong> strictly require <strong><code>[X, Y] = [longitude, latitude]</code></strong> order: <code>[3.2154, 36.6910]</code>!</details>

### Scenario 9: The False-Positive 500 hPa Jet Stream Alert (Day 4 — MongoDB `$elemMatch`)
- **Symptom:** Each document in `db.radiosonde_soundings` has an array `vertical_levels: [ { pressure_hpa: 1000, wind_speed_kt: ... }, ..., { pressure_hpa: 300, wind_speed_kt: 95 } ]`. An engineer runs:
  ```javascript
  db.radiosonde_soundings.find({
    "vertical_levels.pressure_hpa": 850,
    "vertical_levels.wind_speed_kt": { $gte: 80 }
  })
  ```
  It returns almost every balloon launch, even when the `850 hPa` wind was only `15 kt`!
- **Question:** Why did this happen, and how do you fix the query?
- <details><summary><strong>Answer</strong></summary>Dot-notation conditions on an array match if <em>any</em> element has <code>pressure_hpa: 850</code> and <em>any other</em> element (such as <code>300 hPa</code>!) has <code>wind_speed_kt >= 80</code>. Use <strong><code>$elemMatch</code></strong> so both conditions must match the <strong>same</strong> array element: <code>vertical_levels: { $elemMatch: { pressure_hpa: 850, wind_speed_kt: { $gte: 80 } } }</code>.</details>

### Scenario 10: The 100 MB Blocking Sort Error in MongoDB (Day 4 — Indexing & ESR Rule)
- **Symptom:** A query `db.radiosonde_soundings.find({ station_id: 60390, cape_j_kg: { $gte: 500 } }).sort({ launch_time: -1 })` is slow and shows a `SORT` stage in `.explain("executionStats")`, even though an index exists on `{ station_id: 1, cape_j_kg: 1, launch_time: -1 }`.
- **Question:** Why couldn't MongoDB use the index to avoid sorting in memory, and how should the index keys be reordered?
- <details><summary><strong>Answer</strong></summary>Because the range field (<code>cape_j_kg</code>) was placed <em>before</em> the sort field (<code>launch_time</code>)! Follow the <strong>ESR Rule (Equality &rarr; Sort &rarr; Range)</strong>: <code>{ station_id: 1, launch_time: -1, cape_j_kg: 1 }</code>.</details>

### Scenario 11: The 10-Shard MongoDB Cluster Where Only 1 Shard Works (Day 4 — Sharding)
- **Symptom:** To scale writes for 5,000 automated weather stations, an administrator deploys a 10-shard MongoDB cluster and shards the `observations` collection on `{ obs_time: 1 }`. CPU utilization on Shard 10 hits 100%, while Shards 1–9 sit at 0% CPU during live ingestion!
- **Question:** Why did `{ obs_time: 1 }` create a hotspot on Shard 10, and what is the proper Shard Key?
- <details><summary><strong>Answer</strong></summary><code>obs_time</code> is monotonically increasing, so 100% of live observations fall into the newest <code>maxKey</code> chunk on a single shard. Prefix the shard key with a high-cardinality station identifier: <strong><code>{ "station_meta.station_id": 1, obs_time: 1 }</code></strong>.</details>

### Scenario 12: The 12 GB CSV Laptop Freeze (Day 5 — Columnar Parquet & DuckDB)
- **Symptom:** A climate scientist has a 12 GB CSV file (`synoptic_2020_2026.csv`) with 55 columns. Every morning their Python script runs `pd.read_csv('synoptic_2020_2026.csv')` just to calculate daily mean `temp_c` for 3 desert stations, crashing their 16 GB RAM laptop.
- **Question:** How should they convert this file and run the query in < 0.3 seconds using < 200 MB of RAM?
- <details><summary><strong>Answer</strong></summary>Convert the row-oriented CSV into a column-oriented ZSTD-compressed <strong>Apache Parquet</strong> file using <strong>DuckDB</strong>: <code>COPY (SELECT * FROM read_csv_auto('synoptic_2020_2026.csv')) TO 'synoptic.parquet' (FORMAT PARQUET, COMPRESSION ZSTD);</code> and query <code>'synoptic.parquet'</code> directly in DuckDB (which uses Projection Pushdown to read only <code>station_id</code>, <code>obs_time</code>, and <code>temp_c</code>, plus Predicate Pushdown to skip irrelevant Row Groups).</details>

### Scenario 13: The 450,000 Tiny Parquet Files Disaster (Day 5 — Hive Partitioning & Small Files Problem)
- **Symptom:** An engineer modifies the MQTT stream router to write a brand-new Parquet file every 10 seconds partitioned by `year/month/day/hour/minute`. Within 2 months, querying `read_parquet('lake/**/*.parquet')` in DuckDB takes **4 minutes** just to scan 2 GB of data!
- **Question:** Why did writing 10-second Parquet files ruin DuckDB's performance, and what is the target file size and compaction strategy?
- <details><summary><strong>Answer</strong></summary>This is the <strong>"Small Files Problem"</strong>: opening 450,000 tiny 4 KB files spends 99% of wall-clock time on OS inode lookups / S3 HTTP `GET` handshakes and Thrift footer parsing rather than vectorized SIMD execution.<br><strong>Fix:</strong> Partition strictly by coarse temporal boundaries (<code>year=YYYY/month=MM</code>) and run a scheduled compaction job to merge files into <strong>128 MB – 512 MB</strong> Parquet blocks with 100k–250k rows per Row Group.</details>

### Scenario 14: The S3 / Ceph RGW `GRIB2` Cloud Bottleneck (Day 5 — Gridded Data: `GRIB2` vs. `NetCDF4` vs. `Zarr`)
- **Symptom:** A machine learning team stores 50 TB of global NWP model grids on an on-premises **Ceph RGW (S3)** cluster as monolithic `NetCDF4` (`.nc`) and `GRIB2` files. When 64 Dask/PyTorch workers try to slice a 30-year time-series for a single grid cell over Algiers, network throughput maxes out while CPU sits idle.
- **Question:** Why do monolithic `NetCDF4` / `GRIB2` files struggle on S3 object storage, and how should the 4D arrays be stored and chunked?
- <details><summary><strong>Answer</strong></summary><code>NetCDF4</code> (HDF5) requires multiple sequential pointer seeks across internal B-trees, and <code>GRIB2</code> is a sequential message stream optimized for 2D horizontal maps—forcing workers to pull entire multi-megabyte horizontal slices just to read 1 coordinate.<br><strong>Fix:</strong> Convert the archive to <strong>Cloud-Native `Zarr`</strong> stored on Ceph RGW S3, where each 4D chunk is an independent S3 object (`s3://bucket/temp/0.1.4`), and re-chunk along the time dimension for time-series training (or use `.idx` byte-range index sidecars for operational GRIB2).</details>

### Scenario 15: Remote Saharan Stations Exhausting PostgreSQL Connections (Day 5 — Edge MQTT & Polyglot Routing)
- **Symptom:** 1,200 remote solar-powered weather stations over 2G/satellite modems are configured to connect directly to the central PostgreSQL server (`port 5432`) every minute to run `INSERT INTO observations...`. Whenever a sandstorm causes intermittent packet loss, PostgreSQL hits `FATAL: sorry, too many clients already` and crashes!
- **Question:** Why is direct SQL over unstable field links an architectural antipattern, and how does the Day 5 Edge-to-Core pipeline solve it?
- <details><summary><strong>Answer</strong></summary>Each direct PostgreSQL connection requires a heavy TCP + TLS + auth handshake and spawns an OS backend process that hangs in `idle in transaction` when a satellite link drops.<br><strong>Fix:</strong> Buffer observations locally in <strong>SQLite (`WAL` mode)</strong> on the station logger, publish lightweight 2-byte-header <strong>MQTT (`QoS 1`)</strong> packets to an edge <strong>Mosquitto / Kafka</strong> broker, and use a central <strong>Polyglot Stream Router</strong> to batch-insert (`execute_values` / `COPY` / `bulk_write`) into PostgreSQL and MongoDB using a fixed connection pool.</details>

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
