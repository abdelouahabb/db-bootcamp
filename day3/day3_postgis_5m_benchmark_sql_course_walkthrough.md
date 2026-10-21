> **Navigation:** [Master README](../README.md) | [SQL Basics Guide](../SQL_BASICS_CRUD_GUIDE.md) | [PostGIS vs MongoDB & Partitioning Cheatsheet](../POSTGIS_VS_MONGODB_GEOSPATIAL_AND_PARTITIONING_CHEATSHEET.md) | [Interactive Portal](../bootcamp_portal.html) | [Reference Cards](../reference_cards/README.md) | [Day 2 Coursebook](../day2/day2_master_coursebook.md) | [Day 3 Coursebook](./day3_master_coursebook.md) | [Advanced Weather PG Walkthrough](./day3_weather_advanced_pg_sql_course_walkthrough.md) | [Day 4 Coursebook](../day4/day4_master_coursebook.md)

# Day 3 SQL Course Walkthrough: 5,000,000-Row Partitioned Telemetry, B-Tree vs. BRIN Benchmark & PostGIS Geodesic Proximity (`day3_postgis_5m_benchmark.sql`)

**Source Script:** [`day3_postgis_5m_benchmark.sql`](./day3_postgis_5m_benchmark.sql) (`299 lines`)  
**Companion Curriculum:** [`day3_master_coursebook.md`](./day3_master_coursebook.md) | [`day3_postgres_advanced_cheatsheet.md`](./day3_postgres_advanced_cheatsheet.md) | [`POSTGIS_VS_MONGODB_GEOSPATIAL_AND_PARTITIONING_CHEATSHEET.md`](../POSTGIS_VS_MONGODB_GEOSPATIAL_AND_PARTITIONING_CHEATSHEET.md)  
**Target Database:** `weather_ops_db` (created automatically if not present)  
**Execution Commands:**
- **Linux / macOS (local peer socket):** `psql -d postgres -f day3_postgis_5m_benchmark.sql` *(or from inside `day3/`: `psql -d postgres -f day3_postgis_5m_benchmark.sql`)*
- **Docker / TCP / `postgres` superuser:** `psql -U postgres -f day3_postgis_5m_benchmark.sql`

---

## 1. Architectural Overview & What Is PostGIS?

### 1.1 Why We Benchmark on 5,000,000 Rows

At small table sizes (a few thousand rows), the PostgreSQL query planner can mask severe architectural mistakes because the entire relation fits inside a handful of 8 KB shared-memory buffers. To prove why **Declarative Range Partitioning (`PARTITION BY RANGE`)**, **Block Range Indexing (`BRIN`)**, **Tuple-Tetris Column Alignment**, and **PostGIS Geodesic Spatial Indexing (`GiST`)** are indispensable in operational meteorology, we must test them against a multi-million-row high-frequency telemetry stream.

The [`day3_postgis_5m_benchmark.sql`](./day3_postgis_5m_benchmark.sql) script is a self-contained, zero-dependency benchmark harness that:

1. **Bootstraps `weather_ops_db` Idempotently (`\gexec`):** Dynamically creates and connects to `weather_ops_db`.
2. **Enables Native PostGIS or a Dual-Mode WGS-84 Haversine Geodesic Shim:** Automatically enables the native C-compiled `postgis` extension if installed on the host OS, or falls back transparently to a pure-SQL **WGS-84 Great-Circle Haversine engine** (`ST_MakePoint`, `ST_SetSRID`, `ST_Distance`, `ST_DWithin` over native `point` domains) so every spatial and geodesic benchmark query executes with sub-meter accuracy on any PostgreSQL installation.
3. **Seeds 50 Spatial Automated Weather Stations (`AWS-001` .. `AWS-050`):** Fixes the pseudo-random seed (`SELECT setseed(0.42);`), populates 50 stations across Northern Algeria—pinning exact GPS ground-truth coordinates and elevations for all 8 named Algerian stations (`Algiers Port`, `Boumerdes Coastal`, `Dellys Cape`, `Tizi Ouzou`, `Bejaia Airport`, `Jijel Achouat`, `Oran Marine`, and `Constantine Plateau`)—constructs `geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)` directly from each station's `(longitude, latitude)`, and indexes them with a **Generalized Search Tree (`GiST`)**.
4. **Synthesizes 5,000,000 High-Frequency Telemetry Rows (`2.1 s` cadence):** Populates a byte-aligned parent table (`raw_telemetry_partitioned`) across 4 monthly partitions (`telemetry_y2026m09` through `telemetry_y2026m12`) plus `telemetry_default`.
5. **Executes Live Storage, Pruning, and Geodesic Proximity Benchmarks:** Audits physical partition sizes via `pg_class`/`pg_inherits`, verifies **Partition Pruning** via `EXPLAIN (COSTS OFF)`, benchmarks **B-Tree (`27 MB`) vs. BRIN (`24 kB`)** on 1.27 million October rows, and executes meter-accurate **PostGIS `ST_DWithin` storm-proximity and spatial-temporal join queries**.

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                     day3_postgis_5m_benchmark.sql EXECUTION PIPELINE                     │
├──────────────────────┬───────────────────────────────────────────────────────────────────┤
│ Section 0 (L1-17)    │ Idempotent DB Bootstrap (\gexec), \c weather_ops_db, UTC Session  │
├──────────────────────┼───────────────────────────────────────────────────────────────────┤
│ Section 1 (L18-70)   │ Dual-Mode Spatial Engine: Native PostGIS OR WGS-84 Haversine Shim │
├──────────────────────┼───────────────────────────────────────────────────────────────────┤
│ Section 2 (L71-142)  │ 50 Spatial Weather Stations (AWS-001..AWS-050) + GiST Index       │
├──────────────────────┼───────────────────────────────────────────────────────────────────┤
│ Section 3 & 4        │ Tuple-Tetris Aligned Parent Table (raw_telemetry_partitioned)     │
│ (L143-177)           │  ├── telemetry_y2026m09 [2026-09-01, 2026-10-01) (1,234,285 rows) │
│                      │  ├── telemetry_y2026m10 [2026-10-01, 2026-11-01) (1,275,429 rows) │
│                      │  ├── telemetry_y2026m11 [2026-11-01, 2026-12-01) (1,234,285 rows) │
│                      │  ├── telemetry_y2026m12 [2026-12-01, 2027-01-01) (1,256,001 rows) │
│                      │  └── telemetry_default  (DEFAULT Catch-All Partition: 0 rows)     │
├──────────────────────┼───────────────────────────────────────────────────────────────────┤
│ Section 5 & 6        │ 5,000,000-Row Telemetry Generator (generate_series, 2.1s step)    │
│ (L178-206)           │ Master BRIN Index (pages_per_range = 64) + ANALYZE                │
├──────────────────────┼───────────────────────────────────────────────────────────────────┤
│ Section 7 (L207-230) │ Catalog Forensics (pg_class + pg_inherits) & EXPLAIN Pruning      │
├──────────────────────┼───────────────────────────────────────────────────────────────────┤
│ Section 8 (L231-246) │ Lab 1 Benchmark: B-Tree (27 MB) vs. BRIN (24 kB) on Oct Partition │
├──────────────────────┼───────────────────────────────────────────────────────────────────┤
│ Section 9 (L247-299) │ Lab 2 Benchmark: Geodesic ST_DWithin (40 km Squall Line & 50 km   │
│                      │ Spatial-Temporal CTE Join with October Partition)                 │
└──────────────────────┴───────────────────────────────────────────────────────────────────┘
```

### 1.2 What Is PostGIS & Why Do Weather Databases Need It?

**PostGIS** (`CREATE EXTENSION postgis;`) is the industry-standard spatial extension that turns PostgreSQL into a full Open Geospatial Consortium (**OGC**) geographic information system powered by three C/C++ computational geometry engines: **`GEOS`** (topological predicates: `ST_Covers`, `ST_Intersects`, `ST_Buffer`), **`PROJ`** (coordinate reference system transformations across `8,000+` map projections), and **`GDAL`** (raster processing).

1. **Why Plain `latitude` / `longitude` Float Columns + B-Tree Bounding Boxes Fail in Meteorology:**
   - Because meridians of longitude converge toward the poles ($\Delta x \propto \cos(\phi)$), $1^\circ$ of latitude is $\approx 111.1\text{ km}$ everywhere, whereas $1^\circ$ of longitude shrinks from $111.3\text{ km}$ at the Equator to **$\approx 89.3\text{ km}$** along the Algerian Mediterranean coast ($\phi \approx 36.8^\circ\text{N}$) and $0\text{ km}$ at the poles.
   - A naive SQL filter `WHERE latitude BETWEEN ... AND longitude BETWEEN ...` searches a **distorted rectangle** (whose corners are $\sqrt{2} \approx 1.414\times$ farther away than the radius!), cannot test whether a weather station falls inside a 24-vertex radar storm polygon, and cannot use a single 1D B-Tree to prune 2D/3D space efficiently.
2. **`GEOMETRY(Point, 4326)` vs. `GEOGRAPHY(Point, 4326)`:**
   - **`GEOMETRY(Point, 4326)`:** Treats longitude and latitude as flat 2D Cartesian $(X, Y)$ coordinates. `ST_Distance` returns **decimal degrees** (meaningless for physical distance!).
   - **`GEOGRAPHY(Point, 4326)` (or `geom::geography`):** Models coordinates on the curved **WGS-84 Earth ellipsoid** ($a = 6,378,137\text{ m}$, $f = 1/298.257223563$). `ST_Distance` and `ST_DWithin` compute true geodesic distances in **meters** (`40000` = `40 km`).
3. **The #1 Coordinate Order Rule — `(X, Y) = (Longitude, Latitude)`:**
   - In PostGIS (`ST_MakePoint(lon, lat)`)—and in MongoDB GeoJSON (`coordinates: [lon, lat]`)—**Longitude ($X$) ALWAYS comes first, and Latitude ($Y$) ALWAYS comes second!** Passing `(36.7538, 3.0588)` instead of `(3.0588, 36.7538)` teleports Algiers (`36.75° N, 3.05° E`) into the Indian Ocean off Somalia (`3.05° N, 36.75° E`)!

---

## 2. Section 0: Idempotent Database Bootstrap & Session Configuration (Lines 1–17)

### 2.1 Exact SQL Code (`Lines 1–17`)

```sql
-- ============================================================================
-- DAY 3 BOOTCAMP: 5,000,000-ROW PARTITIONED TELEMETRY SEED, B-TREE VS BRIN
-- BENCHMARK & POSTGIS GEODESIC PROXIMITY QUERIES
-- File: day3_postgis_5m_benchmark.sql
-- Usage: psql -d postgres -f day3_postgis_5m_benchmark.sql
--    or: psql -U postgres -f day3_postgis_5m_benchmark.sql
-- ============================================================================

