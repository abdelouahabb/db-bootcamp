> **Navigation:** [Master README](../README.md) | [Interactive Portal](../bootcamp_portal.html) | [Reference Cards](../reference_cards/README.md) | [Day 1 Coursebook](../day1/day1_master_coursebook.md) | [Day 2 Coursebook](day2_master_coursebook.md) | [Day 3 Coursebook](../day3/day3_master_coursebook.md)

# Day 2 Master Cheatsheet: PostgreSQL Installation, Storage Internals, WAL, Vacuum, Locking & `EXPLAIN` Forensics

**Companion to:** [day2_master_coursebook.md](./day2_master_coursebook.md) | [day2_postgres_vs_mysql_mvcc_guide.md](./day2_postgres_vs_mysql_mvcc_guide.md) | [Reference Card 14 (MySQL/MariaDB Guide)](../reference_cards/14_mysql_and_mariadb_innodb_complete_engineering_guide.md) | [day2_pageinspect_and_storage_lab.sql](./day2_pageinspect_and_storage_lab.sql) | [day2_two_terminal_acid_lab.sql](./day2_two_terminal_acid_lab.sql)

---

> [!CAUTION]
> ### STOP & READ FIRST — Day 2 PostgreSQL Database (`weather_ops`), Scripts, Schemas & Tables Map
>
> All Day 2 PostgreSQL commands run inside the **`weather_ops`** database (`psql -d weather_ops`). Day 2 uses **3 `.sql` scripts** in `day2/` across **4 schemas (`synoptic`, `nwp`, `alerts`, `public`)**:
>
> | SQL Script in `day2/` | How to Run It | Schemas & Tables Created Inside `weather_ops` |
> | :--- | :--- | :--- |
> | **1. [`day2/weather_ops_pg.sql`](./weather_ops_pg.sql)** | `cd day2 && psql -d weather_ops -f weather_ops_pg.sql` | • **`synoptic.stations`** (`7` WMO stations + TOAST `raw_metadata`)<br/>• **`synoptic.observations`** (`18,432` hourly observations)<br/>• **`nwp.forecasts`** (`4,608` NWP forecast rows with `STORED` `valid_time`)<br/>• **`alerts.weather_alerts`** (`4` weather alerts) |
> | **2. [`day2/day2_pageinspect_and_storage_lab.sql`](./day2_pageinspect_and_storage_lab.sql)** | `cd day2 && psql -d weather_ops -f day2_pageinspect_and_storage_lab.sql` | • **`public.telemetry_unaligned`** & **`public.telemetry_aligned`** (`80B` vs. `64B` Tuple Tetris)<br/>• **`public.layout_padded`** & **`public.layout_packed`** (`48B` vs. `40B` `pageinspect`)<br/>• **`public.mvcc_demo`** (`t_xmin`, `t_xmax`, `t_ctid` chain)<br/>• **`public.bloat_lab`** (`100k` rows — `pgstattuple` `VACUUM` vs. `VACUUM FULL`)<br/>• **`public.plan_lab`** (`1,000,000` rows — Row-Store Scan Penalty & `Index Only Scan`) |
> | **3. [`day2/day2_two_terminal_acid_lab.sql`](./day2_two_terminal_acid_lab.sql)** | Open **Terminal A** & **Terminal B** side-by-side (`psql -d weather_ops`) and paste steps interactively | • **`public.station_calibration`** (`3` rows: `'AWS-001'`, `'AWS-002'`, `'AWS-003'`) |
>
> * **Schema `search_path` Tip:** If `SELECT * FROM observations;` gives `ERROR: relation "observations" does not exist`, either qualify the schema (**`synoptic.observations`**) or run `ALTER DATABASE weather_ops SET search_path TO synoptic, nwp, alerts, public;` and reconnect (`\c weather_ops`).*

---

## 1. Installing, Initializing & Hardening the Host OS

### 1.1 Installation Commands (Ubuntu/Debian, RHEL/Rocky, Docker)

#### Option A: Ubuntu / Debian (APT)
```bash
# 1. Install PostgreSQL server and contrib extensions (pageinspect, pgstattuple, pg_stat_statements)
sudo apt update
sudo apt install -y postgresql postgresql-contrib

# 2. Verify service status (runs on port 5432 by default)
sudo systemctl status postgresql
sudo systemctl enable postgresql

# 3. Create an operational weather engineer role & database
sudo -u postgres createuser --interactive --pwprompt weather_eng
sudo -u postgres createdb -O weather_eng weather_ops
```

#### Option B: RHEL / Rocky / AlmaLinux (DNF)
```bash
sudo dnf install -y postgresql-server postgresql-contrib
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql
```

