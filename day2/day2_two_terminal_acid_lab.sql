-- ============================================================================
-- WEATHER FORECAST ENGINEERING DATABASE BOOTCAMP — DAY 2
-- File: day2_two_terminal_acid_lab.sql
-- Companion to: day2_master_coursebook.md & reference_cards/09_acid_transactions_and_two_terminal_lock_debugging.md
-- Purpose: Complete, Annotated Two-Terminal ACID Concurrency, Snapshot Isolation,
--          Row-Level Lock Contention, Deadlock Circular Wait & Emergency Forensics Lab
-- ============================================================================
-- HOW TO USE THIS SCRIPT IN CLASS:
--   1. Open TWO independent terminal windows side-by-side:
--      * TERMINAL A (Session 1): psql -d weather_ops
--      * TERMINAL B (Session 2): psql -d weather_ops (or DBeaver SQL Editor)
--   2. Optional: Open TERMINAL C (Observer / DBA Session) to run the live
--      pg_stat_activity & pg_locks forensic queries while Terminal B is blocked.
--   3. Execute the chronological steps below across Terminal A and Terminal B.
-- ============================================================================

-- ============================================================================
-- SECTION 0: LAB SETUP — THE WEATHER STATION CALIBRATION & SYNOPTIC REGISTRY
-- (Run this once in Terminal A before starting the two-terminal exercises)
-- ============================================================================

DROP TABLE IF EXISTS station_calibration;

