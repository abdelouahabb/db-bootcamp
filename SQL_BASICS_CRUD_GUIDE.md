# Dedicated SQL Basics & CRUD Guide (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `WHERE`, `GROUP BY`, `JOIN`)

> **Navigation:** [Bootcamp README](./README.md) | [MongoDB NoSQL Basics Guide](./MONGODB_NOSQL_BASICS_CRUD_GUIDE.md) | [Interactive Portal](./bootcamp_portal.html) | [Day 1 (SQLite)](./day1/day1_master_coursebook.md) | [Day 2 (PostgreSQL)](./day2/day2_master_coursebook.md) | [Day 3 (Advanced PostgreSQL)](./day3/day3_master_coursebook.md)

---

## 1. Purpose of This Dedicated SQL Basics Guide

Before diving into hardware sentinels (`-9999.0`), Three-Valued Logic (`3VL`), 8 KB PostgreSQL heap pages (`pageinspect`), or range partitioning, every attendee needs **100% fluency in the core daily SQL commands to view, filter, sort, aggregate, join, insert, update, and delete data (`CRUD`)** on the exact relational databases used in Days 1, 2, and 3 of this bootcamp.

Every single SQL block in this document is **copy-and-paste runnable** against the actual bootcamp databases:
- **Part I — Day 1 SQLite Databases (`day1/weather_ops.db` and `day1/weather_telemetry.db`)**
- **Part II — Days 2 & 3 PostgreSQL Databases (`weather_ops` and `weather_ops_db`)**

---

## 2. Master SQL Orientation Map: Which Database, File, Schema & Exact Column Names Am I Using?

| Bootcamp Day & SQL Engine | How to Connect from Your Terminal | Database / File Name | Exact Tables & Column Names Inside | Seed Command (To Reset to Clean State) |
| :--- | :--- | :--- | :--- | :--- |
| **Day 1 — SQLite (Part A: Operational WMO DB)** | ```bash\ncd day1\nsqlite3 weather_ops.db\n``` | **`day1/weather_ops.db`** | • **`stations`** (`7` rows): `station_id` *(INT PK: `60390`..)*, `station_name`, `latitude`, `longitude`, `elevation_m`, `climate_zone`, `is_active`<br/>• **`observations`** (`36` rows): `obs_id`, `station_id`, **`obs_time`**, **`temp_c`**, `dewpoint_c`, `humidity_pct`, **`pressure_hpa`**, **`wind_speed_kt`**, **`precip_1h_mm`**, `qc_flag`<br/>• **`forecasts`** (`22` rows): `forecast_id`, `station_id`, `model_name`, `init_time`, `valid_time`, `lead_hours`, `pred_temp_c`, `pred_wind_kt`, `pred_precip_mm`<br/>• **`weather_alerts`** (`4` rows): `alert_id`, `station_id`, `issued_at`, `phenomenon`, `severity`, `message` | `cd day1 && sqlite3 weather_ops.db < weather_ops_seed.sql` |
| **Day 1 — SQLite (Part B: 250k High-Frequency DB)** | ```bash\ncd day1\nsqlite3 weather_telemetry.db\n```<br/>*(Or inside `sqlite3`: `.open weather_telemetry.db`)* | **`day1/weather_telemetry.db`** | • **`stations`** (`50` rows): `station_id` *(TEXT PK: `'AWS-001'..'AWS-050'`)*, `station_name`, `latitude`, `longitude`, `elevation_m`, `is_active`<br/>• **`raw_telemetry`** (`250,000` rows): `id`, `station_id`, **`recorded_at`**, **`temperature`**, **`pressure`**, **`wind_speed`**, `wind_direction`, `rain_accum_1m` | `cd day1 && python3 generate_weather_db.py` |
| **Days 2 & 3 — PostgreSQL (`weather_ops` DB)** | ```bash\ncd day2\npsql -U postgres -d weather_ops\n``` | **`weather_ops`** *(PostgreSQL database)* | • **`synoptic.stations`** (`7` rows): `station_id`, `station_name`, `latitude`, `longitude`, `elevation_m`, `climate_zone`, `is_active`, `raw_metadata`<br/>• **`synoptic.observations`** (`18,432` rows): `obs_id`, `station_id`, `obs_time`, `temp_c`, `dewpoint_c`, `humidity_pct`, `pressure_hpa`, `wind_speed_kt`, `precip_1h_mm`, `qc_flag`, `raw_metar`<br/>• **`nwp.forecasts`** (`4,608` rows): `forecast_id`, `station_id`, `model_name`, `init_time`, `lead_interval`, `valid_time` *(STORED)*, `pred_temp_c`, `pred_wind_kt`, `pred_precip_mm`<br/>• **`alerts.weather_alerts`** (`4` rows): `alert_id`, `station_id`, `issued_at`, `phenomenon`, `severity`, `message` | `cd day2 && psql -U postgres -d weather_ops -f weather_ops_pg.sql` |
| **Day 3 — PostgreSQL (`weather_ops_db` 5M-Row Benchmark DB)** | ```bash\ncd day3\npsql -U postgres -d weather_ops_db\n``` | **`weather_ops_db`** *(PostgreSQL database)* | • **`public.stations`** (`50` rows): `station_id` *(`'STN-001'..'STN-050'`)*, `station_name`, `elevation_m`, `latitude`, `longitude`, `geom`, `is_active`<br/>• **`public.raw_telemetry_partitioned`** (`5,000,000` rows across `telemetry_oct2023`, `telemetry_nov2023`, `telemetry_dec2023`): `station_id`, `recorded_at`, `temperature_c`, `pressure_hpa`, `wind_speed_ms`, `rain_1h_mm` | `cd day3 && psql -U postgres -d postgres -f day3_postgis_5m_benchmark.sql` |

