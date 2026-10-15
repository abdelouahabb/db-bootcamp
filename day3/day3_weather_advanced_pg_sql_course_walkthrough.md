> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [⏮️ Day 2 Coursebook](../day2/day2_master_coursebook.md) | [📘 Day 3 Coursebook](./day3_master_coursebook.md) | [⚡ 5M-Row PostGIS Benchmark Walkthrough](./day3_postgis_5m_benchmark_sql_course_walkthrough.md) | [⏭️ Day 4 Coursebook](../day4/day4_master_coursebook.md)

# Day 3 SQL Course Walkthrough: Advanced Production PostgreSQL for Weather Engineers (`day3_weather_advanced_pg.sql`)

**Source Script:** [day3_weather_advanced_pg.sql](./day3_weather_advanced_pg.sql)  
**Companion Curriculum:** [day3_master_coursebook.md](./day3_master_coursebook.md) | [day3_postgres_advanced_cheatsheet.md](./day3_postgres_advanced_cheatsheet.md)  
**Target Database:** `weather_ops` (seeded by [../day2/weather_ops_pg.sql](../day2/weather_ops_pg.sql))  
**Execution Command:** `psql -d weather_ops -f day3_weather_advanced_pg.sql`

---

## 1. Architectural Overview

Operational meteorological databases ingest continuous streams of surface synoptic observations, automated weather station (AWS) telemetry, and Numerical Weather Prediction (NWP) model grids. Left in a monolithic relational table, multi-year weather histories cause severe B-Tree index bloat, buffer-pool thrashing (`shared_buffers` eviction), and expensive random disk I/O during analytical verification queries.

The [day3_weather_advanced_pg.sql](./day3_weather_advanced_pg.sql) script upgrades the Day 2 `weather_ops` database with four production PostgreSQL architectures:

1. **Declarative Range Partitioning (`PARTITION BY RANGE (obs_time)`):** Splits the synoptic time-series stream into isolated monthly physical child tables (`synoptic.obs_y2026m06` through `synoptic.obs_y2026m10`) plus a fail-safe `DEFAULT` partition (`synoptic.obs_default`), while enriching every observation with binary `JSONB` IoT hardware diagnostics (`sensor_payload`).
2. **Specialized Access Methods (5 Index Architectures):** Deploys and contrasts **BRIN** (Block Range Index), **B-Tree**, **Partial B-Tree** (`WHERE qc_flag != 'VALID'`), **Covering B-Tree** (`INCLUDE`), and **GIN** (Generalized Inverted Index on `JSONB`).
3. **Pre-Aggregated NWP Model Verification (`MATERIALIZED VIEW` + `CONCURRENTLY`):** Caches daily Mean Bias and Mean Absolute Error (MAE) across NWP models (`AROME_DZ_2.5KM`, `ECMWF_IFS_9KM`, `GFS_NOAA_13KM`) and attaches a composite `UNIQUE INDEX` to unlock non-blocking concurrent refreshes.
4. **Dynamic PostGIS Geodesic Upgrade (`GEOGRAPHY(Point, 4326)` + `GiST`):** Detects whether the PostGIS spatial extension is installed on the host and automatically upgrades `synoptic.stations` with WGS-84 spheroidal coordinates and an R-Tree-on-GiST spatial index.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                     day3_weather_advanced_pg.sql EXECUTION PIPELINE                    │
├──────────────────────┬─────────────────────────────────────────────────────────────────┤
│ Session Environment  │ UTC Timezone Enforcement, ISO-8601 Date Formatting, Search Path │
├──────────────────────┼─────────────────────────────────────────────────────────────────┤
│ Module 1             │ synoptic.observations_part (PARTITION BY RANGE (obs_time))      │
│                      │  ├── synoptic.obs_y2026m06  [2026-06-01, 2026-07-01)            │
│                      │  ├── synoptic.obs_y2026m07  [2026-07-01, 2026-08-01)            │
│                      │  ├── synoptic.obs_y2026m08  [2026-08-01, 2026-09-01)            │
│                      │  ├── synoptic.obs_y2026m09  [2026-09-01, 2026-10-01)            │
│                      │  ├── synoptic.obs_y2026m10  [2026-10-01, 2026-11-01)            │
│                      │  └── synoptic.obs_default   (DEFAULT Catch-All Partition)       │
├──────────────────────┼─────────────────────────────────────────────────────────────────┤
│ Module 2             │ 5 Specialized Indexes:                                          │
│                      │  1. idx_obs_brin_time            (BRIN, pages_per_range = 8)    │
│                      │  2. idx_obs_btree_time           (B-Tree size baseline)         │
│                      │  3. idx_obs_suspect_only         (Partial: qc_flag != 'VALID')  │
│                      │  4. idx_obs_station_time_covering(Covering: INCLUDE 3 columns)  │
│                      │  5. idx_obs_part_sensor_gin      (GIN on JSONB sensor_payload)  │
├──────────────────────┼─────────────────────────────────────────────────────────────────┤
│ Module 4             │ nwp.mv_daily_model_verification (Materialized View + Unique Key)│
│                      │ Dynamic PL/pgSQL PostGIS Enablement (GEOGRAPHY(Point,4326)+GiST)│
│                      │ Cluster-Wide VACUUM ANALYZE                                     │
└──────────────────────┴─────────────────────────────────────────────────────────────────┘
```

---

## 2. Header Banner & Session Environment Configuration (Lines 1–11)

### Exact SQL Code (`Lines 1–11`)

```sql
-- ============================================================================
-- DAY 3 BOOTCAMP: ADVANCED PRODUCTION POSTGRESQL FOR WEATHER ENGINEERS
-- File: day3_weather_advanced_pg.sql
-- Prerequisite: Run after weather_ops_pg.sql (Day 2)
-- Usage: psql -d weather_ops -f day3_weather_advanced_pg.sql
-- ============================================================================