CREATE TABLE station_calibration (
    station_id     VARCHAR(10) PRIMARY KEY,
    station_name   VARCHAR(64) NOT NULL,
    temp_offset    REAL        NOT NULL DEFAULT 0.0,
    calibrated_by  VARCHAR(32) NOT NULL DEFAULT 'SYSTEM',
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO station_calibration (station_id, station_name, temp_offset, calibrated_by)
VALUES 
    ('AWS-001', 'Algiers Port Marine', 0.15,  'TECH_ALICE'),
    ('AWS-002', 'Boumerdes Coastal',   -0.05, 'TECH_BOB'),
    ('AWS-003', 'Dellys Cape Station', 0.00,  'TECH_CHARLIE');

-- Verify initial physical tuple positions (ctid) and transaction IDs (xmin, xmax):
SELECT ctid, xmin, xmax, station_id, station_name, temp_offset, calibrated_by
FROM station_calibration
ORDER BY station_id;


-- ============================================================================
-- LAB 1: THE INVISIBLE UPDATE — MVCC SNAPSHOT ISOLATION & ATOMIC ROLLBACK
-- Objective: Prove that uncommitted changes in Terminal A are completely
--            invisible to Terminal B (Zero Dirty Reads), and verify that
--            ROLLBACK leaves the original tuple untouched.
-- ============================================================================

-- [Step 1.1 — TERMINAL A] Open a transaction and update AWS-001's calibration offset:
BEGIN;

SELECT pg_backend_pid() AS terminal_a_pid, pg_current_xact_id() AS terminal_a_xid;

UPDATE station_calibration 
SET temp_offset = 5.50, calibrated_by = 'TECH_DAVE_UNCOMMITTED'
WHERE station_id = 'AWS-001';

-- Confirm change is visible locally inside Terminal A (notice the new ctid!):
SELECT ctid, xmin, xmax, station_id, temp_offset, calibrated_by
FROM station_calibration
WHERE station_id = 'AWS-001';
-- Expected in Terminal A: AWS-001 | 5.5 | TECH_DAVE_UNCOMMITTED


-- [Step 1.2 — TERMINAL B] Concurrently read the exact same row (Readers NEVER block Writers!):
SELECT ctid, xmin, xmax, station_id, temp_offset, calibrated_by
FROM station_calibration
WHERE station_id = 'AWS-001';
-- Expected in Terminal B: AWS-001 | 0.15 | TECH_ALICE (Sees OLD committed snapshot!)
-- Why? Because Terminal A's XID is still in-progress, PostgreSQL MVCC serves
-- Terminal B the prior committed tuple version at (0,1) without waiting on a lock!


-- [Step 1.3 — TERMINAL A] Abort the transaction:
ROLLBACK;


-- [Step 1.4 — TERMINAL B] Verify baseline consistency after rollback:
SELECT ctid, xmin, xmax, station_id, temp_offset, calibrated_by
FROM station_calibration
WHERE station_id = 'AWS-001';
-- Expected in Terminal B: AWS-001 | 0.15 | TECH_ALICE
-- Under the hood: ROLLBACK is an instant O(1) bit flip in pg_xact marking Terminal A's
-- XID as ABORTED. The dead tuple left at (0,4) will be reclaimed later by VACUUM.


-- ============================================================================
-- LAB 2: ROW-LEVEL LOCK CONTENTION — WRITERS BLOCK WRITERS (EXCLUSIVE LOCKS)
-- Objective: Demonstrate what happens when two transactions attempt to UPDATE
--            the exact same weather station row concurrently, and inspect the
--            live lock wait tree using pg_blocking_pids() and pg_locks.
-- ============================================================================

-- [Step 2.1 — TERMINAL A] Lock row 'AWS-002' inside an open transaction:
BEGIN;

UPDATE station_calibration 
SET temp_offset = 1.20, calibrated_by = 'TERMINAL_A_LOCK_HOLDER'
WHERE station_id = 'AWS-002';
-- Row-level Exclusive Lock acquired on 'AWS-002'! Do NOT commit yet!


-- [Step 2.2 — TERMINAL B] Attempt to update the exact same row 'AWS-002':
BEGIN;

UPDATE station_calibration 
SET temp_offset = 2.40, calibrated_by = 'TERMINAL_B_WAITER'
WHERE station_id = 'AWS-002';
-- OBSERVE: Terminal B FREEZES! The psql cursor hangs waiting for Terminal A's XID.


-- [Step 2.3 — TERMINAL A or TERMINAL C] Live Forensic Lock Inspection while Terminal B hangs!
-- Method A: Fast Modern PostgreSQL pg_blocking_pids() Query:
SELECT 
    blocked.pid                                    AS blocked_pid,
    blocked.usename                                AS blocked_user,
    blocked.state                                  AS blocked_state,
    blocked.wait_event_type || ':' || blocked.wait_event AS wait_event,
    NOW() - blocked.query_start                    AS waiting_duration,
    blocked.query                                  AS blocked_query,
    pg_blocking_pids(blocked.pid)                  AS blocking_pids,
    blocker.query                                  AS blocker_last_query,
    blocker.state                                  AS blocker_state
FROM pg_stat_activity AS blocked
LEFT JOIN pg_stat_activity AS blocker
       ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE CARDINALITY(pg_blocking_pids(blocked.pid)) > 0;

-- Method B: Full Catalog Join across pg_stat_activity and pg_locks:
SELECT 
    blocked_activity.pid                  AS blocked_pid,
    blocked_activity.query                AS blocked_query,
    blocking_activity.pid                 AS blocking_pid,
    blocking_activity.query               AS blocking_query,
    NOW() - blocked_activity.query_start  AS waiting_duration
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


-- [Step 2.4 — TERMINAL A] Commit to release the Exclusive Row Lock:
COMMIT;
-- OBSERVE IN TERMINAL B: The hung UPDATE 1 unblocks and finishes in < 1 millisecond!


-- [Step 2.5 — TERMINAL B] Commit Terminal B's transaction and inspect final state:
COMMIT;

SELECT ctid, xmin, xmax, station_id, temp_offset, calibrated_by
FROM station_calibration
WHERE station_id = 'AWS-002';
-- Expected: temp_offset = 2.40, calibrated_by = 'TERMINAL_B_WAITER'


-- ============================================================================
-- LAB 3: THE DEADLOCK DILEMMA — CIRCULAR WAIT & AUTOMATIC DEADLOCK DETECTION
-- Objective: Trigger a classic circular lock dependency between Terminal A and
--            Terminal B, and observe PostgreSQL's deadlock detector (1000ms
--            deadlock_timeout) automatically abort one transaction with SQLSTATE 40P01.
-- ============================================================================