#### Option C: Docker (Fastest Lab Setup with Mandatory UTC)
```bash
docker run -d \
  --name weather-pg \
  -e POSTGRES_USER=weather_eng \
  -e POSTGRES_PASSWORD=meteo_pass \
  -e POSTGRES_DB=weather_ops \
  -e TZ=UTC \
  -p 5432:5432 \
  -v pg_weather_data:/var/lib/postgresql/data \
  postgres:16
```

### 1.2 Host Storage Decoupling & Linux Kernel Hardening (`/etc/fstab` & `/etc/sysctl.conf`)
* **Decouple `$PGDATA` and `pg_wal`:** Mount `$PGDATA` (`/data/pgdata`) and `pg_wal` (`/data/pgwal`) on separate physical NVMe volumes so random analytical heap reads never interrupt sequential WAL append writes.
* **Disable Access-Time Writes in `/etc/fstab` (Saves up to 25% read I/O metadata churn):**
  ```ini
  UUID=xxxx-xxxx-xxxx  /var/lib/postgresql/data  ext4  noatime,nodiratime,errors=remount-ro,data=ordered  0  2
  ```
* **Protect `postmaster` from Swap & Linux OOM-Killer in `/etc/sysctl.conf`:**
  ```ini
  vm.swappiness = 1
  vm.overcommit_memory = 2
  vm.overcommit_ratio = 80
  kernel.shmmax = 18446744073709551615
  kernel.shmall = 18446744073709551615
  ```

---

## 2. Critical Cluster Paths & Remote Access Configuration

Run inside `psql` to locate the active cluster files on any operating system:
```sql
SHOW data_directory;   -- Physical cluster data ($PGDATA, e.g., /var/lib/postgresql/16/main)
SHOW config_file;      -- Main tuning file (e.g., /etc/postgresql/16/main/postgresql.conf)
SHOW hba_file;         -- Client authentication rules (pg_hba.conf)
```

| Directory / File | Purpose in Weather Operations |
| :--- | :--- |
| `postgresql.conf` | Memory, WAL, checkpoint, parallel query, autovacuum, and mandatory `UTC` settings |
| `postgresql.auto.conf` | Persistent dynamic settings written by `ALTER SYSTEM SET ...` (overrides `postgresql.conf`) |
| `pg_hba.conf` | Controls which IPs (synoptic ingest servers, forecaster workstations) can connect |
| `$PGDATA/base/<db_oid>/` | Physical 8 KB heap files (`<relfilenode>`), Free Space Maps (`_fsm`), and Visibility Maps (`_vm`) |
| `$PGDATA/pg_wal/` | Sequential 16 MB Write-Ahead Log segments for crash recovery & streaming replication |
| `$PGDATA/pg_xact/` | Transaction commit/abort status bitmaps (formerly `pg_clog`) |
| `$PGDATA/log/` | Server error logs, checkpoint statistics (`log_checkpoints`), and slow-query logs |

### Enabling Remote Connections (DBeaver / Automated Ingest Scripts)
1. In `postgresql.conf`: `listen_addresses = '*'` (Default is `'localhost'`).
2. In `pg_hba.conf`:
   ```text
   # TYPE  DATABASE      USER          ADDRESS          METHOD
   host    weather_ops   weather_eng   10.20.0.0/16     scram-sha-256
   ```
3. Reload live without dropping connections: `SELECT pg_reload_conf();` (or `sudo systemctl reload postgresql`).

---

## 3. Production `postgresql.conf` Profile for Weather Workloads

### Reference Server Profile: **32 GB RAM, 8 vCPU, NVMe SSD**