SET timezone = 'UTC';
SET datestyle = 'iso, ymd';
SET search_path TO synoptic, nwp, alerts, public;
```

### Line-by-Line Architectural Breakdown

- **Header Comments (`Lines 1–6`):** Documents the prerequisite database state. The script expects the `weather_ops` database and its three operational schemas (`synoptic`, `nwp`, `alerts`) plus the base tables (`synoptic.stations`, `synoptic.observations`, `nwp.forecasts`, `alerts.cap_bulletins`) created by [../day2/weather_ops_pg.sql](../day2/weather_ops_pg.sql).
- **`SET timezone = 'UTC';` (`Line 8`):**
  - **Meteorological Mandate:** World Meteorological Organization (WMO) synoptic reporting (`00Z`, `06Z`, `12Z`, `18Z`) and NWP initialization cycles operate strictly in Coordinated Universal Time (`UTC`).
  - **PostgreSQL Internals:** PostgreSQL always stores `TIMESTAMPTZ` (`timestamp with time zone`) on disk as a 64-bit integer (`8 bytes`) representing microseconds elapsed since `2000-01-01 00:00:00 UTC`. However, when evaluating partition boundary literals, rendering timestamps to the client, or executing `EXTRACT(HOUR FROM obs_time)` and `DATE_TRUNC('day', f.valid_time)`, PostgreSQL converts the internal UTC value into the active session `timezone`. Locking the session to `'UTC'` guarantees that partition boundaries (`00:00:00+00`), diurnal solar windows (`07:00` to `18:00 UTC`), and daily NWP aggregation buckets (`DATE_TRUNC('day', ...)`) never shift due to local Daylight Saving Time (DST) transitions or server OS timezone settings.
- **`SET datestyle = 'iso, ymd';` (`Line 9`):**
  - Enforces unambiguous **ISO-8601** date input parsing and text output formatting (`YYYY-MM-DD HH:MI:SS+00`). This prevents regional locale ambiguities between European (`DD/MM/YYYY`) and US (`MM/DD/YYYY`) date strings during partition bound declarations and client ingestion.
- **`SET search_path TO synoptic, nwp, alerts, public;` (`Line 10`):**
  - Configures the schema resolution order for unqualified relation, type, and function names. While all DDL statements in this script explicitly qualify tables with their schema prefix (`synoptic.observations_part`, `nwp.mv_daily_model_verification`), including `public` in the `search_path` ensures that extension functions and spatial types installed into `public` (such as PostGIS `GEOGRAPHY`, `ST_MakePoint`, and `ST_SetSRID`) resolve automatically without requiring `public.` prefixes.

---

## 3. Module 1: Declarative Time-Series Partitioning (`PARTITION BY RANGE`) (Lines 12–81)

### 3.1 Partitioned Parent Table Declaration (`Lines 12–31`)

#### Exact SQL Code (`Lines 12–31`)

```sql
-- ============================================================================
-- MODULE 1: DECLARATIVE TIME-SERIES PARTITIONING (PARTITION BY RANGE)
-- Splitting synoptic observations into monthly child partitions
-- ============================================================================
DROP TABLE IF EXISTS synoptic.observations_part CASCADE;

CREATE TABLE synoptic.observations_part (
    station_id     INTEGER      NOT NULL REFERENCES synoptic.stations(station_id),
    obs_time       TIMESTAMPTZ  NOT NULL,
    temp_c         NUMERIC(4,1),
    dewpoint_c     NUMERIC(4,1),
    humidity_pct   NUMERIC(4,1),
    pressure_hpa   NUMERIC(6,1),
    wind_speed_kt  NUMERIC(4,1),
    precip_1h_mm   NUMERIC(5,1),
    qc_flag        VARCHAR(15)  NOT NULL DEFAULT 'VALID',
    sensor_payload JSONB        DEFAULT '{}'::JSONB,
    PRIMARY KEY (obs_time, station_id) -- Partition key (obs_time) MUST be part of Primary/Unique Key
) PARTITION BY RANGE (obs_time);
```

#### Line-by-Line Architectural Breakdown

- **`DROP TABLE IF EXISTS synoptic.observations_part CASCADE;` (`Line 16`):**
  - Makes the script 100% idempotent. Dropping the partitioned parent table with `CASCADE` automatically drops all attached child partitions (`obs_y2026m06` through `obs_y2026m10` and `obs_default`) and any dependent indexes.
- **Virtual Parent Table (`CREATE TABLE synoptic.observations_part ... PARTITION BY RANGE (obs_time);`, `Lines 18–30`):**
  - In PostgreSQL declarative partitioning (`relkind = 'p'` in `pg_class`), the parent table `synoptic.observations_part` has **zero physical storage (`0 bytes` heap file on disk)**. It acts purely as a metadata router and schema contract. Every row inserted into `synoptic.observations_part` is dynamically routed by the executor's tuple-routing engine into the matching physical child table (`relkind = 'r'`).
- **Column Definitions (`Lines 19–28`):**
  - `station_id INTEGER NOT NULL REFERENCES synoptic.stations(station_id)`: Foreign key referencing the WMO 5-digit station identifier (`60390` Dar El Beida, `60580` Ouargla, etc.). PostgreSQL 12+ supports foreign keys declared directly on partitioned parent tables and enforces them across all child partitions.
  - `obs_time TIMESTAMPTZ NOT NULL`: The chronological partition key (`8 bytes`, UTC microsecond resolution).
  - `temp_c`, `dewpoint_c`, `humidity_pct`, `wind_speed_kt` (`NUMERIC(4,1)`), `pressure_hpa` (`NUMERIC(6,1)`), `precip_1h_mm` (`NUMERIC(5,1)`): Exact decimal meteorological measurements avoiding IEEE-754 floating-point rounding drift in official WMO climate summaries.
  - `qc_flag VARCHAR(15) NOT NULL DEFAULT 'VALID'`: Quality Control status code (`'VALID'`, `'SUSPECT'`, or `'ERRONEOUS'`).
  - `sensor_payload JSONB DEFAULT '{}'::JSONB`: Binary decomposed JSON column (`JSONB`) storing semi-structured IoT telemetry. Unlike plain text `JSON`, `JSONB` parses keys and values at write time into a binary tree structure with typed scalars, stripped whitespace, deduplicated keys, and full support for `GIN` inverted indexing.
- **Why the Partition Key (`obs_time`) MUST Be Part of `PRIMARY KEY (obs_time, station_id)` (`Line 29`):**
  - Notice the inline architectural rule on `Line 29`: `-- Partition key (obs_time) MUST be part of Primary/Unique Key`.
  - In PostgreSQL, there is **no global cross-partition B-Tree index**. Each child partition (`obs_y2026m06`, `obs_y2026m07`, etc.) maintains its own independent local B-Tree index file on disk.
  - To guarantee that a `PRIMARY KEY` or `UNIQUE` constraint holds across the entire partitioned table without locking and scanning every single child partition on every `INSERT`, PostgreSQL mathematically requires that the partition key (`obs_time`) be a subset of the unique key. Because `obs_time` determines which unique child partition a row belongs to, guaranteeing uniqueness of `(obs_time, station_id)` inside a single child partition automatically guarantees global uniqueness across all partitions!
  - Furthermore, placing `obs_time` first in `PRIMARY KEY (obs_time, station_id)` aligns the local B-Tree leaf ordering with chronological time-range scans.

---

### 3.2 Monthly Child Partitions & Half-Open Range Bounds (`Lines 32–50`)

#### Exact SQL Code (`Lines 32–50`)

```sql
-- Create Monthly Partitions (June 2026 through October 2026)
CREATE TABLE synoptic.obs_y2026m06 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE synoptic.obs_y2026m07 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');