> [!WARNING]
> **Watch Out for Column Name Differences Between the Two Day 1 SQLite Files!**
> | Physical Metric | Column Name in `day1/weather_ops.db` (`observations`) | Column Name in `day1/weather_telemetry.db` (`raw_telemetry`) |
> | :--- | :--- | :--- |
> | **Station ID Type** | `station_id` (`INTEGER`: `60390`, `60490`, `60419`...) | `station_id` (`TEXT`: `'AWS-001'`, `'AWS-013'`, `'AWS-042'`...) |
> | **Timestamp** | **`obs_time`** (`'2026-10-05 06:00:00'`) | **`recorded_at`** (`'2026-10-02 14:10:00'`) |
> | **Air Temperature** | **`temp_c`** | **`temperature`** |
> | **Barometric Pressure** | **`pressure_hpa`** | **`pressure`** |
> | **Wind Speed** | **`wind_speed_kt`** | **`wind_speed`** |
> | **Precipitation** | **`precip_1h_mm`** (Sentinel: `-9999.0`) | **`rain_accum_1m`** (Sentinel: `-999.0` on `temperature`/`pressure`/`wind_speed`) |

---

## 3. SQLite vs. PostgreSQL Side-by-Side SQL Quick Reference

| SQL Operation | Day 1: SQLite (`sqlite3`) | Days 2–3: PostgreSQL (`psql`) |
| :--- | :--- | :--- |
| **Check Current Database / File** | `.databases` | `\conninfo` |
| **Switch Database / File** | `.open weather_ops.db` | `\c weather_ops` |
| **List All Tables** | `.tables` | `\dt+ synoptic.*` (or `\dt *.*`) |
| **Inspect Table Columns & Types** | `.schema stations`<br/>`PRAGMA table_info('stations');` | `\d+ synoptic.stations` |
| **Show All Rows (`SELECT *`)** | `SELECT * FROM stations;` | `SELECT * FROM synoptic.stations;` |
| **Select Specific Columns** | `SELECT station_id, station_name FROM stations;` | `SELECT station_id, station_name FROM synoptic.stations;` |
| **Filter Rows (`WHERE`)** | `SELECT * FROM stations WHERE climate_zone = 'Arid';` | `SELECT * FROM synoptic.stations WHERE climate_zone = 'Arid';` |
| **Sort & Limit (`ORDER BY` / `LIMIT`)** | `SELECT * FROM stations ORDER BY elevation_m DESC LIMIT 3;` | `SELECT * FROM synoptic.stations ORDER BY elevation_m DESC LIMIT 3;` |
| **Count Rows (`COUNT(*)`)** | `SELECT COUNT(*) FROM observations;` | `SELECT COUNT(*) FROM synoptic.observations;` |
| **Aggregate (`GROUP BY`)** | `SELECT climate_zone, COUNT(*) FROM stations GROUP BY climate_zone;` | `SELECT climate_zone, COUNT(*) FROM synoptic.stations GROUP BY climate_zone;` |
| **Insert Row (`INSERT INTO`)** | `INSERT INTO stations VALUES (...);` | `INSERT INTO synoptic.stations VALUES (...) RETURNING *;` |
| **Update Row (`UPDATE ... SET`)** | `UPDATE stations SET is_active = 1 WHERE station_id = 60402;` | `UPDATE synoptic.stations SET is_active = TRUE WHERE station_id = 60402 RETURNING *;` |
| **Delete Row (`DELETE FROM`)** | `DELETE FROM weather_alerts WHERE alert_id = 4;` | `DELETE FROM alerts.weather_alerts WHERE alert_id = 4 RETURNING *;` |

