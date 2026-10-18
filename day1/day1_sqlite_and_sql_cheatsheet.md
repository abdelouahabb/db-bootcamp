> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [📘 Day 1 Coursebook](day1_master_coursebook.md) | [⏭️ Day 2 Coursebook](../day2/day2_master_coursebook.md)

# Day 1 Authoritative Reference Card & Cheatsheet: SQLite CLI Directives, Core SQL & Time-Series Telemetry Wrangling

**Companion to:**
- `day1_master_coursebook.md` — Complete Day 1 Master Coursebook & Telemetry Reference
- `day1_hardware_sentinels_and_qc_guide.md` — Deep-Dive on `-9999` In-Band Signaling & 3VL
- `weather_ops_seed.sql` / `weather_ops.db` — WMO Synoptic & NWP Verification Database
- `generate_weather_db.py` / `weather_telemetry.db` — 250,000-Row High-Frequency AWS Telemetry Stream

---

## PART I: SQLite CLI Shell Directives & Dot-Commands Reference

### 1. Core Concept: Client Directives vs. Declarative SQL

When interacting with a database via a Command-Line Interface (CLI), engineers must distinguish between two completely different types of instructions:

1. **SQL Statements (`SELECT`, `INSERT`, `CREATE`):** Declarative code sent across the database driver to the relational query engine. They compile into bytecode, manipulate storage tables, and must always end with a semicolon (`;`).
2. **Shell Directives ("Dot-Commands"):** Control instructions evaluated **strictly by the client terminal program** (`sqlite3`). They configure terminal display formatting, toggle performance timers, manage import/export streams, and inspect database metadata. They **must start with a dot (`.`) at column 1** and **must never end with a semicolon**.

```
┌─────────────────────────────────────────────────────────────┐
│                       Terminal User                         │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
      Starts with "."?                 Standard SQL?
               │                              │
               ▼                              ▼
┌─────────────────────────────┐┌──────────────────────────────┐
│    SQLite Shell Client      ││     SQLite Storage Core      │
│  (Configures display,       ││  (Parses AST, executes plan, │
│   measures timer, exports)  ││   reads B-tree pages)        │
└─────────────────────────────┘└──────────────────────────────┘
```

### 2. Launching & Building Databases from Terminal

```bash
# Build weather_ops.db from the WMO synoptic seed script:
sqlite3 weather_ops.db < weather_ops_seed.sql

# Generate the 250,000-row AWS telemetry database:
python3 generate_weather_db.py

# Open interactive shell:
sqlite3 weather_ops.db
sqlite3 weather_telemetry.db
```

### 3. Complete `sqlite3` CLI Dot-Commands Reference Table

| Dot-Command | Category | Purpose in Weather Lab | Typical Output / Effect |
| :--- | :--- | :--- | :--- |
| `.help` | Help | List all available `sqlite3` CLI dot-commands | Full command index |
| `.headers on` | Formatting | Render column attribute names above data rows | `station_id \| temperature` displayed at top |
| `.mode box` | Formatting | Draw clean Unicode table borders (SQLite 3.33+) | Box grid with aligned column widths |
| `.mode column` | Formatting | Format query output in aligned plain-text columns | Traditional fixed-width columns |
| `.mode list` | Formatting | Pipe-delimited output (default; ideal for `grep`/`awk`) | `AWS-001\|2026-10-04\|18.4` |
| `.mode csv` | Formatting | Format output as Comma-Separated Values | Exports ready for pandas or Excel |
| `.mode json` | Formatting | Render each row as a JSON object | Useful for API payload inspection |
| `.timer on` | Performance | Display CPU & wall-clock execution time per query | `Run Time: real 0.084 user 0.071 sys 0.012` |
| `.nullvalue NULL` | Formatting | Print `NULL` explicitly instead of an empty blank string | Makes missing sensor values visually obvious |
| `.tables` | Metadata | List all tables and views in the connected database | `forecasts observations stations weather_alerts` |
| `.tables %telemetry%` | Metadata | Filter table list by pattern match | `raw_telemetry` |
| `.schema <table>` | Metadata | Show exact `CREATE TABLE`, `CHECK`, and `CREATE INDEX` DDL | Prints full DDL for `stations` or `raw_telemetry` |
| `.import file.csv tbl` | I/O | Import a raw synoptic CSV file into a table (use with `.mode csv`) | Bulk loads CSV rows |
| `.output results.csv` | I/O | Redirect next query results to a file (reset with `.output stdout`) | Saves query output to disk |
| `.quit` (or `Ctrl+D`) | Session | Exit the `sqlite3` interactive shell | Returns to bash terminal |