```ini
# =========================================================================
# 1. TIMEZONE & LOCALE (MANDATORY FOR METEOROLOGY!)
# =========================================================================
timezone = 'UTC'                        # Always store and display in UTC (Zulu time)
log_timezone = 'UTC'                    # Match server logs to synoptic UTC timestamps
datestyle = 'iso, ymd'                  # Enforce ISO-8601 (YYYY-MM-DD)

# =========================================================================
# 2. CONNECTIONS (PROTECT AGAINST STATION CONNECTION STORMS)
# =========================================================================
max_connections = 200                   # Keep moderate (100-300); place PgBouncer in front
                                        # if 1,000+ automated stations push concurrently!

# =========================================================================
# 3. DUAL-TIER MEMORY ARCHITECTURE (25% shared_buffers + 75% OS Page Cache)
# =========================================================================
shared_buffers = 8GB                    # ~25% of total RAM. Caches hot 8KB pages of
                                        # recent synoptic observations & indexes.
effective_cache_size = 24GB             # ~75% of total RAM (planner hint: shared_buffers +
                                        # Linux OS page cache). Favors Index Scans.
work_mem = 32MB                         # Per sort/hash operation (32MB-64MB). Prevents Hash Joins
                                        # and ORDER BYs from spilling to temporary disk files!
maintenance_work_mem = 1GB              # 1GB-2GB: Accelerates CREATE INDEX, VACUUM, ALTER TABLE.
huge_pages = try                        # Reduces OS TLB memory overhead for 8GB+ shared_buffers.

# =========================================================================
# 4. WAL & CHECKPOINT SMOOTHING (SURVIVING 00Z / 12Z NWP BULK LOADS)
# =========================================================================
wal_level = replica                     # Supports physical backups (pg_basebackup) & standbys
full_page_writes = on                   # Mandatory protection against 4KB/8KB torn pages on crash
wal_compression = lz4                   # (or zstd) Compresses full-page writes in WAL (saves 40-60%!)
wal_buffers = 64MB                      # Ring buffer for bursty synoptic/NWP transaction logs

checkpoint_timeout = 15min              # Default 5min is too short during NWP model ingestion
max_wal_size = 16GB                     # (16GB-32GB) Default 1GB forces constant I/O stalls on COPY!
min_wal_size = 2GB                      # (2GB-4GB) Retain recycled WAL segments
checkpoint_completion_target = 0.9      # Spreads dirty 8KB page flushes over 90% of interval (13.5m)

# =========================================================================
# 5. QUERY PLANNER, PARALLEL EXECUTION & JIT (FOR NVMe & CLIMATOLOGY)
# =========================================================================
random_page_cost = 1.1                  # Default 4.0 assumes spinning HDDs! Set 1.1 for NVMe/SSD.
effective_io_concurrency = 200          # Prefetch concurrency for Bitmap Heap Scans on NVMe.
default_toast_compression = lz4         # 4x faster TOAST compression/decompression than legacy pglz!

max_worker_processes = 8
max_parallel_workers_per_gather = 4     # Parallelizes Seq Scans, Hash Joins & Aggregations
max_parallel_maintenance_workers = 4    # Parallelizes CREATE INDEX & VACUUM across CPU cores!
max_parallel_workers = 8                # across CPU cores for multi-year climatology queries!
jit_above_cost = 500000                 # Default 100000 triggers 100ms LLVM JIT overhead on fast partitioned queries!

# =========================================================================
# 6. AUTOVACUUM & HORIZON SAFETY (PREVENTING QC UPDATE & NWP PURGE BLOAT)
# =========================================================================
autovacuum = on
autovacuum_max_workers = 4              # Scale workers across cores
autovacuum_naptime = 30s                # Wake up every 30s to check table bloat
autovacuum_vacuum_scale_factor = 0.05   # Trigger at 5% dead tuples (default 0.20 waits too long!)
autovacuum_analyze_scale_factor = 0.02  # Refresh planner histograms after 2% row churn
autovacuum_vacuum_cost_limit = 2000     # Allow autovacuum to work 10x faster on NVMe SSDs
autovacuum_vacuum_cost_delay = 2ms
idle_in_transaction_session_timeout = 60000 # Kill idle open transactions after 60s to protect VACUUM!

# =========================================================================
# 7. OBSERVABILITY & SLOW QUERY LOGGING
# =========================================================================
log_min_duration_statement = 1000       # Log any query taking > 1000 ms (1 second)
log_checkpoints = on                    # Verify checkpoints are time-triggered, not WAL-forced
log_lock_waits = on                     # Log any query waiting on locks > deadlock_timeout (1s)
track_io_timing = on                    # Enables exact disk I/O ms timing in EXPLAIN (ANALYZE, BUFFERS)
shared_preload_libraries = 'pg_stat_statements'
```

---

## 4. Storage Engine Internals & "Tuple Tetris" Quick Reference

```
================================================================================
               POSTGRESQL 8 KB STORAGE ENGINE REFERENCE CARD
================================================================================
 1. Page Size        : Fixed 8 KB (8192 bytes)
 2. Page Header      : 24 bytes (pd_lsn, pd_checksum, pd_lower, pd_upper)
 3. Line Pointer     : 4 bytes per row (ItemIdData array growing downward)
 4. Tuple Header     : 23 bytes minimum (padded to 24 bytes on 64-bit CPUs)
                       t_xmin(4B) + t_xmax(4B) + t_cid(4B) + t_ctid(6B) +
                       t_infomask2(2B) + t_infomask(2B) + t_hoff(1B)
 5. Row Coordinate   : ctid = (block_number, line_pointer_index) [6 bytes]
 6. Column Alignment : Order fields 8B -> 4B -> 2B -> 1B -> Variable (TEXT/JSONB)
                       to eliminate silent CPU byte-alignment padding!
 7. TOAST Threshold  : ~2 KB per tuple (compresses via LZ4/pglz or moves out-of-line)
 8. fillfactor       : 100 for append-only telemetry; 80-90 for HOT-updated tables
================================================================================
```

