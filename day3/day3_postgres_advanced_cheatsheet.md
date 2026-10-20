> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [⏮️ Day 2 Coursebook](../day2/day2_master_coursebook.md) | [📘 Day 3 Coursebook](day3_master_coursebook.md) | [⏭️ Day 4 Coursebook](../day4/day4_master_coursebook.md)

# Day 3 Cheatsheet: Partitioning, Advanced Indexing, PostGIS Geodesy, Window Functions & JSONB

**Companion to:**
- [../reference_cards/00_sql_and_mongodb_crud_fundamentals_for_weather_data.md](../reference_cards/00_sql_and_mongodb_crud_fundamentals_for_weather_data.md) — **Dedicated SQL & MongoDB CRUD & Data Exploration Fundamentals (`SELECT`, `INSERT ... RETURNING`, `UPDATE`, `DELETE`, `JOIN`s)**
- [day3_master_coursebook.md](./day3_master_coursebook.md)
- [day3_weather_advanced_pg.sql](./day3_weather_advanced_pg.sql) (`weather_ops`: `synoptic.observations_part`, `nwp.mv_daily_model_verification`, `synoptic.stations.geog`)
- [day3_postgis_5m_benchmark.sql](./day3_postgis_5m_benchmark.sql) (`weather_ops_db`: 5M-row `public.raw_telemetry_partitioned` & 50-station `public.stations.geom`)

---

> [!IMPORTANT]
> **Which Database Am I In? (`weather_ops` vs. `weather_ops_db`)**
> - Queries on **`synoptic.observations_part`**, **`synoptic.observations`**, **`synoptic.stations`**, and **`nwp.mv_daily_model_verification`** run in **`weather_ops`** (`\c weather_ops`, loaded via `day3_weather_advanced_pg.sql`).
> - Queries on **`public.raw_telemetry_partitioned`** (`5,000,000` rows) and **`public.stations`** (`AWS-001`..`AWS-050`, `geom`) run in **`weather_ops_db`** (`\c weather_ops_db`, loaded via `day3_postgis_5m_benchmark.sql`).

---

## 1. Declarative Time-Series Partitioning (`PARTITION BY RANGE`)

```
                   The 5 Physical Drivers of Partitioning
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ 1. Memory Working Set Fit  : Active B-Trees stay pinned in RAM cache        │
 │ 2. Vacuum & Maintenance    : Autovacuum isolates writes; old partitions freeze│
 │ 3. Heap Fragmentation      : Eliminates dead-space holes across 8 KB pages  │
 │ 4. I/O Boundary Pruning    : Queries read ONLY matching physical disks/files│
 │ 5. Abstraction Layer       : Master table routes queries with ZERO app logic│
 └─────────────────────────────────────────────────────────────────────────────┘
```

```sql
-- 1. Create Parent Partitioned Table (Partition key MUST be in PRIMARY KEY / UNIQUE)
CREATE TABLE synoptic.observations_part (
    station_id     INTEGER     NOT NULL,
    obs_time       TIMESTAMPTZ NOT NULL,
    temp_c         NUMERIC(4,1),
    pressure_hpa   NUMERIC(6,1),
    precip_1h_mm   NUMERIC(5,1),
    qc_flag        VARCHAR(15) NOT NULL DEFAULT 'VALID',
    sensor_payload JSONB       DEFAULT '{}'::JSONB,
    PRIMARY KEY (obs_time, station_id)
) PARTITION BY RANGE (obs_time);

-- 2. Create Monthly Child Partition (Inclusive lower bound, Exclusive upper bound)
CREATE TABLE synoptic.obs_y2026m11 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');

-- 3. Default Partition (Safety net for out-of-range timestamps)
CREATE TABLE synoptic.obs_default PARTITION OF synoptic.observations_part DEFAULT;

-- 4. Inspect Partition Sizes & Estimated Row Counts
SELECT
    inhrelid::regclass AS partition_name,
    pg_size_pretty(pg_relation_size(inhrelid)) AS heap_size,
    pg_size_pretty(pg_total_relation_size(inhrelid)) AS total_size,
    (SELECT reltuples::BIGINT FROM pg_class WHERE oid = inhrelid) AS estimated_rows
FROM pg_inherits
WHERE inhparent = 'synoptic.observations_part'::regclass
ORDER BY partition_name;

-- 5. Zero-Bloat Archival (O(1) metadata unlink — NEVER run DELETE on millions of old weather rows!)
ALTER TABLE synoptic.observations_part
    DETACH PARTITION synoptic.obs_y2026m06 CONCURRENTLY;
-- Optional: pg_dump the detached table to cold storage, then:
DROP TABLE synoptic.obs_y2026m06;
```