---

### 4. Deep-Dive on Essential Directives

#### 4.1 `.headers on`
Controls whether column attribute names are displayed as the top row of a query result set.
* **Default:** Often `off` in script-piping modes to simplify unix-pipe parsing (`awk`, `sed`).
* **Impact on Meteorological Telemetry:** Weather stations output multi-column floating-point series (`temperature`, `dew_point`, `wet_bulb_temp`, `soil_temp_5cm`). Without headers, an analyst viewing raw numeric streams cannot distinguish ambient temperature from dew point.

```text
-- Without .headers on (Unusable & Risky):
AWS-001|2026-10-04 12:00:00|18.4|12.1|1014.2|4.5
AWS-001|2026-10-04 12:10:00|18.6|12.0|1014.1|5.1

-- With .headers on (Unambiguous):
station_id|recorded_at|temperature|dew_point|pressure|wind_speed
AWS-001|2026-10-04 12:00:00|18.4|12.1|1014.2|4.5
AWS-001|2026-10-04 12:10:00|18.6|12.0|1014.1|5.1
```

#### 4.2 `.mode box` vs. `.mode list`
Sets the output presentation layout to use Unicode line-drawing box borders with automatic column width calculation. In exploratory data analysis (EDA), `box` mode immediately reveals alignment shifts caused by negative numbers, long timestamps, or sentinel values (`-999.0`), making visual QC scanning effortless.

```text
-- Default Mode (.mode list):
station_id|recorded_at|temperature|pressure
AWS-013|2026-10-04 12:00:00|-999.0|1012.4
AWS-013|2026-10-04 12:10:00|16.2|1012.3

-- Box Mode (.mode box):
┌────────────┬─────────────────────┬─────────────┬──────────┐
│ station_id │     recorded_at     │ temperature │ pressure │
├────────────┼─────────────────────┼─────────────┼──────────┤
│ AWS-013    │ 2026-10-04 12:00:00 │ -999.0      │ 1012.4   │
│ AWS-013    │ 2026-10-04 12:10:00 │ 16.2        │ 1012.3   │
└────────────┴─────────────────────┴─────────────┴──────────┘
```

#### 4.3 `.timer on`
Instructs the SQLite shell to measure and print the precise CPU and elapsed wall-clock execution time for every SQL statement executed:
```text
Run Time: real 0.084 user 0.071230 sys 0.012410
```
* **`real` (Wall-Clock Time):** Total elapsed human time from query dispatch to final row delivery (includes disk I/O, OS scheduling).
* **`user` (User-Space CPU Time):** CPU time spent actively executing instructions inside SQLite code (math expressions, hashing groups, sorting arrays).
* **`sys` (Kernel-Space CPU Time):** CPU time spent handling OS system calls on behalf of SQLite (allocating memory pages, reading physical file blocks via `read()`).
* **The Pedagogical Bridge to Day 2:** On 250,000 rows, SQLite takes $\approx 0.08\text{ seconds}$ because the entire $20\text{ MB}$ database resides in OS RAM cache. On Day 2, running an unindexed table scan across 50 million records in PostgreSQL jumps from $80\text{ ms}$ to $45\text{ seconds}$ due to disk head read amplification.

#### 4.4 `.tables` and `.schema <table>` Under the Hood
Both commands are syntactic sugar querying SQLite's internal system catalog (`sqlite_schema`, formerly `sqlite_master`):

```sql
-- What .tables actually runs:
SELECT name 
FROM sqlite_schema 
WHERE type IN ('table', 'view') 
  AND name NOT LIKE 'sqlite_%'
ORDER BY 1;

-- What .schema raw_telemetry actually runs:
SELECT sql 
FROM sqlite_schema 
WHERE tbl_name = 'raw_telemetry' 
  AND type IN ('table', 'index', 'trigger')
ORDER BY type = 'table' DESC, name;
```
**Why Weather Engineers Must Run `.schema` First:**
1. **Index Verification:** Immediately reveals whether composite indexes exist on temporal columns (`station_id`, `recorded_at`).
2. **Constraint Auditing:** Confirms whether sensor metrics allow `NULL` or enforce physical `CHECK` constraints.
3. **Type Affinity Inspection:** Ensures sensor timestamps are stored consistently as ISO-8601 `TEXT` strings (`YYYY-MM-DD HH:MM:SS`).

