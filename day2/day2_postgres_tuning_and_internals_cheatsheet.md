> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [⏮️ Day 1 Coursebook](../day1/day1_master_coursebook.md) | [📘 Day 2 Coursebook](day2_master_coursebook.md) | [⏭️ Day 3 Coursebook](../day3/day3_master_coursebook.md)

# Day 2 Master Cheatsheet: PostgreSQL Installation, Storage Internals, WAL, Vacuum, Locking & `EXPLAIN` Forensics

**Companion to:** [day2_master_coursebook.md](./day2_master_coursebook.md) | [day2_postgres_vs_mysql_mvcc_guide.md](./day2_postgres_vs_mysql_mvcc_guide.md) | [day2_pageinspect_and_storage_lab.sql](./day2_pageinspect_and_storage_lab.sql) | [day2_two_terminal_acid_lab.sql](./day2_two_terminal_acid_lab.sql)

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
# 5. QUERY PLANNER & PARALLEL EXECUTION (FOR NVMe & CLIMATOLOGY)
# =========================================================================
random_page_cost = 1.1                  # Default 4.0 assumes spinning HDDs! Set 1.1 for NVMe/SSD.
effective_io_concurrency = 200          # Prefetch concurrency for Bitmap Heap Scans on NVMe.

max_worker_processes = 8
max_parallel_workers_per_gather = 4     # Parallelizes Seq Scans, Hash Joins & Aggregations
max_parallel_workers = 8                # across CPU cores for multi-year climatology queries!

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
| **1-Byte / Packed** (Any offset) | `'c'` (`char`) | `BOOLEAN`, `"char"`, and short variable-length (`NUMERIC`, `VARCHAR`, `TEXT`, `JSONB` with 1B `varlena` header) |

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

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [⏮️ Day 1 Coursebook](../day1/day1_master_coursebook.md) | [📘 Day 2 Coursebook](day2_master_coursebook.md) | [⏭️ Day 3 Coursebook](../day3/day3_master_coursebook.md)