### Alignment Size Lookup Table ("Tuple Tetris")
| Alignment Boundary | `typalign` | PostgreSQL Data Types |
| :--- | :--- | :--- |
| **8-Byte Aligned** (Offsets `0, 8, 16...`) | `'d'` (`double`) | `BIGINT` (`int8`), `BIGSERIAL`, `TIMESTAMPTZ`, `TIMESTAMP`, `DOUBLE PRECISION` (`float8`), `INTERVAL` (16B) |
| **4-Byte Aligned** (Offsets `0, 4, 8...`) | `'i'` (`int`) | `INTEGER` (`int4`), `SERIAL`, `REAL` (`float4`), `DATE`, `TIME` |
| **2-Byte Aligned** (Offsets `0, 2, 4...`) | `'s'` (`short`) | `SMALLINT` (`int2`) |
| **1-Byte / Packed** (Any offset) | `'c'` (`char`) | `UUID` (**16B fixed, zero alignment padding!**), `BOOLEAN` (1B), `"char"`, and short variable-length (`NUMERIC`, `VARCHAR`, `TEXT`, `JSONB` with 1B `varlena` header) |

### 4.1 Data Type & Uniqueness Decision Matrices (Black Boxes 2A, 2B, 2C, 2D)

#### A. Temporal Types (`TIMESTAMPTZ` vs. `TIMESTAMP` — Both Are 8 Bytes on Disk!)
> **The Hardware Secret:** Neither `TIMESTAMPTZ` nor `TIMESTAMP` stores a timezone string or offset in its 8 bytes on disk. Both store a `BIGINT` count of microseconds since `2000-01-01 00:00:00`. The difference is **Boundary Normalization**: `TIMESTAMPTZ` converts any input offset to **UTC** on `INSERT` and converts back to the session's `timezone` on `SELECT`, whereas `TIMESTAMP` strips the offset and stores raw wall-clock numbers (causing 1-hour duplicate collisions during Autumn DST fallback).

| Pattern | SQL Declaration | Disk Size | UTC Normalized? | DST-Safe? | When to Use |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Absolute Physical Instant** | `TIMESTAMPTZ NOT NULL` | `8 bytes` | **YES** | **YES** | **99% of meteorological timestamps:** `obs_time`, `init_time`, `valid_time`, `issued_at`. |
| **2. Local Wall-Clock + IANA Zone** | `TIMESTAMPTZ` + `TEXT` (`'Africa/Algiers'`) | `8B + varlena` | **YES** | **YES** | Solar-noon climatology or legal local-time reporting across DST rules. |
| **3. Abstract Calendar Date/Time** | `DATE` (`4B`) / `TIME` (`8B`) | `4B / 8B` | N/A | N/A | Daily climatological summaries (`valid_date DATE`) or scheduled launch times (`00:00`, `12:00`). |
| **4. Naive `TIMESTAMP` *(Anti-Pattern)*** | `TIMESTAMP WITHOUT TIME ZONE` | `8 bytes` | **NO** | **NO** | **Avoid for physical events.** Only acceptable for synthetic simulation clocks with no real-world timezone. |

#### B. Exact Decimal (`NUMERIC(p,s)`) vs. IEEE-754 Binary Float (`REAL` / `DOUBLE PRECISION`)
> **The `(p, s)` Trap:** In `NUMERIC(p, s)`, $p$ is **total digits** (left + right of decimal) and $s$ is **fractional digits**. Maximum integer digits = $p - s$. Thus `NUMERIC(4,1)` holds `-999.9` to `999.9` (inserting `1013.2` raises `22003: numeric field overflow`; pressure requires `NUMERIC(6,1)`).