---

# PART I: Day 1 SQLite SQL Basics (`day1/weather_ops.db` & `day1/weather_telemetry.db`)

## 1.1 Opening the Database & Inspecting Tables ("Show Me What Exists!")

Open your terminal, `cd` into the `day1/` folder, and launch `sqlite3` on `weather_ops.db`:

```bash
cd day1
sqlite3 weather_ops.db
```

Run these commands inside the `sqlite>` prompt to enable box-drawing tables and inspect the schema:

```sql
-- TARGET FILE: day1/weather_ops.db
-- In sqlite3 CLI, switch first with: .open weather_ops.db

-- 1. Turn on column headers and box-drawing tables:
.headers on
.mode box
PRAGMA foreign_keys = ON;

-- 2. Verify which .db file is open and list all tables:
.databases
.tables
-- Expected: forecasts  observations  stations  weather_alerts

-- 3. Inspect the columns and types of the 'stations' and 'observations' tables:
PRAGMA table_info('stations');
PRAGMA table_info('observations');

-- 4. Count how many rows exist in all 4 tables at once:
SELECT 'stations'       AS table_name, COUNT(*) AS row_count FROM stations
UNION ALL
SELECT 'observations',                 COUNT(*)              FROM observations
UNION ALL
SELECT 'forecasts',                    COUNT(*)              FROM forecasts
UNION ALL
SELECT 'weather_alerts',               COUNT(*)              FROM weather_alerts;
```

---

## 1.2 Basic `SELECT` — Viewing Data, Choosing Columns, Aliases & Math Expressions

```sql
-- TARGET FILE: day1/weather_ops.db
-- In sqlite3 CLI, switch first with: .open weather_ops.db

-- 1. Show ALL columns and ALL rows from 'stations' (7 Algerian WMO stations):
SELECT * FROM stations;

-- 2. Show ALL weather alerts:
SELECT * FROM weather_alerts;

-- 3. Select ONLY specific columns (Projection) from 'stations':
SELECT
    station_id,
    station_name,
    climate_zone,
    elevation_m
FROM stations;

-- 4. Preview the first 10 rows of 'observations' using LIMIT:
SELECT
    obs_id,
    station_id,
    obs_time,
    temp_c,
    humidity_pct,
    pressure_hpa,
    wind_speed_kt,
    precip_1h_mm,
    qc_flag
FROM observations
LIMIT 10;

-- 5. Computed Columns & Column Aliases (AS):
--    Convert Celsius to Fahrenheit/Kelvin and Knots to km/h on the fly:
SELECT
    station_id,
    obs_time,
    temp_c,
    ROUND(temp_c * 1.8 + 32.0, 1)    AS temp_fahrenheit,
    ROUND(temp_c + 273.15, 2)        AS temp_kelvin,
    wind_speed_kt,
    ROUND(wind_speed_kt * 1.852, 1)  AS wind_speed_kmh
FROM observations
WHERE temp_c IS NOT NULL
LIMIT 8;

-- 6. SELECT DISTINCT — List unique values without duplicates:
SELECT DISTINCT climate_zone FROM stations;
SELECT DISTINCT model_name, lead_hours FROM forecasts;
```

---

## 1.3 Filtering Rows with `WHERE` (`=`, `!=`, `>`, `<`, `BETWEEN`, `IN`, `LIKE`, `AND`/`OR`, `IS NULL`)