CREATE TABLE synoptic.obs_y2026m08 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');

CREATE TABLE synoptic.obs_y2026m09 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE synoptic.obs_y2026m10 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');

-- Default partition to catch any out-of-range timestamps so ingestion never fails
CREATE TABLE synoptic.obs_default PARTITION OF synoptic.observations_part DEFAULT;
```

#### Deep-Dive Architectural Explanation

- **Half-Open Interval Semantics ($[T_{\text{start}}, T_{\text{end}})$):**
  - Every PostgreSQL range partition bound `FOR VALUES FROM (lower_bound) TO (upper_bound)` is **inclusive at the lower bound** and **strictly exclusive at the upper bound**:
    $$\text{Partition Range} = [T_{\text{start}}, T_{\text{end}}) \iff T_{\text{start}} \le \text{obs\_time} < T_{\text{end}}$$
  - For example, in `synoptic.obs_y2026m06`:
    - A timestamp of `'2026-06-01 00:00:00.000000+00'` satisfies $\ge \text{'2026-06-01 00:00:00+00'}$ and routes into `obs_y2026m06`.
    - A timestamp of `'2026-06-30 23:59:59.999999+00'` satisfies $< \text{'2026-07-01 00:00:00+00'}$ and routes into `obs_y2026m06`.
    - Exactly at midnight `'2026-07-01 00:00:00.000000+00'`, the row is excluded from `obs_y2026m06` and routes cleanly into `obs_y2026m07`.
  - Why half-open intervals are superior to `BETWEEN`: Continuous `TIMESTAMPTZ` values have microsecond precision (`0.000001 s`). Using closed bounds would require fragile upper limits like `'2026-06-30 23:59:59.999999+00'`, risking microsecond gaps or overlaps. With $[T_{\text{start}}, T_{\text{end}})$, the upper bound of month $N$ is identical to the lower bound of month $N+1$, ensuring zero gaps across time.
- **Why `synoptic.obs_default` (`PARTITION OF ... DEFAULT`, `Line 49`) is Critical in Live Telemetry Ingestion:**
  - Without a `DEFAULT` partition, if a weather station's RTC clock drifts (sending a timestamp from `2025` or `2027`), or if a cron job (`pg_partman`) fails to pre-create next month's partition before midnight on the 1st of the month, PostgreSQL immediately aborts the `INSERT` batch with:
    `ERROR: no partition of relation "observations_part" found for row`
  - In high-throughput meteorological ingestion, an unhandled exception drops an entire batch of real-time WMO observations. Defining `synoptic.obs_default` acts as a physical safety net: any timestamp outside `[2026-06-01, 2026-11-01)` is safely captured on disk in `obs_default` so ingestion never halts. Database administrators monitor `pg_relation_size('synoptic.obs_default')` and periodically inspect/migrate those rows.

---

### 3.3 Populating the Partitioned Table & Synthesizing Binary `JSONB` Payloads (`Lines 51–80`)

#### Exact SQL Code (`Lines 51–80`)

```sql
-- Populate partitioned table from Day 2 observations + attach rich JSONB sensor telemetry
INSERT INTO synoptic.observations_part (
    station_id, obs_time, temp_c, dewpoint_c, humidity_pct,
    pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag, sensor_payload
)
SELECT
    station_id,
    obs_time,
    temp_c,
    dewpoint_c,
    humidity_pct,
    pressure_hpa,
    wind_speed_kt,
    precip_1h_mm,
    qc_flag,
    jsonb_build_object(
        'battery_v', ROUND((12.1 + RANDOM() * 1.4)::NUMERIC, 2),
        'solar_w_m2', CASE
            WHEN EXTRACT(HOUR FROM obs_time) BETWEEN 7 AND 18
            THEN ROUND((300 + RANDOM() * 650)::NUMERIC, 0)
            ELSE 0
        END,
        'gust_3s_kt', ROUND((wind_speed_kt * (1.15 + RANDOM() * 0.35))::NUMERIC, 1),
        'sensors', jsonb_build_array('PT100_THERM', 'CAP_HYGRO', 'ULTRASONIC_WIND'),
        'diagnostics', jsonb_build_object(
            'door_open', (RANDOM() > 0.995),
            'firmware', CASE WHEN station_id IN (60390, 60490) THEN 'v4.2.1' ELSE 'v3.9.0' END
        )
    )