#### 4.5 Permanent Shell Automation (`~/.sqliterc`)
Persist display and profiling directives so every `sqlite3` session opens pre-configured:

```bash
# Linux / macOS:
cat << 'EOF' > ~/.sqliterc
.headers on
.mode box
.timer on
.nullvalue NULL
EOF
```

```powershell
# Windows (PowerShell):
Set-Content -Path "$HOME\.sqliterc" -Value ".headers on`n.mode box`n.timer on`n.nullvalue NULL"
```

---

## PART II: Declarative SQL Execution Order, DDL & Three-Valued Logic (3VL)

### 1. Declarative Execution Order (The 8 Logical Phases)

SQL is not executed top-to-bottom. The query planner evaluates statements in eight distinct logical phases:

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. FROM & JOIN     Identify candidate relations & compute cross/joins  │
│ 2. WHERE           Filter raw rows from disk BEFORE memory allocation   │
│ 3. GROUP BY        Partition remaining rows into aggregated buckets    │
│ 4. HAVING          Filter aggregated buckets based on aggregate results │
│ 5. SELECT          Evaluate scalar expressions & assign column aliases  │
│ 6. DISTINCT        Sort/hash to remove duplicate row states             │
│ 7. ORDER BY        Sort output stream (can spill to disk/temp files)    │
│ 8. LIMIT / OFFSET  Slice row window returned to the client application  │
└────────────────────────────────────────────────────────────────────────┘
```

> **The Alias Trap:** You **cannot** use a `SELECT` column alias in `WHERE` or `GROUP BY` because Step 2 and Step 3 execute **before** Step 5 allocates the alias.
> ```sql
> -- FAILS (Step 2 doesn't know temp_f):
> SELECT station_id, (temperature * 1.8 + 32.0) AS temp_f
> FROM raw_telemetry
> WHERE temp_f > 85.0;
> 
> -- CORRECT (Repeat expression or wrap in a CTE):
> SELECT station_id, (temperature * 1.8 + 32.0) AS temp_f
> FROM raw_telemetry
> WHERE (temperature * 1.8 + 32.0) > 85.0;
> ```

---

### 2. DDL & Physical Meteorology Constraints (`CREATE TABLE`)

```sql
-- CRITICAL: SQLite disables Foreign Keys by default on every new connection!
-- Always run this first:
PRAGMA foreign_keys = ON;

CREATE TABLE stations (
    station_id   INTEGER PRIMARY KEY,               -- Natural key (5-digit WMO ID)
    station_name TEXT    NOT NULL UNIQUE,
    latitude     REAL    NOT NULL CHECK (latitude BETWEEN -90.0 AND 90.0),
    longitude    REAL    NOT NULL CHECK (longitude BETWEEN -180.0 AND 180.0),
    elevation_m  REAL    NOT NULL CHECK (elevation_m BETWEEN -500.0 AND 9000.0),
    climate_zone TEXT    NOT NULL CHECK (climate_zone IN ('Mediterranean', 'Arid', 'Semi-Arid', 'Highland', 'Maritime')),
    is_active    INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);
```

---

### 3. Three-Valued Logic (3VL) & `NULL` Truth Tables

SQL implements Three-Valued Logic: `TRUE`, `FALSE`, and `UNKNOWN` (represented by `NULL`).

#### Logical Truth Matrix

| Condition $A$ | Condition $B$ | $A \text{ AND } B$ | $A \text{ OR } B$ | $\text{NOT } A$ |
| :--- | :--- | :--- | :--- | :--- |
| `TRUE` | `NULL` | `UNKNOWN` | `TRUE` | `FALSE` |
| `FALSE` | `NULL` | `FALSE` | `UNKNOWN` | `TRUE` |
| `NULL` | `NULL` | `UNKNOWN` | `UNKNOWN` | `UNKNOWN` |

#### Comparison Propagation & Row Filtering Gate
* `val = NULL` $\implies$ `UNKNOWN` (never evaluates to `TRUE`).
* `val != NULL` $\implies$ `UNKNOWN` (never evaluates to `TRUE`).
* `NULL = NULL` $\implies$ `UNKNOWN` (never evaluates to `TRUE`).
* **Always use** `IS NULL` or `IS NOT NULL`.
* **Row Filtering Gate:** A `WHERE` or `HAVING` filter admits rows **if and only if** the expression evaluates strictly to `TRUE`. Rows evaluating to `FALSE` or `UNKNOWN` are discarded silently.