| Pattern | SQL Declaration | Disk Size | Math Representation | `0.1 + 0.2 = 0.3`? | When to Use |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Exact Base-10 Contract** | `NUMERIC(p, s)` | `5–11 bytes` (`varlena`) | Base-10000 exact digits | **YES (`TRUE`)** | Official WMO synoptic archives (`temp_c NUMERIC(4,1)`), station `latitude NUMERIC(7,4)`, `precip_1h_mm NUMERIC(5,1)` where `= 0.3` must never fail due to binary float drift. |
| **2. High-Speed 64-Bit Scientific Float** | `DOUBLE PRECISION` (`float8`) | `8 bytes` (fixed) | IEEE-754 binary64 ($\approx 15–17$ digits) | **NO (`0.30000000000000004`)** | High-frequency 10 Hz ultrasonic turbulence, NWP perturbation matrices, and hardware-accelerated CPU math. |
| **3. Compact 32-Bit Sensor Float** | `REAL` (`float4`) | `4 bytes` (fixed) | IEEE-754 binary32 ($\approx 6–7$ digits) | **NO** | Massive 5M–1B row raw IoT tables (`day3` benchmark) where saving 4 bytes/column in Tuple Tetris is paramount. |
| **4. Scaled Integer Quantization** | `SMALLINT` (`int2`) / `INTEGER` (`int4`) | `2B / 4B` (fixed) | Integer $\times \text{scale\_factor}$ | **YES** | Satellite rasters (`COG`/`NetCDF4` `UInt16` with `scale_factor = 0.01`) and ultra-compact wire protocols. |

#### C. `PRIMARY KEY` vs. `UNIQUE NOT NULL` vs. Nullable `UNIQUE` (`NULLS DISTINCT`)
| Constraint Pattern | Implicitly Adds `NOT NULL`? | Multiple `NULL`s Allowed? | When to Use |
| :--- | :--- | :--- | :--- |
| **`PRIMARY KEY (col)`** | **YES** | **NO** (`0` `NULL`s) | Every table's canonical row identity (`station_id`, `obs_id`, or partitioned `(obs_time, station_id)`). |
| **`UNIQUE NOT NULL`** | Explicit | **NO** (`0` `NULL`s) | Secondary mandatory natural keys (`icao_code VARCHAR(4) UNIQUE NOT NULL`, `station_id, obs_time`). |
| **`UNIQUE` (Default `NULLS DISTINCT`)** | **NO** | **YES (Unlimited `NULL`s!)** | Optional external identifiers (`wigos_id VARCHAR(32) UNIQUE`) where unassigned stations are `NULL`, but every assigned ID must be unique. |
| **`UNIQUE NULLS NOT DISTINCT` *(PG 15+)*** | **NO** | **At most ONE `NULL`** | Composite keys with optional dimensions where `(60390, NULL)` must not be inserted twice. |

#### D. Surrogate Primary Keys (`BIGINT IDENTITY` vs. `UUIDv7` RFC 9562 vs. `UUIDv4`)
> **The B-Tree & WAL Secret:** Random `UUIDv4` (`gen_random_uuid()`) scatters `INSERT`s uniformly across all B-Tree leaf pages, causing **50/50 page splits** (~55% fill density), `shared_buffers` cache thrashing, and **$500\times$ `pg_wal` Full-Page Write (`FPW`) amplification** (dirtying 1,000 random 8 KB pages after a checkpoint logs $8\text{ MB}$ of WAL instead of $16\text{ KB}$!). **`UUIDv7` (RFC 9562)** places a **48-bit big-endian Unix millisecond timestamp** in the top 6 bytes (`[48b unix_ts_ms][4b ver=7][12b rand_a][2b var=10][62b rand_b]`), restoring 100% rightmost B-Tree leaf append locality while allowing offline edge weather stations to generate globally unique IDs without central sequence coordination.

| Identifier Strategy | SQL Declaration | Disk Size | B-Tree Locality | WAL FPW Cost | When to Use |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **1. `BIGINT IDENTITY`** | `BIGINT GENERATED ALWAYS AS IDENTITY` | **`8B`** (`typalign='d'`) | **Rightmost Append** | **Minimal** | Default for centralized DB-generated surrogate keys (`obs_id`). |
| **2. `UUIDv7` (RFC 9562)** | `UUID DEFAULT uuid_generate_v7()` *(PG 18+: `uuidv7()`)* | **`16B`** (`typalign='c'`) | **Rightmost Append** | **Minimal** | Distributed/offline edge stations, microservices, multi-region ingest. |
| **3. `UUIDv4` (Random)** | `UUID DEFAULT gen_random_uuid()` | **`16B`** (`typalign='c'`) | **Random Scatter!** | **$500\times$ Bloat** | **Avoid for large indexed PKs!** Use only for unindexed tokens or tiny tables. |
| **4. Text UUID *(Anti-Pattern)*** | `VARCHAR(36)` / `TEXT` | **`37B`** (`1B varlena + 36B`) | Wastes `21B`/row | High | **Never!** Always use PostgreSQL's native `16-byte` binary `UUID` type. |

---

## 5. WAL, Crash Recovery & High-Speed Ingestion Summary Matrix