FROM synoptic.observations;
```

#### Line-by-Line Architectural Breakdown

- **Bulk Tuple Routing (`INSERT INTO synoptic.observations_part ... SELECT ... FROM synoptic.observations`, `Lines 52–80`):**
  - Reads all 4,320 historical synoptic rows from the monolithic Day 2 table `synoptic.observations` (spanning `2026-08-17` to `2026-10-15` across 8 Algerian stations) and streams them into the partitioned parent table `synoptic.observations_part`.
  - During execution, PostgreSQL inspects `obs_time` on each row and routes August rows into `synoptic.obs_y2026m08`, September rows into `synoptic.obs_y2026m09`, and October rows into `synoptic.obs_y2026m10`.
- **Synthesizing Binary `JSONB` Hardware Payloads (`Lines 66–79`):**
  - **`jsonb_build_object(key1, val1, key2, val2, ...)` (`Line 66`):** Variadic PostgreSQL function that constructs a binary `JSONB` object directly in memory from alternating key/value arguments, preserving native data types (numeric, boolean, array, nested object) without string concatenation or text-parsing overhead.
  - **`'battery_v', ROUND((12.1 + RANDOM() * 1.4)::NUMERIC, 2)` (`Line 67`):** Simulates a 12V lead-acid / LiFePO4 solar-charged station battery voltage fluctuating between $12.10\text{ V}$ and $13.50\text{ V}$ with 2 decimal places. Because `RANDOM()` returns a `DOUBLE PRECISION` in $[0.0, 1.0)$, the expression is cast via `::NUMERIC` before calling `ROUND(val, 2)`.
  - **Diurnal Solar Irradiance Simulation (`'solar_w_m2'`, `Lines 68–72`):**
    - `EXTRACT(HOUR FROM obs_time) BETWEEN 7 AND 18`: Extracts the UTC hour ($0\text{..}23$) from `obs_time`. If the observation occurs during daylight hours (`07:00 UTC` through `18:00 UTC` inclusive), the pyranometer sensor reports shortwave global horizontal irradiance (GHI) between $300\text{ W/m}^2$ and $950\text{ W/m}^2$ (`ROUND((300 + RANDOM() * 650)::NUMERIC, 0)`).
    - During nighttime hours (`19:00 UTC` through `06:00 UTC`), `'solar_w_m2'` deterministically evaluates to `0`.
  - **3-Second Peak Wind Gust Factor (`'gust_3s_kt'`, `Line 73`):**
    - `ROUND((wind_speed_kt * (1.15 + RANDOM() * 0.35))::NUMERIC, 1)`: In boundary-layer meteorology, the WMO 3-second peak wind gust ($G_{3\text{s}}$) exceeds the 10-minute sustained mean wind speed ($U_{10\text{m}}$) by a turbulence gust factor typically ranging from $1.15\times$ to $1.50\times$. This formula scales each row's `wind_speed_kt` by $[1.15, 1.50)$ and rounds to $0.1\text{ kt}$.
  - **`'sensors', jsonb_build_array('PT100_THERM', 'CAP_HYGRO', 'ULTRASONIC_WIND')` (`Line 74`):**
    - `jsonb_build_array(...)` constructs a native `JSONB` array `["PT100_THERM", "CAP_HYGRO", "ULTRASONIC_WIND"]` representing the hardware probe manifest (Platinum Resistance Thermometer PT100, Capacitive Hygrometer, and 2D/3D Ultrasonic Anemometer).
  - **Nested `'diagnostics'` Object (`Lines 75–78`):**
    - Calls a nested `jsonb_build_object(...)` containing two operational telemetry attributes:
      1. `'door_open', (RANDOM() > 0.995)`: Evaluates a boolean expression that is `true` for $\approx 0.5\%$ of observations (simulating a physical datalogger enclosure intrusion or maintenance visit).
      2. `'firmware', CASE WHEN station_id IN (60390, 60490) THEN 'v4.2.1' ELSE 'v3.9.0' END`: Assigns firmware `'v4.2.1'` to primary international airport stations (`60390` Algiers Dar El Beida and `60490` Oran Es Senia) and `'v3.9.0'` to regional stations.

#### Sample Synthesized `sensor_payload` Document

```json
{
  "sensors": ["PT100_THERM", "CAP_HYGRO", "ULTRASONIC_WIND"],
  "battery_v": 12.84,
  "gust_3s_kt": 19.6,
  "solar_w_m2": 742,
  "diagnostics": {
    "firmware": "v4.2.1",
    "door_open": false
  }
}
```

---

## 4. Module 2: Deep Walkthrough of the 5 Specialized Indexes (Lines 82–107)

### Exact SQL Code (`Lines 82–107`)

```sql
-- ============================================================================
-- MODULE 2: ADVANCED INDEXING (BRIN, PARTIAL, COVERING & GIN)
-- ============================================================================

-- 1. BRIN Index (Block Range Index) on chronological time-series column
CREATE INDEX idx_obs_brin_time
ON synoptic.observations USING BRIN (obs_time) WITH (pages_per_range = 8);

-- 2. Standard B-Tree Index on obs_time (to compare disk size against BRIN!)
CREATE INDEX idx_obs_btree_time
ON synoptic.observations USING BTREE (obs_time);

-- 3. Partial Index: Only index anomalous ('SUSPECT' or 'ERRONEOUS') observations (~4% of rows)
CREATE INDEX idx_obs_suspect_only
ON synoptic.observations (station_id, obs_time)
WHERE qc_flag != 'VALID';

-- 4. Covering Index (INCLUDE) for Index-Only Scans on station temperature queries
CREATE INDEX idx_obs_station_time_covering
ON synoptic.observations (station_id, obs_time)
INCLUDE (temp_c, pressure_hpa, precip_1h_mm);