-- [Step 3.1 — TERMINAL A] Open transaction and lock Station 1 ('AWS-001'):
BEGIN;
UPDATE station_calibration SET temp_offset = 0.50 WHERE station_id = 'AWS-001';


-- [Step 3.2 — TERMINAL B] Open transaction and lock Station 2 ('AWS-002'):
BEGIN;
UPDATE station_calibration SET temp_offset = 0.80 WHERE station_id = 'AWS-002';


-- [Step 3.3 — TERMINAL A] Request lock on Station 2 ('AWS-002', currently held by B):
UPDATE station_calibration SET temp_offset = 0.99 WHERE station_id = 'AWS-002';
-- OBSERVE: Terminal A now hangs waiting for Terminal B!


-- [Step 3.4 — TERMINAL B] Request lock on Station 1 ('AWS-001', currently held by A):
UPDATE station_calibration SET temp_offset = 0.99 WHERE station_id = 'AWS-001';
-- OBSERVE: Circular wait created! After ~1 second (deadlock_timeout = 1s),
-- PostgreSQL traverses the wait-for graph, detects the cycle, and raises:
--   ERROR:  deadlock detected (SQLSTATE 40P01)
--   DETAIL: Process XXXX waits for ShareLock on transaction YYY; blocked by process ZZZZ.
--           Process ZZZZ waits for ShareLock on transaction WWW; blocked by process XXXX.
-- Meanwhile, Terminal A immediately unblocks and succeeds!


-- [Step 3.5 — CLEANUP BOTH TERMINALS]
-- In Terminal A (which succeeded):
COMMIT;
-- In Terminal B (which was aborted by the deadlock detector):
ROLLBACK;

-- PRODUCTION ENGINEERING RULE:
-- 1. Always lock/update multi-row batches in deterministic primary-key order (ORDER BY station_id)
--    so two workers can never lock rows in opposite directions!
-- 2. Always wrap database transactions in application retry loops catching SQLSTATE '40P01'.


-- ============================================================================
-- LAB 4: READ COMMITTED (DEFAULT) VS. REPEATABLE READ ISOLATION LEVELS
-- Objective: Prove how READ COMMITTED takes a fresh snapshot at the start of
--            EVERY statement (allowing Non-Repeatable Reads), whereas
--            REPEATABLE READ pins the snapshot at the FIRST statement of the
--            transaction for consistent multi-query meteorological analytics.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PART 4A: Default READ COMMITTED Behavior (Statement-Level Snapshot)
-- ----------------------------------------------------------------------------

-- [Step 4A.1 — TERMINAL B] Start a default READ COMMITTED transaction and read AWS-003:
BEGIN;
SHOW transaction_isolation; -- outputs: read committed
SELECT station_id, temp_offset FROM station_calibration WHERE station_id = 'AWS-003';
-- Expected Output: 0.00


-- [Step 4A.2 — TERMINAL A] Update and immediately COMMIT a change to AWS-003:
UPDATE station_calibration SET temp_offset = 9.99 WHERE station_id = 'AWS-003';
-- (Autocommit executes and commits immediately)


-- [Step 4A.3 — TERMINAL B] Re-run the exact same SELECT inside the STILL-OPEN transaction:
SELECT station_id, temp_offset FROM station_calibration WHERE station_id = 'AWS-003';
-- Expected Output: 9.99!
-- Why? Under READ COMMITTED, PostgreSQL takes a brand-new snapshot for each SQL statement,
-- so Terminal B sees Terminal A's newly committed value midway through its own transaction!
COMMIT;


-- ----------------------------------------------------------------------------
-- PART 4B: REPEATABLE READ Behavior (Transaction-Level Pinned Snapshot)
-- ----------------------------------------------------------------------------