| Mechanism / Feature | SQLite Rollback | SQLite WAL | PostgreSQL 16+ | MySQL InnoDB 8.0+ |
| :--- | :--- | :--- | :--- | :--- |
| **Primary Crash Log** | `.db-journal` (Undo copies) | `.db-wal` + `.db-shm` | Monolithic WAL (`pg_wal/` 16MB segments) | Circular Redo Log (`innodb_redo_log_capacity`) |
| **Readers vs. Writers** | Writers block Readers; Readers block Writers | **Non-blocking** (Multi-reader, 1 writer) | **Non-blocking MVCC** (Multi-reader, multi-writer) | **Non-blocking MVCC** (Multi-reader, multi-writer) |
| **Torn-Page Defense** | Full pre-image in `.db-journal` | Full frame append in `.db-wal` | **`full_page_writes = on`** (8KB image in WAL after checkpoint) | **Doublewrite Buffer** (`innodb_doublewrite = 1`) |
| **Fast Relaxed Commit** | `PRAGMA synchronous = OFF;` | `PRAGMA synchronous = NORMAL;` | `SET LOCAL synchronous_commit = off;` (5x–10x faster, $\le 0.6\text{s}$ risk) | `innodb_flush_log_at_trx_commit = 2` (OS flush on commit, 1s disk sync) |
| **Zero-Log Bulk Table** | `PRAGMA journal_mode = OFF;` | `TEMP` table | **`CREATE UNLOGGED TABLE`** (3x–5x faster; truncated on OS crash) | `MEMORY` / `TEMPORARY` table |
| **Bulk Stream Protocol** | Batched `INSERT` in `BEGIN...COMMIT` | Batched `INSERT` | **`COPY` / `\copy` ($\approx 120,000\text{ rows/sec}$)** | `LOAD DATA INFILE` |

---

## 6. `VACUUM` vs. `VACUUM FULL` vs. `pg_repack` Matrix

| Dimension | Standard `VACUUM` (Concurrent) | `VACUUM FULL` (Destructive Rewrite) | `pg_repack` (Online Extension) |
| :--- | :--- | :--- | :--- |
| **Lock Acquired** | `ShareUpdateExclusiveLock` | **`AccessExclusiveLock`** | Brief lock only at swap (< 50 ms) |
| **Reads & Writes Allowed?** | **YES** (100% online) | **NO** (Blocks all `SELECT`/`INSERT`/`UPDATE`/`DELETE`) | **YES** (Online via shadow table + trigger log) |
| **Returns Disk Space to OS?** | **NO** (Marks slots reusable in `_fsm`) | **YES** (Writes new `relfilenode` & deletes old file) | **YES** (Drops bloated file after swap) |
| **Extra Free Disk Required** | $\approx 0\text{ bytes}$ | **$\ge 100\%$ of table + indexes** | $\ge 100\%$ of table + indexes |
| **Updates `_fsm` & `_vm`?** | **YES** (Enables Index-Only Scans) | **YES** (Rebuilds table & all indexes from scratch) | **YES** (Rebuilds table & all indexes) |
| **Freezes XIDs ($2^{31}$ wrap)?** | **YES** | **YES** | **YES** |

---

## 7. Query Execution Plan Forensics: The 7 Deadly Sins of `EXPLAIN`

Always profile queries using:
```sql
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING) <SQL_QUERY>;
```
> **Warning:** `EXPLAIN ANALYZE` actually executes the query! Wrap `DELETE` / `UPDATE` in `BEGIN; EXPLAIN ANALYZE ...; ROLLBACK;`.

| # | Red-Flag Symptom in `EXPLAIN (ANALYZE, BUFFERS)` | Root Cause | Engineering Fix |
| :--- | :--- | :--- | :--- |
| **1** | `Seq Scan` on a multi-million-row table returning few rows | Missing index, non-SARGable function (`EXTRACT(YEAR FROM obs_time) = 2026`), or `random_page_cost = 4.0` | Create B-Tree/BRIN index, rewrite filter as range (`obs_time >= ...`), set `random_page_cost = 1.1` |
| **2** | `Sort Method: external merge  Disk: 42100kB` | `work_mem` is too small to hold sort keys in RAM; spilled to `$PGDATA/base/pgsql_tmp` | Increase session/global `SET work_mem = '64MB';` |
| **3** | `Hash Join` with `Batches: 4  Disk Usage: 104856kB` | Inner hash table exceeded `work_mem` and spilled temporary hash partitions to disk | Increase `work_mem` so `Batches: 1` executes 100% in RAM |
| **4** | **Extreme Cardinality Skew:** `rows=2` vs. `actual rows=500000` | Outdated statistics or multi-column correlation blindspot (e.g., `climate_zone` + `temp_c`) | Run `ANALYZE <table>;` and create extended statistics (`CREATE STATISTICS ...`) |
| **5** | `Index Only Scan` with high `Heap Fetches: 14500` | Visibility Map (`_vm`) pages are not marked all-visible due to recent writes | Run `VACUUM <table>;` so `Heap Fetches` drops to `0` |
| **6** | `Nested Loop` with `loops=150000` taking minutes | Planner underestimated outer row count and ran 150,000 inner index/seq scans | Run `ANALYZE`, index inner join key, or increase `work_mem` to enable `Hash Join` |
| **7** | `Rows Removed by Filter: 999946` (with `actual rows=54`) | CPU read and discarded 99.99% of rows after fetching 8 KB blocks from disk/RAM | Add the filtered columns to a composite index `(station_id, obs_time) INCLUDE (temp_c)` |