-- Create dedicated benchmark database if running standalone (or run inside existing DB)
SELECT 'CREATE DATABASE weather_ops_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'weather_ops_db')\gexec

\c weather_ops_db

SET timezone = 'UTC';
SET datestyle = 'iso, ymd';
```

### 2.2 Line-by-Line Architectural Breakdown

- **Why `CREATE DATABASE` Cannot Use `IF NOT EXISTS` Directly (`Lines 10–11`):**
  - Unlike `CREATE TABLE IF NOT EXISTS` or `CREATE EXTENSION IF NOT EXISTS`, PostgreSQL's grammar has **no native `CREATE DATABASE IF NOT EXISTS` syntax**. Furthermore, `CREATE DATABASE` cannot be executed inside a transaction block or a PL/pgSQL `DO $$ ... $$` block (`ERROR: CREATE DATABASE cannot be executed from a function or multi-command string`).
- **How the `SELECT ... WHERE NOT EXISTS (...)\gexec` Idiom Works (`Lines 10–11`):**
  1. The query inspects the cluster-wide system catalog `pg_database` for an existing database named `'weather_ops_db'`.
  2. Notice `SELECT FROM pg_database WHERE ...` (`Line 11`): PostgreSQL allows an empty `SELECT` list inside `EXISTS (...)` because `EXISTS` only checks whether at least one tuple qualifies, avoiding unnecessary column projection.
  3. If `weather_ops_db` does **not** exist, the outer `SELECT` returns a single 1-row, 1-column result containing the text string `'CREATE DATABASE weather_ops_db'`. If `weather_ops_db` **already** exists, the outer `SELECT` returns `0 rows`.
  4. The `psql` meta-command **`\gexec`** sends the preceding query to the server, reads every returned cell of every returned row, and immediately executes that text string back against the server as a top-level SQL command!
  5. Consequently, on the first run, `\gexec` executes `CREATE DATABASE weather_ops_db;`. On subsequent runs, `0 rows` are returned and `\gexec` is a clean no-op.
- **`\c weather_ops_db` (`Line 13`):**
  - `psql` meta-command that closes the current database connection and opens a fresh backend session connected directly to `weather_ops_db`.
- **`SET timezone = 'UTC';` & `SET datestyle = 'iso, ymd';` (`Lines 15–16`):**
  - Locks the new `weather_ops_db` session to Coordinated Universal Time (`UTC`) and ISO-8601 `YYYY-MM-DD` date formatting so all partition boundary literals (`+00`) and synthetic timestamp calculations (`TIMESTAMP WITH TIME ZONE '2026-09-01 00:00:00+00' + ...`) evaluate deterministically regardless of the host machine's local timezone.

---

## 3. Section 1: Dual-Mode PostGIS Spatial Engine & WGS-84 Haversine Geodesic Fallback (Lines 18–70)

### 3.1 Exact SQL Code (`Lines 18–70`)

```sql
-- ============================================================================
-- 1. ENABLE POSTGIS SPATIAL EXTENSION (OR WGS-84 GEODESIC SHIM IF BARE HOST)
-- ============================================================================
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'postgis') THEN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geometry' AND typtype = 'd') THEN
            DROP DOMAIN geometry CASCADE;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geography' AND typtype = 'd') THEN
            DROP DOMAIN geography CASCADE;
        END IF;
        CREATE EXTENSION IF NOT EXISTS postgis;
        RAISE NOTICE 'Native PostGIS extension enabled!';
    ELSE
        RAISE NOTICE 'PostGIS OS package not installed on host — enabling built-in WGS-84 Haversine geodesic fallback so all 5M-row Partitioning, BRIN, and Proximity queries execute cleanly!';
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geometry') THEN
            CREATE DOMAIN geometry AS point;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geography') THEN
            CREATE DOMAIN geography AS point;
        END IF;
        EXECUTE $fn$
            CREATE OR REPLACE FUNCTION postgis_full_version() RETURNS text AS $body$
                SELECT 'WGS-84 Geodesic Fallback Mode (Use Docker postgis/postgis:16-3.4 for native GEOS/PROJ PostGIS)'::text;
            $body$ LANGUAGE sql IMMUTABLE;

            CREATE OR REPLACE FUNCTION ST_MakePoint(lon double precision, lat double precision) RETURNS point AS $body$
                SELECT point(lon, lat);
            $body$ LANGUAGE sql IMMUTABLE;

            CREATE OR REPLACE FUNCTION ST_SetSRID(pt point, srid int) RETURNS point AS $body$
                SELECT pt;
            $body$ LANGUAGE sql IMMUTABLE;

            CREATE OR REPLACE FUNCTION ST_Distance(p1 point, p2 point) RETURNS double precision AS $body$
                SELECT 2.0 * 6371008.8 * asin(sqrt(
                    power(sin(radians((p2[1] - p1[1]) / 2.0)), 2) +
                    cos(radians(p1[1])) * cos(radians(p2[1])) * power(sin(radians((p2[0] - p1[0]) / 2.0)), 2)
                ));
            $body$ LANGUAGE sql IMMUTABLE;

            CREATE OR REPLACE FUNCTION ST_DWithin(p1 point, p2 point, dist_m double precision) RETURNS boolean AS $body$
                SELECT ST_Distance(p1, p2) <= dist_m;
            $body$ LANGUAGE sql IMMUTABLE;
        $fn$;
    END IF;
END
$$;

-- Explicit verification of PostGIS spatial engine (or geodesic fallback)
SELECT postgis_full_version();
```

### 3.2 Deep-Dive Architectural & Mathematical Breakdown

#### 3.2.1 Native PostGIS Path (`Lines 23–31`)
- Queries `pg_available_extensions` for `'postgis'`. When the OS package (`postgresql-16-postgis-3`) or Docker image (`postgis/postgis:16-3.4`) is present, it first checks `pg_type` (`WHERE typname = 'geometry' AND typtype = 'd'`) to drop any fallback domain created during an earlier bare-host run, and then executes `CREATE EXTENSION IF NOT EXISTS postgis;`, registering the C-compiled `GEOMETRY` and `GEOGRAPHY` types, `GEOS`/`PROJ` libraries, and GiST spatial operator classes.

#### 3.2.2 Bare-Host Geodesic Fallback Path (`Lines 32–64`)
- If an engineer runs this script on a bare Linux/macOS/Windows PostgreSQL host before installing the PostGIS OS package, the `ELSE` branch constructs an API-compatible **WGS-84 Geodesic Fallback Engine** using PostgreSQL's native 16-byte geometric `point` type (`(x, y)` = `(lon, lat)`):
  - **`CREATE DOMAIN geometry AS point;` & `CREATE DOMAIN geography AS point;` (`Lines 34–39`):**
    - Checks `pg_type` (`WHERE typname = 'geometry'` / `'geography'`) for idempotency and creates SQL domains aliasing `geometry` and `geography` to PostgreSQL's built-in `point` data type.
    - Because both `geometry` and `geography` are domains over `point`, expressions in downstream queries such as `geom::geography` and `CREATE INDEX ... USING GIST (geom)` work identically without syntax changes!
  - **Nested Dollar-Quoting (`DO $$ ... EXECUTE $fn$ ... $body$ ... $body$ ... $fn$; $$`, `Lines 21, 40–63`):**
    - Demonstrates three distinct levels of PostgreSQL dollar-quoting (`$$` for the outer `DO` block, `$fn$` for the dynamic `EXECUTE` string, and `$body$` for each `CREATE OR REPLACE FUNCTION` body) so single quotes and nested function definitions require zero escaping.
  - **`IMMUTABLE` Volatility Marking (`Lines 43, 47, 51, 58, 62`):**
    - Every function is marked `LANGUAGE sql IMMUTABLE`. In PostgreSQL's query optimizer, `IMMUTABLE` guarantees that for fixed arguments, the function always returns the exact same output with zero side effects. This allows the planner to **inline** the SQL functions and **constant-fold** expressions like `ST_SetSRID(ST_MakePoint(3.9000, 36.9500), 4326)::geography` once at query planning time rather than re-evaluating them 50 times per scan!

#### 3.2.3 Mathematical Derivation of the WGS-84 Haversine Great-Circle Formula (`Lines 53–58`)

Look closely at `ST_Distance(p1 point, p2 point)` on `Lines 53–58`:

```sql
CREATE OR REPLACE FUNCTION ST_Distance(p1 point, p2 point) RETURNS double precision AS $body$
    SELECT 2.0 * 6371008.8 * asin(sqrt(
        power(sin(radians((p2[1] - p1[1]) / 2.0)), 2) +
        cos(radians(p1[1])) * cos(radians(p2[1])) * power(sin(radians((p2[0] - p1[0]) / 2.0)), 2)
    ));