-- 5. GIN Index on JSONB sensor_payload for fast NoSQL-style containment queries (@>)
CREATE INDEX idx_obs_part_sensor_gin
ON synoptic.observations_part USING GIN (sensor_payload);
```

---

### Architectural Comparison of the 5 Specialized Indexes

| # | Index Name | Target Table | Access Method & Clause | What is Stored on Disk | Primary Meteorological Use Case | Relative Storage Footprint |
| :- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `idx_obs_brin_time` | `synoptic.observations` | `USING BRIN (obs_time) WITH (pages_per_range = 8)` | Only `[min(obs_time), max(obs_time)]` summary pair per 8 contiguous 8 KB heap pages (`64 KB` block range) | Chronological time-window scans on append-only telemetry | **Ultra-Tiny** ($\approx 24\text{ KB}$, ~95–99.9% smaller than B-Tree) |
| **2** | `idx_obs_btree_time` | `synoptic.observations` | `USING BTREE (obs_time)` | Doubly-linked tree of 8 KB pages storing `(obs_time, ctid)` for **every single row** in the table | Baseline size comparison vs. BRIN; exact timestamp point lookups and `ORDER BY obs_time` | **Baseline Full Size** ($\approx 112\text{ KB}$ on 4.3k rows; ~28 MB per 1.27M rows) |
| **3** | `idx_obs_suspect_only` | `synoptic.observations` | `USING BTREE (station_id, obs_time) WHERE qc_flag != 'VALID'` | B-Tree entries **only** for rows satisfying `qc_flag != 'VALID'` (`'SUSPECT'` or `'ERRONEOUS'`), skipping the 96% `'VALID'` majority | Quality Control (QC) dashboards auditing anomalous sensor readings | **Tiny** ($\approx 16\text{ KB}$, ~90%+ smaller than full composite B-Tree) |
| **4** | `idx_obs_station_time_covering` | `synoptic.observations` | `USING BTREE (station_id, obs_time) INCLUDE (temp_c, pressure_hpa, precip_1h_mm)` | Search keys `(station_id, obs_time)` in internal + leaf nodes; non-key payload `(temp_c, pressure_hpa, precip_1h_mm)` appended to **leaf nodes only** | High-frequency API/meteogram queries fetching station time series via `Index Only Scan` (`Heap Fetches: 0`) | **Medium-Large** ($\approx 240\text{ KB}$, trades index disk space for zero random heap I/O) |
| **5** | `idx_obs_part_sensor_gin` | `synoptic.observations_part` | `USING GIN (sensor_payload)` (propagates to all 6 child partitions) | Inverted B-Tree of extracted `JSONB` keys/paths/values mapped to sorted posting lists/trees of tuple `ctid`s | NoSQL-style `@>` containment queries on nested IoT diagnostics (`door_open: true`, `firmware: "v4.2.1"`) | **Large** (multi-entry per row, partitioned monthly to stay in RAM) |

---

### Individual Deep-Dive Breakdown of Each Index

#### 1. `idx_obs_brin_time` — Block Range Index (`Lines 86–88`)

```sql
CREATE INDEX idx_obs_brin_time
ON synoptic.observations USING BRIN (obs_time) WITH (pages_per_range = 8);
```

- **How BRIN Works Internally:**
  - Unlike a B-Tree—which stores an explicit 6-byte tuple pointer (`ctid = (block_number, item_offset)`) for every row in the table—a **Block Range Index (BRIN)** is a *lossy, course-grained summary index*.
  - It groups contiguous 8 KB physical heap pages into fixed-size ranges controlled by the storage parameter `pages_per_range`.
  - Here, `WITH (pages_per_range = 8)` overrides PostgreSQL's default of `128` pages (`1 MB`) down to **8 physical 8 KB heap pages ($8 \times 8\text{ KB} = 64\text{ KB}$ per range)** so that fine-grained range skipping is visible even on a compact multi-thousand-row synoptic table.
  - For each 8-page (`64 KB`) block range, `idx_obs_brin_time` stores only a tiny summary tuple containing:
    $$\text{Block Range } k \longrightarrow \big[\min(\text{obs\_time}),\; \max(\text{obs\_time})\big]$$
- **Two-Phase Bitmap Execution (`Bitmap Index Scan` $\rightarrow$ `Bitmap Heap Scan`):**
  1. When a query filters `WHERE obs_time >= T1 AND obs_time < T2`, the `Bitmap Index Scan` checks the `[min, max]` interval of each 8-page range. Any 8-page chunk whose `[min, max]` does not overlap `[T1, T2)` is skipped entirely.
  2. Overlapping 8-page ranges are flagged in a lossy page bitmap. The `Bitmap Heap Scan` then reads those specific 8 KB pages sequentially and applies a `Recheck Cond` to filter the exact tuples inside each page.
- **Physical Correlation Requirement:** BRIN effectiveness depends on the physical correlation between the column value (`obs_time`) and the physical heap file order (measured in `pg_stats.correlation` from `-1.0` to `+1.0`). Because weather observations arrive chronologically (`correlation ≈ 1.0`), each 8-page block spans a tight, non-overlapping time window.

---

#### 2. `idx_obs_btree_time` — Standard B-Tree Baseline (`Lines 90–92`)

```sql
CREATE INDEX idx_obs_btree_time
ON synoptic.observations USING BTREE (obs_time);
```

- **Why It Is Created on the Same Column:**
  - `idx_obs_btree_time` indexes the exact same `obs_time` column on `synoptic.observations` using PostgreSQL's default Lehman-Yao high-concurrency B-Tree (`USING BTREE`).
  - Creating both `idx_obs_brin_time` and `idx_obs_btree_time` side-by-side on the same table enables direct catalog inspection via `pg_relation_size('synoptic.idx_obs_btree_time')` vs. `pg_relation_size('synoptic.idx_obs_brin_time')`.
  - Even on 4,320 rows, the B-Tree consumes `112 KB` while the BRIN consumes only `24 KB` (the minimum 3-page BRIN metadata header + revmap + summary page). At 1.27 million rows (benchmarked in [day3_postgis_5m_benchmark.sql](./day3_postgis_5m_benchmark.sql)), the B-Tree swells to `~28 MB` while the BRIN remains `24–48 KB` (**99.9% reduction**).

---

#### 3. `idx_obs_suspect_only` — Partial (Filtered) B-Tree Index (`Lines 94–97`)

```sql
CREATE INDEX idx_obs_suspect_only
ON synoptic.observations (station_id, obs_time)
WHERE qc_flag != 'VALID';
```

- **How Predicate Filtering (`WHERE qc_flag != 'VALID'`) Works:**
  - In operational synoptic meteorology, **$\approx 96\%$ of incoming observations pass automated WMO Quality Control (`qc_flag = 'VALID'`)**, while only **$\approx 4\%$ are flagged as anomalous (`'SUSPECT'` or `'ERRONEOUS'`)**.
  - If we built a standard index on `(qc_flag, station_id, obs_time)`, 96% of the index pages, RAM cache footprint, and WAL write overhead would be wasted indexing `'VALID'` rows that QC engineers never query by flag.
  - Adding the `WHERE qc_flag != 'VALID'` predicate instructs PostgreSQL to evaluate the filter during `INSERT`/`UPDATE`. If a row has `qc_flag = 'VALID'`, **no index tuple is inserted into `idx_obs_suspect_only` at all**.
  - Whenever an analyst runs a query whose `WHERE` clause mathematically implies `qc_flag != 'VALID'` (for example, `WHERE qc_flag != 'VALID'` or `WHERE qc_flag IN ('SUSPECT', 'ERRONEOUS')`), the PostgreSQL planner automatically selects `idx_obs_suspect_only`, scanning a tiny `16 KB` B-Tree containing only the anomalous 4% of rows.

---

#### 4. `idx_obs_station_time_covering` — Covering Index with `INCLUDE` Payload (`Lines 99–102`)

```sql
CREATE INDEX idx_obs_station_time_covering
ON synoptic.observations (station_id, obs_time)
INCLUDE (temp_c, pressure_hpa, precip_1h_mm);
```

- **How `INCLUDE` Unlocks `Index Only Scan` (`Heap Fetches: 0`):**
  - A standard B-Tree on `(station_id, obs_time)` locates matching rows quickly, but if the query's `SELECT` list requests `SELECT obs_time, temp_c, pressure_hpa, precip_1h_mm`, PostgreSQL must follow each index entry's `ctid` pointer out to the 8 KB table heap pages to fetch those three weather measurements (**random heap I/O amplification**).
  - The `INCLUDE (temp_c, pressure_hpa, precip_1h_mm)` clause appends those three meteorological columns directly into the **leaf pages** of the B-Tree as non-key payload bytes, while keeping them **out of the upper internal branch/root routing nodes**:

```
               ┌───────────────────────────────────────┐
               │   Root / Internal Branch B-Tree Node  │
               │   Stores ONLY (station_id, obs_time)  │  <-- Slim tree fan-out!
               └───────────────────┬───────────────────┘
                                   │
               ┌───────────────────▼───────────────────┐
               │          Leaf B-Tree Page             │
               │ Key: (station_id, obs_time)           │
               │ Payload: temp_c, pressure_hpa, precip │  <-- Full query answer!
               └───────────────────────────────────────┘