### 1.1 Partitioning Black Boxes Quick Reference (Black Box 3A)
* **Why `PRIMARY KEY (obs_id)` Fails on a Partitioned Table (`0A000`):** PostgreSQL does not maintain a single global B-Tree across all partitions (which would break $O(1)$ `DETACH PARTITION`). Every child partition owns an independent local B-Tree. Therefore, every `PRIMARY KEY` or `UNIQUE` constraint **must include the partition key** (`PRIMARY KEY (obs_time, station_id)`).
* **Why `FOR VALUES FROM (A) TO (B)` Is a Half-Open Interval $[A, B)$:** Lower bound `A` is **inclusive** ($\ge A$) and upper bound `B` is **strictly exclusive** ($< B$). Because timestamps are continuous microsecond points (`2026-06-30 23:59:59.999999+00`), setting `TO ('2026-07-01 00:00:00+00')` guarantees zero microsecond gaps between months and deterministic routing of exact midnight `00:00:00` to the new month.

---

## 2. Index Selection Matrix for Meteorological Data

| Index Type | Physical Mechanism | Disk Footprint (per 1.27M rows) | When to Use in Weather Databases | SQL Syntax |
| :--- | :--- | :--- | :--- | :--- |
| **B-Tree** *(Default)* | Balanced tree storing a pointer (`ctid`) for **every single row** | `~28 MB` (`~3.2 GB` per 100M rows) | High-cardinality lookups & joins: `(station_id, obs_time)` or `(station_id, valid_time)` | `CREATE INDEX idx_name ON synoptic.observations (station_id, obs_time);` |
| **BRIN** *(Block Range)* | Stores only **`MIN(time)` and `MAX(time)`** per contiguous range of 8 KB heap pages | **`~32 KB`** (**99.9% smaller** than B-Tree!) | Append-only chronological time-series (`obs_time` / `recorded_at` on 10M+ row tables) | `CREATE INDEX idx_brin ON synoptic.observations USING BRIN (obs_time) WITH (pages_per_range = 8);` |
| **Partial Index** | B-Tree that indexes **only rows matching a `WHERE` filter** | `~1 MB` (scales with filtered fraction) | Filtering rare operational states (e.g., `qc_flag != 'VALID'` or `severity = 'RED'`) | `CREATE INDEX idx_suspect ON synoptic.observations (station_id, obs_time) WHERE qc_flag != 'VALID';` |
| **Covering (`INCLUDE`)** | Appends non-key payload columns directly into B-Tree leaf pages | `~35 MB` | Frequent dashboard queries needing `temp_c`, `pressure_hpa` with **`Index Only Scan` (`Heap Fetches: 0`)** | `CREATE INDEX idx_cov ON synoptic.observations (station_id, obs_time) INCLUDE (temp_c, pressure_hpa);` |
| **GiST** *(Spatial)* | Balanced tree of 2D/spherical bounding boxes (R-Tree) | Small | PostGIS spatial proximity (`ST_DWithin`), polygon containment (`ST_Intersects`), range overlaps (`&&`) | `CREATE INDEX idx_geog ON synoptic.stations USING GIST (geog);` |
| **GIN** *(Inverted)* | Maps each internal key/element/trigram to a posting list of row `ctid`s | Moderate | Searching inside `JSONB` sensor payloads (`@>`, `?`, `?&`) or trigram fuzzy text (`pg_trgm`) | `CREATE INDEX idx_gin ON synoptic.observations_part USING GIN (sensor_payload);` |

### 2.1 Why `BRIN` Always Uses `Bitmap Heap Scan + Recheck Cond` (Black Box 3B)
* **Lossy Block Summary vs. Exact Row Pointer:** A B-Tree leaf node stores exact 6-byte `ctid = (block, offset)` pointers to individual rows. A `BRIN` index stores **zero row pointers**—only `[min_value, max_value]` per range of `pages_per_range` (e.g., 8 or 128) physical 8 KB heap blocks.
* **Two-Step Execution:** `Bitmap Index Scan` checks the tiny `BRIN` summary in RAM and marks matching 8 KB block ranges as *"might contain target rows."* Then `Bitmap Heap Scan` reads those sequential 8 KB blocks from disk and runs `Recheck Cond` on each tuple inside the block to discard non-matching rows. Because `BRIN` does not know individual row values, it **cannot enforce `UNIQUE`** and degrades to a full scan if rows are inserted out of chronological order (`correlation` near `0.0`).

---

## 3. PostGIS Geodesy Quick Reference (`GEOMETRY` vs. `GEOGRAPHY`)