---

### 4. Aggregate Hygiene & Hardware Sentinel Handling (`NULL` vs. `-999.0` / `-9999.0`)

In SQL, **`NULL` means "missing/unknown"** and is **ignored** by `AVG()`, `MIN()`, `MAX()`, `SUM()`, and `COUNT(column)`. Legacy Fortran/WMO/datalogger codes like `-9999.0`, `-999.0`, or `9999.0` are treated as real numbers and corrupt averages!

#### Aggregate Function Behavior Matrix

| Aggregate | Behavior on `NULL` | Behavior on Sentinel (`-999.0` / `-9999.0`) |
| :--- | :--- | :--- |
| `COUNT(*)` | Counts the row regardless of column content | Counts the row |
| `COUNT(column)` | **Silently ignores `NULL`** | Counts the sentinel as a valid reading |
| `AVG(column)` | **Silently ignores `NULL`** | **Corrupts mean:** sums $-999.0$ / $-9999.0$ into accumulator |
| `MIN(column)` | **Silently ignores `NULL`** | **Returns** $-999.0$ / $-9999.0$ as absolute network minimum |
| `MAX(column)` | **Silently ignores `NULL`** | Returns sentinel if ADC shorts to `9999.0` |

#### Essential Null & Cleaning Functions

| SQL Function / Operator | Meteorological Example | What It Does |
| :--- | :--- | :--- |
| `IS NULL` / `IS NOT NULL` | `WHERE temp_c IS NOT NULL` | Correct way to filter missing sensor values (`= NULL` never works!) |
| `NULLIF(col, sentinel)` | `AVG(NULLIF(precip_1h_mm, -9999.0))` | Converts `-9999.0` to `NULL` on the fly so `AVG()` ignores it! |
| `COALESCE(col, fallback)` | `SUM(COALESCE(precip_1h_mm, 0.0))` | Replaces `NULL` with `0.0` when summing rainfall |
| `ROUND(expr, decimals)` | `ROUND(temp_c + 273.15, 2) AS temp_k` | Rounds floating-point calculations |

#### In-Flight & Permanent Sanitization Patterns

```sql
-- 1. Exact sentinel replacement in-flight with NULLIF
SELECT
    AVG(NULLIF(temperature, -999.0))    AS clean_aws_temp,
    AVG(NULLIF(precip_1h_mm, -9999.0))  AS clean_synoptic_rain
FROM raw_telemetry;

-- 2. Range-bound clamping with CASE WHEN (Handles sensor drift like -998.2 or 9999.0)
SELECT
    AVG(CASE 
        WHEN temperature BETWEEN -60.0 AND 60.0 THEN temperature 
        ELSE NULL 
    END) AS physical_mean_temp
FROM raw_telemetry;

-- 3. ANSI SQL / PostgreSQL Native FILTER clause (Supported in SQLite 3.30+ & PostgreSQL)
SELECT
    AVG(temperature) FILTER (WHERE temperature BETWEEN -60.0 AND 60.0) AS filtered_mean_temp
FROM raw_telemetry;

-- 4. Permanently clean sentinel values in a table via UPDATE:
UPDATE observations
SET precip_1h_mm = NULL
WHERE precip_1h_mm = -9999.0;
```

---

## PART III: Filtering, Classification, Temporal Bucketing & `JOIN` Verification

### 1. Operational Classification (`CASE WHEN`) & Climatological Rollups (`GROUP BY` / `HAVING`)

```sql
-- 1. Operational Wind Classification (Beaufort Categories via CASE WHEN)
SELECT
    station_id,
    obs_time,
    wind_speed_kt,
    CASE
        WHEN wind_speed_kt >= 34.0 THEN 'Gale Warning'
        WHEN wind_speed_kt >= 22.0 THEN 'Strong Wind'
        WHEN wind_speed_kt >= 10.0 THEN 'Moderate Wind'
        ELSE 'Light Breeze'
    END AS wind_category
FROM observations
WHERE wind_speed_kt IS NOT NULL
ORDER BY wind_speed_kt DESC;

-- 2. Daily Climatology Rollup + Sensor Uptime % (GROUP BY & HAVING)
SELECT
    station_id,
    DATE(obs_time)                                 AS obs_date,
    COUNT(*)                                       AS total_hours,
    COUNT(temp_c)                                  AS valid_temp_hours,
    ROUND(100.0 * COUNT(temp_c) / COUNT(*), 1)     AS sensor_uptime_pct,
    ROUND(MIN(temp_c), 1)                          AS tmin_c,
    ROUND(MAX(temp_c), 1)                          AS tmax_c,
    ROUND(AVG(temp_c), 1)                          AS tmean_c,
    ROUND(SUM(COALESCE(precip_1h_mm, 0.0)), 1)     AS daily_rain_mm
FROM observations
WHERE qc_flag = 'VALID'                            -- Filters rows BEFORE grouping (Step 2)
GROUP BY station_id, DATE(obs_time)                -- Partitions buckets (Step 3)
HAVING SUM(COALESCE(precip_1h_mm, 0.0)) > 10.0     -- Filters groups AFTER aggregation (Step 4)
ORDER BY daily_rain_mm DESC;
```

