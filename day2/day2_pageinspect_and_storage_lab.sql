-- ============================================================================
-- DAY 2 HANDS-ON FORENSICS LAB: PAGEINSPECT, TUPLE TETRIS, MVCC & EXPLAIN BUFFERS
-- File: day2_pageinspect_and_storage_lab.sql
-- Usage: psql -U postgres -d weather_ops -f day2_pageinspect_and_storage_lab.sql
-- ============================================================================

\pset pager off
\timing on
SET timezone = 'UTC';

-- Enable physical block & bloat forensics extensions
CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE EXTENSION IF NOT EXISTS pgstattuple;

-- ============================================================================
-- LAB 1: CPU BYTE-ALIGNMENT PADDING & "TUPLE TETRIS" (SAVING 8 TO 16 BYTES/ROW)
-- Objective: Prove how column ordering eliminates invisible CPU alignment padding
-- ============================================================================

-- Part 1A: 16-Byte Tuple Tetris Savings (Interleaved 1B / 8B / 2B / 8B / 1B / 8B)
DROP TABLE IF EXISTS telemetry_unaligned CASCADE;
DROP TABLE IF EXISTS telemetry_aligned CASCADE;

-- UNOPTIMIZED: Interleaving 1-byte/2-byte columns with 8-byte columns forces
-- 7 bytes + 6 bytes + 7 bytes of internal padding (56 bytes total tuple length!)
CREATE TABLE telemetry_unaligned (
    is_active     BOOLEAN,          -- 1B + 7B PADDING (to align next 8B column)
    recorded_at   TIMESTAMPTZ,      -- 8B (offset 8)
    wind_dir_deg  SMALLINT,         -- 2B + 6B PADDING (to align next 8B column)
    latitude      DOUBLE PRECISION, -- 8B (offset 24)
    sensor_fault  BOOLEAN,          -- 1B + 7B PADDING (to align next 8B column)
    longitude     DOUBLE PRECISION, -- 8B (offset 40)
    station_num   INTEGER,          -- 4B (offset 48)
    temperature   REAL              -- 4B (offset 52 -> total payload 56B + 24B header = 80B)
);

-- OPTIMIZED ("Tuple Tetris"): Order strictly 8B -> 4B -> 2B -> 1B
-- Eliminates 16 bytes of wasted padding per row (40 bytes payload + 24B header = 64B!)
CREATE TABLE telemetry_aligned (
    recorded_at   TIMESTAMPTZ,      -- 8B (offset 0)
    latitude      DOUBLE PRECISION, -- 8B (offset 8)
    longitude     DOUBLE PRECISION, -- 8B (offset 16)
    station_num   INTEGER,          -- 4B (offset 24)
    temperature   REAL,             -- 4B (offset 28)
    wind_dir_deg  SMALLINT,         -- 2B (offset 32)
    is_active     BOOLEAN,          -- 1B (offset 34)
    sensor_fault  BOOLEAN           -- 1B (offset 35 + 4B tail padding = 40B payload)
);

INSERT INTO telemetry_unaligned
SELECT true, NOW(), 270::SMALLINT, 36.6910, false, 3.2154, 60390, 22.5
FROM generate_series(1, 10000);

INSERT INTO telemetry_aligned
SELECT NOW(), 36.6910, 3.2154, 60390, 22.5, 270::SMALLINT, true, false
FROM generate_series(1, 10000);

-- Compare exact row size via pg_column_size() and physical lp_len via pageinspect
(
    SELECT
        'telemetry_unaligned' AS table_design,
        pg_column_size(t.*)   AS row_bytes_pg_column_size,
        pg_size_pretty(pg_relation_size('telemetry_unaligned')) AS table_heap_size
    FROM telemetry_unaligned t
    LIMIT 1
)
UNION ALL
(
    SELECT
        'telemetry_aligned'   AS table_design,
        pg_column_size(t.*)   AS row_bytes_pg_column_size,
        pg_size_pretty(pg_relation_size('telemetry_aligned'))   AS table_heap_size
    FROM telemetry_aligned t
    LIMIT 1
);

-- Part 1B: Coursebook 4-Column Pageinspect Comparison (48 Bytes vs. 40 Bytes on Disk)
DROP TABLE IF EXISTS layout_padded CASCADE;
DROP TABLE IF EXISTS layout_packed CASCADE;

CREATE TABLE layout_padded (
    flag_a      BOOLEAN,
    recorded_at TIMESTAMPTZ,
    flag_b      BOOLEAN,
    reading_val DOUBLE PRECISION
);

CREATE TABLE layout_packed (
    recorded_at TIMESTAMPTZ,
    reading_val DOUBLE PRECISION,
    flag_a      BOOLEAN,
    flag_b      BOOLEAN
);