| Type | Coordinate System | Distance / Area Units | Distortion Profile | Primary Weather Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **`GEOGRAPHY(Point, 4326)`** | Spherical / Ellipsoidal Earth (WGS 84 `lon, lat`) | **Meters** (and $\text{m}^2$) automatically | **Zero spatial distortion** anywhere on Earth | Global/national station networks, radial storm warnings (`ST_DWithin`), true great-circle distances |
| **`GEOMETRY(Point, 4326)`** | Flat 2D Cartesian plane ($x, y$) | **Degrees** (if SRID 4326) or Meters (if local UTM SRID) | Severe distortion away from the Equator if using 4326 | Fast planar clipping, local projected grids, casting on-the-fly via `geom::geography` |

> **Coordinate Order Rule:** `ST_MakePoint(longitude, latitude)` always takes **`(X, Y)` = `(longitude, latitude)`**!

```sql
-- 📂 TARGET DATABASE: PostgreSQL 'weather_ops_db' (Switch in psql with: \c weather_ops_db)
-- 📜 PREREQUISITE SCRIPT: day3/day3_postgis_5m_benchmark.sql (Table: public.stations)
-- Find all active stations within 40 km (40,000 meters) of an offshore squall line [3.90E, 36.95N]
SELECT
    station_id,
    station_name,
    ROUND((ST_Distance(
        geom::geography,
        ST_SetSRID(ST_MakePoint(3.9000, 36.9500), 4326)::geography
    ) / 1000.0)::numeric, 2) AS distance_km
FROM stations
WHERE is_active = TRUE
  AND ST_DWithin(
      geom::geography,
      ST_SetSRID(ST_MakePoint(3.9000, 36.9500), 4326)::geography,
      40000 -- Radius in meters (40 km)
  )
ORDER BY distance_km ASC;
```

---

## 4. Meteorological Window Functions Quick Reference

```sql
SELECT
    station_id,
    obs_time,
    temp_c,
    pressure_hpa,
    precip_1h_mm,

    -- 1. 3-Hour Barometric Pressure Tendency (Storm Front / Cyclogenesis Detection)
    pressure_hpa - LAG(pressure_hpa, 3) OVER (
        PARTITION BY station_id ORDER BY obs_time
    ) AS delta_p_3h,

    -- 2. Rolling 24-Hour Accumulated Precipitation (True time window via RANGE INTERVAL)
    SUM(precip_1h_mm) OVER (
        PARTITION BY station_id
        ORDER BY obs_time
        RANGE BETWEEN INTERVAL '23 hours' PRECEDING AND CURRENT ROW
    ) AS rolling_24h_rain_mm,

    -- 3. 24-Hour Moving Average Temperature
    ROUND(AVG(temp_c) OVER (
        PARTITION BY station_id
        ORDER BY obs_time
        RANGE BETWEEN INTERVAL '23 hours' PRECEDING AND CURRENT ROW
    ), 1) AS moving_avg_24h_temp_c,

    -- 4. Station Temperature Extremes Rank
    DENSE_RANK() OVER (
        PARTITION BY station_id ORDER BY temp_c DESC NULLS LAST
    ) AS station_heat_rank
FROM synoptic.observations;
```

---

## 5. Idempotent Ingestion (`UPSERT`) & Materialized Views

### Safe Synoptic `UPSERT` (Handles Duplicate or `COR` Corrected Transmissions Without Bloat)
```sql
INSERT INTO synoptic.observations (station_id, obs_time, temp_c, pressure_hpa, precip_1h_mm, qc_flag)
VALUES (60390, '2026-10-06 12:00:00+00', 24.8, 1014.4, 2.5, 'VALID')
ON CONFLICT (station_id, obs_time)
DO UPDATE SET
    temp_c       = EXCLUDED.temp_c,
    pressure_hpa = EXCLUDED.pressure_hpa,
    precip_1h_mm = EXCLUDED.precip_1h_mm,
    qc_flag      = EXCLUDED.qc_flag
WHERE (
    synoptic.observations.temp_c       IS DISTINCT FROM EXCLUDED.temp_c OR
    synoptic.observations.precip_1h_mm IS DISTINCT FROM EXCLUDED.precip_1h_mm OR
    synoptic.observations.qc_flag      IS DISTINCT FROM EXCLUDED.qc_flag
)
RETURNING obs_id, (xmax = 0) AS was_inserted;
```

### Non-Blocking Dashboard Refresh (`MATERIALIZED VIEW CONCURRENTLY`)
```sql
-- Requires a UNIQUE INDEX on the Materialized View:
CREATE UNIQUE INDEX idx_mv_verif_uq ON nwp.mv_daily_model_verification (model_name, station_id, valid_date);

-- Refreshes in background without locking out forecasters reading the view:
REFRESH MATERIALIZED VIEW CONCURRENTLY nwp.mv_daily_model_verification;
```

---

## 6. `JSONB` Operators for Semi-Structured Sensor Telemetry