$body$ LANGUAGE sql IMMUTABLE;
```

- **Coordinate Indexing (`p[0]` vs. `p[1]`):**
  - Because `ST_MakePoint(lon, lat)` constructs `point(lon, lat)`, PostgreSQL's 0-indexed `point` subscript operator maps:
    - `p[0]` = **Longitude ($\lambda$)** in decimal degrees ($^\circ\text{E}$).
    - `p[1]` = **Latitude ($\phi$)** in decimal degrees ($^\circ\text{N}$).
- **The Haversine Formula:**
  - Given two points $P_1 = (\lambda_1, \phi_1)$ and $P_2 = (\lambda_2, \phi_2)$ on a sphere of mean radius $R$, the central angle $\Delta\sigma$ (in radians) between them is governed by the spherical law of haversines ($\text{hav}(\theta) = \sin^2(\theta/2)$):
    $$a = \sin^2\left(\frac{\Delta\phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta\lambda}{2}\right)$$
    $$\Delta\sigma = 2 \arcsin\left(\sqrt{a}\right)$$
    $$d = R \cdot \Delta\sigma = 2 R \arcsin\left(\sqrt{\sin^2\left(\frac{\Delta\phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta\lambda}{2}\right)}\right)$$
  - where:
    - $\Delta\phi = \text{radians}(\phi_2 - \phi_1) = \text{radians}(\text{p2}[1] - \text{p1}[1])$ is the latitude difference in radians.
    - $\Delta\lambda = \text{radians}(\lambda_2 - \lambda_1) = \text{radians}(\text{p2}[0] - \text{p1}[0])$ is the longitude difference in radians.
    - **$R = 6,371,008.8\text{ meters}$** is the **IUGG / WGS-84 arithmetic mean radius of the Earth**:
      $$R_{\text{mean}} = \frac{2a + b}{3} = \frac{2(6,378,137.0\text{ m}) + 6,356,752.3142\text{ m}}{3} \approx 6,371,008.8\text{ meters}$$
  - Why Haversine instead of the Spherical Law of Cosines ($\arccos(\sin\phi_1\sin\phi_2 + \cos\phi_1\cos\phi_2\cos\Delta\lambda)$)? For closely spaced weather stations ($1\text{ km}$ to $50\text{ km}$ apart), $\cos(\Delta\sigma)$ is extremely close to $1.0000000$, causing severe floating-point catastrophic cancellation in $\arccos$. Using $\arcsin(\sqrt{\sin^2(\dots)})$ preserves full 64-bit IEEE-754 `DOUBLE PRECISION` accuracy down to sub-meter distances!
- **`ST_DWithin(p1 point, p2 point, dist_m double precision)` (`Lines 60–62`):**
  - Evaluates `SELECT ST_Distance(p1, p2) <= dist_m;`, returning `TRUE` whenever the geodesic distance in meters between `p1` and `p2` is within the specified radius `dist_m`.
- **`SELECT postgis_full_version();` (`Line 69`):**
  - Prints either the full native PostGIS build string (`POSTGIS="3.4.x" GEOS="3.12.x" PROJ="9.x"...`) or the fallback banner so the engineer immediately knows which spatial execution mode is active.

---

## 4. Section 2: Spatial Weather Stations Master Registry & GiST Indexing (Lines 71–142)

### 4.1 Exact SQL Code (`Lines 71–142`)

```sql
-- ============================================================================
-- 2. CREATE SPATIAL WEATHER STATIONS MASTER REGISTRY TABLE
-- ============================================================================
DROP TABLE IF EXISTS stations CASCADE;
CREATE TABLE stations (
    station_id   VARCHAR(10) PRIMARY KEY,
    station_name VARCHAR(64) NOT NULL,
    latitude     DOUBLE PRECISION NOT NULL,
    longitude    DOUBLE PRECISION NOT NULL,
    elevation_m  REAL NOT NULL,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        ALTER TABLE stations ADD COLUMN geom GEOMETRY(Point, 4326);
    ELSE
        ALTER TABLE stations ADD COLUMN geom geometry;
    END IF;
END
$$;

-- Fix PRNG seed so all 50 station coordinates are 100% deterministic across machines
SELECT setseed(0.42);

-- Seed 50 Meteorological Stations across Northern Algeria
INSERT INTO stations (station_id, station_name, latitude, longitude, elevation_m, is_active)
SELECT 
    'AWS-' || LPAD(g::TEXT, 3, '0'),
    CASE g
        WHEN 1 THEN 'Algiers Port Marine'
        WHEN 2 THEN 'Boumerdes Coastal Point'
        WHEN 3 THEN 'Dellys Cape Lighthouse'
        WHEN 4 THEN 'Tizi Ouzou Valley'
        WHEN 5 THEN 'Bejaia Gulf Airport'
        WHEN 6 THEN 'Jijel Achouat Ridge'
        WHEN 7 THEN 'Oran Marine Terminal'
        WHEN 8 THEN 'Constantine Plateau'
        ELSE 'AWS Regional Station ' || LPAD(g::TEXT, 3, '0')
    END,
    ROUND((35.5 + (random() * 2.0))::numeric, 4),
    ROUND((2.0 + (random() * 5.0))::numeric, 4),
    ROUND((10.0 + (random() * 1200.0))::numeric, 1),
    TRUE
FROM generate_series(1, 50) AS g;

-- Pin precise ground-truth coordinates & elevations for all 8 named Algerian stations
UPDATE stations SET latitude = 36.7538, longitude =  3.0588, elevation_m =  12.0 WHERE station_id = 'AWS-001'; -- Algiers Port
UPDATE stations SET latitude = 36.7664, longitude =  3.4772, elevation_m =  18.0 WHERE station_id = 'AWS-002'; -- Boumerdes Coastal
UPDATE stations SET latitude = 36.9172, longitude =  3.9130, elevation_m =  85.0 WHERE station_id = 'AWS-003'; -- Dellys Cape
UPDATE stations SET latitude = 36.7118, longitude =  4.0459, elevation_m = 189.0 WHERE station_id = 'AWS-004'; -- Tizi Ouzou
UPDATE stations SET latitude = 36.7559, longitude =  5.0699, elevation_m =   6.0 WHERE station_id = 'AWS-005'; -- Bejaia Airport
UPDATE stations SET latitude = 36.7950, longitude =  5.8736, elevation_m =  11.0 WHERE station_id = 'AWS-006'; -- Jijel Achouat
UPDATE stations SET latitude = 35.6971, longitude = -0.6308, elevation_m =  22.0 WHERE station_id = 'AWS-007'; -- Oran Marine
UPDATE stations SET latitude = 36.2760, longitude =  6.6200, elevation_m = 694.0 WHERE station_id = 'AWS-008'; -- Constantine Plateau

-- Construct WGS-84 spatial point geometry (X = longitude, Y = latitude) from exact station coordinates
UPDATE stations
SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326);

-- Create Spatial Index on Station Geometries (GiST: Generalized Search Tree)
CREATE INDEX idx_stations_gist_geom ON stations USING GIST (geom);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        CREATE INDEX idx_stations_gist_geog ON stations USING GIST ((geom::geography));
    END IF;
END
$$;
```

### 4.2 Line-by-Line Architectural Breakdown

- **Master Station Registry (`CREATE TABLE stations`, `Lines 74–92`):**
  - Defines the dimension table for 50 Automated Weather Stations (`AWS-001` through `AWS-050`).
  - The `DO $$ ... $$` block (`Lines 84–92`) checks `pg_extension WHERE extname = 'postgis'` (which tracks extensions actively enabled in the current database) and adds `geom GEOMETRY(Point, 4326)` when native PostGIS is active, or `geom geometry` (domain over `point`) when running in fallback mode.
- **Deterministic PRNG Seeding (`SELECT setseed(0.42);`, `Line 95`):**
  - Fixes PostgreSQL's session pseudo-random number generator (`random()`) to `0.42` before generating the 50 stations so that regional stations `AWS-009`..`AWS-050` receive the exact same coordinates on every laptop and server.
- **50-Station Set-Based Generator (`Lines 98–116`):**
  - Uses `FROM generate_series(1, 50) AS g` (`Line 116`) to generate 50 station rows in a single set-based query:
    - `'AWS-' || LPAD(g::TEXT, 3, '0')` (`Line 100`): Formats `1..50` as zero-padded station IDs `'AWS-001'` through `'AWS-050'`.
    - `CASE g WHEN 1 THEN ... ELSE ... END` (`Lines 101–111`): Names the first 8 primary stations after major Northern Algerian coastal and Tell Atlas meteorological sites and labels `9..50` as `'AWS Regional Station 009'` .. `'050'`.
    - `latitude`: Generated in $[35.5000^\circ\text{N}, 37.5000^\circ\text{N}]$ (`Line 112`), spanning the Tell Atlas and Algerian Mediterranean coastline.
    - `longitude`: Generated in $[2.0000^\circ\text{E}, 7.0000^\circ\text{E}]$ (`Line 113`), spanning central and eastern Northern Algeria.
    - `elevation_m`: Generated in $[10.0\text{ m}, 1210.0\text{ m}]$ above mean sea level (`Line 114`).
- **Pinning Ground-Truth Coordinates & Elevations for All 8 Named Algerian Stations (`Lines 119–126`):**
  - Pins exact real-world WGS-84 coordinates and elevations for `AWS-001` through `AWS-008`:

| Station ID | Station Name | Elevation (`m`) | Latitude ($\phi$) | Longitude ($\lambda$) | Distance to Dellys Offshore (`36.95N, 3.90E`) | Distance to Boumerdes (`36.7664N, 3.4772E`) |
| :--- | :--- | :---: | :--- | :--- | :--- | :--- |
| **`AWS-001`** | `Algiers Port Marine` | `12.0 m` | `36.7538° N` | `3.0588° E` | `77.96 km` (Outside 40 km) | **`37.30 km`** (Inside 50 km) |
| **`AWS-002`** | `Boumerdes Coastal Point` | `18.0 m` | `36.7664° N` | `3.4772° E` | `42.80 km` (Outside 40 km) | **`0.00 km`** (Origin Center) |
| **`AWS-003`** | `Dellys Cape Lighthouse` | `85.0 m` | `36.9172° N` | `3.9130° E` | **`3.83 km`** (Inside 40 km) | **`42.25 km`** (Inside 50 km) |
| **`AWS-004`** | `Tizi Ouzou Valley` | `189.0 m` | `36.7118° N` | `4.0459° E` | **`29.50 km`** (Inside 40 km) | `51.04 km` (Outside 50 km) |
| **`AWS-005`** | `Bejaia Gulf Airport` | `6.0 m` | `36.7559° N` | `5.0699° E` | `106.31 km` (Outside 40 km) | `141.88 km` (Outside 50 km) |
| **`AWS-006`** | `Jijel Achouat Ridge` | `11.0 m` | `36.7950° N` | `5.8736° E` | `176.40 km` (Outside 40 km) | `213.44 km` (Outside 50 km) |
| **`AWS-007`** | `Oran Marine Terminal` | `22.0 m` | `35.6971° N` | `-0.6308° W` | `429.09 km` (Outside 40 km) | `387.13 km` (Outside 50 km) |
| **`AWS-008`** | `Constantine Plateau` | `694.0 m` | `36.2760° N` | `6.6200° E` | `254.07 km` (Outside 40 km) | `286.07 km` (Outside 50 km) |

- **Constructing `geom` Directly from `(longitude, latitude)` (`Lines 129–130`):**
  - `UPDATE stations SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326);`
  - **Why We Construct `geom` After Populating `(latitude, longitude)`:** If you call `random()` inside `latitude`, `longitude`, *and* a second time inside `ST_MakePoint(random(), random())`, each `random()` invocation generates a different number—causing `geom` to disagree with the `latitude` and `longitude` columns! Constructing `geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)` directly from the table's `longitude` ($X$) and `latitude` ($Y$) columns guarantees **100% geometric consistency** across all 50 stations and demonstrates how any legacy relational table with `latitude`/`longitude` columns is upgraded to PostGIS in a single SQL statement.
- **Spatial Indexing (`idx_stations_gist_geom` & Functional `idx_stations_gist_geog`, `Lines 133–141`):**
  - **`CREATE INDEX idx_stations_gist_geom ON stations USING GIST (geom);` (`Line 133`):** Builds an R-Tree-on-GiST index over the `geom` column (supporting 2D bounding-box operators `&&` and geometry `ST_DWithin`). Note that PostgreSQL's native `point` type also has a built-in `point_ops` GiST operator class, so `USING GIST (geom)` succeeds in both native PostGIS mode and fallback mode!
  - **`CREATE INDEX idx_stations_gist_geog ON stations USING GIST ((geom::geography));` (`Line 138`):**
    - Why is this **functional expression index** on `(geom::geography)` so important?
    - In Section 9 (`Lines 264–268` and `Lines 281–285`), the proximity queries store `geom` as `GEOMETRY(Point, 4326)` but filter using spheroidal geodesic meters via `WHERE ST_DWithin(geom::geography, target::geography, 40000)`.
    - In PostgreSQL, an index on raw `geom` (`GEOMETRY`) **cannot** be used when the column is wrapped inside a cast expression `geom::geography`! By creating a functional GiST index explicitly on the cast expression `((geom::geography))` (note the mandatory double parentheses around an expression in `CREATE INDEX`), the PostGIS planner can use the 3D geocentric GiST index directly whenever `geom::geography` appears in `ST_DWithin` or `<->` KNN queries.

---

## 5. Sections 3, 4, 5 & 6: Declarative Range Partitioning, 5,000,000-Row Telemetry Synthesis & BRIN Propagation (Lines 143–206)

### 5.1 Section 3: Declarative Partitioned Parent Table & Tuple-Tetris Alignment (`Lines 143–159`)

#### 5.1.1 Exact SQL Code (`Lines 143–159`)

```sql
-- ============================================================================
-- 3. CREATE DECLARATIVE PARTITIONED MASTER TABLE (ALIGNED COLUMNS)
-- ============================================================================
DROP TABLE IF EXISTS raw_telemetry_partitioned CASCADE;
CREATE TABLE raw_telemetry_partitioned (
    -- 8-Byte Types First (Offset 0-8)
    recorded_at    TIMESTAMPTZ NOT NULL,
    -- 4-Byte / Variable Types Second (Offset 8-28)
    station_id     VARCHAR(10) NOT NULL,
    temperature    REAL,
    pressure       REAL,
    wind_speed     REAL,
    rain_accum_1m  REAL,
    -- 2-Byte Types
    wind_direction SMALLINT,
    CONSTRAINT fk_station FOREIGN KEY (station_id) REFERENCES stations(station_id)
) PARTITION BY RANGE (recorded_at);
```

#### 5.1.2 Course Concept 1: What Is Declarative Table Partitioning & Why Do Weather Databases Need It?

When an Automated Weather Station (AWS) network ingests millions of observations per month into a **single monolithic table**, four severe architectural bottlenecks emerge as the table grows past 50–100 million rows:
1. **B-Tree Index Bloat & RAM Cache Thrashing:** A B-Tree index on a monolithic table grows to multiple gigabytes. Once internal and leaf B-Tree pages exceed `shared_buffers` RAM, every index insert or lookup triggers random disk I/O.
2. **Full-Table Sequential Scan Penalties:** Analytical queries that inspect a single storm date (`WHERE recorded_at >= '2026-10-15' AND recorded_at < '2026-10-16'`) risk scanning gigabytes of historical data from other months if an index is not selective enough.
3. **Catastrophic `DELETE` & `VACUUM` Bloat During Data Retention:** When you expire old telemetry using `DELETE FROM raw_telemetry WHERE recorded_at < '2026-10-01';`, PostgreSQL does **not** free disk space! Under MVCC (Day 2), `DELETE` merely visits 1.23 million rows, stamps their `t_xmax` transaction ID, writes 80+ MB of Write-Ahead Log (`pg_wal`), and leaves 80 MB of dead tuples behind that `autovacuum` must clean up.
4. **All-or-Nothing Maintenance:** Running `VACUUM`, `REINDEX`, or `CLUSTER` on a monolithic table processes immutable 6-month-old history alongside today's active data.

**How `PARTITION BY RANGE (recorded_at)` (`Line 159`) Solves All Four Bottlenecks:**

```
                     ┌───────────────────────────────────────────────────────────┐
                     │          VIRTUAL PARENT TABLE (relkind = 'p')             │
  INSERT / SELECT ──►│               raw_telemetry_partitioned                   │
                     │     • Stores ZERO rows on disk (0-byte routing shell)     │
                     │     • Partition Key: PARTITION BY RANGE (recorded_at)     │
                     └──────┬─────────────┬─────────────┬─────────────┬──────────┘
                            │             │             │             │
         ┌──────────────────┴──┐   ┌──────┴──────┐   ┌──┴──────────┐  └──────────────────┐
         ▼                     ▼   ▼             ▼   ▼             ▼                     ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│telemetry_y2026m09│ │telemetry_y2026m10│ │telemetry_y2026m11│ │telemetry_y2026m12│ │telemetry_default│