INSERT INTO layout_padded
SELECT true, NOW(), false, 42.125 FROM generate_series(1, 10000);

INSERT INTO layout_packed
SELECT NOW(), 42.125, true, false FROM generate_series(1, 10000);

-- 1. Inspect Block 0 Page Header (24-byte PageHeaderData)
SELECT
    lsn,
    checksum,
    flags,
    lower AS free_space_start_byte,
    upper AS free_space_end_byte,
    special,
    pagesize
FROM page_header(get_raw_page('layout_padded', 0));

-- 2. Inspect Tuple Physical Lengths on Disk (48 bytes vs 40 bytes)
SELECT
    'layout_padded' AS table_name,
    lp,
    lp_off,
    lp_flags,
    lp_len AS physical_bytes_on_disk,
    t_xmin,
    t_ctid
FROM heap_page_items(get_raw_page('layout_padded', 0))
LIMIT 3;

SELECT
    'layout_packed' AS table_name,
    lp,
    lp_off,
    lp_flags,
    lp_len AS physical_bytes_on_disk,
    t_xmin,
    t_ctid
FROM heap_page_items(get_raw_page('layout_packed', 0))
LIMIT 3;


-- ============================================================================
-- LAB 2: MVCC TUPLE VERSIONING & HEAP FORENSICS (t_xmin, t_xmax, t_ctid, HOT)
-- Objective: Observe out-of-place tuple appends and ctid version chaining on UPDATE
-- ============================================================================

DROP TABLE IF EXISTS mvcc_demo CASCADE;
CREATE TABLE mvcc_demo (
    id      INT PRIMARY KEY,
    reading REAL
);

-- 1. Insert Initial Row (Transaction 1)
INSERT INTO mvcc_demo VALUES (1, 19.5);

-- Inspect physical tuple header after INSERT
SELECT
    lp,
    lp_off,
    lp_flags,
    lp_len AS bytes,
    t_xmin,
    t_xmax,
    t_ctid,
    t_infomask
FROM heap_page_items(get_raw_page('mvcc_demo', 0));

-- 2. Update the Row (Transaction 2)
UPDATE mvcc_demo SET reading = 23.8 WHERE id = 1;

-- Inspect physical page items after UPDATE:
-- Observe Tuple 1 (lp=1) now has t_xmax set and t_ctid pointing to (0,2),
-- while Tuple 2 (lp=2) is the new live version at (0,2)!
SELECT
    lp,
    lp_off,
    lp_flags,
    lp_len AS bytes,
    t_xmin,
    t_xmax,
    t_ctid,
    t_infomask,
    t_infomask2
FROM heap_page_items(get_raw_page('mvcc_demo', 0));


-- ============================================================================
-- LAB 3: STANDARD VACUUM vs. VACUUM FULL (PHYSICAL BLOAT RECLAMATION)
-- Objective: Prove why standard VACUUM reuses in-page space via FSM without
-- shrinking the OS file, whereas VACUUM FULL rewrites a new relfilenode.
-- ============================================================================

DROP TABLE IF EXISTS bloat_lab CASCADE;
CREATE TABLE bloat_lab (
    id         SERIAL PRIMARY KEY,
    station_id VARCHAR(10),
    reading    DOUBLE PRECISION,
    padding    TEXT
);

-- Insert 100,000 rows
INSERT INTO bloat_lab (station_id, reading, padding)
SELECT
    'AWS-' || LPAD((g % 50)::TEXT, 3, '0'),
    random() * 40.0,
    repeat('X', 128)
FROM generate_series(1, 100000) AS g;

SELECT
    pg_relation_filepath('bloat_lab')                       AS initial_filepath,
    pg_size_pretty(pg_total_relation_size('bloat_lab'))     AS initial_size;

-- Update 80% of rows to generate 80,000 dead tuples
UPDATE bloat_lab SET reading = reading + 1.0 WHERE id > 20000;

-- Measure physical dead tuple bloat using pgstattuple
SELECT
    table_len                          AS total_bytes,
    tuple_count                        AS live_tuples,
    dead_tuple_count                   AS dead_tuples,
    ROUND(dead_tuple_percent::numeric, 2) AS dead_pct,
    ROUND(free_percent::numeric, 2)       AS free_pct
FROM pgstattuple('bloat_lab');

-- Run Standard Concurrent VACUUM
VACUUM bloat_lab;

SELECT
    'After Standard VACUUM'                                 AS stage,
    pg_relation_filepath('bloat_lab')                       AS filepath_unchanged,
    pg_size_pretty(pg_total_relation_size('bloat_lab'))     AS disk_size_unchanged,
    dead_tuple_count                                        AS dead_tuples_now_zero,
    ROUND(free_percent::numeric, 2)                         AS reusable_fsm_free_pct