| Operator | Returns | Example | Description |
| :--- | :--- | :--- | :--- |
| `->` | `JSONB` | `sensor_payload -> 'diagnostics'` | Get JSON sub-object by key |
| `->>` | `TEXT` | `(sensor_payload ->> 'battery_v')::NUMERIC` | Extract value as text (cast for math!) |
| `#>>` | `TEXT` | `sensor_payload #>> '{diagnostics,firmware}'` | Extract nested path as text |
| `@>` | `BOOLEAN` | `sensor_payload @> '{"diagnostics": {"door_open": true}}'` | **Containment check (Uses GIN Index!)** |
| `?` | `BOOLEAN` | `sensor_payload ? 'soil_probes_cm'` | Check if top-level key exists (Uses GIN Index!) |
| `\|\|` | `JSONB` | `sensor_payload \|\| '{"calibrated": true}'::JSONB` | Merge/append keys into JSONB object |
| `-` | `JSONB` | `sensor_payload - 'deprecated_key'` | Remove key from JSONB object |

---

## 6.1 Streaming Replication, Split-Brain Fencing & `synchronous_commit` Matrix (Black Box 3C)

* **Why PostgreSQL Needs `Patroni` + 3-Node `etcd` + `HAProxy`:** PostgreSQL has no built-in Raft election loop. If a Standby promoted itself on a 2-node network glitch, **both nodes would accept writes (`Split-Brain`)**, corrupting WAL timelines. `Patroni` uses a **10s TTL Leader Lock in 3-node `etcd`** + `/dev/watchdog` hardware fencing so an isolated Primary demotes itself *before* the Standby runs `pg_promote()`, while `HAProxy` polls `:8008/primary` to reroute port `5000`.
* **The 4-Pattern `synchronous_commit` Durability & Failover Decision Matrix:**

| Pattern | `synchronous_commit` | When `COMMIT` Returns | Failover Data Loss (`RPO`) | Latency | Weather Use Case |
| :--- | :--- | :--- | :---: | :---: | :--- |
| **1. Async RAM** | `off` | Immediately in `wal_buffers` ($200\text{ms}$ disk flush) | $\le 0.6\text{s}$ of telemetry | $\approx 0.05\text{ ms}$ | $10\text{ Hz}$ ultrasonic wind / lightning raw ingest |
| **2. Local Disk (Async Standby)** | `local` | After Primary NVMe `fsync()` | $> 0$ if Primary disk dies | $\approx 0.3\text{ ms}$ | Routine hourly synoptic ingest & NWP `COPY` |
| **3. Quorum WAL (`Zero Loss`)** | `on` *(with `synchronous_standby_names`)* | After Primary + 1 Sync Standby `fsync()` WAL | **`RPO = 0` (Zero Loss!)** | $+1\text{–}3\text{ ms}$ | **Official WMO `stations` & `weather_alerts`** |
| **4. Zero Read-Lag Standby** | `remote_apply` | After Sync Standby replays WAL in `shared_buffers` | **`RPO = 0` + Zero Read Lag** | $+2\text{–}5\text{ ms}$ | Read-after-write APIs querying Standbys (`:5001`) |

---

## 7. Executive Summary Card: Day 3 Production Directives

```
================================================================================
             POSTGRESQL TIME-SERIES, POSTGIS & JSONB CHEAT SHEET
================================================================================
 1. Range Partitioning  : ALWAYS partition tables exceeding 50M rows by timestamp.
                          Drop old data via ALTER TABLE ... DETACH + DROP TABLE
                          for O(1) instant space reclamation without dead tuples.
 2. BRIN Indexing       : Use BRIN on append-only sequential timestamps.
                          Reduces index RAM footprint by 99.9% compared to B-Trees.
 3. Partial & Covering  : Index only rare flags (WHERE qc_flag != 'VALID') and use
                          INCLUDE (...) to unlock zero-heap-fetch Index-Only Scans.
 4. PostGIS Geodesics   : Always cast to ::geography (or store GEOGRAPHY(Point,4326))
                          when computing real-world meter distances (ST_DWithin).
 5. Window Analytics    : Use LAG() for 3h barometric pressure tendency and
                          RANGE BETWEEN INTERVAL '23 hours' PRECEDING for 24h rain.
 6. Idempotent UPSERT   : Pair ON CONFLICT DO UPDATE with WHERE ... IS DISTINCT FROM
                          to prevent useless MVCC dead tuples on duplicate packets.
================================================================================
```

---

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards](../reference_cards/README.md) | [⏮️ Day 2 Coursebook](../day2/day2_master_coursebook.md) | [📘 Day 3 Coursebook](day3_master_coursebook.md) | [⏭️ Day 4 Coursebook](../day4/day4_master_coursebook.md)