```sql
-- TARGET FILE: day1/weather_ops.db
-- In sqlite3 CLI, switch first with: .open weather_ops.db

-- 1. Exact Equality (=): Show all observations for Algiers Dar El Beida (WMO ID 60390)
SELECT station_id, obs_time, temp_c, pressure_hpa, wind_speed_kt, precip_1h_mm
FROM observations
WHERE station_id = 60390;

-- 2. Text Equality (=): Find all stations in the 'Mediterranean' climate zone
SELECT station_id, station_name, latitude, longitude, elevation_m
FROM stations
WHERE climate_zone = 'Mediterranean';

-- 3. Numeric Comparison (> / >= / < / <=): Stations above 500 meters elevation
SELECT station_id, station_name, elevation_m, climate_zone
FROM stations
WHERE elevation_m >= 500.0;

-- 4. Range Filter (BETWEEN ... AND ... is inclusive of both endpoints!):
SELECT station_id, obs_time, temp_c, humidity_pct
FROM observations
WHERE temp_c BETWEEN 25.0 AND 38.0;

-- 5. Set Membership (IN): Filter for specific stations (Algiers, Oran, Constantine)
SELECT station_id, obs_time, temp_c, wind_speed_kt
FROM observations
WHERE station_id IN (60390, 60490, 60419);

-- 6. Text Pattern Matching (LIKE with '%' wildcard):
--    'Algiers%' = starts with Algiers | '%gusts%' = contains the word gusts anywhere
SELECT station_id, station_name FROM stations WHERE station_name LIKE 'Algiers%';
SELECT alert_id, station_id, phenomenon, severity, message FROM weather_alerts WHERE message LIKE '%gusts%';

-- 7. Combining Conditions with AND / OR (Always use parentheses around OR!):
SELECT station_id, station_name, climate_zone, elevation_m, is_active
FROM stations
WHERE (climate_zone = 'Arid' OR climate_zone = 'Highland')
   AND is_active = 1;

-- 8. Finding Missing Sensor Readings (IS NULL vs. IS NOT NULL):
--    Remember: "WHERE temp_c = NULL" NEVER returns rows in SQL! Always use IS NULL:
SELECT obs_id, station_id, obs_time, temp_c, dewpoint_c, wind_speed_kt, qc_flag
FROM observations
WHERE temp_c IS NULL
   OR dewpoint_c IS NULL
   OR wind_speed_kt IS NULL;
```

---

## 1.4 Sorting & Pagination (`ORDER BY`, `ASC`, `DESC`, `LIMIT`, `OFFSET`)

```sql
-- TARGET FILE: day1/weather_ops.db
-- In sqlite3 CLI, switch first with: .open weather_ops.db

-- 1. Sort stations from highest elevation to lowest (DESC = Descending):
SELECT station_id, station_name, climate_zone, elevation_m
FROM stations
ORDER BY elevation_m DESC;

-- 2. Sort by multiple columns: first by climate_zone (A->Z), then by elevation (high->low):
SELECT climate_zone, station_id, station_name, elevation_m
FROM stations
ORDER BY climate_zone ASC, elevation_m DESC;

-- 3. Top-5 Leaderboard: Find the 5 highest wind speeds recorded across all valid observations:
SELECT station_id, obs_time, wind_speed_kt, pressure_hpa, qc_flag
FROM observations
WHERE wind_speed_kt IS NOT NULL
ORDER BY wind_speed_kt DESC
LIMIT 5;

-- 4. Pagination (Page 1 vs. Page 2, 5 rows per page):
-- Page 1 (rows 1..5):
SELECT obs_id, station_id, obs_time, temp_c FROM observations ORDER BY obs_id ASC LIMIT 5 OFFSET 0;
-- Page 2 (rows 6..10):
SELECT obs_id, station_id, obs_time, temp_c FROM observations ORDER BY obs_id ASC LIMIT 5 OFFSET 5;
```

---

## 1.5 Basic Aggregations (`COUNT`, `MIN`, `MAX`, `AVG`, `SUM`), `GROUP BY` / `HAVING` & `JOIN`