---

### 2. Synoptic Bucketing & Temporal Intervals (SQLite vs. PostgreSQL)

Raw pings arrive asynchronously. Telemetry must be aggregated into regular synoptic hours ($00:00, 01:00, \dots$).

| Task | SQLite Syntax | PostgreSQL Syntax (Day 2+) |
| :--- | :--- | :--- |
| **Hourly Bucket** | `strftime('%Y-%m-%d %H:00:00', recorded_at)` | `date_trunc('hour', recorded_at)` |
| **Daily Bucket** | `DATE(recorded_at)` or `strftime('%Y-%m-%d 00:00:00', recorded_at)` | `date_trunc('day', recorded_at)` |
| **Extract Hour** | `strftime('%H', obs_time)` | `EXTRACT(HOUR FROM obs_time)` |
| **Time Arithmetic** | `datetime(recorded_at, '+1 hour')` | `recorded_at + INTERVAL '1 hour'` |
| **Past 24 Hours** | `recorded_at >= datetime('now', '-24 hours')` | `recorded_at >= NOW() - INTERVAL '24 hours'` |
| **UTC Force** | `datetime(recorded_at, 'utc')` | `recorded_at AT TIME ZONE 'UTC'` |

---

### 3. Normalization (`1NF`–`3NF`) vs. Denormalization Quick Reference

| Pattern | Rule / Structure | Where We Use It in the Bootcamp | Key Trade-Off |
| :--- | :--- | :--- | :--- |
| **`1NF` (First Normal Form)** | Atomic scalar columns; no CSV strings (`'19.4,27.8'`) or repeating columns (`temp_00z`, `temp_06z`). | All SQL tables (`stations`, `observations`, `forecasts`). | Enables SQL indexing, `AVG()`, and `WHERE` filtering. |
| **`2NF` (Second Normal Form)** | `1NF` + no partial dependency on a composite key `(station_id, obs_time)`. | Splitting `stations` (depends only on `station_id`) from `observations` (depends on `station_id + obs_time`). | Eliminates **Insertion**, **Update**, and **Deletion** anomalies; saves `~68 bytes/row`. |
| **`3NF` (Third Normal Form)** | `2NF` + no transitive dependency (`non_key_A -> non_key_B`). | `day1/weather_ops.db` & `day2/weather_ops_pg.sql` (`synoptic.stations`, `synoptic.observations`). | Gold standard for **Row-Store OLTP** (`SQLite`, `PostgreSQL`). Requires `JOIN` on reads. |
| **Deliberate Denormalization (Pre-Joined / Embedded / Columnar)** | Intentionally duplicating attributes or pre-joining tables for read performance. | • **Day 3 PG:** `MATERIALIZED VIEW nwp.mv_daily_model_verification` + Covering Index `INCLUDE (temp_c)`<br>• **Day 4 Mongo:** Embedded `vertical_levels: [...]` array in `radiosonde_soundings`<br>• **Day 5 Parquet/DuckDB:** Wide flat Parquet files | • **Row Store (`SQLite`/`PG`):** Bloats disk if done on raw tables; safe via Materialized Views.<br>• **Columnar (`Parquet`):** **Dictionary Encoding + RLE** compresses repeated strings (`'Mediterranean'`) to near-zero bytes while eliminating `JOIN`s! |

---

### 4. SQL `JOIN` Compatibility Matrix (`SQLite < 3.39` vs. `3.39+` vs. `PostgreSQL` vs. `DuckDB`)