FROM pgstattuple('bloat_lab');

-- Run Destructive VACUUM FULL (Rewrites table into brand-new relfilenode)
VACUUM FULL bloat_lab;

SELECT
    'After VACUUM FULL'                                     AS stage,
    pg_relation_filepath('bloat_lab')                       AS new_relfilenode_filepath,
    pg_size_pretty(pg_total_relation_size('bloat_lab'))     AS compacted_disk_size,
    dead_tuple_count                                        AS dead_tuples,
    ROUND(free_percent::numeric, 2)                         AS free_pct
FROM pgstattuple('bloat_lab');


-- ============================================================================
-- LAB 4: PROFILING THE ROW-STORE SCAN PENALTY & COVERING INDEXES (1,000,000 ROWS)
-- Objective:
--   1. Prove the ~9.5x I/O amplification penalty of row-store sequential scans
--   2. Compare Seq Scan -> Bitmap Heap Scan -> Index Only Scan (INCLUDE)
-- ============================================================================

DROP TABLE IF EXISTS plan_lab CASCADE;
CREATE TABLE plan_lab (
    -- Ordered by alignment rule: 8B -> 4B -> variable
    recorded_at    TIMESTAMPTZ NOT NULL,
    id             SERIAL PRIMARY KEY,
    temperature    REAL,
    pressure       REAL,
    wind_speed     REAL,
    rain_accum_1m  REAL,
    wind_direction SMALLINT,
    station_id     VARCHAR(10) NOT NULL,
    payload        TEXT
) WITH (fillfactor = 100);

-- Synthesize 1,000,000 high-frequency sensor observations
INSERT INTO plan_lab (
    recorded_at, station_id, temperature, pressure,
    wind_speed, wind_direction, rain_accum_1m, payload
)
SELECT
    TIMESTAMPTZ '2026-01-01 00:00:00+00' + (g * INTERVAL '2 seconds'),
    'AWS-' || LPAD((1 + (g % 50))::TEXT, 3, '0'),
    ROUND((15.0 + (sin(g / 1000.0) * 10.0) + (random() * 2.0))::numeric, 2),
    ROUND((1013.25 + (cos(g / 1000.0) * 5.0))::numeric, 2),
    ROUND((random() * 15.0)::numeric, 2),
    (random() * 359)::SMALLINT,
    0.0,
    repeat('A', 32)
FROM generate_series(1, 1000000) AS g;

ANALYZE plan_lab;

-- 4A. Demonstrate the Row-Store Analytical Scan I/O Amplification Penalty
-- Observe total 8KB buffers read vs. the 8 bytes/row (station_id + temperature) needed!
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT
    station_id,
    ROUND(AVG(temperature)::numeric, 2) AS mean_temp
FROM plan_lab
WHERE temperature > -900.0
GROUP BY station_id;

-- 4B. Phase 0 (Unoptimized): Selective 3-Hour Station Query -> Catastrophic Seq Scan
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT
    station_id,
    ROUND(AVG(temperature)::numeric, 2) AS avg_temp,
    MAX(temperature)                    AS peak_temp
FROM plan_lab
WHERE station_id = 'AWS-042'
  AND recorded_at BETWEEN '2026-01-10 00:00:00+00' AND '2026-01-10 03:00:00+00'
GROUP BY station_id;

-- 4C. Phase 1 (Single-Column Index): Bitmap Index Scan + Bitmap Heap Scan
CREATE INDEX idx_plan_lab_station ON plan_lab (station_id);
ANALYZE plan_lab;

EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT
    station_id,
    ROUND(AVG(temperature)::numeric, 2) AS avg_temp,
    MAX(temperature)                    AS peak_temp
FROM plan_lab
WHERE station_id = 'AWS-042'
  AND recorded_at BETWEEN '2026-01-10 00:00:00+00' AND '2026-01-10 03:00:00+00'
GROUP BY station_id;

-- 4D. Phase 2 (Composite Covering Index with INCLUDE): Sub-Millisecond Index-Only Scan!
CREATE INDEX idx_plan_lab_covering
ON plan_lab (station_id, recorded_at)
INCLUDE (temperature);

-- Freeze Visibility Map (_vm) so Index Only Scan achieves Heap Fetches: 0
VACUUM ANALYZE plan_lab;

EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT
    station_id,
    ROUND(AVG(temperature)::numeric, 2) AS avg_temp,
    MAX(temperature)                    AS peak_temp
FROM plan_lab
WHERE station_id = 'AWS-042'
  AND recorded_at BETWEEN '2026-01-10 00:00:00+00' AND '2026-01-10 03:00:00+00'
GROUP BY station_id;