```

- **Why `INCLUDE` Is Better Than a 5-Column Composite Key `(station_id, obs_time, temp_c, pressure_hpa, precip_1h_mm)`:**
  - Omitting `temp_c`, `pressure_hpa`, and `precip_1h_mm` from the upper branch nodes keeps internal B-Tree keys narrow (`12 bytes` instead of `30+ bytes`), maximizing fan-out per 8 KB branch page and avoiding redundant sort comparisons on payload columns.
  - When combined with a freshly vacuumed Visibility Map (`VACUUM ANALYZE;` on `Line 151`), PostgreSQL answers station meteogram queries purely from the index leaf pages (`Index Only Scan` with `Heap Fetches: 0`).

---

#### 5. `idx_obs_part_sensor_gin` — Generalized Inverted Index on Partitioned `JSONB` (`Lines 104–106`)

```sql
CREATE INDEX idx_obs_part_sensor_gin
ON synoptic.observations_part USING GIN (sensor_payload);
```

- **How `GIN` Decomposes `JSONB` into an Inverted Posting List:**
  - Standard B-Tree indexes can only compare whole scalar values (`=`, `<`, `>`). They cannot search inside a `JSONB` document with multi-level nested keys and arrays.
  - A **Generalized Inverted Index (`USING GIN`)** uses the default `jsonb_ops` operator class to recursively shred every `JSONB` document in `sensor_payload` into individual keys, scalar values, and array elements.
  - It stores these tokens in an internal B-Tree where each token points to a compressed **posting list (or posting tree)** of tuple `ctid`s where that token appears:
    ```
    Token Key/Value               Posting List of Tuple CTIDs
    ───────────────────────────   ──────────────────────────────────────
    "door_open" : true       ───► [(0, 14), (3, 29), (11, 4)]
    "firmware"  : "v4.2.1"   ───► [(0, 1), (0, 2), (0, 9), (1, 5), ...]
    "ULTRASONIC_WIND"        ───► [(0, 1), (0, 2), (0, 3), ...]
    ```
- **Partitioned Index Propagation:**
  - Because `idx_obs_part_sensor_gin` is created on the partitioned parent table `synoptic.observations_part`, PostgreSQL automatically creates and maintains **6 independent local `GIN` indexes**—one on each monthly child partition (`obs_y2026m06_sensor_payload_idx` through `obs_y2026m10_sensor_payload_idx` and `obs_default_sensor_payload_idx`).
  - When a query executes a JSONB containment check such as `WHERE sensor_payload @> '{"diagnostics": {"door_open": true}}'`, PostgreSQL combines **Partition Pruning** (if `obs_time` is filtered) with a **GIN Bitmap Index Scan** inside each relevant child partition.

---

## 5. Module 4: Materialized View, Concurrent Refresh & Dynamic PostGIS Block (Lines 108–152)

### 5.1 Pre-Aggregated NWP Model Verification Materialized View (`Lines 108–130`)

#### Exact SQL Code (`Lines 108–130`)

```sql
-- ============================================================================
-- MODULE 4: MATERIALIZED VIEW FOR NWP MODEL VERIFICATION DASHBOARD
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS nwp.mv_daily_model_verification;

CREATE MATERIALIZED VIEW nwp.mv_daily_model_verification AS
SELECT
    f.model_name,
    f.station_id,
    s.station_name,
    DATE_TRUNC('day', f.valid_time)::DATE                       AS valid_date,
    COUNT(*)                                                    AS verified_runs,
    ROUND(AVG(f.pred_temp_c - o.temp_c), 2)                     AS temp_bias_c,
    ROUND(AVG(ABS(f.pred_temp_c - o.temp_c)), 2)                AS temp_mae_c,
    ROUND(AVG(ABS(f.pred_wind_kt - o.wind_speed_kt)), 2)        AS wind_mae_kt
FROM nwp.forecasts f
INNER JOIN synoptic.observations o
    ON o.station_id = f.station_id
   AND o.obs_time   = f.valid_time
INNER JOIN synoptic.stations s
    ON s.station_id = f.station_id