> [!IMPORTANT]
> **SQLite `3.39.0` Version Boundary:** Prior to **SQLite `3.39.0` (July 2022)**, SQLite threw `Parse error: RIGHT and FULL OUTER JOINs are not currently supported`. Modern **SQLite `3.39.0+`** (Ubuntu 24.04 ships `3.45.x`) supports `RIGHT` and `FULL OUTER JOIN` natively, but embedded Linux dataloggers often run older SQLite versions—use the portable rewrites below when targeting edge hardware!

| `JOIN` Type | SQLite `< 3.39` | SQLite `3.39+` | PostgreSQL 16 | DuckDB | Portable Emulation / Engine Note |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **`INNER JOIN`** | ✅ | ✅ | ✅ | ✅ | Returns only matching rows ($A \cap B$). |
| **`LEFT [OUTER] JOIN`** | ✅ | ✅ | ✅ | ✅ | All left rows + matching right rows ($A \cup (A \cap B)$). |
| **`LEFT ANTI-JOIN`** | ✅ | ✅ | ✅ | ✅ | `A LEFT JOIN B ON ... WHERE B.id IS NULL` ($A \setminus B$). |
| **`RIGHT [OUTER] JOIN`** | ❌ | ✅ | ✅ | ✅ | **Portable `< 3.39` Rewrite:** Flip table order to `B LEFT JOIN A`. |
| **`FULL [OUTER] JOIN`** | ❌ | ✅ | ✅ | ✅ | **Portable `< 3.39` Rewrite:** `A LEFT JOIN B UNION ALL B LEFT JOIN A WHERE A.id IS NULL`. |
| **`CROSS JOIN`** | ✅ | ✅ | ✅ | ✅ | Cartesian product ($M \times N$ rows; no `ON` clause). |
| **`SELF JOIN`** | ✅ | ✅ | ✅ | ✅ | `FROM stations s1 JOIN stations s2 ON s1.climate_zone = s2.climate_zone AND s1.station_id < s2.station_id`. |
| **`LATERAL` Join** | ❌ | ❌ | ✅ | ✅ | Correlated subquery per left row. In SQLite, use `ROW_NUMBER() OVER (PARTITION BY ...)` in a CTE. |
| **`ASOF JOIN`** | ❌ | ❌ | ❌ *(use `LATERAL`)* | ✅ | Time-series nearest-timestamp match (`ON a.id = b.id AND a.ts >= b.ts`). |
| **Join Algorithms** | Nested Loop only | Nested Loop only | Nested Loop, Parallel Hash, Merge Join | Vectorized Hash & Merge Join | SQLite has no `Hash Join` or `Merge Join`. |

---

### 5. All 7 Relational `JOIN` Recipes on `weather_ops.db`

```sql
-- 1. LEFT ANTI-JOIN (LEFT JOIN + IS NULL): Find silent/offline stations with 0 observations!
SELECT s.station_id, s.station_name, s.climate_zone, s.is_active
FROM stations s
LEFT JOIN observations o ON s.station_id = o.station_id
WHERE o.obs_id IS NULL;

-- 2. Multi-Column INNER JOIN + CTE: NWP Forecast Verification (Bias & MAE across ECMWF, GFS, AROME)
--    CRITICAL: Must join on BOTH station_id AND valid_time = obs_time to avoid a Cartesian product!
WITH pairs AS (
    SELECT
        f.model_name,
        (f.pred_temp_c - o.temp_c)     AS err_c,
        ABS(f.pred_temp_c - o.temp_c)  AS abs_err_c,
        (f.pred_wind_kt - o.wind_speed_kt)    AS wind_err_kt,
        ABS(f.pred_wind_kt - o.wind_speed_kt) AS wind_abs_err_kt
    FROM forecasts f
    INNER JOIN observations o
        ON f.station_id = o.station_id
       AND f.valid_time = o.obs_time
    WHERE o.temp_c IS NOT NULL
      AND o.wind_speed_kt IS NOT NULL
)
SELECT
    model_name,
    COUNT(*)                       AS n_verified,
    ROUND(AVG(err_c), 2)           AS mean_temp_bias_c,
    ROUND(AVG(abs_err_c), 2)       AS temp_mae_c,
    ROUND(AVG(wind_err_kt), 2)     AS mean_wind_bias_kt,
    ROUND(AVG(wind_abs_err_kt), 2) AS wind_mae_kt
FROM pairs
GROUP BY model_name
ORDER BY temp_mae_c ASC;

-- 3. RIGHT JOIN (SQLite 3.39+) & Portable < 3.39 LEFT JOIN Flip:
-- Native 3.39+: FROM weather_alerts a RIGHT JOIN stations s ON a.station_id = s.station_id
-- Portable:     FROM stations s LEFT JOIN weather_alerts a ON s.station_id = a.station_id

-- 4. FULL OUTER JOIN (SQLite 3.39+) vs Portable < 3.39 UNION ALL Emulation:
SELECT s.station_id, s.station_name, a.phenomenon, a.severity
FROM stations s
LEFT JOIN weather_alerts a ON s.station_id = a.station_id
UNION ALL
SELECT a.station_id, s.station_name, a.phenomenon, a.severity
FROM weather_alerts a
LEFT JOIN stations s ON a.station_id = s.station_id
WHERE s.station_id IS NULL;

-- 5. CROSS JOIN: Generate Expected (7 Stations x 3 NWP Models = 21 Pairs) Audit Grid
WITH models AS (SELECT 'ECMWF-HRES' AS model_name UNION ALL SELECT 'GFS' UNION ALL SELECT 'AROME')
SELECT s.station_id, s.station_name, m.model_name, COUNT(f.forecast_id) AS forecast_count
FROM stations s
CROSS JOIN models m
LEFT JOIN forecasts f ON f.station_id = s.station_id AND f.model_name = m.model_name
GROUP BY s.station_id, s.station_name, m.model_name
ORDER BY s.station_id, m.model_name;

-- 6. SELF JOIN: Compare Distinct Stations in the Same Climate Zone (s1.station_id < s2.station_id)
SELECT s1.climate_zone, s1.station_name AS station_a, s2.station_name AS station_b,
       ROUND(ABS(s1.elevation_m - s2.elevation_m), 1) AS elev_diff_m
FROM stations s1
INNER JOIN stations s2
    ON s1.climate_zone = s2.climate_zone
   AND s1.station_id < s2.station_id;
```