│ (relkind = 'r') │ │ (relkind = 'r') │ │ (relkind = 'r') │ │ (relkind = 'r') │ │ (relkind = 'r') │
│  [Sept 2026)    │ │   [Oct 2026)    │ │   [Nov 2026)    │ │   [Dec 2026)    │ │   Out-of-Range  │
│ 1,234,285 rows  │ │ 1,275,429 rows  │ │ 1,234,285 rows  │ │ 1,256,001 rows  │ │     0 rows      │
│   80 MB Heap    │ │   82 MB Heap    │ │   80 MB Heap    │ │   81 MB Heap    │ │   0 bytes Heap  │
└─────────────────┘ └─────────────────┘ └─────────────────┘ └─────────────────┘ └─────────────────┘
```

- **Virtual Parent Table (`relkind = 'p'`):** Appending `PARTITION BY RANGE (recorded_at)` tells PostgreSQL that `raw_telemetry_partitioned` is a **partitioned parent table**. In `pg_catalog.pg_class`, it has `relkind = 'p'` and **allocates zero 8 KB heap pages of its own (`0 bytes` on disk)**.
- **Transparent Tuple Routing on `INSERT`:** Applications still write to `INSERT INTO raw_telemetry_partitioned ...`. PostgreSQL's internal Tuple Routing engine inspects each row's `recorded_at` timestamp and routes it into the matching monthly child table (`relkind = 'r'`).
- **Transparent Partition Pruning on `SELECT`:** Applications still query `SELECT ... FROM raw_telemetry_partitioned WHERE recorded_at >= ...`. The query planner automatically prunes away every monthly child table whose date range does not overlap the `WHERE` filter.
- **Why `RANGE` Instead of `LIST` or `HASH`?**
  | PostgreSQL Partition Strategy | SQL Clause | How It Routes Rows | When to Use in Weather Engineering |
  | :--- | :--- | :--- | :--- |
  | **1. Range Partitioning** | `PARTITION BY RANGE (recorded_at)` | Continuous non-overlapping intervals $[A, B)$ | **Chronological time-series telemetry** (`recorded_at`, `obs_time`, `valid_time`). Enables time-window pruning and instant monthly `DROP TABLE` / `DETACH PARTITION` retention. |
  | **2. List Partitioning** | `PARTITION BY LIST (climate_zone)` | Explicit discrete values (`IN ('Mediterranean', 'Highland')`) | Isolating discrete regional networks or WMO bulletin types with distinct storage policies. |
  | **3. Hash Partitioning** | `PARTITION BY HASH (station_id)` | Modulo hash `MODULUS N REMAINDER R` | Evenly spreading a massive static lookup table across $N$ disks when no time range exists. |

#### 5.1.3 Course Concept 2: Primary Keys & Foreign Keys on Partitioned Tables (`Line 158`)

- **Partitioned Foreign Key (`CONSTRAINT fk_station FOREIGN KEY (station_id) REFERENCES stations(station_id)`, `Line 158`):**
  - PostgreSQL 12+ supports declaring `FOREIGN KEY` constraints directly on the partitioned parent table referencing a standard primary key (`stations.station_id`). Every child partition automatically inherits and enforces this referential integrity check.
- **Why Partitioned `PRIMARY KEY`s Must Include the Partition Key — And Why Section 3 Omits `PRIMARY KEY` Here:**
  - As established in [`day3_weather_advanced_pg.sql`](./day3_weather_advanced_pg.sql) (`PRIMARY KEY (obs_time, station_id)`), PostgreSQL does **not** maintain a single global B-Tree across all partitions (because a global index would ruin instant $O(1)$ `DETACH PARTITION`). Therefore, any `PRIMARY KEY` or `UNIQUE` constraint on a partitioned table **must include `recorded_at`**.
  - Why does `raw_telemetry_partitioned` intentionally omit `PRIMARY KEY (recorded_at, station_id)` in this benchmark script?
    1. **Pure Heap-Append Bulk Ingestion Speed:** Without a B-Tree primary key to update on every row, Section 5 streams 5,000,000 rows into the 4 monthly heaps in **~5–8 seconds**.
    2. **Clean Unindexed Baseline for Section 8:** Omitting an automatic B-Tree on `recorded_at` allows Section 8 (`Lines 231–245`) to build `idx_oct_btree` (`27 MB`) and `idx_oct_brin` (`24 kB`) side-by-side from scratch under `\timing on` and measure their exact creation speed and byte size.

#### 5.1.4 Course Concept 3: Tuple-Tetris Memory Alignment Inside Each Child Partition (`Lines 148–157`)

On a 64-bit CPU architecture, PostgreSQL aligns every column inside a heap tuple according to its `pg_type.typalign` requirement:
- **`d` (`double` = 8-byte alignment):** `TIMESTAMPTZ`, `BIGINT`, `DOUBLE PRECISION` must start at a byte offset divisible by `8` (`0, 8, 16, 24, ...`).
- **`i` (`int` = 4-byte alignment):** `REAL` (`float4`), `INTEGER` (`int4`), `DATE` must start at a byte offset divisible by `4` (`0, 4, 8, 12, ...`).
- **`s` (`short` = 2-byte alignment):** `SMALLINT` (`int2`) must start at a byte offset divisible by `2` (`0, 2, 4, 6, ...`).
- **`c` (`char` = 1-byte alignment):** Short `VARCHAR(10)` strings use a 1-byte *short varlena* header (`1 byte` length prefix + `7 bytes` for `'AWS-001'` = `8 bytes` total) and require no alignment padding (`typalign = 'c'`).

Look at how `raw_telemetry_partitioned` orders its columns (`8B -> 4B/var -> 2B`) to achieve **zero wasted internal padding bytes**:

```
Byte Offset:  0         8         16    20    24    28    32  34   (MAXALIGN to 40B)
              ┌─────────┬─────────┬─────┬─────┬─────┬─────┬───┬──────┐
Tuple Layout: │recorded_│station_ │temp │press│wind_│rain_│dir│pad   │
              │at (8B)  │id (8B*) │(4B) │(4B) │(4B) │(4B) │2B │(6B)  │
              └─────────┴─────────┴─────┴─────┴─────┴─────┴───┴──────┘
              *Short varlena: 1-byte header + 7-byte string 'AWS-001' = 8 bytes!