GROUP BY f.model_name, f.station_id, s.station_name, DATE_TRUNC('day', f.valid_time)::DATE
WITH DATA;
```

#### Line-by-Line Architectural & Mathematical Breakdown

- **`DROP MATERIALIZED VIEW IF EXISTS nwp.mv_daily_model_verification;` (`Line 111`):**
  - Ensures idempotent re-execution by dropping any previously cached physical view relation.
- **Standard `VIEW` vs. `MATERIALIZED VIEW` (`Line 113`):**
  - A standard PostgreSQL `VIEW` is just a saved query macro that re-executes the underlying 3-table join and aggregation on every `SELECT`.
  - A `MATERIALIZED VIEW` (`relkind = 'm'` in `pg_class`) allocates a physical 8 KB page heap on disk and persists the pre-computed query result set. Forecast verification dashboards can query `nwp.mv_daily_model_verification` in `< 0.2 ms` instead of repeatedly joining millions of forecast and observation rows.
- **The 3-Table Verification Join (`Lines 123–128`):**
  1. `FROM nwp.forecasts f`: Reads NWP model predictions (`model_name`, `station_id`, `model_run_time`, `valid_time`, `pred_temp_c`, `pred_wind_kt`). Note that because multiple NWP initialization cycles (`00Z`, `12Z` across lead times) predict the same `valid_time`, multiple forecast rows can match a single synoptic observation.
  2. `INNER JOIN synoptic.observations o ON o.station_id = f.station_id AND o.obs_time = f.valid_time`: Pairs each forecast prediction with the ground-truth surface observation recorded at the exact same station (`station_id`) and valid timestamp (`obs_time = valid_time`).
  3. `INNER JOIN synoptic.stations s ON s.station_id = f.station_id`: Enriches the result with the human-readable `station_name` (e.g., `'Dar El Beida (Algiers)'`).
- **Temporal Bucketing (`DATE_TRUNC('day', f.valid_time)::DATE AS valid_date`, `Line 118` & `Line 129`):**
  - `DATE_TRUNC('day', f.valid_time)` truncates the `TIMESTAMPTZ` down to `00:00:00+00` UTC of that calendar day, and `::DATE` casts it to a 4-byte `DATE` (`YYYY-MM-DD`). Grouping by `(f.model_name, f.station_id, s.station_name, DATE_TRUNC('day', f.valid_time)::DATE)` produces one verification summary row per NWP model, per station, per UTC day.
- **Meteorological Verification Formulas (`Lines 119–122`):**
  - **`COUNT(*) AS verified_runs` (`Line 119`):** Counts the number of matched `(forecast, observation)` verification pairs evaluated for that `(model_name, station_id, valid_date)` group.
  - **Mean Temperature Bias (`ROUND(AVG(f.pred_temp_c - o.temp_c), 2) AS temp_bias_c`, `Line 120`):**
    $$\text{Mean Bias} = \frac{1}{N} \sum_{i=1}^{N} \left( T_{\text{pred}, i} - T_{\text{obs}, i} \right)$$
    Measures systematic directional error (**warm bias** if $> 0$, **cold bias** if $< 0$). Because positive and negative errors cancel out in `AVG(f.pred_temp_c - o.temp_c)`, a model that is $+5^\circ\text{C}$ too warm at noon and $-5^\circ\text{C}$ too cold at midnight has a `temp_bias_c` of `0.00`, which is why Mean Bias must always be paired with Mean Absolute Error (MAE).
  - **Temperature Mean Absolute Error (`ROUND(AVG(ABS(f.pred_temp_c - o.temp_c)), 2) AS temp_mae_c`, `Line 121`):**
    $$\text{MAE}_{T} = \frac{1}{N} \sum_{i=1}^{N} \left| T_{\text{pred}, i} - T_{\text{obs}, i} \right|$$
    Applies `ABS(...)` before `AVG(...)` so warm and cold errors do not cancel out, quantifying true average error magnitude in $^\circ\text{C}$.
  - **Wind Speed Mean Absolute Error (`ROUND(AVG(ABS(f.pred_wind_kt - o.wind_speed_kt)), 2) AS wind_mae_kt`, `Line 122`):**
    $$\text{MAE}_{W} = \frac{1}{N} \sum_{i=1}^{N} \left| W_{\text{pred}, i} - W_{\text{obs}, i} \right|$$
    Quantifies average wind speed forecast error magnitude in knots (`kt`).
- **`WITH DATA;` (`Line 130`):**
  - Instructs PostgreSQL to execute the query immediately during `CREATE MATERIALIZED VIEW` and populate the underlying heap pages (as opposed to `WITH NO DATA`, which creates an empty unpopulated structure requiring a subsequent `REFRESH`).

---

### 5.2 Enabling Non-Blocking Concurrent Refresh (`Lines 132–135`)

#### Exact SQL Code (`Lines 132–135`)

```sql
-- Unique index required to enable REFRESH MATERIALIZED VIEW CONCURRENTLY!
CREATE UNIQUE INDEX idx_mv_daily_verif_unique
ON nwp.mv_daily_model_verification (model_name, station_id, valid_date);
```

#### Deep-Dive Architectural Explanation

- **Why a `UNIQUE INDEX` Is Mandatory for `REFRESH MATERIALIZED VIEW CONCURRENTLY`:**
  - A standard `REFRESH MATERIALIZED VIEW nwp.mv_daily_model_verification;` acquires an **`ACCESS EXCLUSIVE` lock** on the materialized view while recomputing the entire query from scratch. Any weather dashboard or API executing a `SELECT` against the view is completely blocked until the refresh finishes.
  - Appending the `CONCURRENTLY` keyword (`REFRESH MATERIALIZED VIEW CONCURRENTLY nwp.mv_daily_model_verification;`) downgrades the lock to an **`EXCLUSIVE` lock** that **does NOT block concurrent `SELECT` readers**.
  - How PostgreSQL performs `REFRESH ... CONCURRENTLY` under the hood:
    1. PostgreSQL executes the view query into a temporary staging relation (`pg_temp_...`).
    2. It performs an outer join (`FULL JOIN`) between the existing materialized view and the new staging table to identify which rows were **inserted**, **updated**, or **deleted**.
    3. It applies those exact `INSERT`, `UPDATE`, and `DELETE` diffs in-place on `nwp.mv_daily_model_verification`, allowing existing dashboard queries to keep reading the previous MVCC snapshot seamlessly!
  - Because PostgreSQL must uniquely match each old row to its corresponding new row during step 2, PostgreSQL refuses to run `REFRESH MATERIALIZED VIEW CONCURRENTLY` unless the materialized view has at least one **`UNIQUE` index without a `WHERE` clause** over non-null columns.
  - Because the `GROUP BY` grain of `mv_daily_model_verification` is `(model_name, station_id, valid_date)` (`station_name` is functionally dependent on `station_id`), creating `idx_mv_daily_verif_unique` on `(model_name, station_id, valid_date)` satisfies this exact requirement and also serves as the primary lookup index for dashboard filters.

---

### 5.3 Dynamic PL/pgSQL PostGIS Enablement & `GEOGRAPHY(Point, 4326)` Upgrade (`Lines 136–152`)

#### Exact SQL Code (`Lines 136–152`)

```sql
-- Automatically enable PostGIS and populate synoptic.stations.geog if PostGIS package is installed
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'postgis') THEN
        CREATE EXTENSION IF NOT EXISTS postgis;
        ALTER TABLE synoptic.stations ADD COLUMN IF NOT EXISTS geog GEOGRAPHY(Point, 4326);
        UPDATE synoptic.stations SET geog = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::GEOGRAPHY;
        CREATE INDEX IF NOT EXISTS idx_stations_geog_gist ON synoptic.stations USING GIST (geog);
        RAISE NOTICE 'PostGIS enabled and synoptic.stations.geog populated!';
    ELSE
        RAISE NOTICE 'PostGIS extension not installed on host OS yet (skipping optional geog column).';
    END IF;
END
$$;

