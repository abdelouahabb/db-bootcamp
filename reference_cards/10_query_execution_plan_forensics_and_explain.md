# Query Execution Plan Forensics: The `EXPLAIN` & Performance Optimization Reference Card

## Cost Modeling, Physical Access Methods, Join Algorithms, Memory Forensics, and Cross-Engine Plan Debugging

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./09_acid_transactions_and_two_terminal_lock_debugging.md) | **Card 10 of 14** | [Next Card ➡️](./11_python_database_drivers_for_weather_engineers.md)

## 🧭 Quick-Jump Table of Contents

- [Executive Summary for Systems & Database Engineers](#executive-summary-for-systems--database-engineers)
- [1. The Query Optimizer Pipeline: `EXPLAIN` vs. `EXPLAIN ANALYZE`](#1-the-query-optimizer-pipeline-explain-vs-explain-analyze)
  - [1.1 The Critical Distinction: Theoretical Plan vs. Physical Execution](#11-the-critical-distinction-theoretical-plan-vs-physical-execution)
- [2. Deconstructing the PostgreSQL Cost Model](#2-deconstructing-the-postgresql-cost-model)
  - [2.1 The Cost Currency: Arbitrary Page Fetch Units](#21-the-cost-currency-arbitrary-page-fetch-units)
  - [2.2 Mathematical Proof: Calculating a Sequential Scan Cost](#22-mathematical-proof-calculating-a-sequential-scan-cost)
- [3. Physical Access Methods & The Scan Hierarchy](#3-physical-access-methods--the-scan-hierarchy)
  - [3.1 Sequential Scan (`Seq Scan`)](#31-sequential-scan-seq-scan)
  - [3.2 Index Scan (`Index Scan`)](#32-index-scan-index-scan)
  - [3.3 Index-Only Scan (`Index Only Scan`)](#33-index-only-scan-index-only-scan)
  - [3.4 Bitmap Index Scan + Bitmap Heap Scan](#34-bitmap-index-scan--bitmap-heap-scan)
- [4. Physical Join Strategies: Mechanics and Failure Modes](#4-physical-join-strategies-mechanics-and-failure-modes)
  - [4.1 Nested Loop Join](#41-nested-loop-join)
  - [4.2 Hash Join](#42-hash-join)
  - [4.3 Merge Join](#43-merge-join)
- [5. Buffer & Memory Forensics: The `EXPLAIN (ANALYZE, BUFFERS)` Toolkit](#5-buffer--memory-forensics-the-explain-analyze-buffers-toolkit)
  - [5.1 Interpreting Buffer Metrics](#51-interpreting-buffer-metrics)
  - [5.2 Calculating the Buffer Cache Hit Ratio of a Query](#52-calculating-the-buffer-cache-hit-ratio-of-a-query)
  - [5.3 WorkMem and Sorting Forensics](#53-workmem-and-sorting-forensics)
- [6. The Cardinality Skew Trap: Root Cause of Bad Plans](#6-the-cardinality-skew-trap-root-cause-of-bad-plans)
  - [6.1 How the Optimizer Estimates Cardinality](#61-how-the-optimizer-estimates-cardinality)
  - [6.2 The Correlation Factor (`pg_stats.correlation`)](#62-the-correlation-factor-pg_statscorrelation)
  - [6.3 Fixing Correlated Multi-Column Blindspots (`CREATE STATISTICS`)](#63-fixing-correlated-multi-column-blindspots-create-statistics)
- [7. The 7 Deadly Sins of Execution Plans (Red-Flag Diagnostic Catalog)](#7-the-7-deadly-sins-of-execution-plans-red-flag-diagnostic-catalog)
- [8. Cross-Engine `EXPLAIN` Cheat Sheet](#8-cross-engine-explain-cheat-sheet)
  - [8.1 SQLite 3: `EXPLAIN QUERY PLAN`](#81-sqlite-3-explain-query-plan)
  - [8.2 MySQL 8.0+: `EXPLAIN FORMAT=TREE` & `EXPLAIN ANALYZE`](#82-mysql-80-explain-formattree--explain-analyze)
  - [8.3 DuckDB: Vectorized SIMD Execution Plans](#83-duckdb-vectorized-simd-execution-plans)
- [9. Hands-On Forensics Lab: Query Optimization in Action](#9-hands-on-forensics-lab-query-optimization-in-action)
  - [Step 1: Synthesize a Diagnostic Table (1,000,000 Rows)](#step-1-synthesize-a-diagnostic-table-1000000-rows)
  - [Step 2: The Unoptimized Query (The Catastrophic Plan)](#step-2-the-unoptimized-query-the-catastrophic-plan)
  - [Step 3: Optimization Phase 1 — Naive Single-Column Indexing](#step-3-optimization-phase-1--naive-single-column-indexing)
  - [Step 4: Optimization Phase 2 — Composite Covering Index (`INCLUDE`)](#step-4-optimization-phase-2--composite-covering-index-include)
- [10. Summary Checklist: Production Plan Debugging Directives](#10-summary-checklist-production-plan-debugging-directives)

---

### Executive Summary for Systems & Database Engineers

When a database query runs slowly, adding random indexes or blindly rewriting SQL statements is an anti-pattern. Relational database engines do not execute SQL code procedurally; they compile declarative SQL text into a physical execution tree of relational operators.

The **`EXPLAIN`** command exposes the Query Planner/Optimizer's internal decision tree. It reveals how the optimizer intends to fetch data (access paths), how it combines relations (join strategies), how much memory it will consume (`work_mem`), and where its mathematical cost estimates diverge from physical hardware reality.

This reference guide provides an exhaustive engineering breakdown of:

1. **The Query Lifecycle:** Parser $\to$ Analyzer/Rewriter $\to$ Cost-Based Optimizer (CBO) $\to$ Executor.

2. **Cost Formulas:** Deconstructing `cost=startup..total`, arbitrary disk page cost units, and CPU operator models.

3. **The Access Path Hierarchy:** `Seq Scan`, `Index Scan`, `Index Only Scan`, `Bitmap Index/Heap Scan`, and `TID Scan`.

4. **Physical Join Algorithms:** `Nested Loop`, `Hash Join` (and disk spills), and `Merge Join`.

5. **Buffer & Memory Forensics:** Interpreting `EXPLAIN (ANALYZE, BUFFERS, WAL, TIMING)` shared hit/read ratios and memory allocations.

6. **The Cardinality Skew Trap:** Root causes of catastrophic plan selection ($100\times\text{--}1000\times$ estimation errors).

7. **The 7 Deadly Sins of Execution Plans:** An actionable red-flag diagnostic catalog.

8. **Cross-Engine Syntax & Reading Matrix:** PostgreSQL, SQLite (`EXPLAIN QUERY PLAN`), MySQL (`FORMAT=TREE`), and DuckDB.

9. **Hands-On Query Optimization Lab:** A reproducible SQL performance triage from catastrophic scan to sub-millisecond execution.

## 1. The Query Optimizer Pipeline: `EXPLAIN` vs. `EXPLAIN ANALYZE`

Every SQL query passes through four discrete architectural subsystems before a single byte of data is returned to the client application:

```
                            The Relational Engine Pipeline
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ 1. PARSER           : Validates syntax; builds Abstract Syntax Tree (AST)   │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ 2. ANALYZER/REWRITER: Resolves catalog names (tables, types), applies views, │
 │                       and expands rewrite rules                             │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ 3. COST-BASED OPTIMIZER (CBO) [EXPLAIN]                                     │
 │    • Evaluates mathematically equivalent relational algebra permutations    │
 │    • Consults catalog statistics (pg_statistic, histograms, MCVs)           │
 │    • Generates candidate physical execution trees; selects lowest total cost│
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │ Physical Plan Tree
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ 4. EXECUTOR [EXPLAIN ANALYZE]                                               │
 │    • Drives Volcano iterator / Vector engine (.next() / Morsel)             │
 │    • Fetches 8 KB pages from shared_buffers or storage NVMe                 │
 │    • Measures physical elapsed wall-clock time and real row counts          │
 └─────────────────────────────────────────────────────────────────────────────┘

```

### 1.1 The Critical Distinction: Theoretical Plan vs. Physical Execution

| Dimension | `EXPLAIN` (Dry-Run Estimation) | `EXPLAIN ANALYZE` (Physical Execution) | 
| ----- | ----- | ----- | 
| **Executes the Query?** | **NO.** Zero data blocks are read; no writes occur. | **YES.** The query is **fully executed** to completion. | 
| **Data Modifications?** | Safe to run on `DELETE` / `UPDATE` / `INSERT`. | **DANGER:** Running on `DELETE` will **permanently delete** data! | 
| **Row Counts** | **Estimated** by the Cost-Based Optimizer (`rows=N`). | **Actual** observed rows processed (`actual rows=N`). | 
| **Timings** | None (pure mathematical simulation). | Microsecond-accurate wall-clock timings per operator. | 
| **I/O & Buffer Metrics** | None. | Reports exact pages read, cached, dirtied, and written. | 
| **Execution Overhead** | Zero ($\approx 0.1\text{ ms}$ optimizer planning time). | Adds instrumentation timer overhead ($5\%\text{--}20\%$ CPU tax). | 

> **Production Warning:** Running `EXPLAIN ANALYZE DELETE FROM raw_telemetry;` will delete the entire table. To analyze data modification queries safely without persisting mutations, wrap them in an explicit transaction rollback:
>
> ```
> BEGIN;
> EXPLAIN ANALYZE DELETE FROM raw_telemetry WHERE recorded_at < '2026-01-01';
> ROLLBACK;
> 
> ```

## 2. Deconstructing the PostgreSQL Cost Model

When you inspect an `EXPLAIN` output node, you observe:

```
Seq Scan on raw_telemetry  (cost=0.00..38450.00 rows=1999980 width=36)

```

This node contains four fundamental planning variables:

* **`cost=0.00` (Startup Cost):** The estimated effort required before the first row can be returned by this node.

* **`38450.00` (Total Cost):** The estimated effort to execute the node to completion (returning all matching rows).

* **`rows=1999980`:** The optimizer's mathematical estimate of how many rows will survive this node's filters.

* **`width=36`:** The estimated average size of each returned row in physical bytes.

```
                  Cost Metric Anatomy: Startup vs. Total
 
                      cost = [ Startup Cost ] .. [ Total Cost ]
                                    │                   │
  Time to return FIRST row ─────────┘                   └──────── Time to finish node
  
  Example 1: Seq Scan         (cost=0.00..38450.00)     -> Returns row 1 immediately!
  Example 2: Sort (ORDER BY)  (cost=28400.00..31200.00) -> MUST read & sort ALL rows
                                                           before row 1 can be emitted!

```

### 2.1 The Cost Currency: Arbitrary Page Fetch Units

Cost is **not measured in milliseconds or seconds**. Cost is a dimensionless, arbitrary unit calibrated against a single baseline constant:

$$
\mathbf{1.0\text{ Cost Unit}} \equiv \text{The cost of fetching a single } 8\text{ KB page sequentially from disk } (\texttt{seq\_page\_cost})
$$

The default planner configuration establishes these foundational unit weights:

| Planner Parameter | Default Value | Meaning | Production NVMe Tuning Recommendation | 
| ----- | ----- | ----- | ----- | 
| `seq_page_cost` | `1.0` | Cost of a sequential 8 KB page fetch from disk. | `1.0` (Leave as baseline). | 
| `random_page_cost` | `4.0` | Cost of a random 8 KB page seek (calibrated for spinning HDDs). | **`1.1` to `1.25`** on fast enterprise NVMe SSDs. | 
| `cpu_tuple_cost` | `0.01` | CPU processing cost to parse and evaluate one row. | `0.01` | 
| `cpu_index_tuple_cost` | `0.005` | CPU processing cost to inspect one index entry. | `0.005` | 
| `cpu_operator_cost` | `0.0025` | CPU cost to evaluate a `WHERE` operator (e.g. `+`, `<`, `AND`). | `0.0025` | 

> **The NVMe Tuning Imperative:** If `random_page_cost` is left at the historical default of `4.0` on an enterprise NVMe server, the planner falsely assumes that random index lookups are $4\times$ more expensive than sequential scans. This causes the optimizer to abandon healthy B-Tree indexes in favor of slow, full-table sequential scans. Set `random_page_cost = 1.1` on SSD/NVMe systems.

### 2.2 Mathematical Proof: Calculating a Sequential Scan Cost

Assume table `raw_telemetry` contains:

* $N = 2,000,000$ rows (`reltuples = 2000000`)

* $P = 18,520$ physical 8 KB pages on disk (`relpages = 18520`)

* Query: `SELECT * FROM raw_telemetry WHERE temperature > 25.0;`

The optimizer evaluates total cost mathematically:

$$
\text{Cost}_{\text{I/O}} = P \times \text{seq\_page\_cost} = 18,520 \times 1.0 = \mathbf{18,520.0}
$$

$$
\text{Cost}_{\text{CPU\_tuples}} = N \times \text{cpu\_tuple\_cost} = 2,000,000 \times 0.01 = \mathbf{20,000.0}
$$

$$
\text{Cost}_{\text{CPU\_operators}} = N \times \text{cpu\_operator\_cost} = 2,000,000 \times 0.0025 = \mathbf{5,000.0}
$$

$$
\text{Total Cost} = \text{Cost}_{\text{I/O}} + \text{Cost}_{\text{CPU\_tuples}} + \text{Cost}_{\text{CPU\_operators}} = 18,520 + 20,000 + 5,000 = \mathbf{43,520.0}
$$

The cost displayed in `EXPLAIN` matches this mathematical derivation exactly.

## 3. Physical Access Methods & The Scan Hierarchy

When a query demands rows from a table, the executor selects one of five physical access strategies:

```
                      The 5 Physical Access Paths in PostgreSQL
 
 1. Seq Scan           [══════════════════════════════════════════════] Reads 100% of blocks
 
 2. Index Scan         [Index Tree] ──> Random Heap Hop (Block 4, Off 1) ──> Fetch Row
 
 3. Index Only Scan    [Index Tree] ──> Inspect Visibility Map ──> Returns directly from RAM!
 
 4. Bitmap Index Scan  [Index Tree] ──> Builds RAM Bitmap ──> Sorted Sequential Heap Read
 
 5. TID Scan           Physical CTID (0, 3) ──> Instant Block Seek (< 0.01 ms)

```

### 3.1 Sequential Scan (`Seq Scan`)

* **How it operates:** Reads the table heap sequentially from physical Block 0 to EOF, feeding every tuple through the filter qualification engine.

* **When it is optimal:**

  1. Small tables ($< 500$ blocks) where index traversal overhead exceeds sequential read speed.

  2. Broad analytical queries reading $> 15\%\text{--}25\%$ of the table's total tuples.

* **When it is catastrophic:** Point queries or selective filters on tables with millions of rows.

### 3.2 Index Scan (`Index Scan`)

* **How it operates:**

  1. Traverses the B-Tree from the root node to the matching leaf node ($O(\log N)$).

  2. Extracts the tuple's physical disk coordinate (`CTID = (block, offset)`).

  3. Performs a random I/O hop into the table heap to retrieve the full row payload.

* **When it is optimal:** Selective point queries or small range scans fetching $< 5\%$ of table rows.

* **The Cliff:** If the query matches 500,000 rows, an Index Scan performs 500,000 individual random seeks into heap pages, causing severe storage controller queue thrashing.

### 3.3 Index-Only Scan (`Index Only Scan`)

* **How it operates:** The queried columns are completely contained within the index itself (a "Covering Index").

* **The Visibility Map Catch:** Because MVCC tuple visibility flags (`t_xmin`, `t_xmax`) reside in the heap, how does the engine know if an indexed row is visible to the active transaction?

  * It consults the table's **Visibility Map (`_vm`)**.

  * If the target page is flagged as all-visible, the engine returns the value directly from index memory with **zero heap page reads**.

  * If the page is not flagged in the `_vm`, it must execute a random heap read (reported as `Heap Fetches: N` in `EXPLAIN`).

### 3.4 Bitmap Index Scan + Bitmap Heap Scan

* **How it operates:** The architectural bridge between Index Scans and Sequential Scans.

  1. **Bitmap Index Scan:** Traverses the index and builds an in-memory bitset (array of 1s and 0s) representing physical block and tuple IDs that match the filter.

  2. **Bitmap Heap Scan:** Sorts the bitmap by physical disk block address, then reads the required heap blocks **sequentially in physical order**, completely eliminating backward random seeks.

* **Multi-Index AND/OR Combinations:** Enables combining two independent indexes on the fly using bitmap operations:

  ```
  BitmapAnd
    -> Bitmap Index Scan on idx_station_id
    -> Bitmap Index Scan on idx_recorded_at
  
  ```

* **Lossy vs. Exact Bitmaps:** If the bitmap exceeds the allocated `work_mem`, PostgreSQL downgrades the bitmap from tuple-level precision to page-level precision (**Lossy Bitmap**). It fetches entire pages and rechecks filters, increasing CPU utilization (`Recheck Cond:`).

## 4. Physical Join Strategies: Mechanics and Failure Modes

When combining two relations, the optimizer selects one of three core join algorithms:

```
                            The Three Join Algorithms
 
   A. Nested Loop Join           B. Hash Join                   C. Merge Join
 
   Outer Loop: For each row      1. Build Hash Table (RAM)       1. Both inputs pre-sorted
   ┌──────────────────────┐         ┌───────────────────┐           ┌───────────────────┐
   │ Outer Tuple 1        │         │ Inner Relation    │           │ Sorted Stream A   │
   └──────────┬───────────┘         └─────────┬─────────┘           ├───────────────────┤
              │ Probe Index                   │ In-Memory Buckets   │ Sorted Stream B   │
              ▼                               ▼                     └─────────┬─────────┘
   ┌──────────────────────┐      2. Stream Outer Relation                     │
   │ Inner Index Lookup   │         ┌───────────────────┐                     ▼
   └──────────────────────┘         │ Probe Hash Table  │           Single Linear Zip Pass
                                    └───────────────────┘           (Zero Memory Spills!)

```

### 4.1 Nested Loop Join

* **Algorithm:** Iterates over the outer relation row-by-row; for each outer row, searches the inner relation (typically using an index).

* **Cost Complexity:** $O(M \times \log N)$ where $M$ is outer rows, $N$ is inner rows.

* **When it is optimal:** Small outer table (e.g., 5 weather stations) joining against a indexed massive table (5,000,000 observations).

* **The Failure Mode:** If the outer table cardinality is miscalculated (e.g., optimizer expects 2 rows, but receives 200,000 rows), the executor executes 200,000 inner index scans, locking CPU threads for minutes.

### 4.2 Hash Join

* **Algorithm:**

  1. **Build Phase:** Scans the inner relation and builds an in-memory hash table over the join keys.

  2. **Probe Phase:** Sequentially scans the outer relation, hashes its join key, and probes the hash table for matches.

* **Cost Complexity:** $O(M + N)$ linear time.

* **Memory Limits (`work_mem`):**

  * If the inner table hash fits in `work_mem`, it executes as an ultra-fast **Single-Batch Hash Join**.

  * If the hash exceeds `work_mem`, the planner splits the data into multiple batches and **spills temporary hash partitions to disk** (`Batches: 4  Memory Usage: 32768kB  Disk Usage: 104856kB`), causing severe I/O penalties.

### 4.3 Merge Join

* **Algorithm:** Both relations must be pre-sorted on the join keys. The executor scans both streams concurrently, zipping them together in a single synchronized linear sweep.

* **Cost Complexity:** $O(M + N)$ (assuming pre-sorted data).

* **When it is optimal:** Massive joins where relations are already sorted by an existing B-Tree index or when memory is too constrained for large hash tables.

## 5. Buffer & Memory Forensics: The `EXPLAIN (ANALYZE, BUFFERS)` Toolkit

Running standard `EXPLAIN` without buffer introspection hides root causes. The production standard for execution plan forensics is:

```
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING) 
SELECT station_id, AVG(temperature) 
FROM raw_telemetry 
WHERE recorded_at >= NOW() - INTERVAL '7 days' 
GROUP BY station_id;

```

### 5.1 Interpreting Buffer Metrics

```
Buffers: shared hit=4102 read=1204 dirtied=18 written=2

```

* **`shared hit`:** The number of 8 KB blocks found already cached in PostgreSQL's `shared_buffers` in RAM. (Access latency: $< 1\text{ }\mu\text{s}$).

* **`shared read`:** The number of 8 KB blocks that were **not** in `shared_buffers` and had to be fetched via operating system system calls from physical storage / Linux OS Page Cache. (Access latency: $10\text{--}100\text{ }\mu\text{s}$ on NVMe; $5\text{--}10\text{ ms}$ on HDD).

* **`shared dirtied`:** The number of 8 KB blocks modified in memory by this query (e.g., hint bits written during visibility evaluation).

* **`shared written`:** The number of 8 KB blocks pushed to disk by this query backend due to buffer pool eviction pressure.

### 5.2 Calculating the Buffer Cache Hit Ratio of a Query

$$
\text{Query Buffer Hit Ratio} = \frac{\text{shared hit}}{\text{shared hit} + \text{shared read}} \times 100
$$

* **Target:** Production queries should achieve $\ge 99\%$ buffer cache hit ratios.

* If `shared read` dominates, your working set exceeds `shared_buffers`, forcing heavy disk read operations.

### 5.3 WorkMem and Sorting Forensics

When a query contains `ORDER BY`, `DISTINCT`, or hash aggregations, inspect the sort execution details:

```
Sort Method: quicksort  Memory: 2840kB

```

* **Optimal:** `quicksort` or `top-N heapsort` executing entirely in RAM (`Memory: N kB`).

```
Sort Method: external merge  Disk: 42100kB

```

* **CATASTROPHIC:** The dataset exceeded `work_mem`. The executor paused, wrote intermediate sort runs to temporary disk files (`/base/pgsql_tmp/`), and performed an external merge sort from disk, causing massive disk write/read amplification.

* **Remediation:** Increase `work_mem` for the query session:

  ```
  SET work_mem = '128MB';
  
  ```

## 6. The Cardinality Skew Trap: Root Cause of Bad Plans

The most common cause of slow queries is not missing indexes, but **Cardinality Estimation Skew**.

```
                         The Cardinality Skew Cascade
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ Outdated Statistics in pg_statistic (e.g., Table expanded 100x since vacuum)│
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ Optimizer Estimates: rows=2  (Expects almost zero rows)                     │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │ Selects algorithm suited ONLY for 2 rows!
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ Optimizer Choice: Nested Loop Join without Index                            │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │ Runtime Reality Strikes!
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ Actual Execution: actual rows=1,500,000 (Loops=1,500,000!)                  │
 │ RESULT: Query locks CPU cores and runs for 45 minutes instead of 200 ms!    │
 └─────────────────────────────────────────────────────────────────────────────┘

```

### 6.1 How the Optimizer Estimates Cardinality

The Cost-Based Optimizer inspects system catalogs populated by `ANALYZE`:

* **`pg_class.reltuples`:** Total estimated row count.

* **`pg_class.relpages`:** Total physical 8 KB blocks.

* **`pg_stats`:**

  * `null_frac`: Percentage of `NULL` values.

  * `n_distinct`: Number of distinct values (positive integer = count; negative = fraction of table).

  * `most_common_vals` (MCV) & `most_common_freqs` (MCF): Top frequent values and their exact probabilities.

  * `histogram_bounds`: Divides the remaining non-MCV values into equal-frequency buckets.

### 6.2 The Correlation Factor (`pg_stats.correlation`)

Inspect physical disk correlation:

```
SELECT attname, correlation 
FROM pg_stats 
WHERE tablename = 'raw_telemetry';

```

* **`correlation = 1.0`:** Data is ordered contiguously on disk matching the index (e.g., sequential timestamps). Index Scans are fast and read contiguous disk pages.

* **`correlation \approx 0.0`:** Data is physically scattered across disk pages at random. Index Scans will jump back and forth across thousands of disparate 8 KB blocks, driving `random_page_cost` through the roof.

### 6.3 Fixing Correlated Multi-Column Blindspots (`CREATE STATISTICS`)

By default, PostgreSQL calculates column statistics independently. It assumes attributes are completely uncorrelated:

$$
P(A \land B) = P(A) \times P(B)
$$

In meteorological databases, atmospheric attributes are physically coupled:

* `WHERE region = 'SAHARA_NORTH' AND temperature > 40.0`

* The optimizer multiplies the probability of Sahara by the probability of high temperature, calculating a tiny predicted row count (`rows=10`). In reality, high temperatures occur regularly in the Sahara (`actual rows=500000`).

#### The Fix: Extended Statistics

```
-- Tell the optimizer that region and temperature are physically correlated!
CREATE STATISTICS stat_region_temp ON region, temperature FROM raw_telemetry;
ANALYZE raw_telemetry;

```

## 7. The 7 Deadly Sins of Execution Plans (Red-Flag Diagnostic Catalog)

When auditing an execution plan, scan for these seven critical anti-patterns:

| \# | Diagnostic Symptom | Root Cause | Engineering Remediation | 
| ----- | ----- | ----- | ----- | 
| **1** | `Seq Scan` on a multi-million-row table with high selective filters. | Missing index, unindexed foreign key, or `random_page_cost` set too high. | Create B-Tree/BRIN index; lower `random_page_cost = 1.1` on NVMe. | 
| **2** | `Sort Method: external merge Disk: N kB` | `work_mem` is too small to hold sorting payload in RAM. | Elevate session `SET work_mem = '64MB';` or optimize `SELECT` column list. | 
| **3** | `Hash Join Batches: > 1 Disk Usage: N kB` | Inner relation hash table exceeded `work_mem` and spilled to disk. | Elevate `work_mem` to allow single-batch in-memory hashing. | 
| **4** | **Extreme Cardinality Skew:** `rows=1` vs `actual rows=500000` (Ratio $> 100\times$). | Stale catalog statistics, correlation blindspots, or non-sargable functions. | Run `ANALYZE <table>;` or build extended statistics (`CREATE STATISTICS`). | 
| **5** | `Index Only Scan` with high `Heap Fetches: N` | Autovacuum has not processed the table; Visibility Map (`_vm`) pages are dirty. | Run `VACUUM <table>;` to freeze clean pages and update the Visibility Map. | 
| **6** | `Nested Loop` with high `loops=N` ($N > 10,000$). | Inner scan called tens of thousands of times due to cardinality underestimation. | Fix statistics, or add index on inner relation join key. | 
| **7** | `Rows Removed by Filter: N` ($N$ represents $> 90\%$ of rows read). | Filter condition evaluated in CPU *after* loading blocks, instead of using index. | Include filtered column in the index key or covering definition. | 

## 8. Cross-Engine `EXPLAIN` Cheat Sheet

Different database engines expose execution plans through distinct syntax and output conventions:

```
                            Cross-Engine Syntax Matrix
 ┌──────────────────────┬───────────────────────────────────────────────────────┐
 │ Engine               │ Recommended Production Diagnostic Invocation          │
 ├──────────────────────┼───────────────────────────────────────────────────────┤
 │ PostgreSQL 16+       │ EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING) <SQL>;   │
 │ SQLite 3.38+         │ EXPLAIN QUERY PLAN <SQL>;                             │
 │ MySQL (InnoDB 8.0+)  │ EXPLAIN FORMAT=TREE <SQL>; (or EXPLAIN ANALYZE <SQL>;)│
 │ DuckDB               │ EXPLAIN ANALYZE <SQL>;                                │
 └──────────────────────┴───────────────────────────────────────────────────────┘

```

### 8.1 SQLite 3: `EXPLAIN QUERY PLAN`

SQLite's plan generator reports high-level algorithmic intent:

```
EXPLAIN QUERY PLAN
SELECT station_id, AVG(temperature)
FROM raw_telemetry
WHERE recorded_at >= '2026-10-01 00:00:00'
GROUP BY station_id;

```

#### Reading SQLite Output:

* **`SCAN TABLE raw_telemetry`:** Sequential scan across entire database file (Danger on large tables).

* **`SEARCH TABLE raw_telemetry USING INDEX idx_time (recorded_at>?)`:** Efficient B-Tree lookup.

* **`SEARCH TABLE ... USING COVERING INDEX ...`:** Optimal. Direct fetch from index without touching table pages.

* **`USE TEMP B-TREE FOR GROUP BY`:** Memory allocation required to resolve aggregation buckets.

* **RED FLAG: `SCAN TABLE ... USING AUTOMATIC COVERING INDEX`:** SQLite detected a missing index, created an ephemeral B-Tree in RAM for this query, and dropped it immediately after. Create a permanent index on that column.

### 8.2 MySQL 8.0+: `EXPLAIN FORMAT=TREE` & `EXPLAIN ANALYZE`

MySQL 8.0 deprecated the confusing legacy tabular format in favor of structured trees and physical timings:

```
EXPLAIN FORMAT=TREE
SELECT s.station_name, AVG(r.temperature)
FROM stations s
JOIN raw_telemetry r ON s.station_id = r.station_id
WHERE r.recorded_at >= '2026-10-01'
GROUP BY s.station_name;

```

#### Reading MySQL Output:

```
-> Table scan on <temporary>  (actual time=48.2..49.1 rows=50 loops=1)
    -> Aggregate using temporary table
        -> Nested loop inner join  (cost=1240.25 rows=1250) (actual time=0.15..32.4 rows=1240 loops=1)
            -> Filter: (r.recorded_at >= TIMESTAMP'2026-10-01 00:00:00')  (cost=42.1)
                -> Index range scan on r using idx_time  (cost=42.1 rows=1240)
            -> Single-row index lookup on s using PRIMARY (station_id=r.station_id)

```

* Read from **bottom-most indented node upward**.

* Node displays: `cost=Estimated Cost`, `rows=Estimated Rows`, followed by `actual time=startup..total`, `rows=Actual Rows`, and `loops=Iteration Count`.

* **MySQL Join & Index Forensics:** Remember that MySQL 8.0.18+ supports `Hash Join` alongside `Nested Loop`, but does **not** implement `Sort-Merge Join`, and every non-covering secondary index lookup requires a second B+Tree traversal into the Clustered Primary Key (`PRIMARY`). See **[Reference Card 14: MySQL 8.0/8.4 & MariaDB Complete Engineering Guide](./14_mysql_and_mariadb_innodb_complete_engineering_guide.md)** for full InnoDB optimizer & `sys.statement_analysis` diagnostics.

### 8.3 DuckDB: Vectorized SIMD Execution Plans

DuckDB displays columnar operators, SIMD vector timings, and predicate pushdown status:

```
EXPLAIN ANALYZE
SELECT region, AVG(temperature)
FROM read_parquet('climatology_lake/**/*.parquet')
WHERE temperature > 35.0
GROUP BY region;

```

#### Reading DuckDB Output:

* **`SEQ_SCAN (Parquet)`:** Inspect `Filters: [temperature > 35.0]`. If present under `SEQ_SCAN`, DuckDB successfully pushed the filter into Parquet metadata, pruning row groups before reading pixels from disk.

* **`PERFECT_HASH_GROUP_BY`:** Hash aggregation executed entirely inside CPU vector registers without memory hash tables.

* **`Timing (N%)`:** Percentage of total CPU cycle time spent in each operator chunk.

## 9. Hands-On Forensics Lab: Query Optimization in Action

Run this reproducible laboratory in PostgreSQL (`psql`) to profile, diagnose, and optimize a failing query.

### Step 1: Synthesize a Diagnostic Table (1,000,000 Rows)

```
DROP TABLE IF EXISTS plan_lab CASCADE;
CREATE TABLE plan_lab (
    id SERIAL PRIMARY KEY,
    station_id VARCHAR(10) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    temperature REAL,
    pressure REAL,
    payload TEXT
);

-- Seed 1,000,000 observations
INSERT INTO plan_lab (station_id, recorded_at, temperature, pressure, payload)
SELECT 
    'AWS-' || LPAD((g % 100)::TEXT, 3, '0'),
    TIMESTAMPTZ '2026-01-01 00:00:00+00' + (g * INTERVAL '2 seconds'),
    ROUND((15.0 + random() * 25.0)::numeric, 2),
    ROUND((980.0 + random() * 40.0)::numeric, 2),
    repeat('A', 64)
FROM generate_series(1, 1000000) AS g;

-- Explicitly analyze catalog statistics
ANALYZE plan_lab;

```

### Step 2: The Unoptimized Query (The Catastrophic Plan)

Execute an operational storm query searching for extreme temperatures within a 3-hour window at station `AWS-042`:

```
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT 
    station_id,
    ROUND(AVG(temperature)::numeric, 2) AS avg_temp,
    MAX(temperature) AS peak_temp
FROM plan_lab
WHERE station_id = 'AWS-042'
  AND recorded_at BETWEEN '2026-01-10 00:00:00+00' AND '2026-01-10 03:00:00+00'
GROUP BY station_id;

```

#### Unoptimized Output Analysis:

```
HashAggregate  (cost=25412.00..25412.01 rows=1 width=42) (actual time=142.180..142.182 rows=1 loops=1)
  Group Key: station_id
  Buffers: shared hit=12910
  ->  Seq Scan on plan_lab  (cost=0.00..25412.00 rows=1 width=12) (actual time=3.120..141.850 rows=54 loops=1)
        Filter: ((recorded_at >= '2026-01-10 00:00:00+00'::timestamptz) AND (recorded_at <= '2026-01-10 03:00:00+00'::timestamptz) AND ((station_id)::text = 'AWS-042'::text))
        Rows Removed by Filter: 999946
        Buffers: shared hit=12910
Planning Time: 0.180 ms
Execution Time: 142.250 ms

```

#### Diagnosis:

1. **Red Flag #1 (`Seq Scan`):** The engine scanned 1,000,000 rows across 12,910 blocks ($100.8\text{ MB}$) to return only **54 matching rows**!

2. **Red Flag #7 (`Rows Removed by Filter`):** The CPU evaluated and discarded **999,946 non-matching rows** in user space.

3. **Execution Latency:** $142.25\text{ ms}$.

### Step 3: Optimization Phase 1 — Naive Single-Column Indexing

Create a standard index on `station_id`:

```
CREATE INDEX idx_lab_station ON plan_lab (station_id);

```

Re-run the exact same query with `EXPLAIN (ANALYZE, BUFFERS)`:

```
Bitmap Heap Scan on plan_lab  (cost=194.20..4210.15 rows=1 width=12) (actual time=1.850..6.420 rows=54 loops=1)
  Recheck Cond: ((station_id)::text = 'AWS-042'::text)
  Filter: ((recorded_at >= '2026-01-10 00:00:00+00'::timestamptz) AND (recorded_at <= '2026-01-10 03:00:00+00'::timestamptz))
  Rows Removed by Filter: 9946
  Buffers: shared hit=1820
  ->  Bitmap Index Scan on idx_lab_station  (cost=0.00..194.20 rows=10000 width=0) (actual time=1.210..1.211 rows=10000 loops=1)
        Index Cond: ((station_id)::text = 'AWS-042'::text)
        Buffers: shared hit=32
Execution Time: 6.490 ms

```

#### Diagnosis:

* Latency dropped from $142\text{ ms}$ to $6.49\text{ ms}$ ($22\times$ faster).

* **Remaining Inefficiency:** The Bitmap Index Scan found all 10,000 rows belonging to `AWS-042`, loaded 1,820 heap blocks, and discarded 9,946 rows that did not match the timestamp filter.

### Step 4: Optimization Phase 2 — Composite Covering Index (`INCLUDE`)

Deploy an optimized Composite Covering Index matching query filter order and embedding metrics:

```
-- Composite B-Tree: (Filter Key 1, Filter Key 2) INCLUDE (Metrics)
CREATE INDEX idx_lab_covering 
ON plan_lab (station_id, recorded_at) 
INCLUDE (temperature);

-- Update Visibility Map to enable Index-Only Scan
VACUUM plan_lab;

```

Re-run the exact same query with `EXPLAIN (ANALYZE, BUFFERS)`:

```
GroupAggregate  (cost=0.42..8.65 rows=1 width=42) (actual time=0.042..0.051 rows=1 loops=1)
  Group Key: station_id
  Buffers: shared hit=4
  ->  Index Only Scan using idx_lab_covering on plan_lab  (cost=0.42..8.62 rows=54 width=8) (actual time=0.031..0.041 rows=54 loops=1)
        Index Cond: ((station_id = 'AWS-042'::text) AND (recorded_at >= '2026-01-10 00:00:00+00'::timestamptz) AND (recorded_at <= '2026-01-10 03:00:00+00'::timestamptz))
        Heap Fetches: 0
        Buffers: shared hit=4
Planning Time: 0.120 ms
Execution Time: 0.075 ms

```

#### Final Optimization Audit:

| Performance Metric | Baseline (Unoptimized) | Single Index | Composite Covering Index | Net Architectural Gain | 
| ----- | ----- | ----- | ----- | ----- | 
| **Physical Access Node** | `Seq Scan` | `Bitmap Heap Scan` | **`Index Only Scan`** | Zero Heap Page Reads | 
| **Blocks Fetched (Buffers)** | 12,910 blocks ($100.8\text{ MB}$) | 1,820 blocks ($14.2\text{ MB}$) | **4 blocks (32 KB)** | $3,227\times$ **I/O Reduction** | 
| **Rows Removed by Filter** | 999,946 rows | 9,946 rows | **0 rows** | Zero Wasted CPU Cycles | 
| **Execution Latency** | $142.25\text{ ms}$ | $6.49\text{ ms}$ | $0.075\text{ ms}$ **(75** $\mu\text{s}$**)** | $1,896\times$ **Speedup!** | 

## 10. Summary Checklist: Production Plan Debugging Directives

```
================================================================================
                    QUERY PLAN FORENSICS CHECKLIST
================================================================================
 1. Always Use Buffers   : Execute EXPLAIN (ANALYZE, BUFFERS, TIMING). Never rely
                           on raw theoretical costs alone.
 2. Check Hit/Read Ratio : If shared read dominates, working set exceeds RAM.
                           If shared hit dominates, analyze CPU evaluation costs.
 3. Eliminate Spills     : If Sort or Hash Join reports "Disk: N kB", increase
                           work_mem to keep execution within fast RAM registers.
 4. Verify Index-Only    : Ensure Index Only Scans report Heap Fetches: 0. If high,
                           run VACUUM to update the Visibility Map (_vm).
 5. Target NVMe Costs    : Set random_page_cost = 1.1 on NVMe storage arrays to
                           prevent the optimizer from discarding viable indexes.
 6. Audit Skew Ratios    : If estimated rows deviates from actual rows by > 10x,
                           run ANALYZE or define CREATE STATISTICS for correlations.
 7. Beware Wrapped Funcs : Never write WHERE func(col) = val; it blinds B-Trees.
                           Write SARGable expressions or build Expression Indexes.
 8. Guard Against JIT    : If EXPLAIN ANALYZE on partitioned tables shows "JIT:
                           Time: 140 ms" for a 2 ms query, raise jit_above_cost =
                           500000 or run SET LOCAL jit = off.
 9. Generic vs Custom    : If prepared statements ($1, $2) regress on the 6th run
                           due to skewed station counts, set plan_cache_mode =
                           force_custom_plan.
10. MySQL 8.0+ Histograms: Unlike PostgreSQL ANALYZE, MySQL requires explicit
                           ANALYZE TABLE ... UPDATE HISTOGRAM ON col WITH 100 BUCKETS
                           for non-indexed column skew, plus ALTER INDEX ... INVISIBLE
                           for zero-risk index retirement (see Card 14 Section 10.3).
================================================================================
```

> **Cross-Reference:** For the full **Unified 10-Layer Performance Optimization Master Matrices**, see [Day 2 Master Coursebook — Section 7.3 (PostgreSQL)](../day2/day2_master_coursebook.md#73-advanced-query--ingestion-acceleration-jit-parallel-ddl-plan-caching--the-10-layer-optimization-matrix), [Day 2 MVCC Guide — Section 6.3 (`postgresql.conf` vs. `my.cnf` Translator)](../day2/day2_postgres_vs_mysql_mvcc_guide.md#63-side-by-side-performance-tuning-translator-postgresql-postgresqlconf-vs-mysql-innodb-mycnf), and [Reference Card 14 — Section 10.4 (MySQL 8.0/8.4 & MariaDB)](./14_mysql_and_mariadb_innodb_complete_engineering_guide.md#104-the-unified-10-layer-mysql-8084--mariadb-performance-optimization-master-matrix).

---

### 🔗 Reference Library Navigation

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./09_acid_transactions_and_two_terminal_lock_debugging.md) | **Card 10 of 14** | [Next Card ➡️](./11_python_database_drivers_for_weather_engineers.md) | [⬆️ Back to Top](#query-execution-plan-forensics-the-explain--performance-optimization-reference-card)