```

1. **Offset `0..7` (`8 bytes`):** `recorded_at TIMESTAMPTZ` (`typalign = 'd'`, divisible by 8 — `0 bytes` padding).
2. **Offset `8..15` (`8 bytes`):** `station_id VARCHAR(10)` storing `'AWS-001'` (`1-byte` short varlena header + `7` ASCII bytes = `8 bytes` total, `typalign = 'c'`). Because `8 + 8 = 16` is already a multiple of 4, the next `REAL` column starts immediately at Offset `16` with `0 bytes` padding!
3. **Offset `16..31` (`16 bytes`):** Four consecutive 4-byte IEEE-754 single-precision floats (`temperature REAL`, `pressure REAL`, `wind_speed REAL`, `rain_accum_1m REAL`, each `4 bytes`, `typalign = 'i'`).
4. **Offset `32..33` (`2 bytes`):** `wind_direction SMALLINT` (`2 bytes` storing $0^\circ\text{..}359^\circ$, `typalign = 's'`).
- If we had interleaved `SMALLINT` before `TIMESTAMPTZ` and `REAL`, PostgreSQL would have injected up to `8–12 bytes` of dead alignment air per row—which across **5,000,000 rows** would waste **40–60 MB** of disk and `shared_buffers` RAM!

---

### 5.2 Section 4: Explicit Monthly Child Partitions, Half-Open $[A, B)$ Bounds & The `DEFAULT` Partition (`Lines 161–176`)

#### 5.2.1 Exact SQL Code (`Lines 161–176`)

```sql
-- ============================================================================
-- 4. CREATE EXPLICIT MONTHLY CHILD PARTITIONS
-- ============================================================================
CREATE TABLE telemetry_y2026m09 PARTITION OF raw_telemetry_partitioned
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE telemetry_y2026m10 PARTITION OF raw_telemetry_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');

CREATE TABLE telemetry_y2026m11 PARTITION OF raw_telemetry_partitioned
    FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');

