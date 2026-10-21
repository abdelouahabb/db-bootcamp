# PostgreSQL Vacuum Mechanics: `VACUUM` vs. `VACUUM FULL` Reference Card

## Storage Engine Page Forensics, MVCC Dead Tuples, Locking Hierarchies, and Zero-Downtime Bloat Reclamation

> **Navigation:** [Bootcamp Home](../README.md) | [Reference Cards Index](./README.md) | [Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅ Previous Card](./07_wal_crash_recovery_sqlite_postgres_mysql.md) | **Card 08 of 14** | [Next Card](./09_acid_transactions_and_two_terminal_lock_debugging.md)

## Quick-Jump Table of Contents

- [Executive Summary for Systems & Database Engineers](#executive-summary-for-systems--database-engineers)
- [1. Physical Anatomy of Table Bloat Inside 8 KB Pages](#1-physical-anatomy-of-table-bloat-inside-8-kb-pages)
  - [1.1 The Lifecycle of a Dead Tuple](#11-the-lifecycle-of-a-dead-tuple)
- [2. Standard `VACUUM`: Concurrent In-Page Maintenance](#2-standard-vacuum-concurrent-in-page-maintenance)
  - [2.1 Locking Level: `ShareUpdateExclusiveLock`](#21-locking-level-shareupdateexclusivelock)
  - [2.2 What Standard `VACUUM` Actually Does:](#22-what-standard-vacuum-actually-does)
  - [2.3 The Core Limitation: Why Standard `VACUUM` Does Not Shrink Files](#23-the-core-limitation-why-standard-vacuum-does-not-shrink-files)
- [3. `VACUUM FULL`: Destructive Physical Heap Rewrite](#3-vacuum-full-destructive-physical-heap-rewrite)
  - [3.1 Locking Level: `AccessExclusiveLock` (The Complete Lockout)](#31-locking-level-accessexclusivelock-the-complete-lockout)
  - [3.2 What `VACUUM FULL` Physically Does:](#32-what-vacuum-full-physically-does)
  - [3.3 The Two Fatal Production Traps of `VACUUM FULL`:](#33-the-two-fatal-production-traps-of-vacuum-full)
- [4. Head-to-Head Architectural Matrix](#4-head-to-head-architectural-matrix)
- [5. Autovacuum Tuning: Preventing Bloat Before It Starts](#5-autovacuum-tuning-preventing-bloat-before-it-starts)
  - [5.1 The Mathematical Autovacuum Trigger](#51-the-mathematical-autovacuum-trigger)
  - [5.2 Production Autovacuum Hardening (`postgresql.conf`)](#52-production-autovacuum-hardening-postgresqlconf)
  - [5.3 Aggressive Per-Table Tuning for High-Churn Tables](#53-aggressive-per-table-tuning-for-high-churn-tables)
- [6. Zero-Downtime Alternatives to `VACUUM FULL`](#6-zero-downtime-alternatives-to-vacuum-full)
  - [6.1 Strategy A: Native Declarative Partitioning (The Cleanest Solution)](#61-strategy-a-native-declarative-partitioning-the-cleanest-solution)
  - [6.2 Strategy B: `pg_repack` (Online Table Compaction)](#62-strategy-b-pg_repack-online-table-compaction)
- [7. Hands-On Forensics & Diagnostic SQL Lab](#7-hands-on-forensics--diagnostic-sql-lab)
  - [Step 1: Install `pgstattuple` for Physical Bloat Inspection](#71-step-1-install-pgstattuple-for-physical-bloat-inspection)
  - [Step 2: Create a Demo Table and Synthesize 500,000 Rows](#72-step-2-create-a-demo-table-and-synthesize-500000-rows)
  - [Step 3: Generate Severe Table Bloat (Update 80% of Rows)](#73-step-3-generate-severe-table-bloat-update-80-of-rows)
  - [Step 4: Run Standard `VACUUM` and Observe Disk Footprint](#74-step-4-run-standard-vacuum-and-observe-disk-footprint)
  - [Step 5: Run `VACUUM FULL` and Observe Disk Compaction](#75-step-5-run-vacuum-full-and-observe-disk-compaction)
- [8. Summary Checklist: Production Vacuum Rules](#8-summary-checklist-production-vacuum-rules)

---

### Executive Summary for Systems & Database Engineers

PostgreSQL implements **Multi-Version Concurrency Control (MVCC)** via an out-of-place tuple append architecture. When an application executes an `UPDATE` or `DELETE`, PostgreSQL does not overwrite or remove the row in-place on the underlying $8\text{ KB}$ disk page. Instead:

* **`DELETE`:** Sets the tuple header's `t_xmax` to the deleting transaction's ID ($\text{XID}$), marking the row as invisible to future transactions.

* **`UPDATE`:** Marks the existing tuple dead (`t_xmax = XID`) and inserts an entirely new tuple version elsewhere in the heap.

These defunct row versions are called **dead tuples**. Over time, dead tuples cause **table and index bloat**, which degrades sequential scan performance, wastes RAM buffer pool space, and exhausts disk capacity.

The database provides two fundamentally different operations to clean up dead tuples: **Standard `VACUUM`** (often called "Lazy" or "Concurrent" Vacuum) and **`VACUUM FULL`**. Conflating the two in production can cause catastrophic table locking, service outages, and out-of-space crashes.

```
                    The MVCC Bloat & Vacuuming Spectrum
                    
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ ACTIVE PRODUCTION HEAP (8 KB Pages containing live and dead tuples)         │
 └──────────────────────┬──────────────────────────────┬───────────────────────┘
                        │                              │
         STANDARD `VACUUM`                             │ `VACUUM FULL`
         (Concurrent Maintenance)                      │ (Destructive Rewrite)
                        ▼                              ▼
 ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐
 │ • Lock: `ShareUpdateExclusiveLock`      │   │ • Lock: `AccessExclusiveLock`           │
 │ • Reads & Writes: FULLY ALLOWED         │   │ • Reads & Writes: TOTALLY BLOCKED       │
 │ • Disk Reclamation: REUSES EMPTY SLOTS  │   │ • Disk Reclamation: RETURNS TO LINUX OS │
 │   DOES NOT return disk space to OS!     │   │   Reclaims 100% of dead bloat.          │
 │ • Strategy: Reclaims space within 8 KB  │   │ • Strategy: Rewrites entire table to a  │
 │   pages for future `INSERT`s via FSM.   │   │   brand new physical file on disk.      │
 └─────────────────────────────────────────┘   └─────────────────────────────────────────┘

```

## 1. Physical Anatomy of Table Bloat Inside 8 KB Pages

To understand why standard `VACUUM` cannot shrink physical disk files, we must examine the internal structure of an $8\text{ KB}$ heap page:

```
 0 bytes ┌─────────────────────────────────────────────────────────────┐
         │ PageHeaderData (24 bytes)                                   │
         ├─────────────────────────────────────────────────────────────┤
         │ ItemIdData Array (Line Pointers: lp1, lp2, lp3, lp4)        │
         │  • lp1: points to Live Tuple A (Offset 8096, Length 96B)    │
         │  • lp2: points to DEAD Tuple B (Deleted via t_xmax)         │
         │  • lp3: points to Live Tuple C (Offset 7800, Length 120B)   │
         ├─────────────────────────────────────────────────────────────┤
         │                     FREE SPACE HOLE                         │
         │          (Available for new tuple allocations)              │
         ├─────────────────────────────────────────────────────────────┤
         │ Tuple C (LIVE): offset 7800                                 │
         ├─────────────────────────────────────────────────────────────┤
         │ Tuple B (DEAD - Obsolete row version taking physical bytes!)│
         ├─────────────────────────────────────────────────────────────┤
         │ Tuple A (LIVE): offset 8096                                 │
 8192 B  └─────────────────────────────────────────────────────────────┘

```

### 1.1 The Lifecycle of a Dead Tuple

1. An operational weather observation is deleted or updated.

2. The row remains physically stored on the disk block. It cannot be deleted immediately because concurrent transactions that started earlier may still need to read it (Snapshot Isolation).

3. Once all transactions that could view that old version terminate, the tuple becomes **dead** (safe for reclamation).

4. If millions of updates occur across the table, thousands of $8\text{ KB}$ pages become populated by $80\%$ dead tuples and only $20\%$ live tuples. This is **table bloat**.

## 2. Standard `VACUUM`: Concurrent In-Page Maintenance

When you execute `VACUUM table_name;` (or when background `autovacuum` runs):

### 2.1 Locking Level: `ShareUpdateExclusiveLock`

* **Non-Blocking Operation:** Standard `VACUUM` runs concurrently with active production workloads.

* **Allows:** `SELECT`, `INSERT`, `UPDATE`, and `DELETE`.

* **Conflicts with:** DDL commands that change table structure (`ALTER TABLE`, `DROP TABLE`, `CREATE INDEX`, `VACUUM FULL`).

### 2.2 What Standard `VACUUM` Actually Does:

1. **Marks Dead Space:** Scans the table heap, identifies dead tuples whose `t_xmax` is older than the oldest running transaction, and marks their line pointers as dead (`LP_DEAD`) or unused (`LP_UNUSED`).

2. **Defragments the** $8\text{ KB}$ **Block:** Compacts live tuples to the bottom of the page, turning fragmented spaces into a single contiguous free-space window within that specific block.

3. **Updates the Free Space Map (`_fsm`):** Records how many free bytes are now available inside that block into the table's auxiliary Free Space Map fork. When new rows are inserted, PostgreSQL consults the `_fsm` and writes the new rows into those empty slots **instead of allocating new pages**.

4. **Updates the Visibility Map (`_vm`):** Marks pages that contain exclusively live tuples visible to all current transactions. This enables high-speed **Index-Only Scans** (the engine avoids touching the table heap altogether).

5. **Transaction ID Freezing (`relfrozenxid`):** Freezes transaction IDs older than `vacuum_freeze_min_age` (replaces `xmin` with a special `FrozenTransactionId` bit). This prevents **Transaction ID (XID) Wraparound**, a fatal scenario where old transactions loop past the $2^{31}$ limit and historic rows become invisible.

### 2.3 The Core Limitation: Why Standard `VACUUM` Does Not Shrink Files

```
  Page 0: [Live][Dead][Live]   ──Standard Vacuum──>   Page 0: [Live][Free][Live] (Still 8 KB!)
  Page 1: [Dead][Dead][Live]   ──Standard Vacuum──>   Page 1: [Free][Free][Live] (Still 8 KB!)
  Page 2: [Live][Dead][Dead]   ──Standard Vacuum──>   Page 2: [Live][Free][Free] (Still 8 KB!)

```

* Standard `VACUUM` **never moves live tuples from one page to another**. Because a single live tuple remains on Page 0, Page 1, and Page 2, the underlying file cannot be shortened.

* **The Only Exception (Tail Truncation):** If pages at the very physical end (EOF) of the file become $100\%$ empty, `VACUUM` acquires a momentary lock on the tail pages and calls `ftruncate()` to return those tail blocks to Linux. However, if a single live tuple resides on the last block of a $500\text{ GB}$ file, **zero bytes are returned to the operating system**.

## 3. `VACUUM FULL`: Destructive Physical Heap Rewrite

When you execute `VACUUM FULL table_name;`:

```
                           The VACUUM FULL Physical Rewrite
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ OLD TABLE FILE: base/16384/28491 (Bloated: 100 GB on disk)                  │
 │ [Live Tuple A] [Dead] [Dead] [Live Tuple B] [Dead] ...                      │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │ Copies ONLY Live Tuples sequentially!
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ NEW TABLE FILE: base/16384/39201 (Compacted: 20 GB on disk)                 │
 │ [Live Tuple A] [Live Tuple B] [Live Tuple C] ...                            │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ├─► Swaps filenode pointer in pg_class
                                        ├─► Rebuilds ALL indexes from scratch
                                        └─► Unlinks & deletes old 100 GB file

```

### 3.1 Locking Level: `AccessExclusiveLock` (The Complete Lockout)

* **The Heaviest Lock in PostgreSQL:** Equivalent to an aggressive `ALTER TABLE` or `DROP TABLE`.

* **Blocks Everything:** All `SELECT`, `INSERT`, `UPDATE`, and `DELETE` queries are placed in an operating system wait queue.

* **The Lock Cascade Danger:** If a long-running analytical query is active, `VACUUM FULL` waits behind it. Meanwhile, every subsequent read/write query sent by applications queues behind `VACUUM FULL`, exhausting PostgreSQL's `max_connections` and taking the entire platform down.

### 3.2 What `VACUUM FULL` Physically Does:

1. **Creates a Fresh File:** Allocates a brand-new physical file on disk with a new `relfilenode`.

2. **Sequentially Migrates Live Tuples:** Reads the old table, ignores every dead tuple, and packs live tuples contiguously into fresh $8\text{ KB}$ pages with zero fragmentation.

3. **Rebuilds All Indexes:** Drops the old index trees and builds completely new B-Trees, BRIN, or GiST indexes from scratch.

4. **Atomically Swaps File Nodes:** Updates the system catalog (`pg_class.relfilenode`) to point to the new compacted file.

5. **Deletes the Old File:** Unlinks the old bloated file from disk, immediately returning physical gigabytes to the Linux filesystem.

### 3.3 The Two Fatal Production Traps of `VACUUM FULL`:

1. **The** $2\times$ **Disk Space Requirement:** Because PostgreSQL builds the entire new table and its indexes alongside the old table before deleting the original, you must have **more free disk space available than the size of the table**. If an $80\text{ GB}$ table sits on a disk with $50\text{ GB}$ of remaining free space, `VACUUM FULL` will fill the disk to $100\%$, abort with an out-of-space error, roll back the transaction, and potentially crash the database.

2. **Downtime Duration:** Compacting a multi-hundred-gigabyte table and rebuilding indexes can take hours. During this entire window, all applications querying that table are blocked.

## 4. Head-to-Head Architectural Matrix

| Dimension | Standard `VACUUM` | `VACUUM FULL` | 
| ----- | ----- | ----- | 
| **Lock Acquired** | `ShareUpdateExclusiveLock` | `AccessExclusiveLock` (Exclusive) | 
| **Concurrent Reads (`SELECT`)** | **Allowed** (Zero interruption) | **BLOCKED** | 
| **Concurrent Writes (`INSERT/UPDATE`)** | **Allowed** (Zero interruption) | **BLOCKED** | 
| **Physical Disk Reclamation to OS** | **No** (Only if tail pages are empty) | **Yes** (100% of bloat reclaimed) | 
| **Reclamation Strategy** | Marks tuples dead; updates `_fsm` for reuse | Rewrites entire table to a new `relfilenode` | 
| **Index Handling** | Vacuums dead index keys; leaves tree intact | **Rebuilds all indexes from scratch** | 
| **Extra Disk Space Required** | Negligible ($\approx 0\text{ bytes}$) | $\ge 100\%$ **of table + index size** | 
| **Execution Duration** | Background (throttled by cost limits) | Long-running sequential rewrite | 
| **Transaction Wraparound Safety** | **Yes** (Freezes old `XID`s) | **Yes** (Freezes old `XID`s) | 
| **Recommended Production Use** | **Continuous Automated Default** | **Avoid in Live Production** | 

## 5. Autovacuum Tuning: Preventing Bloat Before It Starts

In high-throughput meteorological or telemetry pipelines, bloat occurs when the background autovacuum daemon cannot keep up with incoming row mutations.

### 5.1 The Mathematical Autovacuum Trigger

PostgreSQL triggers an autovacuum run on a table when the number of dead tuples exceeds:

$$
\text{Trigger Threshold} = \text{autovacuum\_vacuum\_threshold} + (\text{autovacuum\_vacuum\_scale\_factor} \times \text{reltuples})
$$

* **Defaults:** `autovacuum_vacuum_threshold = 50`, `autovacuum_vacuum_scale_factor = 0.2` ($20\%$).

* **The Failure at Scale:** On a table with $100,000,000$ weather observations, autovacuum will not start until **20,000,050 dead tuples** accumulate! By that time, the table has bloated by tens of gigabytes.

### 5.2 Production Autovacuum Hardening (`postgresql.conf`)

```
# 1. Increase worker parallelism and memory
autovacuum_max_workers = 5             # Scale workers across CPU cores
maintenance_work_mem = 1GB             # Memory pool per worker for dead tuple pointers

# 2. Lower table-wide trigger scale factor
autovacuum_vacuum_scale_factor = 0.05  # Trigger at 5% dead tuples instead of 20%
autovacuum_vacuum_threshold = 1000

# 3. Eliminate I/O Throttling Bottlenecks
# Modern NVMe drives can process thousands of IOPS; default limits are calibrated for slow HDDs!
autovacuum_vacuum_cost_limit = 2000    # Raise from default (200) to speed up scans
autovacuum_vacuum_cost_delay = 2ms     # Lower delay between I/O cost budget resets

```

### 5.3 Aggressive Per-Table Tuning for High-Churn Tables

For specific operational tables experiencing heavy updates (e.g., active storm alerts or station status registers):

```
ALTER TABLE station_live_status SET (
    autovacuum_vacuum_scale_factor = 0.01, -- Trigger at 1% dead tuples
    autovacuum_vacuum_cost_limit = 5000,   -- Grant maximum I/O throughput
    autovacuum_vacuum_cost_delay = 0       -- Zero sleep throttling
);

```

## 6. Zero-Downtime Alternatives to `VACUUM FULL`

When a production table is heavily bloated, but you cannot afford downtime or exclusive locks, use these alternatives:

### 6.1 Strategy A: Native Declarative Partitioning (The Cleanest Solution)

As established in Day 3, avoid deleting millions of historical rows with `DELETE`. Use **Range Partitioning by Month**:

```
-- Instant O(1) space reclamation with ZERO vacuuming:
ALTER TABLE raw_telemetry_partitioned DETACH PARTITION telemetry_y2026m09;
DROP TABLE telemetry_y2026m09;

```

* **Impact:** Reclaims $100\%$ of disk space immediately, generates zero dead tuples, and requires zero vacuuming.

### 6.2 Strategy B: `pg_repack` (Online Table Compaction)

[`pg_repack`](https://github.com/reorg/pg_repack) is the industry-standard extension for compacting bloated tables online without holding an exclusive lock.

```
                           The pg_repack Online Workflow
 1. Creates a shadow table copying all live tuples from the target table.
 2. Creates a log table and attaches triggers to the target table to capture
    all ongoing INSERT, UPDATE, and DELETE queries during the copy.
 3. Builds new indexes on the shadow table.
 4. Replays all captured trigger modifications onto the shadow table.
 5. Momentarily acquires an exclusive lock (< 50 ms) to swap catalog pointers.
 6. Drops the old bloated table.

```

#### 6.2.1 How to Run `pg_repack`:

```
# Repack a specific table online with zero downtime
pg_repack -h localhost -U postgres -d weather_ops_db -t raw_telemetry

```

## 7. Hands-On Forensics & Diagnostic SQL Lab

Run this reproducible laboratory in `psql` to measure the physical difference between `VACUUM` and `VACUUM FULL`.

### 7.1 Step 1: Install `pgstattuple` for Physical Bloat Inspection

```
CREATE EXTENSION IF NOT EXISTS pgstattuple;

```

### 7.2 Step 2: Create a Demo Table and Synthesize 500,000 Rows

```
DROP TABLE IF EXISTS bloat_lab;
CREATE TABLE bloat_lab (
    id SERIAL PRIMARY KEY,
    station_id VARCHAR(10),
    reading DOUBLE PRECISION,
    padding TEXT
);

-- Insert 500,000 rows
INSERT INTO bloat_lab (station_id, reading, padding)
SELECT 
    'AWS-' || LPAD((g % 50)::TEXT, 3, '0'),
    random() * 40.0,
    repeat('X', 128) -- Add byte payload to inflate row size
FROM generate_series(1, 500000) AS g;

-- Check initial size
SELECT pg_size_pretty(pg_total_relation_size('bloat_lab')) AS initial_size;
-- Typical Output: ~105 MB

```

### 7.3 Step 3: Generate Severe Table Bloat (Update 80% of Rows)

```
-- Updating rows creates 400,000 DEAD tuples!
UPDATE bloat_lab SET reading = reading + 1.0 WHERE id > 100000;

-- Inspect dead tuples and table bloat via pgstattuple
SELECT 
    table_len AS total_bytes,
    tuple_count AS live_tuples,
    dead_tuple_count AS dead_tuples,
    ROUND(dead_tuple_percent::numeric, 2) AS dead_pct,
    ROUND(free_percent::numeric, 2) AS free_pct
FROM pgstattuple('bloat_lab');

```

*Notice:* The table file has expanded to $\approx 185\text{ MB}$, and `dead_pct` reports over $40\%\text{--}50\%$.

### 7.4 Step 4: Run Standard `VACUUM` and Observe Disk Footprint

```
\timing on
VACUUM bloat_lab;
\timing off

-- Check size again
SELECT pg_size_pretty(pg_total_relation_size('bloat_lab')) AS size_after_vacuum;

```

* **The Result:** The physical file size **remains** $\approx 185\text{ MB}$. It did NOT shrink.

* Run `SELECT * FROM pgstattuple('bloat_lab');` again: `dead_tuples` is now 0, but `free_percent` has jumped to $\approx 45\%$. The space is freed inside the $8\text{ KB}$ pages and registered in the `_fsm`, but the file remains inflated on the Linux filesystem.

### 7.5 Step 5: Run `VACUUM FULL` and Observe Disk Compaction

```
\timing on
VACUUM FULL bloat_lab;
\timing off

-- Check size again
SELECT pg_size_pretty(pg_total_relation_size('bloat_lab')) AS size_after_vacuum_full;

```

* **The Result:** The table shrinks from $185\text{ MB}$ down to $\approx 105\text{ MB}$, and the operating system immediately reclaims $80\text{ MB}$ of physical disk space.

## 8. Summary Checklist: Production Vacuum Rules

```
================================================================================
                    POSTGRESQL VACUUM PRODUCTION RULES
================================================================================
 1. Never Run VACUUM FULL Live : It takes an AccessExclusiveLock that blocks ALL
                                 reads and writes across the entire table.
 2. Check 2x Free Disk Space   : VACUUM FULL creates a complete second copy of the
                                 table; if free space < table size, it crashes!
 3. Use pg_repack Online       : If a production table has > 30% bloat, use pg_repack
                                 to reclaim space online with zero read/write locks.
 4. Tune Autovacuum Scale      : Drop autovacuum_vacuum_scale_factor from 0.20 to
                                 0.05 on large tables so cleaning starts early.
 5. Partition to Avoid Deletes : Use monthly declarative partitions; dropping old
                                 partitions via DETACH + DROP eliminates bloat entirely.
 6. Standard VACUUM Reuses     : Standard VACUUM does not shrink files on disk, but
                                 it enables PostgreSQL to reuse empty space for inserts.
================================================================================

```
---

### 8.1 Reference Library Navigation

> **Navigation:** [Bootcamp Home](../README.md) | [Reference Cards Index](./README.md) | [Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅ Previous Card](./07_wal_crash_recovery_sqlite_postgres_mysql.md) | **Card 08 of 14** | [Next Card](./09_acid_transactions_and_two_terminal_lock_debugging.md) | [⬆ Back to Top](#postgresql-vacuum-mechanics-vacuum-vs-vacuum-full-reference-card)