```sql
-- TARGET FILE: day1/weather_ops.db
-- In sqlite3 CLI, switch first with: .open weather_ops.db

-- 1. Count how many stations exist in each climate_zone:
SELECT
    climate_zone,
    COUNT(*)                  AS total_stations,
    SUM(is_active)            AS active_stations,
    ROUND(AVG(elevation_m),1) AS avg_elevation_m
FROM stations
GROUP BY climate_zone
ORDER BY total_stations DESC;

-- 2. Compute summary weather statistics per station (on clean 'VALID' rows):
SELECT
    station_id,
    COUNT(*)                         AS total_obs,
    COUNT(temp_c)                    AS non_null_temp_obs,
    MIN(temp_c)                      AS min_temp_c,
    MAX(temp_c)                      AS max_temp_c,
    ROUND(AVG(temp_c), 1)            AS avg_temp_c,
    MAX(wind_speed_kt)               AS max_wind_kt,
    ROUND(SUM(precip_1h_mm), 1)      AS total_rain_mm
FROM observations
WHERE qc_flag = 'VALID'
GROUP BY station_id
ORDER BY max_wind_kt DESC;

-- 3. Filter aggregated groups using HAVING (e.g., stations with > 15 mm total rain):
--    Remember: WHERE filters individual rows BEFORE grouping; HAVING filters groups AFTER GROUP BY!
SELECT
    station_id,
    COUNT(*)                    AS valid_hours,
    ROUND(SUM(precip_1h_mm), 1) AS total_rain_mm
FROM observations
WHERE qc_flag = 'VALID'
GROUP BY station_id
HAVING SUM(precip_1h_mm) > 15.0
ORDER BY total_rain_mm DESC;

-- 4. Basic INNER JOIN — Combine 'observations' with 'stations' to show station_name!
SELECT
    s.station_id,
    s.station_name,
    s.climate_zone,
    o.obs_time,
    o.temp_c,
    o.wind_speed_kt,
    o.precip_1h_mm
FROM observations o
INNER JOIN stations s
    ON o.station_id = s.station_id
WHERE o.qc_flag = 'VALID'
ORDER BY o.obs_time DESC, s.station_id ASC
LIMIT 10;

-- 5. Basic LEFT JOIN — Include ALL stations even if they have 0 observations (like 60402 Bejaia):
SELECT
    s.station_id,
    s.station_name,
    s.is_active,
    COUNT(o.obs_id) AS observation_count
FROM stations s
LEFT JOIN observations o
    ON s.station_id = o.station_id
GROUP BY s.station_id, s.station_name, s.is_active
ORDER BY observation_count ASC;
```

---

## 1.6 Basic `INSERT`, `UPDATE` & `DELETE` (DML) on `day1/weather_ops.db`

```sql
-- TARGET FILE: day1/weather_ops.db
-- In sqlite3 CLI, switch first with: .open weather_ops.db
PRAGMA foreign_keys = ON;

-- ============================================================================
-- A. CREATE (INSERT INTO): Add a new Saharan WMO Station & 2 Observations
-- ============================================================================

-- 1. Insert a single row into 'stations' (WMO 60580: Ouargla - Ain Beida):
INSERT INTO stations (station_id, station_name, latitude, longitude, elevation_m, climate_zone, is_active)
VALUES (60580, 'Ouargla - Ain Beida', 31.9172, 5.4128, 141.0, 'Arid', 1);

-- Verify the new station is in the table:
SELECT * FROM stations WHERE station_id = 60580;

-- 2. Insert multiple rows at once into 'observations' for station 60580:
INSERT INTO observations (
    station_id, obs_time, temp_c, dewpoint_c, humidity_pct,
    pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag
)
VALUES
    (60580, '2026-10-06T00:00:00Z', 26.4, 8.2, 31.0, 1012.5, 10.0, 0.0, 'VALID'),
    (60580, '2026-10-06T03:00:00Z', 23.1, 7.9, 36.0, 1013.0,  8.0, 0.0, 'VALID');

-- Verify the newly inserted observations:
SELECT obs_id, station_id, obs_time, temp_c, humidity_pct, pressure_hpa, qc_flag
FROM observations
WHERE station_id = 60580;

-- 3. Upsert (INSERT ... ON CONFLICT DO UPDATE):
--    If (station_id=60580, obs_time='2026-10-06T03:00:00Z') already exists, update its temp_c instead of failing!
INSERT INTO observations (
    station_id, obs_time, temp_c, dewpoint_c, humidity_pct,
    pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag
)
VALUES (60580, '2026-10-06T03:00:00Z', 23.8, 8.0, 35.0, 1013.1, 9.0, 0.0, 'VALID')
ON CONFLICT (station_id, obs_time)
DO UPDATE SET
    temp_c        = excluded.temp_c,
    humidity_pct  = excluded.humidity_pct,
    pressure_hpa  = excluded.pressure_hpa,
    wind_speed_kt = excluded.wind_speed_kt;

-- ============================================================================
-- B. UPDATE: Modify Existing Rows Safely (ALWAYS include a WHERE clause!)
-- ============================================================================

-- 1. Preview the row BEFORE updating:
SELECT obs_id, station_id, obs_time, temp_c, wind_speed_kt, qc_flag
FROM observations
WHERE station_id = 60580 AND obs_time = '2026-10-06T00:00:00Z';

-- 2. Update specific columns on that row:
UPDATE observations
SET temp_c        = 27.0,
    wind_speed_kt = 14.5,
    qc_flag       = 'SUSPECT'
WHERE station_id = 60580
  AND obs_time   = '2026-10-06T00:00:00Z';

-- Verify the update took effect:
SELECT obs_id, station_id, obs_time, temp_c, wind_speed_kt, qc_flag
FROM observations
WHERE station_id = 60580;

-- ============================================================================
-- C. DELETE FROM: Remove Rows Safely & Observe ON DELETE CASCADE
-- ============================================================================

-- 1. Delete a single observation row by its unique (station_id, obs_time):
DELETE FROM observations
WHERE station_id = 60580
  AND obs_time   = '2026-10-06T00:00:00Z';

-- Confirm only 1 observation remains for 60580:
SELECT COUNT(*) AS remaining_obs_for_60580 FROM observations WHERE station_id = 60580;

-- 2. Delete parent station 60580 from 'stations':
--    Because PRAGMA foreign_keys = ON and observations has ON DELETE CASCADE,
--    deleting station 60580 automatically deletes its remaining child observations!
DELETE FROM stations WHERE station_id = 60580;

-- Confirm both station 60580 and its observations are gone (clean slate!):
SELECT COUNT(*) AS station_60580_count FROM stations WHERE station_id = 60580;
SELECT COUNT(*) AS obs_60580_count     FROM observations WHERE station_id = 60580;
```

