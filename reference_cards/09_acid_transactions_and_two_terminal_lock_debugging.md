# Database Transactions & ACID Internals: Two-Terminal Debugging Reference Card

## A Hands-On Guide to Concurrency, Snapshot Isolation, Lock Waits, and Deadlocks

> **Navigation:** [Bootcamp Home](../README.md) | [Reference Cards Index](./README.md) | [Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅ Previous Card](./08_postgresql_vacuum_vs_vacuum_full_and_bloat.md) | **Card 09 of 14** | [Next Card](./10_query_execution_plan_forensics_and_explain.md)

## Quick-Jump Table of Contents

- [Executive Summary: The Two-Terminal Mental Model](#executive-summary-the-two-terminal-mental-model)
- [1. Quick Lab Setup: The Weather Station Registry](#1-quick-lab-setup-the-weather-station-registry)
- [2. Lab 1: The Invisible Update (Snapshot Isolation & Atomicity)](#2-lab-1-the-invisible-update-snapshot-isolation--atomicity)
  - [2.1 Objective](#21-objective)
  - [2.2 Step-by-Step Terminal Commands](#22-step-by-step-terminal-commands)
- [3. Lab 2: Row Locks & Lock Contention (Writers Block Writers)](#3-lab-2-row-locks--lock-contention-writers-block-writers)
  - [3.1 Objective](#31-objective)
  - [3.2 Step-by-Step Terminal Commands](#32-step-by-step-terminal-commands)
- [4. Lab 3: The Deadlock Dilemma (Circular Wait)](#4-lab-3-the-deadlock-dilemma-circular-wait)
  - [4.1 Objective](#41-objective)
  - [4.2 Step-by-Step Terminal Commands](#42-step-by-step-terminal-commands)
- [5. Lab 4: Read Committed vs. Repeatable Read](#5-lab-4-read-committed-vs-repeatable-read)
  - [5.1 Objective](#51-objective)
  - [5.2 Step-by-Step Terminal Commands](#52-step-by-step-terminal-commands)
- [6. Two-Terminal Emergency Diagnostic Commands](#6-two-terminal-emergency-diagnostic-commands)
  - [6.1 View All Active Transactions and Durations (PostgreSQL)](#61-view-all-active-transactions-and-durations-postgresql)
  - [6.2 Spot Idle In Transaction Sessions (The Bloat Culprits)](#62-spot-idle-in-transaction-sessions-the-bloat-culprits)
  - [6.3 Terminate a Stuck Blocking Session](#63-terminate-a-stuck-blocking-session)
  - [6.4 MySQL InnoDB Lock Monitoring Equivalent](#64-mysql-innodb-lock-monitoring-equivalent)
- [7. Summary Checklist: Transaction Debugging Rules](#7-summary-checklist-transaction-debugging-rules)

---

### Executive Summary: The Two-Terminal Mental Model

In database engineering, transaction isolation and locking can feel abstract when reading documentation. The most effective way to understand how transactions work is the **Two-Terminal Method**:

1. Open two independent shell windows side-by-side: **Terminal A** (`Session 1`) and **Terminal B** (`Session 2`).

2. Execute operations chronologically across both connections.

3. Observe directly when data changes are invisible, when queries block, and how the storage engine resolves conflicts in real time.

```
                      The Two-Terminal Concurrency Mental Model
                      
        TERMINAL A (Session 1)                       TERMINAL B (Session 2)
     ┌────────────────────────────────────┐       ┌────────────────────────────────────┐
 t1  │ BEGIN;                             │       │ BEGIN;                             │
     │ UPDATE stations SET temp = 25.0... │       │                                    │
     ├────────────────────────────────────┤       ├────────────────────────────────────┤
 t2  │ Data modified in local transaction;│       │ SELECT temp FROM stations...       │
     │ exclusive row lock held by Sess 1. │       │ Sees OLD value (e.g. 18.5)!        │
     │                                    │       │ (MVCC / Snapshot Isolation)        │
     ├────────────────────────────────────┤       ├────────────────────────────────────┤
 t3  │                                    │       │ UPDATE stations SET temp = 30.0... │
     │                                    │       │ BLOCKED! (Waits on row lock)       │
     ├────────────────────────────────────┤       ├────────────────────────────────────┤
 t4  │ COMMIT; (or ROLLBACK;)             │       │ Instantly unblocks and completes!  │
     └────────────────────────────────────┘       └────────────────────────────────────┘

```

## 1. Quick Lab Setup: The Weather Station Registry

Run this single SQL setup script in either PostgreSQL, MySQL, or SQLite to prepare a demonstration table:

```
-- PostgreSQL / MySQL / SQLite compatible setup
DROP TABLE IF EXISTS station_calibration;
CREATE TABLE station_calibration (
    station_id VARCHAR(10) PRIMARY KEY,
    station_name VARCHAR(64) NOT NULL,
    temp_offset REAL NOT NULL DEFAULT 0.0,
    calibrated_by VARCHAR(32) NOT NULL DEFAULT 'SYSTEM'
);

INSERT INTO station_calibration (station_id, station_name, temp_offset, calibrated_by)
VALUES 
    ('AWS-001', 'Algiers Port Marine', 0.15, 'TECH_ALICE'),
    ('AWS-002', 'Boumerdes Coastal',   -0.05, 'TECH_BOB'),
    ('AWS-003', 'Dellys Cape Station', 0.00,  'TECH_CHARLIE');

```

## 2. Lab 1: The Invisible Update (Snapshot Isolation & Atomicity)

### 2.1 Objective

Prove that uncommitted changes in one session are completely invisible to other sessions, and verify that `ROLLBACK` leaves zero trace on disk.

```
                           Timeline: Lab 1 Execution
     Time      TERMINAL A (Session 1)                 TERMINAL B (Session 2)
      │
     t1        BEGIN;
      │
     t2        UPDATE station_calibration
               SET temp_offset = 5.50
               WHERE station_id = 'AWS-001';
      │
     t3                                               SELECT temp_offset 
                                                      FROM station_calibration 
                                                      WHERE station_id = 'AWS-001';
                                                      -- OUTPUT: 0.15 (Old value!)
      │
     t4        ROLLBACK;
      │
     t5                                               SELECT temp_offset 
                                                      FROM station_calibration 
                                                      WHERE station_id = 'AWS-001';
                                                      -- OUTPUT: 0.15 (Unchanged!)
      ▼

```

### 2.2 Step-by-Step Terminal Commands

#### 2.2.1 Step 1: Terminal A opens a transaction and updates a row

```
-- In Terminal A:
BEGIN;

UPDATE station_calibration 
SET temp_offset = 5.50 
WHERE station_id = 'AWS-001';

-- Confirm change is visible locally in Terminal A:
SELECT station_id, temp_offset FROM station_calibration WHERE station_id = 'AWS-001';
-- Output: AWS-001 | 5.5

```

#### 2.2.2 Step 2: Terminal B reads the same row

```
-- In Terminal B:
SELECT station_id, temp_offset FROM station_calibration WHERE station_id = 'AWS-001';
-- Output: AWS-001 | 0.15

```

*Why?* Terminal B does **not** see `5.50`. Because Terminal A has not committed, Multi-Version Concurrency Control (MVCC) serves Terminal B the consistent snapshot from before Terminal A started. Dirty Reads ($G_1$) are prevented.

#### 2.2.3 Step 3: Terminal A aborts the transaction

```
-- In Terminal A:
ROLLBACK;

```

#### 2.2.4 Step 4: Terminal B verifies baseline consistency

```
-- In Terminal B:
SELECT station_id, temp_offset FROM station_calibration WHERE station_id = 'AWS-001';
-- Output: AWS-001 | 0.15

```

*Under the Hood:* In PostgreSQL, `ROLLBACK` marks the transaction ID ($\text{XID}$) as aborted in `pg_xact`. In MySQL InnoDB, reverse deltas from the Undo Log are applied to revert the clustered index page in RAM.

## 3. Lab 2: Row Locks & Lock Contention (Writers Block Writers)

### 3.1 Objective

Demonstrate what happens when two transactions attempt to update the **exact same row** concurrently. Prove how relational engines enforce mutual exclusion using Exclusive Row Locks (`X-Locks`).

```
                           Timeline: Lab 2 Execution
     Time      TERMINAL A (Session 1)                 TERMINAL B (Session 2)
      │
     t1        BEGIN;
      │
     t2        UPDATE station_calibration
               SET temp_offset = 1.20
               WHERE station_id = 'AWS-002';
               (Holds Exclusive Row Lock)
      │
     t3                                               BEGIN;
      │
     t4                                               UPDATE station_calibration
                                                      SET temp_offset = 2.40
                                                      WHERE station_id = 'AWS-002';
                                                      ──► [PROMPT HANGS / BLOCKED!]
      │
     t5        COMMIT;
               (Releases Row Lock)
      │
     t6                                               ──► [INSTANTLY UNBLOCKS & RUNS!]
                                                      UPDATE 1
      │
     t7                                               COMMIT;
      ▼

```

### 3.2 Step-by-Step Terminal Commands

#### 3.2.1 Step 1: Terminal A locks row `AWS-002`

```
-- In Terminal A:
BEGIN;

UPDATE station_calibration 
SET temp_offset = 1.20 
WHERE station_id = 'AWS-002';
-- Row lock acquired on AWS-002! Do NOT commit yet.

```

#### 3.2.2 Step 2: Terminal B attempts to mutate the same physical row

```
-- In Terminal B:
BEGIN;

UPDATE station_calibration 
SET temp_offset = 2.40 
WHERE station_id = 'AWS-002';

-- NOTICE: Terminal B freezes! The cursor waits.

```

#### 3.2.3 Step 3: Inspect the Lock in a 3rd Terminal (Forensic Diagnosis)

While Terminal B is blocked, open **Terminal C** or query PostgreSQL to see the lock wait in real time:

```
-- PostgreSQL Lock Forensic Query:
SELECT 
    blocked_activity.pid          AS blocked_pid,
    blocked_activity.query        AS blocked_query,
    blocking_activity.pid         AS blocking_pid,
    blocking_activity.query       AS blocking_query,
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

```

#### 3.2.4 Step 4: Release the lock in Terminal A

```
-- In Terminal A:
COMMIT;

```

*Observe:* In Terminal B, the query instantly finishes and outputs `UPDATE 1`. Terminal B can now run `COMMIT;`.

## 4. Lab 3: The Deadlock Dilemma (Circular Wait)

### 4.1 Objective

Create a classic circular wait deadlock and observe how database engines detect the cycle and abort one transaction.

```
                           The Deadlock Cycle
 ┌──────────────────────────────┐              ┌──────────────────────────────┐
 │    TERMINAL A (Session 1)    │              │    TERMINAL B (Session 2)    │
 ├──────────────────────────────┤              ├──────────────────────────────┤
 │ 1. Locks 'AWS-001'           │              │ 2. Locks 'AWS-002'           │
 │ 3. Requests lock on 'AWS-002'│ ── WAITS ON ─► Holds 'AWS-002'              │
 │    (Hangs waiting for B)     │              │ 4. Requests lock on 'AWS-001'│
 │                              │ ◄── WAITS ON ─ (Hangs waiting for A)        │
 └──────────────────────────────┘              └──────────────────────────────┘
                                       │
                      Deadlock Detector Interrupts (~1000ms)
                                       ▼
                  [ERROR: 40P01 deadlock detected on Session B!]

```

### 4.2 Step-by-Step Terminal Commands

#### 4.2.1 Step 1: Open transactions in both terminals

```
-- Terminal A:
BEGIN;
UPDATE station_calibration SET temp_offset = 0.50 WHERE station_id = 'AWS-001';

-- Terminal B:
BEGIN;
UPDATE station_calibration SET temp_offset = 0.80 WHERE station_id = 'AWS-002';

```

#### 4.2.2 Step 2: Create the circular lock dependency

```
-- In Terminal A (attempts to lock Row 2, held by B):
UPDATE station_calibration SET temp_offset = 0.99 WHERE station_id = 'AWS-002';
-- Terminal A hangs!

-- In Terminal B (attempts to lock Row 1, held by A):
UPDATE station_calibration SET temp_offset = 0.99 WHERE station_id = 'AWS-001';

```

#### 4.2.3 The Engine's Resolution:

Within 1 second (`deadlock_timeout = 1s`), the database background engine traverses the wait-for graph, detects the cycle, and terminates one session:

```
ERROR:  deadlock detected
DETAIL:  Process 4821 waits for ShareLock on transaction 789; blocked by process 4790.
Process 4790 waits for ExclusiveLock on tuple (0,2) of relation "station_calibration"; blocked by process 4821.
HINT:  See server log for query details.

```

*Rule:* Applications must always handle serialization/deadlock errors (PostgreSQL SQLSTATE `40P01`, MySQL error `1213`) with **exponential backoff and retry logic**.

## 5. Lab 4: Read Committed vs. Repeatable Read

### 5.1 Objective

Observe how transaction isolation levels change what a query sees when another transaction commits data midway through.

```
| Phenomenon | Read Committed (Postgres Default) | Repeatable Read |
| :--- | :--- | :--- |
| **New query within same transaction** | Takes a **new snapshot per statement**. Sees changes committed by others midway. | Pinned to snapshot taken at **first statement of transaction**. Ignores commits by others. |

```

### 5.2 Step-by-Step Terminal Commands

#### 5.2.1 Test A: Default `READ COMMITTED`

```
-- In Terminal B:
BEGIN;
SELECT temp_offset FROM station_calibration WHERE station_id = 'AWS-003';
-- Output: 0.00

-- In Terminal A (separate session):
UPDATE station_calibration SET temp_offset = 9.99 WHERE station_id = 'AWS-003';
-- (Autocommit executes)

-- Back in Terminal B (SAME transaction still open!):
SELECT temp_offset FROM station_calibration WHERE station_id = 'AWS-003';
-- Output: 9.99! (Non-repeatable read: value changed inside same transaction!)
COMMIT;

```

#### 5.2.2 Test B: `REPEATABLE READ` Isolation

```
-- In Terminal B:
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT temp_offset FROM station_calibration WHERE station_id = 'AWS-003';
-- Output: 9.99

-- In Terminal A:
UPDATE station_calibration SET temp_offset = 0.00 WHERE station_id = 'AWS-003';
-- (Committed)

-- Back in Terminal B:
SELECT temp_offset FROM station_calibration WHERE station_id = 'AWS-003';
-- Output: 9.99! (Snapshot is completely pinned. Ignores Terminal A's commit!)
COMMIT;

-- After commit in Terminal B:
SELECT temp_offset FROM station_calibration WHERE station_id = 'AWS-003';
-- Output: 0.00 (Now sees latest database state)

```

## 6. Two-Terminal Emergency Diagnostic Commands

Keep these commands handy when debugging stuck sessions during development or incident response:

### 6.1 View All Active Transactions and Durations (PostgreSQL)

```
SELECT 
    pid, 
    usename, 
    client_addr, 
    state, 
    NOW() - xact_start AS txn_duration, 
    NOW() - query_start AS query_duration,
    query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY txn_duration DESC NULLS LAST;

```

### 6.2 Spot Idle In Transaction Sessions (The Bloat Culprits)

```
SELECT 
    pid, 
    usename, 
    state, 
    NOW() - state_change AS idle_duration,
    query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY idle_duration DESC;

```

### 6.3 Terminate a Stuck Blocking Session

```
-- Graceful cancel of current query (sends SIGINT):
SELECT pg_cancel_backend(12345);

-- Forceful kill of backend connection (sends SIGTERM):
SELECT pg_terminate_backend(12345);

```

### 6.4 MySQL InnoDB Lock Monitoring Equivalent

> **Deep-Dive Reference:** For a complete explanation of InnoDB `Record Locks`, `Gap Locks`, `Next-Key Locks` (under `REPEATABLE READ`), and why unindexed `WHERE` updates lock every gap in the table, see **[Reference Card 14: MySQL 8.0/8.4 & MariaDB Complete Engineering Guide (Sections 6 & 10)](./14_mysql_and_mariadb_innodb_complete_engineering_guide.md#6-innodb-concurrency--locking-record-gap-next-key--insert-intention-locks)**.

```sql
-- Inspect waiting transactions in MySQL 8.0+ (or query SELECT * FROM sys.innodb_lock_waits;):
SELECT 
    r.trx_id waiting_trx_id,
    r.trx_mysql_thread_id waiting_thread,
    r.trx_query waiting_query,
    b.trx_id blocking_trx_id,
    b.trx_mysql_thread_id blocking_thread,
    b.trx_query blocking_query
FROM performance_schema.data_lock_waits w
JOIN information_schema.innodb_trx b 
  ON b.trx_id = w.blocking_engine_transaction_id
JOIN information_schema.innodb_trx r 
  ON r.trx_id = w.requesting_engine_transaction_id;
```

## 7. Summary Checklist: Transaction Debugging Rules

```
================================================================================
               TWO-TERMINAL TRANSACTION DEBUGGING CHECKLIST
================================================================================
 1. Uncommitted Is Hidden: Edits in Terminal A are completely invisible to
                           Terminal B until Terminal A issues COMMIT.
 2. Writers Block Writers: If Terminal A updates Row X, Terminal B will FREEZE
                           if it attempts to UPDATE or DELETE Row X.
 3. Readers Don't Block  : Plain SELECT statements NEVER block incoming UPDATEs,
                           and UPDATEs never block plain SELECTs under MVCC.
 4. Close Your Txns      : Never leave a terminal sitting on "idle in transaction".
                           It pins the vacuum horizon and causes massive table bloat.
 5. Prevent Deadlocks    : Always update multi-row records in a consistent,
                           deterministic order (e.g. ORDER BY id) across your code.
 6. Handle 40P01 In App  : Build retry loops with exponential backoff for transactions
                           that encounter deadlock or serialization aborts.
================================================================================

```
---

### 7.1 Reference Library Navigation

> **Navigation:** [Bootcamp Home](../README.md) | [Reference Cards Index](./README.md) | [Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅ Previous Card](./08_postgresql_vacuum_vs_vacuum_full_and_bloat.md) | **Card 09 of 14** | [Next Card](./10_query_execution_plan_forensics_and_explain.md) | [⬆ Back to Top](#database-transactions--acid-internals-two-terminal-debugging-reference-card)