-- [Step 4B.1 — TERMINAL B] Start a REPEATABLE READ transaction and read AWS-003:
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SHOW transaction_isolation; -- outputs: repeatable read
SELECT station_id, temp_offset FROM station_calibration WHERE station_id = 'AWS-003';
-- Expected Output: 9.99 (Snapshot is now pinned for the lifetime of this transaction!)


-- [Step 4B.2 — TERMINAL A] Reset AWS-003 back to 0.00 and commit immediately:
UPDATE station_calibration SET temp_offset = 0.00 WHERE station_id = 'AWS-003';


-- [Step 4B.3 — TERMINAL B] Re-run the SELECT inside the pinned REPEATABLE READ transaction:
SELECT station_id, temp_offset FROM station_calibration WHERE station_id = 'AWS-003';
-- Expected Output: Still 9.99! (Ignores Terminal A's commit completely!)

-- Bonus Test in Terminal B: What happens if a REPEATABLE READ transaction tries to
-- UPDATE a row that another transaction modified after our snapshot began?
UPDATE station_calibration SET temp_offset = 1.11 WHERE station_id = 'AWS-003';
-- Expected Output:
--   ERROR: could not serialize access due to concurrent update (SQLSTATE 40001)
ROLLBACK;

-- Now outside the old snapshot, Terminal B sees the latest state (0.00):
SELECT station_id, temp_offset FROM station_calibration WHERE station_id = 'AWS-003';


-- ============================================================================
-- LAB 5: BONUS — SYNOPTIC STATIONS (`synoptic.stations`) LIVE COURSEBOOK DEMO
-- (Matches Day 2 Master Coursebook Lab 3A on Algiers - Dar El Beida 60390)
-- ============================================================================

-- [TERMINAL A]
BEGIN;
SELECT pg_current_xact_id(), pg_current_snapshot();
UPDATE synoptic.stations SET elevation_m = 26.5 WHERE station_id = 60390;
SELECT ctid, xmin, xmax, station_id, station_name, elevation_m FROM synoptic.stations WHERE station_id = 60390;

-- [TERMINAL B]
SELECT ctid, xmin, xmax, station_id, station_name, elevation_m FROM synoptic.stations WHERE station_id = 60390;

-- [TERMINAL A]
COMMIT;


-- ============================================================================
-- SECTION 6: DBA EMERGENCY DIAGNOSTIC & SESSION TERMINATION TOOLKIT
-- ============================================================================

-- 1. View All Active Non-Idle Transactions Ordered by Age:
SELECT 
    pid, 
    usename, 
    application_name,
    client_addr, 
    state, 
    wait_event_type,
    wait_event,
    NOW() - xact_start  AS txn_duration, 
    NOW() - query_start AS query_duration,
    LEFT(query, 90)     AS current_query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY txn_duration DESC NULLS LAST;

-- 2. Spot "idle in transaction" Sessions (The #1 Culprit Behind MVCC Table Bloat!):
--    Any session stuck in 'idle in transaction' pins the global xmin horizon and
--    prevents VACUUM from reclaiming dead tuples across the entire database.
SELECT 
    pid, 
    usename, 
    application_name,
    state, 
    NOW() - xact_start   AS open_txn_age,
    NOW() - state_change AS idle_duration,
    LEFT(query, 90)      AS last_executed_query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY idle_duration DESC;

-- 3. Emergency Cancel or Terminate a Stuck Blocking Backend PID:
--    (Replace 12345 with the actual blocking_pid from pg_stat_activity)
--
--    a) Graceful Query Cancel (sends SIGINT — aborts current query, keeps connection):
--       SELECT pg_cancel_backend(12345);
--
--    b) Forceful Session Termination (sends SIGTERM — disconnects & rolls back open txn):
--       SELECT pg_terminate_backend(12345);

-- 4. Automated Guard-Rail Against Forgotten Transactions & Hung Lock Waits:
--    Apply at database, role, or session level in production:
--    ALTER DATABASE weather_ops SET idle_in_transaction_session_timeout = '60s';
--    ALTER DATABASE weather_ops SET lock_timeout = '5s';
--    ALTER DATABASE weather_ops SET statement_timeout = '30s';