---

## 1.7 Exploring the Second Day 1 Database: `day1/weather_telemetry.db` (`250,000` Rows)

When a Day 1 exercise queries `raw_telemetry`, switch to `weather_telemetry.db`:

```sql
-- TARGET FILE: day1/weather_telemetry.db
-- In sqlite3 CLI, switch first with: .open weather_telemetry.db

.open weather_telemetry.db
.tables
-- Expected: raw_telemetry  stations

-- 1. Inspect the 50 Automated Weather Stations ('AWS-001' .. 'AWS-050'):
SELECT station_id, station_name, latitude, longitude, elevation_m, is_active
FROM stations
ORDER BY elevation_m DESC
LIMIT 10;

-- 2. Count total stations and average elevation:
SELECT
    COUNT(*)                  AS total_aws_stations,
    ROUND(MIN(elevation_m),1) AS min_elev_m,
    ROUND(AVG(elevation_m),1) AS avg_elev_m,
    ROUND(MAX(elevation_m),1) AS max_elev_m
FROM stations;

-- 3. Inspect the 10 most recent high-frequency pings from station 'AWS-001':
SELECT id, station_id, recorded_at, temperature, pressure, wind_speed, wind_direction, rain_accum_1m
FROM raw_telemetry
WHERE station_id = 'AWS-001'
ORDER BY recorded_at DESC
LIMIT 10;

-- 4. Count readings and compute clean average temperature (excluding -999.0 sentinels) for the first 5 stations:
SELECT
    station_id,
    COUNT(*)                                    AS total_pings,
    ROUND(AVG(NULLIF(temperature, -999.0)), 2)  AS clean_avg_temp_c,
    ROUND(MAX(NULLIF(wind_speed, -999.0)), 2)   AS max_wind_speed
FROM raw_telemetry
GROUP BY station_id
ORDER BY station_id ASC
LIMIT 5;
```

---

# PART II: Days 2 & 3 PostgreSQL SQL Basics (`weather_ops` Database)

In Days 2 and 3, we move from SQLite to **PostgreSQL 16+**. When you load [`day2/weather_ops_pg.sql`](./day2/weather_ops_pg.sql), PostgreSQL organizes tables into **three operational schemas**:
- **`synoptic.stations`** (`7` WMO stations) & **`synoptic.observations`** (`18,432` hourly observations)
- **`nwp.forecasts`** (`4,608` NWP model rows with an automatically calculated `valid_time` column)
- **`alerts.weather_alerts`** (`4` severe weather bulletins)