CREATE TABLE telemetry_y2026m12 PARTITION OF raw_telemetry_partitioned
    FOR VALUES FROM ('2026-12-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

CREATE TABLE telemetry_default PARTITION OF raw_telemetry_partitioned DEFAULT;
```

#### 5.2.2 Course Concept 1: How `PARTITION OF` Works Under the Hood (`Lines 164–176`)

When PostgreSQL executes `CREATE TABLE telemetry_y2026m09 PARTITION OF raw_telemetry_partitioned FOR VALUES FROM (...) TO (...);`:
1. **Physical Storage Allocation:** Unlike the virtual parent table (`relkind = 'p'`), `telemetry_y2026m09` is created as a standard physical heap table (`relkind = 'r'`) with its own 8 KB data files on disk (`main`, `_fsm`, `_vm`).
2. **Schema & Constraint Inheritance:** You do **not** repeat the column list `(recorded_at, station_id, ...)` inside `CREATE TABLE telemetry_y2026m09`. The child partition automatically inherits every column, data type, `NOT NULL` rule, `DEFAULT` value, and `FOREIGN KEY` from `raw_telemetry_partitioned`.
3. **Internal Partition Constraint Check:** PostgreSQL registers the partition bound in `pg_catalog.pg_class.relpartbound`. Every row inserted either through the parent `raw_telemetry_partitioned` or directly into `telemetry_y2026m09` is guaranteed to satisfy:
   $$\text{'2026-09-01 00:00:00+00'} \le \text{recorded\_at} < \text{'2026-10-01 00:00:00+00'}$$

#### 5.2.3 Course Concept 2: Why `FOR VALUES FROM (A) TO (B)` Uses Half-Open Intervals $[A, B)$

A critical rule to emphasize when teaching PostgreSQL range partitioning is that **`FOR VALUES FROM (A) TO (B)` is ALWAYS a half-open mathematical interval $[A, B)$**:
- **Lower bound `FROM (A)` is INCLUSIVE (`>= A`).**
- **Upper bound `TO (B)` is STRICTLY EXCLUSIVE (`< B`).**

Why did the PostgreSQL core team design `FROM (A) TO (B)` as $[A, B)$ instead of a closed interval $[A, B]$ like `BETWEEN`?
1. **Zero Microsecond Boundary Gaps:** PostgreSQL `TIMESTAMPTZ` has **1-microsecond ($10^{-6}\text{ s}$) resolution**. If someone tried to define September's upper bound as `'2026-09-30 23:59:59+00'`, then any observation arriving during the last second of September (e.g., `'2026-09-30 23:59:59.450000+00'`) would fall into a 1-second gap between September and October!
2. **Zero Midnight Overlap Collisions:** Because the upper bound `TO ('2026-10-01 00:00:00+00')` on `telemetry_y2026m09` is **exclusive (`<`)** and the lower bound `FROM ('2026-10-01 00:00:00+00')` on `telemetry_y2026m10` is **inclusive (`>=`)**, the two partitions touch seamlessly with zero gap and zero overlap. An observation recorded at exact midnight `'2026-10-01 00:00:00.000000+00'` routes deterministically to `telemetry_y2026m10`.

| Child Partition Name | SQL DDL Bound Clause | Exact Mathematical Interval $[A, B)$ | Sample Boundary Timestamp Routing | Rows Routed in Section 5 |
| :--- | :--- | :---: | :--- | :---: |
| **`telemetry_y2026m09`** | `FROM ('2026-09-01 00:00:00+00')`<br/>`TO ('2026-10-01 00:00:00+00')` | $[\text{2026-09-01 00:00:00},\; \text{2026-10-01 00:00:00})$ | `'2026-09-01 00:00:00.000000+00'` $\rightarrow$ **Included**<br/>`'2026-09-30 23:59:59.999999+00'` $\rightarrow$ **Included**<br/>`'2026-10-01 00:00:00.000000+00'` $\rightarrow$ *Excluded (goes to m10)* | `1,234,285` *(30 days)* |
| **`telemetry_y2026m10`** | `FROM ('2026-10-01 00:00:00+00')`<br/>`TO ('2026-11-01 00:00:00+00')` | $[\text{2026-10-01 00:00:00},\; \text{2026-11-01 00:00:00})$ | `'2026-10-01 00:00:00.000000+00'` $\rightarrow$ **Included**<br/>`'2026-10-31 23:59:59.999999+00'` $\rightarrow$ **Included** | `1,275,429` *(31 days)* |
| **`telemetry_y2026m11`** | `FROM ('2026-11-01 00:00:00+00')`<br/>`TO ('2026-12-01 00:00:00+00')` | $[\text{2026-11-01 00:00:00},\; \text{2026-12-01 00:00:00})$ | `'2026-11-01 00:00:00.000000+00'` $\rightarrow$ **Included**<br/>`'2026-11-30 23:59:59.999999+00'` $\rightarrow$ **Included** | `1,234,285` *(30 days)* |
| **`telemetry_y2026m12`** | `FROM ('2026-12-01 00:00:00+00')`<br/>`TO ('2027-01-01 00:00:00+00')` | $[\text{2026-12-01 00:00:00},\; \text{2027-01-01 00:00:00})$ | `'2026-12-01 00:00:00.000000+00'` $\rightarrow$ **Included**<br/>`'2026-12-31 12:40:00.000000+00'` $\rightarrow$ **Included** | `1,256,001` *(30.53 days)* |
| **`telemetry_default`** | `DEFAULT` | $(-\infty, \text{2026-09-01}) \cup [\text{2027-01-01}, +\infty)$ | Any timestamp $< \text{2026-09-01}$ or $\ge \text{2027-01-01}$ | `0` *(Safety net)* |

#### 5.2.4 Course Concept 3: Why We Create `telemetry_default` (`Line 176`) & The Production Locking Gotcha

- **Why `DEFAULT` Is Essential for High-Frequency Telemetry:**
  - Suppose a remote Saharan station suffers a GPS RTC battery reset and transmits a row stamped `'1970-01-01 00:00:00+00'`, or a midnight batch crosses into `'2027-01-01 00:00:05+00'` before the DBA created the January 2027 partition.
  - **Without `telemetry_default`:** PostgreSQL aborts the entire multi-row `INSERT` or `COPY` transaction with `ERROR: no partition of relation "raw_telemetry_partitioned" found for row (SQLSTATE 23514)`, dropping the whole telemetry batch!
  - **With `CREATE TABLE telemetry_default PARTITION OF raw_telemetry_partitioned DEFAULT;` (`Line 176`):** Any row that does not match an explicit monthly partition is safely routed into `telemetry_default` so ingestion never halts.
- **The Production `DEFAULT` Partition Gotcha (Why `telemetry_default` Must Stay at `0 bytes`):**
  - When you later create a new monthly partition (e.g., `telemetry_y2027m01` for January 2027), PostgreSQL must verify that `telemetry_default` does **not** already contain any rows with `recorded_at` inside January 2027.
  - To check this, PostgreSQL acquires an **`ACCESS EXCLUSIVE` lock** and scans `telemetry_default`! If `telemetry_default` is empty (`0 bytes`, as we verify in Section 7A), adding a new partition takes `< 1 millisecond`. If a DBA forgot to pre-create partitions for 3 months and allowed 4 million rows to pile up inside `telemetry_default`, creating a new partition will lock the table while scanning those 4 million rows!
  - **Production Rule:** Always pre-create monthly partitions ahead of time (or automate via `pg_partman`) and monitor `pg_relation_size('telemetry_default') = 0`.

#### 5.2.5 Course Concept 4: Zero-Bloat Partition Retention (`DETACH PARTITION CONCURRENTLY` vs. `DELETE`)

How do you archive or expire old partitions in production (such as September 2026 `telemetry_y2026m09`) without causing MVCC bloat or locking live `INSERT`s?
1. **Step 1 — Non-Blocking Detach:**
   ```sql
   ALTER TABLE raw_telemetry_partitioned
       DETACH PARTITION telemetry_y2026m09 CONCURRENTLY;
   ```
   - `DETACH PARTITION CONCURRENTLY` unlinks `telemetry_y2026m09` from the parent routing catalog using only a weak `SHARE UPDATE EXCLUSIVE` lock (never blocking concurrent `SELECT` or `INSERT` traffic on active months!).
2. **Step 2 — Cold Lakehouse Export & Instant Drop:**
   - Once detached, `telemetry_y2026m09` is an independent standalone table. You can stream it to compressed Apache Parquet on S3/MinIO (Day 5) and then run `DROP TABLE telemetry_y2026m09;`, reclaiming **80 MB of disk space in `< 5 ms`** with **zero dead tuples** and **zero `autovacuum` work**.

---

### 5.3 Section 5: The 5,000,000-Row Synthetic Telemetry Generator (`Lines 178–194`)

#### 5.3.1 Exact SQL Code (`Lines 178–194`)

```sql
-- ============================================================================
-- 5. INGEST 5,000,000 SYNTHETIC OBSERVATIONS ACROSS SEPT-DEC 2026
-- ============================================================================
SELECT setseed(0.42);

INSERT INTO raw_telemetry_partitioned (
    recorded_at, station_id, temperature, pressure, wind_speed, wind_direction, rain_accum_1m
)
SELECT 
    TIMESTAMP WITH TIME ZONE '2026-09-01 00:00:00+00' + (g * INTERVAL '2.1 seconds'),
    'AWS-' || LPAD((1 + (random() * 49)::INT)::TEXT, 3, '0'),
    ROUND((14.0 + (sin(g / 5000.0) * 12.0) + (random() * 3.0))::numeric, 2)::REAL,
    ROUND((1013.25 + (cos(g / 8000.0) * 8.0) + (random() * 1.5))::numeric, 2)::REAL,
    ROUND((random() * 22.0)::numeric, 2)::REAL,
    (random() * 359)::SMALLINT,
    CASE WHEN random() < 0.05 THEN ROUND((random() * 4.5)::numeric, 2)::REAL ELSE 0.0 END
FROM generate_series(1, 5000000) AS g;
```

#### 5.3.2 Mathematical & Physical Breakdown of the 5,000,000-Row Synthesizer

- **Deterministic Seed (`SELECT setseed(0.42);`, `Line 181`):**
  - Resets PostgreSQL's PRNG stream before generating the 5,000,000 rows so that the station distribution and October mean temperatures (`oct_mean_temp`) in Query 9B are 100% reproducible.
- **Set-Based Series Generation (`FROM generate_series(1, 5000000) AS g`, `Line 194`):**
  - Streams integers $g \in [1, 5,000,000]$ in C memory and routes each synthesized tuple directly into its target monthly child heap.
- **Chronological Timestamp Cadence (`Line 187`):**
  $$T(g) = \text{'2026-09-01 00:00:00+00'} + g \times 2.1\text{ seconds}$$
  - Why exactly **`2.1 seconds`** per step?
    - Total elapsed duration across $5,000,000$ rows:
      $$5,000,000 \times 2.1\text{ seconds} = 10,500,000\text{ seconds} = \frac{10,500,000}{86,400\text{ s/day}} = 121.5278\text{ days}$$
    - The 4 calendar months from `2026-09-01` to `2027-01-01` contain:
      $$\text{Sept } (30) + \text{Oct } (31) + \text{Nov } (30) + \text{Dec } (31) = 122.0\text{ days}$$
    - Thus, a `2.1 second` step spans **121.53 days** (`2026-09-01 00:00:02.1+00` through `2026-12-31 12:40:00+00`), distributing all 5,000,000 rows evenly across all 4 monthly partitions (`telemetry_y2026m09` through `telemetry_y2026m12`) with **0 rows spilling into `telemetry_default`**!
    - Specifically:
      - **30-day months (`Sept`, `Nov`):** $\frac{30 \times 86,400}{2.1} = \mathbf{1,234,285\text{ rows}}$ each.
      - **31-day month (`Oct`):** $\frac{31 \times 86,400}{2.1} = \mathbf{1,275,429\text{ rows}}$.
      - **Remaining rows in `Dec` (`30.53 days`):** $5,000,000 - (1,234,285 \times 2 + 1,275,429) = \mathbf{1,256,001\text{ rows}}$.
- **Station ID Assignment (`Line 188`):**
  - `'AWS-' || LPAD((1 + (random() * 49)::INT)::TEXT, 3, '0')`: Distributes observations across `'AWS-001'` through `'AWS-050'` ($\approx 100,000$ observations per station).
- **Harmonic Temperature Wave (`Line 189`):**
  $$T_c(g) = 14.0 + 12.0 \sin\left(\frac{g}{5000.0}\right) + \text{Uniform}(0, 3.0) \in [2.0^\circ\text{C},\; 29.0^\circ\text{C}]$$
  - Combines a base $14.0^\circ\text{C}$ mean with a sinusoidal diurnal/synoptic wave ($\pm 12.0^\circ\text{C}$ amplitude) plus $[0, 3^\circ\text{C})$ micro-scale turbulence.
- **Harmonic Barometric Pressure Wave (`Line 190`):**
  $$P_{\text{hPa}}(g) = 1013.25 + 8.0 \cos\left(\frac{g}{8000.0}\right) + \text{Uniform}(0, 1.5) \in [1005.25\text{ hPa},\; 1022.75\text{ hPa}]$$
  - Oscillates around standard sea-level pressure ($1013.25\text{ hPa}$) to simulate passing synoptic high- and low-pressure systems.
- **Wind Speed, Wind Direction & Intermittent Precipitation (`Lines 191–193`):**
  - `wind_speed`: Uniformly distributed in $[0.00, 22.00]\text{ m/s}$.
  - `wind_direction`: Azimuth in $[0^\circ, 359^\circ]$ cast to 2-byte `SMALLINT`.
  - `rain_accum_1m`: `CASE WHEN random() < 0.05 ...` models realistic precipitation intermittency (**95% dry minutes (`0.0 mm`)**, **5% wet minutes (`0.00–4.50 mm/min`)**).

---

### 5.4 Section 6: Master BRIN Index Propagation & Optimizer Statistics (`Lines 196–205`)

#### 5.4.1 Exact SQL Code (`Lines 196–205`)

```sql
-- ============================================================================
-- 6. ATTACH BRIN INDEX TO MASTER PARTITIONED TABLE (PROPAGATES TO CHILDREN)
-- ============================================================================
CREATE INDEX idx_telemetry_brin_time 
    ON raw_telemetry_partitioned 
    USING BRIN (recorded_at) 
    WITH (pages_per_range = 64);

ANALYZE stations;
ANALYZE raw_telemetry_partitioned;
```

#### 5.4.2 Course Concept 1: How Partitioned Index Propagation Works (`Lines 199–202`)

When you run `CREATE INDEX idx_telemetry_brin_time ON raw_telemetry_partitioned ...` on a **partitioned parent table**, PostgreSQL performs a two-tier catalog operation:
1. **Virtual Parent Index (`relkind = 'I'`, `0 bytes` on disk):** Creates a partitioned index entry named `idx_telemetry_brin_time` in `pg_class` with `relkind = 'I'` (capital `I` = partitioned index template). Like the parent table (`relkind = 'p'`), the parent index stores zero bytes on disk.
2. **Automatic Child Index Cascade (`relkind = 'i'`, `24 kB` each):** PostgreSQL automatically walks `pg_inherits` and builds **5 real physical BRIN indexes (`relkind = 'i'`)**—one on each child partition—and guarantees that any future monthly partition created via `CREATE TABLE telemetry_y2027m01 PARTITION OF raw_telemetry_partitioned` automatically receives its own local BRIN index:

| Catalog Object Name | `pg_class.relkind` | Attached Table | Physical Size on Disk |
| :--- | :---: | :--- | :---: |
| **`idx_telemetry_brin_time`** | `'I'` *(Virtual Partitioned Index)* | `raw_telemetry_partitioned` *(Parent)* | `0 bytes` |
| **`telemetry_y2026m09_recorded_at_idx`** | `'i'` *(Physical Child BRIN Index)* | `telemetry_y2026m09` | `24 kB` (`3 pages`) |
| **`telemetry_y2026m10_recorded_at_idx`** | `'i'` *(Physical Child BRIN Index)* | `telemetry_y2026m10` | `24 kB` (`3 pages`) |
| **`telemetry_y2026m11_recorded_at_idx`** | `'i'` *(Physical Child BRIN Index)* | `telemetry_y2026m11` | `24 kB` (`3 pages`) |
| **`telemetry_y2026m12_recorded_at_idx`** | `'i'` *(Physical Child BRIN Index)* | `telemetry_y2026m12` | `24 kB` (`3 pages`) |
| **`telemetry_default_recorded_at_idx`** | `'i'` *(Physical Child BRIN Index)* | `telemetry_default` | `24 kB` (`3 pages`) |

#### 5.4.3 Course Concept 2: How BRIN (`WITH (pages_per_range = 64)`) Summarizes an 82 MB Partition Into 24 kB

Why is a **Block Range Index (`BRIN`)** so much smaller than a **B-Tree** on chronological weather data?
- **B-Tree (`USING BTREE`) is a Row-Level Index:** It stores the exact `recorded_at` value and a 6-byte row pointer (`ctid = (block_number, tuple_offset)`) for **every single row** (`1,275,429 entries` in October = `27 MB`).
- **BRIN (`USING BRIN`) is a Lossy Block-Range Summary Index:** It stores **zero row pointers (`ctid`s)**. Instead, it groups every `pages_per_range = 64` consecutive 8 KB heap pages ($64 \times 8\text{ KB} = 512\text{ KB}$ of physical disk blocks, holding $\approx 7,800$ rows) into a single summary entry containing only two timestamps: **`[min(recorded_at), max(recorded_at)]`**:

```
October Partition Heap (telemetry_y2026m10: 82 MB = ~10,480 Pages of 8 KB):
┌───────────────────────────┬───────────────────────────┬─────────┬───────────────────────────┐
│   Heap Pages 0 .. 63      │   Heap Pages 64 .. 127    │   ...   │ Heap Pages 10432 .. 10479 │
│  (512 KB, ~7,800 rows)    │  (512 KB, ~7,800 rows)    │         │  (384 KB, ~5,900 rows)    │
└─────────────┬─────────────┴─────────────┬─────────────┴─────────┴─────────────┬─────────────┘
              │                           │                                     │
              ▼                           ▼                                     ▼
BRIN Index (telemetry_y2026m10_recorded_at_idx: ONLY 24 kB = 3 Pages of 8 KB!):
┌───────────────────────────┬───────────────────────────┬─────────┬───────────────────────────┐
│ Range #0 Summary:         │ Range #1 Summary:         │   ...   │ Range #163 Summary:       │
│ min: 2026-10-01 00:00:01  │ min: 2026-10-01 04:33:01  │         │ min: 2026-10-31 20:15:00  │
│ max: 2026-10-01 04:32:59  │ max: 2026-10-01 09:05:59  │         │ max: 2026-10-31 23:59:59  │
└───────────────────────────┴───────────────────────────┴─────────┴───────────────────────────┘
```

- Because $10,480\text{ pages} / 64\text{ pages per range} = \mathbf{164\text{ block ranges}}$, storing 164 `[min, max]` timestamp pairs requires only **3 pages (`24 kB`)** on disk (Page 0: BRIN metapage, Page 1: Reverse Range Map `revmap`, Page 2: regular summary tuples)!

#### 5.4.4 Course Concept 3: Why `ANALYZE` Is Mandatory After Bulk Partition Ingestion (`Lines 204–205`)

- Bulk `INSERT INTO ... SELECT` populates heap pages rapidly, but PostgreSQL's background `autovacuum` daemon runs asynchronously and may not immediately update catalog statistics before the next query in a script executes.
- Running `ANALYZE stations;` and `ANALYZE raw_telemetry_partitioned;` (`Lines 204–205`) immediately samples both the parent table and all 5 child partitions, updating:
  1. `pg_class.reltuples` and `pg_class.relpages` (read directly by our Section 7A catalog query).
  2. `pg_stats.correlation` on `recorded_at` (`correlation = 1.0`, proving to the query planner that rows are stored in strict chronological order on disk so BRIN scans are ultra-cheap).

---

## 6. Sections 7, 8 & 9: Catalog Forensics, B-Tree vs. BRIN Size Audit & Geodesic `ST_DWithin` Joins (Lines 207–299)

### 6.1 Section 7A: System Catalog Forensics (`pg_class` + `pg_inherits`) (`Lines 207–219`)

#### 6.1.1 Exact SQL Code (`Lines 207–219`)

```sql
-- ============================================================================
-- 7. VERIFY PARTITION ROW DISTRIBUTION & PRUNING
-- ============================================================================
SELECT 
    c.relname AS partition_name,
    pg_size_pretty(pg_relation_size(c.oid)) AS heap_size,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
    c.reltuples::BIGINT AS estimated_rows
FROM pg_class c
JOIN pg_inherits i ON i.inhrelid = c.oid
JOIN pg_class parent ON parent.oid = i.inhparent
WHERE parent.relname = 'raw_telemetry_partitioned'
ORDER BY c.relname;
```

#### 6.1.2 Course Concept 1: How PostgreSQL Tracks Partition Hierarchies & Measures Disk Sizes

1. **Joining `pg_class` and `pg_inherits` (`Lines 215–218`):**
   - If you run `SELECT pg_relation_size('raw_telemetry_partitioned');` on the parent table directly, PostgreSQL returns **`0 bytes`** because the parent (`relkind = 'p'`) has no physical storage fork!
   - To inspect the physical child partitions, we join `pg_catalog.pg_class` (aliased as `parent` for the parent table and `c` for each child partition) through `pg_catalog.pg_inherits i`:
     ```
     pg_class (parent)                    pg_inherits (i)                     pg_class (c)
     ┌───────────────────────────────┐    ┌───────────────────────────┐       ┌──────────────────────┐
     │ oid: 16402                    │◄───│ inhparent: 16402          │       │ oid: 16405           │
     │ relname:                      │    │ inhrelid:  16405          │──────►│ relname:             │
     │  'raw_telemetry_partitioned'  │    │ inhseqno:  1              │       │  'telemetry_y2026m09'│
     │ relkind: 'p' (0 bytes)        │    └───────────────────────────┘       │ relkind: 'r' (80 MB) │
     └───────────────────────────────┘                                        └──────────────────────┘
     ```
2. **Understanding PostgreSQL's Disk Size Functions (`Lines 212–213`):**
   | PostgreSQL Size Function | What Physical Files It Counts on Disk | Value on `telemetry_y2026m10` | Value on `telemetry_default` |
   | :--- | :--- | :---: | :---: |
   | **`pg_relation_size(c.oid)`** | **Only the main 8 KB data heap (`main` fork)** of the table (excludes indexes, `_fsm`, `_vm`, and TOAST). | `82 MB` | `0 bytes` *(0 rows)* |
   | **`pg_indexes_size(c.oid)`** | All physical indexes attached to that table (`telemetry_y2026m10_recorded_at_idx`). | `24 kB` *(BRIN)* | `24 kB` *(3-page BRIN header)* |
   | **`pg_total_relation_size(c.oid)`** | **Everything:** Main heap + Free Space Map (`_fsm`) + Visibility Map (`_vm`) + TOAST + all indexes. | `82 MB` | `24 kB` |

#### 6.1.3 Expected Terminal Output & Forensic Interpretation (`Lines 210–219`)

```text
   partition_name   | heap_size | total_size | estimated_rows 
--------------------+-----------+------------+----------------
 telemetry_default  | 0 bytes   | 24 kB      |              0
 telemetry_y2026m09 | 80 MB     | 80 MB      |        1234285
 telemetry_y2026m10 | 82 MB     | 82 MB      |        1275429
 telemetry_y2026m11 | 80 MB     | 80 MB      |        1234285
 telemetry_y2026m12 | 81 MB     | 81 MB      |        1256001
(5 rows)
```

- **Three Key Insights to Point Out in Class:**
  1. **Why `telemetry_default` has `heap_size = 0 bytes` but `total_size = 24 kB`:** Because `0 rows` fell outside `[2026-09-01, 2027-01-01)`, the data heap is `0 bytes`. The `24 kB` in `total_size` is the empty 3-page BRIN index (`telemetry_default_recorded_at_idx`) propagated from the parent table in Section 6!
  2. **Why `total_size` equals `heap_size` (`80 MB` vs. `80 MB`) on the 4 monthly partitions:** Because the inherited BRIN index is only `24 kB` (`0.03%` of `80 MB`), indexing adds virtually zero storage overhead.
  3. **Exact Row Sum Verification:** $1,234,285 + 1,275,429 + 1,234,285 + 1,256,001 + 0 = \mathbf{5,000,000\text{ rows}}$.

---

### 6.2 Section 7B: Partition Pruning & BRIN Two-Stage Filtering via `EXPLAIN (COSTS OFF)` (`Lines 221–229`)

#### 6.2.1 Exact SQL Code (`Lines 221–229`)

```sql
EXPLAIN (COSTS OFF)
SELECT 
    station_id, 
    ROUND(AVG(temperature)::numeric, 2) AS avg_temp,
    MAX(wind_speed) AS max_gust
FROM raw_telemetry_partitioned
WHERE recorded_at >= '2026-10-15 00:00:00+00' 
  AND recorded_at <  '2026-10-16 00:00:00+00'
GROUP BY station_id;
```

#### 6.2.2 Course Concept 1: How Partition Pruning + BRIN Indexing Work Together in Two Stages

When a forecaster queries a single 24-hour storm window (`2026-10-15`) against the 5,000,000-row `raw_telemetry_partitioned` parent table (`323 MB` total heap), PostgreSQL eliminates **99.18% of disk I/O** in two distinct stages:

```
STAGE 1: Compile-Time Partition Pruning (Catalog Bound Check)
  Query Predicate: recorded_at >= '2026-10-15' AND recorded_at < '2026-10-16'
  ├── [PRUNED] telemetry_y2026m09 (1.23M rows, 80 MB) ──► Never opened!
  ├── [ACTIVE] telemetry_y2026m10 (1.27M rows, 82 MB) ──► Passes to Stage 2
  ├── [PRUNED] telemetry_y2026m11 (1.23M rows, 80 MB) ──► Never opened!
  ├── [PRUNED] telemetry_y2026m12 (1.25M rows, 81 MB) ──► Never opened!
  └── [PRUNED] telemetry_default  (0 rows, 0 bytes)   ──► Never opened!
                                      │
                                      ▼
STAGE 2: Intra-Partition BRIN Block-Range Skipping (Inside telemetry_y2026m10)
  1. Bitmap Index Scan on telemetry_y2026m10_recorded_at_idx (24 kB in RAM):
     • Inspects 164 block-range [min, max] summaries.
     • Skips ~158 block ranges (Oct 1..14 and Oct 16..31).
     • Flags ONLY the ~6 block ranges (~3 MB) overlapping Oct 15 in a bitmap.
  2. Bitmap Heap Scan on telemetry_y2026m10 (Recheck Cond):
     • Reads only those ~6 sequential block ranges and filters exact Oct 15 rows (~41,143 rows).
```

- **Why Does a `BRIN` Plan Always Show `Bitmap Index Scan` $\rightarrow$ `Bitmap Heap Scan` with `Recheck Cond`?**
  - Because BRIN stores `[min, max]` per 64-page block range rather than per-row `ctid`s, the boundary block range where October 14 ends and October 15 begins contains rows from **both** late October 14 and early October 15.
  - Therefore, `Bitmap Index Scan` flags the 64-page range as a candidate, and `Bitmap Heap Scan` applies **`Recheck Cond`** to inspect each tuple inside those candidate pages and discard any row from late October 14 or early October 16.

#### 6.2.3 Expected Terminal Output (`Lines 221–229`)

```text
                                                             QUERY PLAN                                                             
------------------------------------------------------------------------------------------------------------------------------------
 HashAggregate
   Group Key: raw_telemetry_partitioned.station_id
   ->  Bitmap Heap Scan on telemetry_y2026m10 raw_telemetry_partitioned
         Recheck Cond: ((recorded_at >= '2026-10-15 00:00:00+00'::timestamp with time zone) AND (recorded_at < '2026-10-16 00:00:00+00'::timestamp with time zone))
         ->  Bitmap Index Scan on telemetry_y2026m10_recorded_at_idx
               Index Cond: ((recorded_at >= '2026-10-15 00:00:00+00'::timestamp with time zone) AND (recorded_at < '2026-10-16 00:00:00+00'::timestamp with time zone))
```

---

### 6.3 Section 8: Lab 1 Benchmark — B-Tree vs. BRIN Size & Build Speed on 1.27 Million Rows (`Lines 231–245`)

#### 6.3.1 Exact SQL Code (`Lines 231–245`)

```sql
-- ============================================================================
-- 8. LAB 1 BENCHMARK: B-TREE VS. BRIN ON OCTOBER PARTITION (1.27M ROWS)
-- ============================================================================
\timing on
CREATE INDEX idx_oct_btree ON telemetry_y2026m10 (recorded_at);
CREATE INDEX idx_oct_brin  ON telemetry_y2026m10 USING BRIN (recorded_at) WITH (pages_per_range = 64);
\timing off

SELECT 
    relname AS index_name,
    pg_size_pretty(pg_relation_size(c.oid)) AS index_size,
    pg_relation_size(c.oid) AS exact_bytes
FROM pg_class c
WHERE relname IN ('idx_oct_btree', 'idx_oct_brin')
ORDER BY pg_relation_size(c.oid) DESC;
```

#### 6.3.2 Course Concept 1: Side-by-Side Physical Comparison (`B-Tree` vs. `BRIN` on 1,275,429 Rows)

| Engineering Dimension | `idx_oct_btree` (`USING BTREE (recorded_at)`) | `idx_oct_brin` (`USING BRIN (recorded_at) WITH (pages_per_range = 64)`) |
| :--- | :--- | :--- |
| **Index Entries Stored** | **1,275,429 leaf tuples** (`8B timestamp` + `6B ctid` + header per row) | **164 block-range summaries** (`[min_time, max_time]` per 64 heap pages) |
| **Physical Size (`exact_bytes`)** | **`28,672,000 bytes` (`27 MB` = 3,500 pages of 8 KB)** | **`24,576 bytes` (`24 kB` = 3 pages of 8 KB)** |
| **Size Across All 4 Months (5M Rows)** | **`~110 MB`** of RAM/disk | **`96 kB`** total (**`1,166.67x` smaller — `99.914%` savings!**) |
| **Build Mechanism & Speed** | Full scan + external/in-memory sort + tree construction (`~185 ms`) | Single sequential pass computing running `min`/`max` per 64 pages (`~59 ms`, **3x–10x faster**) |
| **Write Amplification on `INSERT`** | Every `INSERT` dirty-writes B-Tree leaf pages and generates WAL records | Near-zero (only updates range `max` when crossing a 64-page boundary) |
| **When to Choose Each** | Need `UNIQUE` constraint, exact single-row point lookup, or `ORDER BY` without sorting | Append-only chronological timestamp column (`correlation > 0.95`) scanned by time range |

#### 6.3.3 Expected Terminal Output (`Lines 234–245`)

```text
Timing is on.
CREATE INDEX
Time: 185.158 ms
CREATE INDEX
Time: 59.354 ms
Timing is off.

  index_name   | index_size | exact_bytes 
---------------+------------+-------------
 idx_oct_btree | 27 MB      |    28672000
 idx_oct_brin  | 24 kB      |       24576
(2 rows)
```

---

### 6.4 Section 9: Lab 2 Benchmark — PostGIS Geodesic Proximity (`ST_DWithin`) & Spatial-Temporal CTE Join (Lines 247–299)

#### 6.4.1 Query 9A: 40 km Radial Search Around an Offshore Squall Line (`Lines 247–269`)

##### 6.4.1.1 Exact SQL Code (`Lines 247–269`)

```sql
-- ============================================================================
-- 9. LAB 2 BENCHMARK: POSTGIS GEODESIC PROXIMITY (ST_DWithin) & TEMPORAL JOIN
-- ============================================================================

-- 9A. Stations within 40 km of an advancing squall line offshore Dellys Cape (36.95N, 3.90E)
SELECT 
    station_id,
    station_name,
    elevation_m,
    latitude,
    longitude,
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
ORDER BY distance_km ASC, station_id ASC;
```

##### 6.4.1.2 Deep-Dive Architectural Breakdown

- **Meteorological Scenario:** Marine weather radar detects an advancing convective squall line centered offshore north-northwest of Dellys Cape at **`36.9500° N, 3.9000° E`**. Forecasters need an immediate list of all active Automated Weather Stations within a **40 km (`40,000 meter`) geodesic radius**, ordered from closest to farthest.
- **Coordinate Construction (`ST_SetSRID(ST_MakePoint(3.9000, 36.9500), 4326)::geography`, `Lines 260, 266`):**
  - Passes longitude `3.9000` ($X$) first and latitude `36.9500` ($Y$) second into `ST_MakePoint`, tags with SRID `4326`, and casts to `::geography` so distances are evaluated in true WGS-84 meters.
- **Why Filter with `ST_DWithin(..., 40000)` Instead of `WHERE ST_Distance(...) <= 40000` (`Lines 264–268`):**
  - **Crucial PostGIS Optimization Rule:** `WHERE ST_Distance(a, b) <= 40000` is a mathematical function comparison that **cannot use a GiST spatial index**—it forces PostgreSQL to execute a full Sequential Scan and run expensive spheroidal trigonometry on every station row in the table!
  - Conversely, **`ST_DWithin(geom::geography, target::geography, 40000)`** is an **index-aware spatial predicate**. Under the hood, `ST_DWithin` expands the target point by a `40,000 m` bounding box, uses the GiST index (`idx_stations_gist_geog`) to prune out all stations outside that bounding box, and only computes the exact geodesic distance on the few candidate rows inside the box.
- **Converting Meters to Kilometers (`Lines 258–261`):**
  - `ST_Distance(geom::geography, ...)` returns the exact geodesic distance in **meters**. Dividing by `1000.0`, casting to `::numeric`, and calling `ROUND(..., 2)` converts the output into kilometers (`distance_km`) with `0.01 km` (`10 meter`) precision.

##### 6.4.1.3 Expected Terminal Output (`Lines 252–269`)

*(Showing our deterministic ground-truth stations `AWS-003` Dellys Cape at `3.83 km` and `AWS-004` Tizi Ouzou at `29.50 km`, plus the two `setseed(0.42)` regional stations `AWS-027` at `9.90 km` and `AWS-047` at `31.96 km` falling inside the 40 km circle)*:

```text
 station_id |       station_name       | elevation_m | latitude | longitude | distance_km 
------------+--------------------------+-------------+----------+-----------+-------------
 AWS-003    | Dellys Cape Lighthouse   |          85 |  36.9172 |     3.913 |        3.83
 AWS-027    | AWS Regional Station 027 |      1134.3 |  36.8916 |     3.816 |        9.90
 AWS-004    | Tizi Ouzou Valley        |         189 |  36.7118 |    4.0459 |       29.50
 AWS-047    | AWS Regional Station 047 |      1126.7 |  36.9473 |    4.2596 |       31.96
(4 rows)
```

---

#### 6.4.2 Query 9B: Spatial-Temporal CTE Join (Stations Within 50 km of Boumerdes $\bowtie$ October 2026 Telemetry) (`Lines 271–299`)

##### 6.4.2.1 Exact SQL Code (`Lines 271–299`)

```sql
-- 9B. Join stations within 50 km of Boumerdes (36.7664N, 3.4772E) with October 2026 telemetry
WITH nearby_stations AS (
    SELECT 
        station_id,
        station_name,
        ROUND((ST_Distance(
            geom::geography, 
            ST_SetSRID(ST_MakePoint(3.4772, 36.7664), 4326)::geography
        ) / 1000.0)::numeric, 2) AS dist_km
    FROM stations
    WHERE ST_DWithin(
        geom::geography, 
        ST_SetSRID(ST_MakePoint(3.4772, 36.7664), 4326)::geography, 
        50000 -- 50 km
    )
)
SELECT 
    ns.station_id,
    ns.station_name,
    ns.dist_km,
    ROUND(AVG(t.temperature)::numeric, 2) AS oct_mean_temp,
    MAX(t.wind_speed) AS oct_peak_gust
FROM nearby_stations ns
JOIN raw_telemetry_partitioned t 
  ON t.station_id = ns.station_id
WHERE t.recorded_at >= '2026-10-01 00:00:00+00' 
  AND t.recorded_at <  '2026-11-01 00:00:00+00'
GROUP BY ns.station_id, ns.station_name, ns.dist_km
ORDER BY ns.dist_km ASC, ns.station_id ASC;
```

##### 6.4.2.2 Deep-Dive Architectural Breakdown

Query 9B combines **every major Day 3 architectural pillar** in a single production query:

1. **Stage 1 — Spatial Filtering in the `nearby_stations` CTE (`Lines 272–286`):**
   - Anchors at **Boumerdes Coastal Point (`36.7664° N, 3.4772° E`, `AWS-002`)** and filters `stations` with `ST_DWithin(..., 50000)` (`50 km` geodesic radius).
   - Out of our 8 ground-truth stations, this captures:
     - **`AWS-002` (`Boumerdes Coastal Point`)** at **`0.00 km`**
     - **`AWS-001` (`Algiers Port Marine`)** at **`37.30 km`** west
     - **`AWS-003` (`Dellys Cape Lighthouse`)** at **`42.25 km`** east-northeast
     - *(While `AWS-004` Tizi Ouzou at `51.14 km`, `AWS-005` Bejaia at `142.21 km`, `AWS-006` Jijel at `202.98 km`, `AWS-008` Constantine at `285.94 km`, and `AWS-007` Oran at `404.60 km` are excluded!)*
     - Plus the 5 deterministic `setseed(0.42)` regional stations inside the 50 km radius (`AWS-048` at `16.66 km`, `AWS-050` at `19.15 km`, `AWS-027` at `33.21 km`, `AWS-022` at `42.25 km`, and `AWS-029` at `42.63 km`).
2. **Stage 2 — Partition Pruning on the 5,000,000-Row Telemetry Table (`Lines 294–297`):**
   - Joins `nearby_stations ns` with `raw_telemetry_partitioned t ON t.station_id = ns.station_id`.
   - Because the `WHERE` clause specifies the exact half-open interval for October 2026 (`t.recorded_at >= '2026-10-01 00:00:00+00' AND t.recorded_at < '2026-11-01 00:00:00+00'`), PostgreSQL's partition pruning engine eliminates `telemetry_y2026m09`, `telemetry_y2026m11`, `telemetry_y2026m12`, and `telemetry_default`, scanning **only `telemetry_y2026m10`** (`1.27M rows` instead of `5.00M rows` — an immediate **74.5% I/O reduction**).
3. **Stage 3 — Hash Join & Parallel Aggregation (`Lines 287–299`):**
   - Hashes the small `nearby_stations` CTE result (`8 stations`) in memory, probes `telemetry_y2026m10` in parallel worker processes, and computes `ROUND(AVG(t.temperature)::numeric, 2) AS oct_mean_temp` and `MAX(t.wind_speed) AS oct_peak_gust` ordered by radial distance `ns.dist_km ASC, ns.station_id ASC`.

##### 6.4.2.3 Expected Terminal Output (`Lines 272–299`)

```text
 station_id |       station_name       | dist_km | oct_mean_temp | oct_peak_gust 
------------+--------------------------+---------+---------------+---------------
 AWS-002    | Boumerdes Coastal Point  |    0.00 |         15.48 |            22
 AWS-048    | AWS Regional Station 048 |   16.66 |         15.37 |            22
 AWS-050    | AWS Regional Station 050 |   19.15 |         15.31 |            22
 AWS-027    | AWS Regional Station 027 |   33.21 |         15.46 |            22
 AWS-001    | Algiers Port Marine      |   37.30 |         15.37 |            22
 AWS-003    | Dellys Cape Lighthouse   |   42.25 |         15.48 |            22
 AWS-022    | AWS Regional Station 022 |   42.25 |         15.50 |            22
 AWS-029    | AWS Regional Station 029 |   42.63 |         15.39 |            22
(8 rows)
```

---

> **Navigation:** [Master README](../README.md) | [Interactive Portal](../bootcamp_portal.html) | [Reference Cards](../reference_cards/README.md) | [Day 2 Coursebook](../day2/day2_master_coursebook.md) | [Day 3 Coursebook](./day3_master_coursebook.md) | [Advanced Weather PG Walkthrough](./day3_weather_advanced_pg_sql_course_walkthrough.md) | [Day 4 Coursebook](../day4/day4_master_coursebook.md)