---

## 8. Essential `psql` Commands & Diagnostic SQL Toolkit

### 8.1 Essential `psql` Slash Commands
| Command | Description |
| :--- | :--- |
| `\conninfo` | Display current database, user, host, and port |
| `\l+` | List all databases with their total disk size |
| `\dn+` | List all schemas (`synoptic`, `nwp`, `alerts`) |
| `\dt+ synoptic.*` | List tables in `synoptic` schema with on-disk sizes |
| `\di+ synoptic.*` | List indexes in `synoptic` schema with on-disk sizes |
| `\d+ synoptic.observations` | Show columns, types, constraints, indexes, TOAST mode, and `reloptions` |
| `\timing on` | Toggle millisecond execution timer for every query |
| `\x auto` | Auto-switch wide query results to vertical card view |
| `\copy ...` | Client-side high-speed bulk CSV/binary import and export |

### 8.2 Production Diagnostic Queries (Copy & Paste Ready)

```sql
-- TARGET DATABASE: PostgreSQL 'weather_ops' (psql -d weather_ops)
-- PREREQUISITE SCRIPT: day2/weather_ops_pg.sql

-- 1. Check Database Buffer Cache Hit Ratio (Target: > 99.0%)
SELECT
    datname,
    blks_hit,
    blks_read,
    ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_ratio_pct
FROM pg_stat_database
WHERE datname = current_database();

-- 2. Inspect Table Size, Index Size, TOAST Size & Exact 8KB Heap Page Count
SELECT
    schemaname || '.' || relname                                               AS table_name,
    pg_relation_filepath(relid)                                                AS filepath,
    pg_size_pretty(pg_relation_size(relid))                                    AS heap_size,
    pg_size_pretty(pg_indexes_size(relid))                                     AS index_size,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid) - pg_indexes_size(relid)) AS toast_and_fsm_size,
    pg_size_pretty(pg_total_relation_size(relid))                              AS total_size,
    pg_relation_size(relid) / 8192                                             AS heap_8kb_pages
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

-- 3. MVCC Dead Tuple Bloat & Autovacuum Monitor
SELECT
    schemaname || '.' || relname AS table_name,
    n_live_tup,
    n_dead_tup,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_tuple_pct,
    n_tup_hot_upd,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- 4. Spot "Idle in Transaction" Sessions Blocking VACUUM
SELECT
    pid,
    usename,
    application_name,
    state,
    NOW() - xact_start   AS txn_duration,
    NOW() - state_change AS idle_duration,
    query
FROM pg_stat_activity
WHERE state IN ('idle in transaction', 'active')
ORDER BY xact_start ASC NULLS LAST;

-- 5. Real-Time Lock Contention Forensics (Who is Blocking Whom?)
SELECT
    blocked_activity.pid                 AS blocked_pid,
    blocked_activity.usename             AS blocked_user,
    blocked_activity.query               AS blocked_query,
    blocking_activity.pid                AS blocking_pid,
    blocking_activity.usename            AS blocking_user,
    blocking_activity.query              AS blocking_query,
    NOW() - blocked_activity.query_start AS waiting_duration
FROM pg_stat_activity AS blocked_activity
JOIN pg_locks AS blocked_locks
  ON blocked_locks.pid = blocked_activity.pid
JOIN pg_locks AS blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
 AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
 AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
 AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
 AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
 AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
 AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
 AND blocking_locks.pid != blocked_locks.pid
JOIN pg_stat_activity AS blocking_activity
  ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- 6. Emergency Cancel / Kill Stuck Backend PID
-- SELECT pg_cancel_backend(12345);    -- Graceful SIGINT (cancels current query)
-- SELECT pg_terminate_backend(12345); -- Forceful SIGTERM (closes connection & rolls back txn)
```

---

## 8. The 10-Layer PostgreSQL Performance Optimization Master Checklist