## 2.1 Connecting & Exploring Schemas/Tables in `psql` ("Show Me the Data!")

```bash
cd day2
psql -U postgres -d weather_ops
```

Run inside `psql`:

```sql
-- TARGET DATABASE: PostgreSQL 'weather_ops' (psql -U postgres -d weather_ops)
-- PREREQUISITE SCRIPT: day2/weather_ops_pg.sql

-- 1. Check current connection, schemas, and tables across all schemas:
\conninfo
\dn+
\dt+ synoptic.*
\dt+ nwp.*
\dt+ alerts.*

-- 2. Inspect column types, constraints, and indexes on synoptic.observations:
\d+ synoptic.observations

-- 3. Set search_path so you can optionally omit schema prefixes in this session:
SET search_path TO synoptic, nwp, alerts, public;
SET timezone = 'UTC';

-- 4. Count rows across all 4 operational PostgreSQL tables:
SELECT 'synoptic.stations'     AS table_name, COUNT(*) AS row_count FROM synoptic.stations
UNION ALL
SELECT 'synoptic.observations',               COUNT(*)              FROM synoptic.observations
UNION ALL
SELECT 'nwp.forecasts',                       COUNT(*)              FROM nwp.forecasts
UNION ALL
SELECT 'alerts.weather_alerts',               COUNT(*)              FROM alerts.weather_alerts;
```

---

## 2.2 Basic `SELECT`, `WHERE` (`ILIKE`, `TIMESTAMPTZ`, `INTERVAL`), `ORDER BY` & `GROUP BY` in PostgreSQL

```sql
-- TARGET DATABASE: PostgreSQL 'weather_ops' (psql -U postgres -d weather_ops)
-- PREREQUISITE SCRIPT: day2/weather_ops_pg.sql

-- 1. View all 7 WMO stations (excluding the large 5.8 KB raw_metadata TOAST column):
SELECT
    station_id,
    station_name,
    latitude,
    longitude,
    elevation_m,
    climate_zone,
    is_active
FROM synoptic.stations
ORDER BY station_id;

-- 2. View all active weather alerts:
SELECT alert_id, station_id, issued_at, phenomenon, severity, message
FROM alerts.weather_alerts
ORDER BY issued_at DESC;

-- 3. Case-Insensitive Pattern Matching with PostgreSQL ILIKE:
SELECT station_id, station_name, climate_zone
FROM synoptic.stations
WHERE station_name ILIKE '%algiers%'
   OR station_name ILIKE '%constantine%';

-- 4. Filter Observations by UTC Timestamp Range & INTERVAL Arithmetic:
SELECT
    obs_id,
    station_id,
    obs_time,
    temp_c,
    humidity_pct,
    pressure_hpa,
    wind_speed_kt,
    precip_1h_mm,
    qc_flag
FROM synoptic.observations
WHERE station_id = 60390
  AND obs_time >= TIMESTAMPTZ '2026-10-06 00:00:00+00' - INTERVAL '12 hours'
ORDER BY obs_time DESC;

-- 5. Inspect NWP Forecasts (Notice valid_time is computed automatically from init_time + lead_interval!):
SELECT
    forecast_id,
    station_id,
    model_name,
    init_time,
    lead_interval,
    valid_time,
    pred_temp_c,
    pred_wind_kt,
    pred_precip_mm
FROM nwp.forecasts
WHERE station_id = 60390
ORDER BY valid_time DESC, model_name ASC
LIMIT 9;

-- 6. Aggregate Climatological Summary per Station Joined with Station Names:
SELECT
    s.station_id,
    s.station_name,
    s.climate_zone,
    COUNT(o.obs_id)                AS total_hourly_obs,
    ROUND(MIN(o.temp_c), 1)        AS min_temp_c,
    ROUND(AVG(o.temp_c), 1)        AS mean_temp_c,
    ROUND(MAX(o.temp_c), 1)        AS max_temp_c,
    ROUND(SUM(o.precip_1h_mm), 1)  AS total_precip_mm
FROM synoptic.stations s
LEFT JOIN synoptic.observations o
    ON s.station_id = o.station_id
GROUP BY s.station_id, s.station_name, s.climate_zone
ORDER BY mean_temp_c DESC NULLS LAST;
```

---

## 2.3 Basic `INSERT`, `UPDATE`, `DELETE` & PostgreSQL's `RETURNING` Superpower