---

## PART IV: Common Table Expressions (CTEs), Recursive Grids & Window Functions

### 1. Multi-Stage CTE Pipeline Blueprint

Use CTEs (`WITH` clauses) to organize transformations as a linear Directed Acyclic Graph (DAG) instead of deeply nested subqueries:

```sql
WITH stage1_cleansed AS (
    -- Strip impossible hardware voltages and wire sentinels
    SELECT 
        station_id,
        recorded_at,
        temperature,
        pressure,
        wind_speed
    FROM raw_telemetry
    WHERE (temperature BETWEEN -60.0 AND 60.0 OR temperature IS NULL)
      AND (pressure BETWEEN 870.0 AND 1085.0 OR pressure IS NULL)
),
stage2_synoptic_hourly AS (
    -- Downsample high-frequency pings into 1-hour reporting bins
    SELECT 
        station_id,
        strftime('%Y-%m-%d %H:00:00', recorded_at) AS obs_hour,
        ROUND(AVG(temperature), 2) AS mean_temp,
        ROUND(AVG(pressure), 2) AS mean_pressure,
        ROUND(MAX(wind_speed), 2) AS peak_gust
    FROM stage1_cleansed
    GROUP BY station_id, obs_hour
)
SELECT * 
FROM stage2_synoptic_hourly
WHERE peak_gust >= 20.0
ORDER BY peak_gust DESC;
```

### 2. Gap Detection via Recursive Time Grid (`WITH RECURSIVE`)

A simple `GROUP BY` cannot report on hours where a station sent zero packets. Generate a continuous reference grid to spot communication blackouts:

```sql
WITH RECURSIVE timeline(slot) AS (
    SELECT datetime('2026-10-01 00:00:00')
    UNION ALL
    SELECT datetime(slot, '+1 hour')
    FROM timeline
    WHERE slot < datetime('2026-10-02 23:00:00')
)
SELECT 
    t.slot AS expected_timestamp,
    s.station_id,
    COUNT(r.recorded_at) AS packets_received,
    CASE 
        WHEN COUNT(r.recorded_at) = 0 THEN 'COMPLETE_BLACKOUT'
        WHEN COUNT(r.recorded_at) < 30 THEN 'PACKET_LOSS'
        ELSE 'NOMINAL'
    END AS telemetry_status
FROM timeline t
CROSS JOIN stations s
LEFT JOIN raw_telemetry r 
       ON strftime('%Y-%m-%d %H:00:00', r.recorded_at) = t.slot 
      AND r.station_id = s.station_id
GROUP BY t.slot, s.station_id;
```

---

### 3. Window Functions for Sensor Streams