| Layer | Optimization Lever | Default / Anti-Pattern | Production Weather Tuning | Typical Speedup / Savings |
| :---: | :--- | :--- | :--- | :--- |
| **1. Hardware & OS** | Separate NVMe for `pg_wal` + `/etc/fstab` + `sysctl` | `$PGDATA` & `pg_wal` on 1 disk; `atime` on; `swappiness=60` | Dedicated `/data/pgwal` NVMe; `noatime,nodiratime`; `vm.swappiness=1`; `huge_pages=try` | **+25% read IOPS**; zero WAL `fsync()` contention |
| **2. Connections** | Transaction Pooler (`PgBouncer`) | `max_connections = 2000` (direct sensor connections) | `max_connections = 200` + **PgBouncer (`pool_mode = transaction`)** | **$3\times\text{–}5\times$ higher TPS** under 2,000-station bursts |
| **3. Memory Pool** | Dual-Tier RAM (`shared_buffers` + `work_mem`) | `shared_buffers = 128MB`, `work_mem = 4MB` (spills to disk) | `shared_buffers = 25% RAM` (`8GB`), `effective_cache_size = 75%` (`24GB`), `work_mem = 32MB–64MB` | **$10\times\text{–}20\times$ faster** `Hash Join` & `GROUP BY` (in-RAM) |
| **4. Tuple Layout** | **"Tuple Tetris"** Column Ordering | Alternating `BOOLEAN` (`1B`) and `BIGINT`/`TIMESTAMPTZ` (`8B`) | Order columns `8B` (`typalign='d'`) $\rightarrow$ `4B` $\rightarrow$ `2B` $\rightarrow$ `1B` (`UUID`, `BOOLEAN`) $\rightarrow$ `varlena` | **Saves 8–21 Bytes/row** (~21 GB per 1B rows!) |
| **5. Primary Keys** | Surrogate Key Locality (`BIGINT` / **`UUIDv7`**) | Random `UUIDv4` (`gen_random_uuid()`) or `VARCHAR(36)` (`37B`) | `BIGINT GENERATED ALWAYS AS IDENTITY` (`8B`) or **RFC 9562 `UUIDv7`** (`16B` native `UUID`) | **Eliminates 50/50 B-Tree splits** & **$500\times$ WAL `FPW` bloat** |
| **6. In-Page Updates** | **`HOT` Updates** & `TOAST` Compression | `fillfactor = 100` on heavily updated tables; `pglz` TOAST | `fillfactor = 80–90` on station status tables (no index on updated cols); `default_toast_compression = lz4` | **$5\times\text{–}10\times$ less index bloat**; $4\times$ faster TOAST decompression |
| **7. WAL & Checkpoints** | Checkpoint Smoothing & WAL Compression | `max_wal_size = 1GB`, `checkpoint_timeout = 5min` | `max_wal_size = 16GB–32GB`, `checkpoint_timeout = 15min`, `checkpoint_completion_target = 0.9`, `wal_compression = lz4` | **Eliminates 00Z/12Z I/O stalls**; cuts WAL volume by **40%–60%** |
| **8. Bulk Ingestion** | Binary `COPY` + Parallel Index Build | Row-by-row `INSERT` with active secondary B-Trees | `psycopg3` Binary **`COPY`** (`UNLOGGED` staging) + `max_parallel_maintenance_workers = 4` | **`800 rows/s` $\rightarrow$ `120,000+ rows/s`** (**$150\times$ speedup!**) |
| **9. Autovacuum** | Per-Table Scale Factor & Cost Limit | `autovacuum_vacuum_scale_factor = 0.20`, `cost_limit = 200` | `autovacuum_vacuum_scale_factor = 0.01–0.05`, `cost_limit = 2000`, `idle_in_transaction_session_timeout = 60s` | Prevents multi-GB dead-tuple table bloat & XID wraparound |
| **10. Planner & Indexes** | NVMe Cost + Partitioning + Covering / `BRIN` + `JIT` | `random_page_cost = 4.0`, monolithic B-Trees, `jit_above_cost = 100000` | `random_page_cost = 1.1`, `effective_io_concurrency = 200`, Monthly Partitions + `BRIN` + `INCLUDE` Covering Indexes + `jit_above_cost = 500000` (`plan_cache_mode = force_custom_plan` on skewed params) | **$100\times\text{–}1,800\times$ faster** point/range queries (`Heap Fetches: 0`) |

---

> **Navigation:** [Master README](../README.md) | [Interactive Portal](../bootcamp_portal.html) | [Reference Cards](../reference_cards/README.md) | [Day 1 Coursebook](../day1/day1_master_coursebook.md) | [Day 2 Coursebook](day2_master_coursebook.md) | [Day 3 Coursebook](../day3/day3_master_coursebook.md)