Unlike older SQL engines where you have to run a second `SELECT` after an `INSERT`, `UPDATE`, or `DELETE` to see what changed or what `BIGSERIAL` ID was generated, PostgreSQL supports **`RETURNING`** on every DML statement!

```sql
-- TARGET DATABASE: PostgreSQL 'weather_ops' (psql -U postgres -d weather_ops)
-- PREREQUISITE SCRIPT: day2/weather_ops_pg.sql

-- ============================================================================
-- A. INSERT INTO ... RETURNING (Create rows and immediately see generated IDs!)
-- ============================================================================

-- 1. Insert a new station and return the inserted row:
INSERT INTO synoptic.stations (
    station_id, station_name, latitude, longitude, elevation_m, climate_zone, is_active, raw_metadata
)
VALUES (
    60580, 'Ouargla - Ain Beida', 31.9172, 5.4128, 141.0, 'Arid', TRUE, 'Saharan Synoptic AWS'
)
RETURNING station_id, station_name, climate_zone, elevation_m, is_active;

-- 2. Insert a new observation and return the auto-generated BIGSERIAL 'obs_id':
INSERT INTO synoptic.observations (
    station_id, obs_time, temp_c, dewpoint_c, humidity_pct,
    pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag, raw_metar
)
VALUES (
    60580, '2026-10-06 12:00:00+00', 35.4, 9.1, 20.5,
    1011.8, 14.0, 0.0, 'VALID', 'METAR DAUU 061200Z 09014KT CAVOK 35/09 Q1012'
)
RETURNING obs_id, station_id, obs_time, temp_c, qc_flag;

-- 3. Insert an NWP forecast: Notice we do NOT insert 'valid_time' because PostgreSQL
--    calculates valid_time = (init_time + lead_interval) automatically and returns it!
INSERT INTO nwp.forecasts (
    station_id, model_name, init_time, lead_interval, pred_temp_c, pred_wind_kt, pred_precip_mm
)
VALUES (
    60580, 'ECMWF-HRES', '2026-10-06 00:00:00+00', INTERVAL '12 hours', 34.8, 15.0, 0.0
)
RETURNING forecast_id, station_id, model_name, init_time, lead_interval, valid_time, pred_temp_c;

-- 4. Upsert (INSERT ... ON CONFLICT DO UPDATE ... RETURNING):
INSERT INTO synoptic.observations (
    station_id, obs_time, temp_c, dewpoint_c, humidity_pct,
    pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag
)
VALUES (
    60580, '2026-10-06 12:00:00+00', 35.9, 9.3, 20.0,
    1011.6, 16.0, 0.0, 'VALID'
)
ON CONFLICT (station_id, obs_time)
DO UPDATE SET
    temp_c        = EXCLUDED.temp_c,
    pressure_hpa  = EXCLUDED.pressure_hpa,
    wind_speed_kt = EXCLUDED.wind_speed_kt
RETURNING obs_id, station_id, obs_time, temp_c, wind_speed_kt;

-- ============================================================================
-- B. UPDATE ... RETURNING (Modify rows and return the new values in 1 step!)
-- ============================================================================

UPDATE synoptic.observations
SET qc_flag = 'SUSPECT',
    temp_c  = 36.2
WHERE station_id = 60580
  AND obs_time   = '2026-10-06 12:00:00+00'
RETURNING obs_id, station_id, obs_time, temp_c, qc_flag;

-- ============================================================================
-- C. DELETE FROM ... RETURNING (Clean up test station 60580 & cascade children)
-- ============================================================================

DELETE FROM synoptic.stations
WHERE station_id = 60580
RETURNING station_id, station_name;

-- Verify cascade deletion removed child observations and forecasts for 60580:
SELECT COUNT(*) AS remaining_60580_obs FROM synoptic.observations WHERE station_id = 60580;
```

---

> **Navigation:** [Bootcamp README](./README.md) | [MongoDB NoSQL Basics Guide](./MONGODB_NOSQL_BASICS_CRUD_GUIDE.md) | [Interactive Portal](./bootcamp_portal.html) | [Day 1 (SQLite)](./day1/day1_master_coursebook.md) | [Day 2 (PostgreSQL)](./day2/day2_master_coursebook.md) | [Day 3 (Advanced PostgreSQL)](./day3/day3_master_coursebook.md)