Unlike `GROUP BY`, which collapses rows, **window functions preserve individual observation rows** while computing context across partitions.

#### Syntax Layout

$$
\text{FUNCTION}(\dots)\ \mathbf{OVER}\ (\mathbf{PARTITION\ BY}\ \text{station}\ \mathbf{ORDER\ BY}\ \text{time}\ [\mathbf{FRAME}])
$$

```
 ┌──────────────────────┬─────────────────────────────────────────────────┐
 │ Window Function      │ Telemetry Engineering Use Case                  │
 ├──────────────────────┼─────────────────────────────────────────────────┤
 │ LAG(col, n)          │ Fetch reading from n steps prior (tendency, ΔP) │
 │ LEAD(col, n)         │ Lookahead n steps for forward anomaly audits    │
 │ ROW_NUMBER()         │ Rank rows per partition to deduplicate latest   │
 │ RANK() / DENSE_RANK()│ Rank extreme weather records with tie handling  │
 │ AVG(col) OVER(...)   │ Moving average across physical/temporal frames  │
 └──────────────────────┴─────────────────────────────────────────────────┘
```

#### Sliding Frames: `ROWS` vs. `RANGE`

```sql
-- ROWS: Exact physical count of preceding rows
ROWS BETWEEN 4 PRECEDING AND CURRENT ROW

-- RANGE: Logical temporal offset (PostgreSQL)
RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW

-- Centered Rolling Window (Microburst / spike baseline)
ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
```

> **Warning:** If an instrument drops offline for 6 hours, `ROWS BETWEEN 4 PRECEDING` will traverse across the 6-hour gap and blend physically unrelated data. For irregular streams, use `RANGE` (PostgreSQL) or bucket into uniform intervals first.

---

### 4. Field-Ready Telemetry Window Recipes

#### Recipe 1: 3-Hour Barometric Tendency ($\Delta P$)
Detect approaching squall lines or frontal passages:
```sql
SELECT 
    station_id,
    recorded_at,
    pressure,
    LAG(pressure, 3) OVER (
        PARTITION BY station_id 
        ORDER BY recorded_at
    ) AS pressure_3step_prior,
    ROUND(pressure - LAG(pressure, 3) OVER (
        PARTITION BY station_id 
        ORDER BY recorded_at
    ), 2) AS barometric_tendency
FROM raw_telemetry
WHERE pressure > -900.0;
```

#### Recipe 2: Latest State Deduplication (`ROW_NUMBER()`)
Retrieve the single latest observation per station without correlated subqueries:
```sql
WITH indexed_stream AS (
    SELECT 
        station_id,
        recorded_at,
        temperature,
        pressure,
        wind_speed,
        ROW_NUMBER() OVER (
            PARTITION BY station_id 
            ORDER BY recorded_at DESC
        ) AS recency_rank
    FROM raw_telemetry
    WHERE temperature > -900.0
)
SELECT * 
FROM indexed_stream 
WHERE recency_rank = 1;
```

#### Recipe 3: Rolling 5-Point Wind Gust Smoother
Filter out single-ping turbulent noise:
```sql
SELECT 
    station_id,
    recorded_at,
    wind_speed,
    ROUND(AVG(wind_speed) OVER (
        PARTITION BY station_id 
        ORDER BY recorded_at 
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ), 2) AS wind_sma5,
    MAX(wind_speed) OVER (
        PARTITION BY station_id 
        ORDER BY recorded_at 
        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ) AS peak_gust_5step
FROM raw_telemetry
WHERE wind_speed >= 0.0;
```

#### Recipe 4: Thermal Spike / Inversion Detector
Flag measurements deviating by $>6.0^\circ\text{C}$ from a centered moving window:
```sql
WITH baseline AS (
    SELECT 
        station_id,
        recorded_at,
        temperature,
        ROUND(AVG(temperature) OVER (
            PARTITION BY station_id 
            ORDER BY recorded_at 
            ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
        ), 2) AS centered_mean
    FROM raw_telemetry
    WHERE temperature > -900.0
)
SELECT 
    station_id,
    recorded_at,
    temperature,
    centered_mean,
    ROUND(ABS(temperature - centered_mean), 2) AS anomaly_magnitude
FROM baseline
WHERE ABS(temperature - centered_mean) > 6.0
ORDER BY anomaly_magnitude DESC;
```

---

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [📘 Day 1 Coursebook](day1_master_coursebook.md) | [⏭️ Day 2 Coursebook](../day2/day2_master_coursebook.md)

