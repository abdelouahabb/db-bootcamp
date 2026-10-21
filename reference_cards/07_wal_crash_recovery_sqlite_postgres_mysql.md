# Deep-Dive Engineering Guide: Write-Ahead Logging (WAL) & Crash Recovery Mechanics

## A Comparative Architectural Study Across SQLite, PostgreSQL, and MySQL / MariaDB

> **Navigation:** [Bootcamp Home](../README.md) | [Reference Cards Index](./README.md) | [Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅ Previous Card](./06_dbt_for_meteorological_telemetry_engineering.md) | **Card 07 of 14** | [Next Card](./08_postgresql_vacuum_vs_vacuum_full_and_bloat.md)

## Quick-Jump Table of Contents

- [Executive Summary](#executive-summary)
- [1. The Core Theoretical Problem: Why Databases Cannot Just Write to Disk](#1-the-core-theoretical-problem-why-databases-cannot-just-write-to-disk)
  - [1.1 The Hardware I/O Impedance Mismatch](#11-the-hardware-io-impedance-mismatch)
  - [1.2 The ARIES Recovery Matrix (Steal / No-Force)](#12-the-aries-recovery-matrix-steal--no-force)
  - [1.3 The Torn-Page Hazard](#13-the-torn-page-hazard)
- [2. SQLite: Rollback Journal vs. Write-Ahead Logging (WAL)](#2-sqlite-rollback-journal-vs-write-ahead-logging-wal)
  - [2.1 The Classical Rollback Journal (`journal_mode`)](#21-the-classical-rollback-journal-journal_mode)
  - [2.2 The SQLite WAL Engine (`PRAGMA journal_mode = WAL;`)](#22-the-sqlite-wal-engine-pragma-journal_mode--wal)
- [3. PostgreSQL: The Monolithic Enterprise WAL Architecture](#3-postgresql-the-monolithic-enterprise-wal-architecture)
  - [3.1 The Log Sequence Number ($\text{LSN}$) and 8 KB Page Synchronization](#31-the-log-sequence-number-textlsn-and-8-kb-page-synchronization)
  - [3.2 The Checkpoint Mechanism & Smoothing](#32-the-checkpoint-mechanism--smoothing)
  - [3.3 The Torn-Page Solution: `full_page_writes`](#33-the-torn-page-solution-full_page_writes)
  - [3.4 PostgreSQL Alternatives & Bypasses to WAL](#34-postgresql-alternatives--bypasses-to-wal)
- [4. MySQL / MariaDB: InnoDB, MyISAM, Aria, and LSM Engines](#4-mysql--mariadb-innodb-myisam-aria-and-lsm-engines)
  - [4.1 MySQL InnoDB: The Tri-Part Durability Architecture](#41-mysql-innodb-the-tri-part-durability-architecture)
  - [4.2 Legacy MyISAM: The "No-WAL" Anti-Pattern](#42-legacy-myisam-the-no-wal-anti-pattern)
  - [4.3 MariaDB Aria: The Modern Crash-Safe MyISAM Replacement](#43-mariadb-aria-the-modern-crash-safe-myisam-replacement)
  - [4.4 MyRocks (RocksDB): Log-Structured Merge (LSM) Architecture](#44-myrocks-rocksdb-log-structured-merge-lsm-architecture)
- [5. Master Comparative Architecture Matrix](#5-master-comparative-architecture-matrix)
- [6. Hands-On Operational Profiling Labs](#6-hands-on-operational-profiling-labs)
  - [Lab 1: SQLite Journal Mode Benchmark (100,000 Ingest Rows)](#61-lab-1-sqlite-journal-mode-benchmark-100000-ingest-rows)
  - [Lab 2: PostgreSQL Ingestion Stress (Logged vs. Unlogged vs. Async Commit)](#62-lab-2-postgresql-ingestion-stress-logged-vs-unlogged-vs-async-commit)
  - [Lab 3: Inspecting SQLite Shared Memory & WAL Checkpoint State](#63-lab-3-inspecting-sqlite-shared-memory--wal-checkpoint-state)
- [7. Summary Checklist for Systems & Weather Telemetry Architects](#7-summary-checklist-for-systems--weather-telemetry-architects)

---

### Executive Summary

Every relational database management system (RDBMS) confronts a fundamental hardware dilemma: **how to guarantee transaction Durability (**$D$ **in ACID) without destroying write throughput on slow, random-access physical storage.**

If a database modified table heap files directly on every transaction commit, disk heads would thrash across millions of disparate data blocks, throughput would crater to tens of operations per second, and a power failure mid-write would irrevocably corrupt storage pages (torn pages).

The universal solution across modern database engineering is **Write-Ahead Logging (WAL)**: serializing changes to an append-only sequential log before modifying multi-dimensional table pages. However, different engines implement this paradigm with fundamentally distinct trade-offs:

1. **SQLite:** Transitioned from legacy **Rollback Journals** (`.db-journal`) that halt all concurrent readers during writes to **WAL mode** (`.db-wal` + `.db-shm`), enabling true concurrent multi-reader, single-writer throughput.

2. **PostgreSQL:** Implements an enterprise monolithic WAL stream (`pg_wal/`) tied to 64-bit Log Sequence Numbers ($\text{LSN}$) with full-page torn write protection (`full_page_writes`), alongside zero-log ephemeral alternatives (`UNLOGGED TABLES`).

3. **MySQL (InnoDB) & MariaDB (Aria/InnoDB):** Decouples recovery into a tri-part logging architecture: a circular **Redo Log** for durability, a **Doublewrite Buffer** to eliminate physical sector tearing, and an **Undo Tablespace** for rollback segments and MVCC, contrasting sharply with legacy unlogged engines like MyISAM.

## 1. The Core Theoretical Problem: Why Databases Cannot Just Write to Disk

### 1.1 The Hardware I/O Impedance Mismatch

Computer storage media—whether spinning magnetic disks or solid-state NVMe drives—have fundamentally different throughput profiles for sequential versus random operations:

* **Sequential Append-Only Writes:** Disk controllers and flash translation layers (FTL) stream contiguous sectors at maximum bus bandwidth (e.g., $3,000\text{–}7,000\text{ MB/s}$ on PCIe Gen 4 NVMe).

* **Random 8 KB / 16 KB In-Place Page Mutations:** Writing directly to scattered table and B-Tree index pages requires read-modify-write cycles, metadata flushes, and random flash block erasures, degrading throughput to a fraction of wire speed.

### 1.2 The ARIES Recovery Matrix (Steal / No-Force)

In 1992, C. Mohan published the seminal **ARIES** (*Algorithms for Recovery and Isolation Exploiting Semantics*) framework, defining how database buffer managers handle memory pages during transaction commits:

```
                       The Buffer Management Design Matrix
                          
                             CAN THE ENGINE EVECT DIRTY PAGES
                                 OF UNCOMMITTED TRANSACTIONS?
                                     (Steal vs. No-Steal)
                                  NO                      YES
                      ┌───────────────────────┬───────────────────────┐
                   NO │       NO-FORCE        │   NO-FORCE / STEAL    │
                      │      / NO-STEAL       │   (Standard Modern    │
   DOES COMMIT REQUIRE│                       │    RDBMS Engine:      │
    FLUSHING ALL DIRTY│ • No REDO Log needed  │    PostgreSQL, InnoDB,│
        PAGES TO DISK?│ • No UNDO Log needed  │    SQLite WAL)        │
   (Force vs. No-Force│ • Destroys RAM pool   │ • Requires REDO (WAL) │
                      ├───────────────────────┼───────────────────────┤
                  YES │        FORCE          │        FORCE          │
                      │      / NO-STEAL       │       / STEAL         │
                      │ • Extreme disk wait   │ • Extreme disk wait   │
                      │ • High I/O stall      │ • Requires UNDO log   │
                      └───────────────────────┴───────────────────────┘

```

Modern database engines (PostgreSQL, MySQL InnoDB, SQLite in WAL mode) operate on a **STEAL / NO-FORCE** policy:

* **STEAL (Memory Scalability):** If memory is exhausted, the buffer manager *can steal* a dirty memory page containing modifications from an uncommitted transaction and write it to disk to free RAM. **Consequence:** The engine requires an **UNDO mechanism** to roll back those dirty changes if the transaction ultimately aborts.

* **NO-FORCE (Write Throughput):** When a transaction issues `COMMIT`, the engine *does not force* the dirty table pages to disk. It writes only a minimal, sequential transaction log record. **Consequence:** The engine requires a **REDO mechanism (the WAL)** to replay committed changes if power cuts before dirty pages migrate from memory to table files.

### 1.3 The Torn-Page Hazard

Physical disk controllers and filesystem blocks write data in physical sectors (traditionally $512\text{ bytes}$, modern Advanced Format drives use $4096\text{ bytes} = 4\text{ KB}$).

* A PostgreSQL page is **8 KB** ($2 \times 4\text{ KB}$ sectors).

* An InnoDB page is **16 KB** ($4 \times 4\text{ KB}$ sectors).

If electrical power cuts while the disk controller is halfway through writing the second $4\text{ KB}$ sector of an 8 KB page, the page is left in a **fractured state (torn page)**. The operating system cannot repair this because internal page checksums fail and page header pointers are misaligned. Recovery architectures must explicitly solve this physical reality.

## 2. SQLite: Rollback Journal vs. Write-Ahead Logging (WAL)

SQLite is unique: it is an in-process, serverless library operating over a single database file. Its evolution from Rollback Journals to WAL represents the canonical case study in concurrency trade-offs.

```
                      SQLite Storage Architecture Comparison
                      
   A. Legacy Rollback Journal (DELETE/TRUNCATE)    B. Write-Ahead Log (WAL Mode)
   
     weather.db            weather.db-journal        weather.db            weather.db-wal
   ┌────────────┐         ┌─────────────────┐      ┌────────────┐         ┌─────────────────┐
   │ Table Page │         │ Original Copies │      │ Immutable  │         │ New Appended    │
   │ Mutated in │         │ of modified     │      │ Baseline   │         │ Commits/Frames  │
   │ Place      │         │ pages for abort │      │ Pages      │         │ (Sequential)    │
   └────────────┘         └─────────────────┘      └────────────┘         └─────────────────┘
         ▲                                                ▲                      ▲
         │                                                │                      │
   EXCLUSIVE LOCK:                                  READERS: Read baseline ┌─────┴──────┐
   Readers BLOCKED by Writer                        merged with WAL frames │ weather.db │
   Writers BLOCKED by Readers                       WRITER: Appends to WAL │    -shm    │
                                                    Readers NEVER block    │Shared Memory│
                                                    Writers!               └────────────┘

```

### 2.1 The Classical Rollback Journal (`journal_mode`)

Before SQLite 3.7.0, all crash safety relied on **Rollback Journals**.

#### 2.1.1 How a Rollback Write Transaction Works:

1. **Acquire Shared Lock:** SQLite establishes a shared read lock on `weather.db`.

2. **Elevate to Reserved Lock:** When a write (`INSERT`/`UPDATE`) begins, the engine acquires a `RESERVED` lock. New readers can continue reading, but other writers are rejected.

3. **Create the Journal File:** SQLite creates a secondary file on disk: `weather.db-journal`.

4. **Copy Original Pages (The Undo Step):** Before modifying any page in `weather.db`, the unmodified original 4 KB page is read from `weather.db` and written into `weather.db-journal`.

5. **Acquire Exclusive Lock:** SQLite promotes the lock to `EXCLUSIVE`. **All concurrent readers are now completely blocked.**

6. **Mutate Database In-Place:** SQLite writes the new data directly into the master `weather.db` file.

7. **Commit & Cleanup:** The journal file is deleted or truncated. Once the journal is gone, the transaction is permanently committed. If the system crashes mid-write, the next boot sees `weather.db-journal` on disk, copies the old pages back into `weather.db`, and restores pre-crash state.

#### 2.1.2 Rollback Journal Pragmas & Variants:

| PRAGMA Setting | Mechanics & Disk Behavior | Failure Risk Profile | Use Case | 
| ----- | ----- | ----- | ----- | 
| `PRAGMA journal_mode = DELETE;` | Default. Creates `.db-journal` on write, deletes on commit. Heavy directory metadata I/O. | Full ACID crash safety. High filesystem metadata write amplification. | Desktop applications, legacy defaults. | 
| `PRAGMA journal_mode = TRUNCATE;` | Overwrites journal file and truncates length to 0 bytes instead of deleting. | Full ACID crash safety. Faster than `DELETE` on systems with slow directory indexing. | Embedded systems with slow flash metadata updates. | 
| `PRAGMA journal_mode = PERSIST;` | Leaves journal file on disk; zeroes out the journal header to invalidate it. | Full ACID crash safety. Eliminates file creation/deletion churn. | Automotive / aerospace flash media. | 
| `PRAGMA journal_mode = MEMORY;` | Keeps rollback journal in volatile RAM. Never writes journal to disk. | **Crash Unsafety:** If process crashes, DB rolls back safely. If host loses power, DB corrupts. | Ephemeral scratchpads, fast unit testing. | 
| `PRAGMA journal_mode = OFF;` | **Completely disables journaling.** Writes directly to disk in-place. | **High Corruption Risk:** Any power outage mid-write destroys the database file permanently. | High-speed initial bulk ingest where DB can be regenerated on failure. | 

### 2.2 The SQLite WAL Engine (`PRAGMA journal_mode = WAL;`)

Introduced in SQLite 3.7.0, WAL mode fundamentally transforms SQLite concurrency:

$$
\text{Concurrency Rule in WAL Mode} \implies \text{Readers do not block Writers} \land \text{Writers do not block Readers}
$$

#### 2.2.1 The Physical File Topology:

When WAL is enabled, SQLite creates two auxiliary files alongside `weather.db`:

* **`weather.db-wal`:** The physical sequential log containing committed frames.

* **`weather.db-shm`:** The **Shared Memory Index**. A memory-mapped file used as an index into the WAL so reader processes can locate the newest version of any page without scanning the `.db-wal` file sequentially.

#### 2.2.2 The Transaction Execution Flow in WAL:

1. **Append-Only Write:** When writing, the original `weather.db` file is left completely untouched. The new 4 KB page is appended as a **frame** to `weather.db-wal`.

2. **Commit Record:** A commit is executed simply by writing a frame with a non-zero commit marker to the end of the WAL and calling `fsync()` on the WAL file.

3. **Read Path Isolation:** When a reader executes a query, it notes the latest valid commit mark in the WAL (the "Read-Mark"). If page 42 was modified in the WAL, the reader fetches page 42 from `weather.db-wal`. If page 43 was untouched, the reader fetches it from `weather.db`.

```
                  SQLite WAL Checkpoint Propagation
 ┌─────────────────────────────────────────────────────────────┐
 │ weather.db (Master Baseline Database File)                 │
 │ [ Page 1 ]   [ Page 2 ]   [ Page 3 ]   [ Page 4 ]           │
 └──────────────────────▲──────────────────────────────────────┘
                        │
                        │ Checkpoint Worker moves dirty frames
                        │ from WAL back to base DB file
                        │
 ┌──────────────────────┴──────────────────────────────────────┐
 │ weather.db-wal (Append-Only Transaction Stream)             │
 │ [ Frame 1: P2 ] ──> [ Frame 2: P4 ] ──> [ Frame 3: P2 ]     │
 └─────────────────────────────────────────────────────────────┘

```

#### 2.2.3 Checkpointing (`PRAGMA wal_checkpoint`) & Companion WAL Pragmas

Because appending to the WAL causes `.db-wal` to grow continuously, SQLite periodically migrates committed 4 KB frames back into the master `weather.db` file via **checkpointing**. Every execution of `PRAGMA wal_checkpoint(<MODE>);` returns a single diagnostic row with **three integers** `(busy, log, checkpointed)`:
- **`busy` (`0` or `1`):** `0` if the checkpoint completed without blocking; `1` if an active concurrent reader or writer prevented completion.
- **`log` (Integer):** Total number of modified 4 KB frames currently residing inside `.db-wal`.
- **`checkpointed` (Integer):** Number of frames successfully copied from `.db-wal` back into the main `.db` file *(if `checkpointed < log`, an active reader is holding a "Read-Mark" on an older snapshot)*.

| Checkpoint Mode / Pragma | SQL Syntax | Blocks Writers / Readers? | Rewinds WAL Write Pointer to Byte `0`? | Truncates `.db-wal` on Disk? | Operational Use Case |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **`PASSIVE`** *(Auto-Checkpoint Default)* | `PRAGMA wal_checkpoint(PASSIVE);` | **Never blocks** (stops at oldest active reader Read-Mark) | Only if `checkpointed == log` and no active readers remain | No (keeps file size unless `journal_size_limit` set) | Triggered automatically by `PRAGMA wal_autocheckpoint = 1000;` ($\approx 4\text{ MB}$) or low-impact background crons. |
| **`FULL`** | `PRAGMA wal_checkpoint(FULL);` | **Waits** (up to `busy_timeout`) for current writers/readers | Only if no new reader started during the flush | No | Scheduled maintenance flush when readers are intermittent. |
| **`RESTART`** | `PRAGMA wal_checkpoint(RESTART);` | **Waits** for all readers **after** flushing so next writer **must** start at frame 1 | **Guaranteed** | No (reuses allocated disk blocks for speed) | High-rate telemetry daemons to prevent `.db-wal` from growing while avoiding `ftruncate()` metadata stalls. |
| **`TRUNCATE`** | `PRAGMA wal_checkpoint(TRUNCATE);` | **Waits** for all writers & readers, flushes all frames, and rewinds | **Guaranteed** | **Yes (`0` bytes)** | Pre-backup / pre-archival hook to fold all state cleanly into `.db` and zero out `.db-wal`. |
| **`wal_autocheckpoint`** | `PRAGMA wal_autocheckpoint = 1000;` | — | Triggers `PASSIVE` at $N$ pages | — | Default `1000` pages (`4 MB`). Set to `<= 0` only if managing checkpoints manually via a dedicated thread. |
| **`journal_size_limit`** | `PRAGMA journal_size_limit = 67108864;` | — | — | Truncates `.db-wal` to cap (`64 MiB`) on rewind | Prevents a temporary burst spike from leaving a multi-GB `.db-wal` file allocated on disk forever. |

#### 2.2.4 Production WAL Pitfalls: "WAL Starvation" & `SQLITE_BUSY_SNAPSHOT`

##### 2.2.4.1 "WAL Starvation" (Unbounded `.db-wal` Growth From Unclosed Read Cursors)
- SQLite can only rewind `.db-wal` to frame 1 when *all* frames are checkpointed and no connection holds a Read-Mark on an earlier snapshot. If a Python script or GUI leaves an unfinished `SELECT` cursor open without closing it, `checkpointed < log` forever and `.db-wal` grows to gigabytes! Always close read cursors promptly and configure `PRAGMA journal_size_limit = 67108864;`.
##### 2.2.4.2 Why `PRAGMA busy_timeout = 5000;` Requires `BEGIN IMMEDIATE;` on Concurrent Writers
- If Connection A starts a deferred `BEGIN;`, runs a `SELECT` (acquiring a read snapshot), and later executes `INSERT` after Connection B has committed a newer WAL frame, SQLite **immediately aborts with `SQLITE_BUSY_SNAPSHOT` (`0 ms`)—ignoring `busy_timeout`**—because upgrading a stale read snapshot would violate serializability. Always start write transactions with **`BEGIN IMMEDIATE;`** so the write lock is acquired up front and `busy_timeout` is respected!

#### 2.2.5 When SQLite WAL Must NOT Be Used:

* **Network Filesystems (NFS, SMB, CIFS):** WAL requires shared memory mapping (`mmap()`) via the `.db-shm` file across processes. POSIX advisory locking and shared memory over network shares are notoriously buggy and will cause silent database corruption.

* **Read-Only Media:** WAL requires the directory to be writable so the engine can create the `.db-wal` and `.db-shm` files.

## 3. PostgreSQL: The Monolithic Enterprise WAL Architecture

In PostgreSQL, the Write-Ahead Log is not merely an engine crash recovery tool; it is the **central nervous system** of the database—driving Point-In-Time Recovery (PITR), physical streaming replication, Patroni high-availability failover, and logical change data capture (CDC).

```
                      PostgreSQL WAL Pipeline Architecture
 ┌───────────────────────────┐
 │ Client: COMMIT            │
 └─────────────┬─────────────┘
               ▼
 ┌───────────────────────────┐     wal_buffers (RAM)
 │ WAL Writer Process        │ <── Buffered in memory (16 MB ring buffer)
 └─────────────┬─────────────┘
               ▼ (Sequential Write)
 ┌───────────────────────────┐
 │ Disk: pg_wal/00000001...  │ <── Sequential 16 MB ring segment files
 └─────────────┬─────────────┘
               │
               ├─────────────────────────────────────────┐
               ▼                                         ▼
 ┌───────────────────────────┐             ┌───────────────────────────┐
 │ Background Checkpointer   │             │ Replication Engine        │
 │ Flushes dirty 8 KB pages  │             │ WAL Sender streams bytes  │
 │ from shared_buffers to    │             │ to Standby Replicas over  │
 │ PGDATA heap disk blocks   │             │ TCP Socket                │
 └───────────────────────────┘             └───────────────────────────┘

```

### 3.1 The Log Sequence Number ($\text{LSN}$) and 8 KB Page Synchronization

Every byte written to the PostgreSQL WAL is assigned a strictly monotonic 64-bit unsigned integer called a **Log Sequence Number (**$\text{LSN}$**)**:

* Represented in hex notation: `0/16B3748` (Log File ID / Byte Offset).

* Every 8 KB page header in PostgreSQL contains a field: `pd_lsn` (Page LSN).

#### 3.1.1 The Fundamental Invariant of PostgreSQL Recovery:

A dirty page in `shared_buffers` **cannot be written to disk** by the checkpointer or background writer until the WAL record describing that change has been pushed and synced to `pg_wal/`:

$$
\text{Disk Write Safe Condition} \iff \text{LSN}_{\text{Page}} \le \text{LSN}_{\text{Flushed\_WAL}}
$$

If this invariant were violated, a crash would leave a disk page containing changes that the WAL has no record of, making atomic rollback impossible.

### 3.2 The Checkpoint Mechanism & Smoothing

A PostgreSQL **checkpoint** is the point in the transaction log stream where the database guarantees that all dirty memory pages up to that LSN have been flushed to the physical table heap on disk.

#### 3.2.1 The Telemetry Ingestion Stall (Under Default Checkpoints):

* Default `max_wal_size` is $1\text{ GB}$.

* Under heavy storm sensor ingestion ($50,000\text{ pings/sec}$), $1\text{ GB}$ of WAL fills in 30 seconds.

* The engine triggers an unthrottled checkpoint. The checkpointer dumps gigabytes of dirty buffers to disk at maximum speed.

* NVMe/SSD controllers exhaust their internal queues; application client connections freeze, waiting for WAL writes to unblock.

#### 3.2.2 The Production Checkpoint Formula:

```
# /etc/postgresql/16/main/postgresql.conf

# 1. Allow WAL volume to accumulate to absorb storm ingestion spikes
max_wal_size = 32GB
min_wal_size = 4GB

# 2. Time-based checkpoint trigger
checkpoint_timeout = 15min

# 3. Checkpoint Smoothing: Spread writes over 90% of the timeout duration
checkpoint_completion_target = 0.9

# 4. Ring Buffer Sizing
wal_buffers = 16MB
wal_compression = zstd

```

With `checkpoint_timeout = 15min` and `checkpoint_completion_target = 0.9`, PostgreSQL spreads the I/O writes over **13.5 minutes**, eliminating the periodic disk write freeze.

### 3.3 The Torn-Page Solution: `full_page_writes`

Because an operating system crash can fracture an 8 KB PostgreSQL page across its underlying 4 KB disk sectors:

* **`full_page_writes = on` (Mandatory for ACID safety):** After every checkpoint, the **first time** an 8 KB page is modified in `shared_buffers`, the entire 8 KB image of that page is written into the WAL stream.

* **During Crash Recovery:** If the checkpointer wrote a torn page to disk right before power cut, PostgreSQL ignores the torn page on disk. It loads the clean 8 KB image directly from the WAL, overwrites the corrupted disk block, and replays subsequent fine-grained WAL deltas forward.

* **Write Amplification Penalty:** Setting `checkpoint_timeout` too low causes frequent checkpoints, which immediately triggers a storm of full 8 KB page writes into the WAL, multiplying disk write volume by $5\times\text{–}10\times$.

### 3.4 PostgreSQL Alternatives & Bypasses to WAL

PostgreSQL provides explicit engineering escape hatches to bypass WAL logging when durability can be sacrificed for speed:

```
                            PostgreSQL Table Logging Tiers
 ┌─────────────────────────────┬───────────────────────────────┬───────────────────────────────┐
 │ Standard Logged Tables      │ UNLOGGED Tables               │ TEMPORARY Tables              │
 ├─────────────────────────────┼───────────────────────────────┼───────────────────────────────┤
 │ • Full WAL generation       │ • Zero WAL written to disk    │ • Zero WAL written to disk    │
 │ • Crash safe & recoverable  │ • NOT crash safe (Truncated)  │ • Dropped at session close    │
 │ • Replicated to standbys    │ • NOT replicated to standbys  │ • Local to single client backend│
 │ • Write latency bound by WAL│ • Writes at raw RAM/IOPS speed│ • Stored in local backend RAM │
 └─────────────────────────────┴───────────────────────────────┴───────────────────────────────┘

```

#### 3.4.1 Unlogged Tables (`CREATE UNLOGGED TABLE`)

For staging high-frequency sensor ingest where raw pings are immediately downsampled into clean tables:

```
CREATE UNLOGGED TABLE raw_telemetry_staging (
    recorded_at TIMESTAMPTZ,
    station_id VARCHAR(10),
    temperature REAL,
    raw_payload JSONB
);

```

* **The Speedup:** Ingestion runs up to $3\times\text{–}5\times$ **faster** because zero bytes pass through `pg_wal/`.

* **The Penalty:** If the database host crashes or loses power, PostgreSQL **automatically truncates (empties) all unlogged tables on reboot** to prevent torn/corrupted pages from poisoning the cluster.

#### 3.4.2 Relaxed Commit Durability (`synchronous_commit`)

You can tune WAL commit durability at the session, transaction, or database level without modifying physical table architecture:

```
-- Client transaction returns immediately after WAL buffer write,
-- without waiting for disk controller fsync flush!
SET synchronous_commit = off;

```

* **The Trade-off:** Transactions commit in $< 0.5\text{ ms}$. If the server physically loses power, up to $3 \times \text{wal\_writer\_delay}$ (default $3 \times 200\text{ ms} = 600\text{ ms}$) of committed telemetry transactions can be lost, but **the physical database file integrity is never corrupted**.

## 4. MySQL / MariaDB: InnoDB, MyISAM, Aria, and LSM Engines

In MySQL and MariaDB, storage engines are pluggable. Consequently, logging and crash recovery are handled differently depending on the table engine.

```
                      MySQL / MariaDB Storage Engine Divergence
 ┌────────────────────────────────────────────────────────────────────────┐
 │                             SQL Parser & Optimizer                     │
 ├────────────────────────────────┬───────────────────────────────────────┤
 │     MySQL InnoDB Storage       │   Legacy / Non-Transactional Engines  │
 ├────────────────────────────────┼───────────────────────────────────────┤
 │ 1. Redo Log (ib_logfile / WAL) │ • MyISAM: ZERO WAL / ZERO Transaction │
 │    Circular sequential buffer  │   Direct disk mutation; Table locks   │
 │ 2. Doublewrite Buffer          │ • MariaDB Aria: Transactional crash-  │
 │    Contiguous disk safety zone │   safe engine replacing MyISAM        │
 │ 3. Undo Tablespaces            │ • MyRocks (RocksDB): Log-Structured   │
 │    Rollback segments & MVCC    │   Merge (LSM) append-only architecture│
 └────────────────────────────────┴───────────────────────────────────────┘

```

### 4.1 MySQL InnoDB: The Tri-Part Durability Architecture

InnoDB does not use a single WAL stream for both recovery and MVCC. It divides these duties across three distinct storage structures:

#### 4.1.1 The Redo Log (`innodb_redo_log_capacity`)

* **Role:** Pure crash-recovery REDO mechanism.

* Unlike PostgreSQL's infinite segmented WAL ring files, InnoDB manages a fixed circular ring buffer.

* Modern MySQL (8.0.30+) replaces fixed `ib_logfile0,1` files with dynamic redo log resizing:

  ```
  [mysqld]
  innodb_redo_log_capacity = 16G
  
  ```

#### 4.1.2 The Doublewrite Buffer (`innodb_doublewrite`)

InnoDB handles torn 16 KB pages differently than PostgreSQL:

* PostgreSQL writes full 8 KB pages into the WAL stream (`full_page_writes`).

* InnoDB writes pages into a dedicated contiguous storage area called the **Doublewrite Buffer** before flushing dirty pages to their final `.ibd` tablespace files:

  1. The buffer manager flushes dirty 16 KB pages to the contiguous doublewrite buffer in a single sequential I/O write.

  2. The buffer manager calls `fsync()`.

  3. The engine then writes the 16 KB pages to their random positions inside the `.ibd` data files.

* **Recovery:** If an OS crash fractures a 16 KB page mid-write inside `sensor_data.ibd`, InnoDB reads the intact 16 KB page from the doublewrite buffer and repairs the corrupted block during recovery.

#### 4.1.3 The Undo Tablespace (MVCC & Rollback)

* While PostgreSQL creates new row versions directly inside the table heap (`t_xmin`/`t_xmax`), InnoDB mutates data pages **in-place** and writes reverse differential deltas into the **Undo Log**.

* When a transaction rolls back or an older transaction needs a past snapshot, InnoDB traverses the undo log chain backward to reconstruct past states.

#### 4.1.4 Ingestion Tuning: `innodb_flush_log_at_trx_commit`

```
[mysqld]
# 1: Full ACID (Flush and sync redo log to disk on EVERY commit). Standard production.
# 0: Flush redo log to disk once per second. High speed; up to 1 second data loss on crash.
# 2: Flush to OS cache on commit; sync to disk once per second. (10x faster ingest).
innodb_flush_log_at_trx_commit = 2

```

### 4.2 Legacy MyISAM: The "No-WAL" Anti-Pattern

MyISAM was MySQL's default storage engine for over a decade. Understanding its failure modes highlights why WAL is essential.

#### 4.2.1 The Physical Structure of MyISAM:

* `.MYD`: The raw data file (heap records).

* `.MYI`: The index file (B-Trees storing file offsets).

#### 4.2.2 How MyISAM Handles Writes (The Crash Trap):

* **No Redo Log:** When an `INSERT` executes, MyISAM writes directly to the `.MYD` and `.MYI` file buffers and lets the operating system flush whenever it wants.

* **No Undo Log:** Transactions do not exist (`BEGIN` and `ROLLBACK` are ignored).

* **Table Locks:** Every write locks the entire table against all readers.

* **The Crash Consequence:** If the server loses power while MyISAM is updating an index tree, the index pointers point to invalid file offsets. The table is marked "crashed."

* **The Recovery Penalty:** Recovery is manual and slow. A systems administrator must run `myisamchk` or `REPAIR TABLE`, which reads every single row off disk and rebuilds the B-Tree from scratch—stalling production systems for hours on large datasets.

### 4.3 MariaDB Aria: The Modern Crash-Safe MyISAM Replacement

MariaDB engineered **Aria** (originally Maria Engine) to provide the lightweight, fast table scans of MyISAM while incorporating WAL crash-recovery.

```
# Enabling transactional logging in MariaDB Aria
default_storage_engine = Aria
aria_log_file_size = 1G
aria_log_purge_type = immediate

```

#### 4.3.1 How Aria Fixes MyISAM:

* **The Aria Transaction Log (`aria_log.00000001`):** Aria logs all page updates into a sequential log file prior to writing dirty pages.

* **Deterministic Recovery:** On crash recovery, Aria replays the log forward to synchronize table and index pages. Instead of rebuilding damaged indexes with `myisamchk`, Aria recovers within seconds.

* **Row-Format Page:** Aria groups data into 8 KB pages rather than variable raw byte offsets, standardizing recovery blocks.

### 4.4 MyRocks (RocksDB): Log-Structured Merge (LSM) Architecture

For ultra-high-throughput weather sensor networks ingesting millions of telemetry readings per second, both PostgreSQL and InnoDB can hit write cliffs because of B-Tree random I/O.

MyRocks (integrated into MariaDB and Percona Server) replaces B-Trees with a **Log-Structured Merge-Tree (LSM)**:

```
                         LSM-Tree Write Path (MyRocks)
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 1. Write to sequential WAL on disk (Durability)                        │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 2. Insert into MemTable in RAM (SkipList / Fast In-Memory Sort)        │
 └──────────────────────────────────┬─────────────────────────────────────┘
                                    │ (When MemTable reaches 64 MB)
                                    ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ 3. Flush to disk as immutable, sequentially ordered SSTable files      │
 │    (Level 0 -> Level 1 -> Level 2 via Background Compaction)           │
 └────────────────────────────────────────────────────────────────────────┘

```

* **No In-Place Page Mutation:** Data is never updated in-place. All writes, updates, and deletes are purely sequential appends.

* **Write Amplification Reduction:** Reduces write amplification on flash storage by up to $5\times\text{–}10\times$ compared to InnoDB, extending SSD lifespan under heavy 24/7 sensor streaming.

## 5. Master Comparative Architecture Matrix

| Architectural Feature | SQLite Rollback | SQLite WAL | PostgreSQL | MySQL InnoDB | MariaDB Aria | MyRocks (LSM) | 
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | 
| **Primary Crash Mechanism** | Rollback Journal (`.db-journal`) | Append-Only Log (`.db-wal`) | Write-Ahead Log (`pg_wal/`) | Redo Log (`ib_logfile`) | Page Transaction Log (`aria_log`) | Append-Only WAL + SSTables | 
| **Concurrency (Writers vs Readers)** | Writer blocks Readers; Readers block Writer | **Readers never block Writers; Writers never block Readers** | **Multi-Version (MVCC): Readers never block Writers** | **Multi-Version (MVCC): Readers never block Writers** | Table-level lock (or Page-level in Aria txn) | **Non-blocking concurrent reads** | 
| **Torn-Page Defense** | Copies full page to journal prior to write | Overwrites entire frame in WAL; base DB safe | Full Page Writes (`full_page_writes = on`) | Doublewrite Buffer (`innodb_doublewrite = 1`) | Page checksum verification + redo log | Immutable SSTables (Zero torn pages) | 
| **Memory Buffer Pool** | SQLite Page Cache (`cache_size`) | SQLite Page Cache + Shared Memory (`-shm`) | Dual-Tier (`shared_buffers` + OS Page Cache) | Single-Tier (`innodb_buffer_pool_size` via `O_DIRECT`) | Aria Page Cache (`aria_pagecache_buffer_size`) | MemTable in RAM + Block Cache | 
| **Zero-Log Fast Alternative** | `PRAGMA journal_mode = OFF;` | `PRAGMA synchronous = OFF;` | `UNLOGGED TABLES` / `synchronous_commit = off` | `innodb_flush_log_at_trx_commit = 2` | `TRANSACTIONAL=0` | Bypass WAL via direct SSTable bulk load | 
| **Network Storage Safety (NFS)** | Unsafe | **Extremely Unsafe (mmap corruption)** | Safe (Handles standard POSIX filesystem calls) | Safe (Handles direct I/O locking) | Safe | Safe | 

> [!TIP]
> **Complete MySQL & MariaDB Engineering Reference:** For a dedicated deep-dive into InnoDB 16 KB Clustered Index pages, Undo Tablespaces (`History List Length`), Change Buffering, `MyRocks` LSM-Tree compaction, and `my.cnf` production tuning, see **[Reference Card 14: MySQL 8.0/8.4 & MariaDB Complete Engineering Guide](./14_mysql_and_mariadb_innodb_complete_engineering_guide.md)**.

## 6. Hands-On Operational Profiling Labs

Run these hands-on benchmarks to observe the mechanical throughput and latency differences across WAL implementations.

### 6.1 Lab 1: SQLite Journal Mode Benchmark (100,000 Ingest Rows)

Compare the raw throughput of classical rollback journaling versus modern WAL mode.

#### 6.1.1 Execution Script (`sqlite_wal_benchmark.sh`):

```
#!/usr/bin/env bash
set -e

python3 - << 'EOF'
import sqlite3
import time

def benchmark_mode(mode_name, pragma_cmd):
    db_file = f"test_{mode_name}.db"
    conn = sqlite3.connect(db_file)
    cur = conn.cursor()
    
    cur.execute(pragma_cmd)
    cur.execute("CREATE TABLE telemetry (id INTEGER PRIMARY KEY, station_id TEXT, temp REAL);")
    
    start = time.time()
    # Execute 1,000 independent commit transactions
    for i in range(1000):
        cur.execute("INSERT INTO telemetry VALUES (NULL, 'AWS-001', 22.4);")
        conn.commit()
        
    duration = time.time() - start
    print(f"Mode: {mode_name:15} | 1,000 Transactions: {duration:6.2f}s | Speed: {1000/duration:7.1f} txn/sec")
    conn.close()

# 1. Classical Rollback Journal (DELETE)
benchmark_mode("ROLLBACK_DELETE", "PRAGMA journal_mode = DELETE;")

# 2. Rollback Journal (MEMORY)
benchmark_mode("ROLLBACK_MEMORY", "PRAGMA journal_mode = MEMORY;")

# 3. Modern WAL Mode
benchmark_mode("WAL_NORMAL", "PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")

# 4. Zero Safety Mode (OFF)
benchmark_mode("JOURNAL_OFF", "PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;")
EOF

```

#### 6.1.2 Typical Benchmark Results:

```
Mode: ROLLBACK_DELETE | 1,000 Transactions:  14.21s | Speed:    70.4 txn/sec
Mode: ROLLBACK_MEMORY | 1,000 Transactions:   0.38s | Speed:  2631.5 txn/sec
Mode: WAL_NORMAL      | 1,000 Transactions:   0.52s | Speed:  1923.0 txn/sec
Mode: JOURNAL_OFF     | 1,000 Transactions:   0.18s | Speed:  5555.5 txn/sec

```

* **Key Takeaway:** SQLite in `DELETE` rollback mode crawls at $\approx 70\text{ txn/sec}$ due to continuous filesystem file creation, synchronization, and deletion. Switching to **WAL mode accelerates commit throughput by over** $25\times$ while maintaining ACID durability.

### 6.2 Lab 2: PostgreSQL Ingestion Stress (Logged vs. Unlogged vs. Async Commit)

Measure the write amplification overhead of the PostgreSQL monolithic WAL stream.

#### 6.2.1 Setup Script in `psql`:

```
-- 1. Create a Standard Logged Table
CREATE TABLE telemetry_standard (
    recorded_at TIMESTAMPTZ,
    station_id VARCHAR(10),
    temperature REAL
);

-- 2. Create an Unlogged Table (Zero WAL generation)
CREATE UNLOGGED TABLE telemetry_unlogged (
    recorded_at TIMESTAMPTZ,
    station_id VARCHAR(10),
    temperature REAL
);

-- Benchmark Test 1: Standard Synchronous WAL Ingestion
\timing on
INSERT INTO telemetry_standard
SELECT NOW() - (g || ' seconds')::INTERVAL, 'AWS-001', 20.0 + random()
FROM generate_series(1, 1000000) AS g;

-- Benchmark Test 2: Relaxed Asynchronous Commit Ingestion
SET synchronous_commit = off;
INSERT INTO telemetry_standard
SELECT NOW() - (g || ' seconds')::INTERVAL, 'AWS-001', 20.0 + random()
FROM generate_series(1, 1000000) AS g;
SET synchronous_commit = on;

-- Benchmark Test 3: Unlogged Table Ingestion (Bypasses WAL entirely)
INSERT INTO telemetry_unlogged
SELECT NOW() - (g || ' seconds')::INTERVAL, 'AWS-001', 20.0 + random()
FROM generate_series(1, 1000000) AS g;

```

#### 6.2.2 Expected Timing Differences Across 1 Million Rows:

```
Standard Synchronous WAL  : 1,840 ms
Asynchronous Commit (off) : 890 ms  (2x faster commit path)
UNLOGGED Table            : 510 ms  (3.6x faster; zero pg_wal I/O)

```

### 6.3 Lab 3: Inspecting SQLite Shared Memory & WAL Checkpoint State

Demonstrate how SQLite coordinates concurrent reads and writes across files.

```
# Open SQLite in WAL mode
sqlite3 weather_monitoring.db "PRAGMA journal_mode = WAL;"

# Inspect the directory while holding a transaction open
ls -la weather_monitoring.db*

```

*Output:*

```
-rw-r--r-- 1 weather ops 40960 Oct 4 14:00 weather_monitoring.db
-rw-r--r-- 1 weather ops 32768 Oct 4 14:05 weather_monitoring.db-shm
-rw-r--r-- 1 weather ops 98304 Oct 4 14:05 weather_monitoring.db-wal

```

#### 6.3.1 Force a Checkpoint and Truncate:

```
sqlite3 weather_monitoring.db "PRAGMA wal_checkpoint(TRUNCATE);"
ls -la weather_monitoring.db*

```

*Output:*

```
-rw-r--r-- 1 weather ops 139264 Oct 4 14:06 weather_monitoring.db
-rw-r--r-- 1 weather ops  32768 Oct 4 14:06 weather_monitoring.db-shm
-rw-r--r-- 1 weather ops      0 Oct 4 14:06 weather_monitoring.db-wal

```

*Notice:* The WAL file has collapsed to 0 bytes, and the master `weather_monitoring.db` file has expanded from 40 KB to 139 KB as all dirty frames were flushed into the master database pages.

## 7. Summary Checklist for Systems & Weather Telemetry Architects

```
================================================================================
                WRITE-AHEAD LOGGING (WAL) OPERATIONAL CHEATSHEET
================================================================================
 1. SQLite Rule          : ALWAYS enable PRAGMA journal_mode = WAL; for multi-process
                           telemetry ingest on local drives. 
                           NEVER run WAL on NFS/SMB network shares.
 2. SQLite Checkpointing : Schedule explicit PRAGMA wal_checkpoint(PASSIVE); during
                           low-traffic windows to prevent the WAL file from growing
                           into multi-gigabyte files.
 3. PostgreSQL Checkpoints: Set checkpoint_completion_target = 0.9 and expand
                           max_wal_size to >= 16GB-32GB to smooth out I/O stalls
                           during storm ingestion spikes.
 4. Torn-Page Safety     : NEVER disable full_page_writes in PostgreSQL or
                           innodb_doublewrite in MySQL unless running on filesystems
                           with native atomic 16KB writes (e.g., ZFS / specialized flash).
 5. Staging Speedup      : Use UNLOGGED tables in PostgreSQL for transient high-volume
                           staging pipelines where data can be regenerated on crash.
 6. Commit Relaxation    : For high-frequency non-critical weather pings, set
                           synchronous_commit = off (Postgres) or
                           innodb_flush_log_at_trx_commit = 2 (MySQL) to boost write
                           rates by 3x-10x with zero risk to physical file integrity.
================================================================================

```
---

### 7.1 Reference Library Navigation

> **Navigation:** [Bootcamp Home](../README.md) | [Reference Cards Index](./README.md) | [Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅ Previous Card](./06_dbt_for_meteorological_telemetry_engineering.md) | **Card 07 of 14** | [Next Card](./08_postgresql_vacuum_vs_vacuum_full_and_bloat.md) | [⬆ Back to Top](#deep-dive-engineering-guide-write-ahead-logging-wal--crash-recovery-mechanics)