VACUUM ANALYZE;
```

#### Line-by-Line Architectural Breakdown

- **`DO $$ BEGIN ... END $$;` (`Lines 137–149`):**
  - Executes an anonymous PL/pgSQL procedural block inside the current transaction without persisting a named stored procedure. This allows conditional DDL execution (`IF EXISTS ... THEN ... ELSE ... END IF;`), which standard declarative SQL does not support natively.
- **Inspecting `pg_available_extensions` (`Line 139`):**
  - Queries the system view `pg_available_extensions` (which scans PostgreSQL's OS `SHAREDIR/extension/*.control` directory, e.g., `/usr/share/postgresql/16/extension/postgis.control`).
  - If the `postgresql-16-postgis-3` OS package is installed on the host, `SELECT 1 FROM pg_available_extensions WHERE name = 'postgis'` returns true and the `THEN` branch executes. If running on a bare host without PostGIS binaries, it gracefully logs a `NOTICE` (`Line 146`) rather than aborting the script.
- **`CREATE EXTENSION IF NOT EXISTS postgis;` (`Line 140`):**
  - Loads the PostGIS C shared libraries (`postgis-3.so`, linked against `GEOS` and `PROJ`), registers the `geometry` and `geography` data types, populates the `spatial_ref_sys` EPSG catalog table, and installs 1,000+ spatial functions (`ST_*`).
- **`ALTER TABLE synoptic.stations ADD COLUMN IF NOT EXISTS geog GEOGRAPHY(Point, 4326);` (`Line 141`):**
  - Appends a spatial column named `geog` to `synoptic.stations` using the PostGIS **`GEOGRAPHY(Point, 4326)`** data type:
    - **`GEOGRAPHY` vs. `GEOMETRY`:** While `GEOMETRY` treats coordinates as flat Cartesian $(X, Y)$ points on an Euclidean plane (returning meaningless "planar degrees" when using EPSG:4326), **`GEOGRAPHY`** models coordinates on the **WGS-84 oblate spheroid** (Earth equatorial radius $a = 6,378,137.0\text{ m}$, flattening $f = 1 / 298.257223563$). All distance (`ST_Distance`), buffer (`ST_Buffer`), and proximity (`ST_DWithin`) calculations on `GEOGRAPHY` are automatically computed in **exact meters** along geodesic great-circle/ellipsoidal paths.
    - **`Point`:** Type modifier restricting the column to 0-dimensional point features (rejecting polygons or linestrings).
    - **`4326`:** Spatial Reference System Identifier (**SRID 4326** = EPSG:4326, the World Geodetic System 1984 / GPS latitude-longitude standard).
- **`UPDATE synoptic.stations SET geog = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::GEOGRAPHY;` (`Line 142`):**
  - **`ST_MakePoint(longitude, latitude)` — Critical Coordinate Order Rule:** PostGIS and OGC spatial standards strictly follow Cartesian **`(X, Y)` = `(longitude, latitude)`** order, **NOT** `(latitude, longitude)`. Passing `(latitude, longitude)` flips North Africa into the Indian Ocean / Arabian Peninsula! Here, `longitude` is passed first ($X$) and `latitude` second ($Y$).
  - **`ST_SetSRID(..., 4326)`:** Tags the constructed `Point` geometry with SRID `4326` (WGS-84).
  - **`::GEOGRAPHY`:** Casts the SRID-4326 `GEOMETRY(Point, 4326)` object into a spheroidal `GEOGRAPHY(Point, 4326)` object and stores it in `synoptic.stations.geog`.
- **`CREATE INDEX IF NOT EXISTS idx_stations_geog_gist ON synoptic.stations USING GIST (geog);` (`Line 143`):**
  - Creates a **Generalized Search Tree (`GiST`)** spatial index on `geog`.
  - A 1D B-Tree cannot accelerate 2D/3D spatial proximity searches because sorting by longitude destroys latitude locality. PostGIS implements an **R-Tree on GiST** that hierarchically groups 3D geocentric bounding boxes (`Minimum Bounding Rectangles / Boxes`) of spatial features. When a query runs `WHERE ST_DWithin(geog, target_point, radius_meters)`, the GiST index prunes non-overlapping bounding boxes in logarithmic time before evaluating exact spheroidal trigonometry on the surviving candidates.
- **`VACUUM ANALYZE;` (`Line 151`):**
  - Runs across every table and materialized view in the `weather_ops` database to accomplish two essential tasks immediately after bulk loading and indexing:
    1. **`VACUUM`:** Sets the **Visibility Map (`VM`)** all-visible bits on every newly populated 8 KB heap page of `synoptic.observations_part` and `synoptic.observations`. Without an up-to-date Visibility Map, `idx_obs_station_time_covering` cannot execute a zero-heap-fetch `Index Only Scan` (it would still have to visit the heap page to check tuple MVCC `xmin`/`xmax` visibility).
    2. **`ANALYZE`:** Samples every table and child partition to populate `pg_statistic` (`pg_stats`) with accurate row counts (`reltuples`), page counts (`relpages`), `most_common_vals` (such as `'VALID'` = 96% in `qc_flag`), and physical `correlation` (`obs_time ≈ 1.0`), ensuring the cost-based optimizer selects our partial, covering, BRIN, and GIN indexes immediately.

---

## 6. Expected Terminal Output & Post-Execution Verification

### Expected `psql` Execution Output

When running `psql -d weather_ops -f day3_weather_advanced_pg.sql`, PostgreSQL produces the following exact sequence of command tags and notices:

```text
SET
SET
SET
DROP TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
INSERT 0 4320
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
DROP MATERIALIZED VIEW
SELECT 80
CREATE UNIQUE INDEX
psql:day3_weather_advanced_pg.sql:149: NOTICE:  PostGIS enabled and synoptic.stations.geog populated!
DO
VACUUM
```

*(Note: If the host OS does not yet have the `postgresql-16-postgis-3` package installed, Line 149 outputs `NOTICE: PostGIS extension not installed on host OS yet (skipping optional geog column).`)*

### Quick Verification Queries

You can immediately verify the physical sizes and row distributions created by `day3_weather_advanced_pg.sql` with the following diagnostic queries:

```sql
-- 1. Verify Partitioned Child Table Row Distribution (August, September, October 2026)
SELECT
    tableoid::regclass AS child_partition,
    COUNT(*)           AS row_count,
    MIN(obs_time)      AS first_obs,
    MAX(obs_time)      AS last_obs
FROM synoptic.observations_part
GROUP BY tableoid
ORDER BY child_partition::text;

-- 2. Compare On-Disk Sizes of the 4 Indexes on synoptic.observations
SELECT
    indexrelname                                 AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_relation_size(indexrelid)                 AS exact_bytes
FROM pg_stat_user_indexes
WHERE schemaname = 'synoptic'
  AND relname = 'observations'
ORDER BY exact_bytes DESC;

-- 3. Inspect NWP Model Verification Materialized View
SELECT *
FROM nwp.mv_daily_model_verification
ORDER BY valid_date DESC, model_name, station_id
LIMIT 10;
```

---

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [⏮️ Day 2 Coursebook](../day2/day2_master_coursebook.md) | [📘 Day 3 Coursebook](./day3_master_coursebook.md) | [⚡ 5M-Row PostGIS Benchmark Walkthrough](./day3_postgis_5m_benchmark_sql_course_walkthrough.md) | [⏭️ Day 4 Coursebook](../day4/day4_master_coursebook.md)
