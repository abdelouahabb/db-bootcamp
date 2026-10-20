# Reference Card 00: SQL & MongoDB CRUD Fundamentals & Data Exploration Playbook (Using Bootcamp Weather Data)

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards Index](./README.md) | [📘 Day 1 (SQLite)](../day1/day1_master_coursebook.md) | [🐘 Day 2 (PostgreSQL)](../day2/day2_master_coursebook.md) | [🍃 Day 4 (MongoDB)](../day4/day4_master_coursebook.md)

---

## 🧭 Purpose of This Playbook: Master the Basics First!

Before diving into hardware sentinels (`-9999.0`), `3VL` truth tables, `pageinspect` 8 KB heap blocks, or multi-stage `$facet` pipelines, every attendee needs **100% fluency in the core daily commands to view, filter, sort, insert, update, and delete data (`CRUD`)** on the exact databases used in this bootcamp.

Every single command in this guide is **copy-and-paste runnable** against the actual bootcamp datasets across **SQLite (Day 1)**, **PostgreSQL (Days 2–3)**, and **MongoDB (Day 4)**.

---

## 🚨 Master Orientation Map: Which Database, File, Schema & Exact Column Names Am I Using?

| Bootcamp Day & Engine | How to Connect from Your Terminal | Database / File Name | Exact Tables / Collections & Column Names Inside | Seed Script (To Reset to Clean State) |
| :--- | :--- | :--- | :--- | :--- |
| **Day 1 — SQLite (Part A: Operational WMO DB)** | ```bash\ncd day1\nsqlite3 weather_ops.db\n``` | **`day1/weather_ops.db`** | • **`stations`** (`7` rows): `station_id` *(INT PK: `60390`..)*, `station_name`, `latitude`, `longitude`, `elevation_m`, `climate_zone`, `is_active`<br/>• **`observations`** (`36` rows): `obs_id`, `station_id`, **`obs_time`**, **`temp_c`**, `dewpoint_c`, `humidity_pct`, **`pressure_hpa`**, **`wind_speed_kt`**, **`precip_1h_mm`**, `qc_flag`<br/>• **`forecasts`** (`22` rows): `forecast_id`, `station_id`, `model_name`, `init_time`, `valid_time`, `lead_hours`, `pred_temp_c`, `pred_wind_kt`, `pred_precip_mm`<br/>• **`weather_alerts`** (`4` rows): `alert_id`, `station_id`, `issued_at`, `phenomenon`, `severity`, `message` | `cd day1 && sqlite3 weather_ops.db < weather_ops_seed.sql` |
| **Day 1 — SQLite (Part B: 250k High-Frequency DB)** | ```bash\ncd day1\nsqlite3 weather_telemetry.db\n```<br/>*(Or inside `sqlite3`: `.open weather_telemetry.db`)* | **`day1/weather_telemetry.db`** | • **`stations`** (`50` rows): `station_id` *(TEXT PK: `'AWS-001'..'AWS-050'`)*, `station_name`, `latitude`, `longitude`, `elevation_m`, `is_active`<br/>• **`raw_telemetry`** (`250,000` rows): `id`, `station_id`, **`recorded_at`**, **`temperature`**, **`pressure`**, **`wind_speed`**, `wind_direction`, `rain_accum_1m` | `cd day1 && python3 generate_weather_db.py` |
| **Days 2 & 3 — PostgreSQL 16+** | ```bash\ncd day2\npsql -d weather_ops\n``` | **`weather_ops`** *(PostgreSQL database)* | • **`synoptic.stations`** (`7` rows): `station_id`, `station_name`, `latitude`, `longitude`, `elevation_m`, `climate_zone`, `is_active`, `raw_metadata`<br/>• **`synoptic.observations`** (`18,432` rows): `obs_id`, `station_id`, `obs_time`, `temp_c`, `dewpoint_c`, `humidity_pct`, `pressure_hpa`, `wind_speed_kt`, `precip_1h_mm`, `qc_flag`, `raw_metar`<br/>• **`nwp.forecasts`** (`4,608` rows): `forecast_id`, `station_id`, `model_name`, `init_time`, `lead_interval`, `valid_time` *(STORED)*, `pred_temp_c`, `pred_wind_kt`, `pred_precip_mm`<br/>• **`alerts.weather_alerts`** (`4` rows): `alert_id`, `station_id`, `issued_at`, `phenomenon`, `severity`, `message` | `cd day2 && psql -d weather_ops -f weather_ops_pg.sql` |
| **Day 4 — MongoDB 7.0 (`mongosh`)** | ```bash\ncd day4\nmongosh weather_nosql\n``` | **`weather_nosql`** *(MongoDB database)* | • **`stations`** (`6` docs): `_id` *(Int32)*, `station_name`, `station_type`, `climate_zone`, `elevation_m`, `is_active`, `location` *(GeoJSON)*, `sensors` *(Array)*, `calibration`<br/>• **`synoptic_timeseries`** (`6` docs): `obs_time`, `station_meta` *(`station_id`, `station_type`, `climate_zone`)*, `temp_c`, `dewpoint_c`, `pressure_hpa`, `wind_speed_kt`, `precip_1h_mm`, `diagnostics`<br/>• **`radiosonde_soundings`** (`3` docs): `station_id`, `station_name`, `launch_time`, `sonde_serial`, `burst_altitude_m`, `cape_j_kg`, `k_index`, `vertical_levels` *(Array)*<br/>• **`cap_alerts`** (`2` docs): `_id` *(String)*, `issued_at`, `expires_at`, `phenomenon`, `severity`, `certainty`, `affected_stations` *(Array)*, `max_observed_gust_kt`, `headline` | `cd day4 && mongosh weather_nosql day4_weather_ops_mongo.js` |

> [!WARNING]
> **⚠️ Watch Out for Column Name Differences Between the Two Day 1 SQLite Files!**
> | Physical Metric | Column Name in `weather_ops.db` (`observations`) | Column Name in `weather_telemetry.db` (`raw_telemetry`) |
> | :--- | :--- | :--- |
> | **Station ID Type** | `station_id` (`INTEGER`: `60390`, `60490`, `60419`...) | `station_id` (`TEXT`: `'AWS-001'`, `'AWS-013'`, `'AWS-042'`...) |
> | **Timestamp** | **`obs_time`** (`'2026-10-05 06:00:00'`) | **`recorded_at`** (`'2026-10-02 14:10:00'`) |
> | **Air Temperature** | **`temp_c`** | **`temperature`** |
> | **Barometric Pressure** | **`pressure_hpa`** | **`pressure`** |
> | **Wind Speed** | **`wind_speed_kt`** | **`wind_speed`** |
> | **Precipitation** | **`precip_1h_mm`** (Sentinel: `-9999.0`) | **`rain_accum_1m`** (Sentinel: `-999.0` on `temperature`/`pressure`/`wind_speed`) |

---

## ⚡ The Cross-Engine CRUD Rosetta Stone (`SQLite` vs. `PostgreSQL` vs. `MongoDB`)

| Operation | Day 1: SQLite (`sqlite3`) | Days 2–3: PostgreSQL (`psql`) | Day 4: MongoDB (`mongosh`) |
| :--- | :--- | :--- | :--- |
| **Check Current DB / File** | `.databases` | `\conninfo` | `db.getName()` / `show dbs` |
| **Switch DB / File** | `.open weather_ops.db` | `\c weather_ops` | `use weather_nosql` |
| **List Tables / Collections** | `.tables` | `\dt+ synoptic.*` (or `\dt *.*`) | `show collections` |
| **Inspect Table Schema / Sample Doc** | `.schema stations`<br/>`PRAGMA table_info('stations');` | `\d+ synoptic.stations` | `db.stations.findOne()` |
| **Show All Rows / Documents** | `SELECT * FROM stations;` | `SELECT * FROM synoptic.stations;` | `db.stations.find()` |
| **Show Specific Columns (Projection)** | `SELECT station_id, station_name FROM stations;` | `SELECT station_id, station_name FROM synoptic.stations;` | `db.stations.find({}, { station_name: 1 })` |
| **Filter (`WHERE` / Query Filter)** | `SELECT * FROM stations WHERE climate_zone = 'Arid';` | `SELECT * FROM synoptic.stations WHERE climate_zone = 'Arid';` | `db.stations.find({ climate_zone: "Arid" })` |
| **Sort & Limit (`ORDER BY` / `LIMIT`)** | `SELECT * FROM stations ORDER BY elevation_m DESC LIMIT 3;` | `SELECT * FROM synoptic.stations ORDER BY elevation_m DESC LIMIT 3;` | `db.stations.find().sort({ elevation_m: -1 }).limit(3)` |
| **Count Rows / Documents** | `SELECT COUNT(*) FROM observations;` | `SELECT COUNT(*) FROM synoptic.observations;` | `db.synoptic_timeseries.countDocuments()` |
| **Create (`INSERT` / `insertOne`)** | `INSERT INTO stations VALUES (...);` | `INSERT INTO synoptic.stations VALUES (...) RETURNING *;` | `db.stations.insertOne({ ... })` |
| **Update (`UPDATE` / `updateOne`)** | `UPDATE stations SET is_active = 1 WHERE station_id = 60402;` | `UPDATE synoptic.stations SET is_active = TRUE WHERE station_id = 60402 RETURNING *;` | `db.stations.updateOne({ _id: 60390 }, { $set: { is_active: true } })` |
| **Delete (`DELETE` / `deleteOne`)** | `DELETE FROM weather_alerts WHERE alert_id = 4;` | `DELETE FROM alerts.weather_alerts WHERE alert_id = 4 RETURNING *;` | `db.cap_alerts.deleteOne({ _id: "DZ-ONM-2026-10-05-002" })` |

---

# PART I: Day 1 SQLite CRUD & Exploration Playbook (`day1/weather_ops.db` & `day1/weather_telemetry.db`)

## 1.1 Opening the Database & Inspecting Tables ("Show Me What Exists!")

First, open your terminal, `cd` into the `day1/` folder, and launch `sqlite3` on `weather_ops.db`:

```bash
cd day1
sqlite3 weather_ops.db
```

Now run these commands inside the `sqlite>` prompt to format the output into clean ASCII boxes and inspect the schema:

```sql
-- 📂 TARGET FILE: day1/weather_ops.db
-- 👉 In sqlite3 CLI, switch first with: .open weather_ops.db

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

## 1.2 Basic `SELECT` — Viewing Rows, Choosing Columns, Aliases & Math Expressions

```sql
-- 📂 TARGET FILE: day1/weather_ops.db
-- 👉 In sqlite3 CLI, switch first with: .open weather_ops.db

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
-- 📂 TARGET FILE: day1/weather_ops.db
-- 👉 In sqlite3 CLI, switch first with: .open weather_ops.db

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
--    'Algiers%' = starts with Algiers | '%rain%' = contains the word rain anywhere
SELECT station_id, station_name FROM stations WHERE station_name LIKE 'Algiers%';
SELECT alert_id, station_id, phenomenon, severity, message FROM weather_alerts WHERE message LIKE '%gusts%';

-- 7. Combining Conditions with AND / OR (Always use parentheses around OR!):
SELECT station_id, station_name, climate_zone, elevation_m, is_active
FROM stations
WHERE (climate_zone = 'Arid' OR climate_zone = 'Highland')
  AND is_active = 1;

-- 8. Finding Missing Sensor Readings (IS NULL vs. IS NOT NULL):
--    ⚠️ Remember: "WHERE temp_c = NULL" NEVER returns rows in SQL! Always use IS NULL:
SELECT obs_id, station_id, obs_time, temp_c, dewpoint_c, wind_speed_kt, qc_flag
FROM observations
WHERE temp_c IS NULL
   OR dewpoint_c IS NULL
   OR wind_speed_kt IS NULL;
```

---

## 1.4 Sorting & Pagination (`ORDER BY`, `ASC`, `DESC`, `LIMIT`, `OFFSET`)

```sql
-- 📂 TARGET FILE: day1/weather_ops.db
-- 👉 In sqlite3 CLI, switch first with: .open weather_ops.db

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

## 1.5 Basic Aggregations (`COUNT`, `MIN`, `MAX`, `AVG`, `SUM`) & `GROUP BY` / `HAVING`

```sql
-- 📂 TARGET FILE: day1/weather_ops.db
-- 👉 In sqlite3 CLI, switch first with: .open weather_ops.db

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
```

---

## 1.6 Basic `INSERT`, `UPDATE` & `DELETE` (DML) on `day1/weather_ops.db`

> [!TIP]
> **The Golden Classroom Safety Rule:** When practicing `INSERT`, `UPDATE`, and `DELETE`, you can wrap your changes in `BEGIN;` ... `ROLLBACK;` to test safely, or clean up the test row at the end so your `weather_ops.db` stays identical to the seed script!

```sql
-- 📂 TARGET FILE: day1/weather_ops.db
-- 👉 In sqlite3 CLI, switch first with: .open weather_ops.db
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

-- 1. Preview the row BEFORE updating (Best Practice!):
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
-- 📂 TARGET FILE: day1/weather_telemetry.db
-- 👉 In sqlite3 CLI, switch first with: .open weather_telemetry.db

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

# PART II: Days 2 & 3 PostgreSQL CRUD & Exploration Playbook (`weather_ops` Database)

In Days 2 and 3, we move from SQLite to **PostgreSQL 16+**. When you load [`day2/weather_ops_pg.sql`](../day2/weather_ops_pg.sql), PostgreSQL organizes tables into **three operational schemas**:
- **`synoptic.stations`** (`7` WMO stations) & **`synoptic.observations`** (`18,432` hourly observations)
- **`nwp.forecasts`** (`4,608` NWP model rows with an automatically calculated `valid_time` column)
- **`alerts.weather_alerts`** (`4` severe weather bulletins)

## 2.1 Connecting & Exploring Schemas/Tables in `psql` ("Show Me the Data!")

```bash
cd day2
psql -d weather_ops
```

Run inside `psql`:

```sql
-- 📂 TARGET DATABASE: PostgreSQL 'weather_ops' (psql -d weather_ops)
-- 📜 PREREQUISITE SCRIPT: day2/weather_ops_pg.sql

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
-- 📂 TARGET DATABASE: PostgreSQL 'weather_ops' (psql -d weather_ops)
-- 📜 PREREQUISITE SCRIPT: day2/weather_ops_pg.sql

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
-- 📂 TARGET DATABASE: PostgreSQL 'weather_ops' (psql -d weather_ops)
-- 📜 PREREQUISITE SCRIPT: day2/weather_ops_pg.sql

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

# PART III: Day 4 MongoDB CRUD & Exploration Playbook (`weather_nosql` Database in `mongosh`)

On Day 4, we use **MongoDB 7.0 (`mongosh`)** on the `weather_nosql` database seeded by [`day4/day4_weather_ops_mongo.js`](../day4/day4_weather_ops_mongo.js). It contains **4 collections**:
1. **`stations`** (`6` polymorphic station documents: `_id`, `station_name`, `station_type`, `climate_zone`, `elevation_m`, `location`, `sensors`, `calibration`)
2. **`synoptic_timeseries`** (`6` time-series documents: `obs_time`, `station_meta`, `temp_c`, `pressure_hpa`, `wind_speed_kt`, plus optional `soil_profile`, `marine_telemetry`, `aerosol_telemetry`, `diagnostics`)
3. **`radiosonde_soundings`** (`3` upper-air balloon launch documents with embedded `vertical_levels: [...]` arrays)
4. **`cap_alerts`** (`2` Common Alerting Protocol severe weather bulletins)

## 3.1 Connecting & Inspecting Collections in `mongosh` ("Show Me the Documents!")

```bash
cd day4
mongosh weather_nosql
```

Run inside `mongosh`:

```javascript
// 📂 TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// 📜 PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

// 1. Verify current database and list all collections:
db.getName();
show collections;

// 2. Count documents in all 4 collections:
printjson({
  stations: db.stations.countDocuments(),
  synoptic_timeseries: db.synoptic_timeseries.countDocuments(),
  radiosonde_soundings: db.radiosonde_soundings.countDocuments(),
  cap_alerts: db.cap_alerts.countDocuments()
});

// 3. Inspect a single sample document from each collection using findOne():
db.stations.findOne();
db.synoptic_timeseries.findOne();
db.radiosonde_soundings.findOne();
db.cap_alerts.findOne();
```

---

## 3.2 Basic Read (`find()` & `findOne()`) — Filtering, Projection, Nested Fields, Arrays & Sorting

In MongoDB:
- `db.collection.find(<filter>, <projection>)` is the equivalent of `SELECT <projection> FROM collection WHERE <filter>`.
- `.sort({ field: 1 })` = `ORDER BY field ASC` (`-1` = `DESC`).
- `.limit(N)` = `LIMIT N` and `.skip(N)` = `OFFSET N`.

```javascript
// 📂 TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// 📜 PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

// 1. Show ALL documents in 'stations' (Equivalent to: SELECT * FROM stations;)
db.stations.find().toArray();

// 2. Find ONE station by its Primary Key '_id' (Equivalent to: WHERE _id = 60390)
db.stations.findOne({ _id: 60390 });

// 3. Projection — Select ONLY specific fields (1 = include, 0 = exclude):
//    Equivalent to: SELECT _id, station_name, station_type, climate_zone, elevation_m FROM stations;
db.stations.find(
  {},
  { station_name: 1, station_type: 1, climate_zone: 1, elevation_m: 1 }
).toArray();

// 4. Exact Equality Filter (Equivalent to: WHERE climate_zone = 'Arid')
db.stations.find(
  { climate_zone: "Arid" },
  { station_name: 1, station_type: 1, elevation_m: 1 }
).toArray();

// 5. Numeric Comparison Operators ($gt, $gte, $lt, $lte, $ne):
//    Equivalent to: WHERE elevation_m >= 500
db.stations.find(
  { elevation_m: { $gte: 500 } },
  { station_name: 1, elevation_m: 1, climate_zone: 1 }
).toArray();

// 6. Range Filter ($gte + $lte on the same field):
//    Equivalent to: WHERE wind_speed_kt BETWEEN 20 AND 35
db.synoptic_timeseries.find(
  { wind_speed_kt: { $gte: 20, $lte: 35 } },
  { _id: 0, obs_time: 1, "station_meta.station_id": 1, temp_c: 1, wind_speed_kt: 1 }
).toArray();

// 7. Set Membership ($in):
//    Equivalent to: WHERE station_type IN ('AGRO_SOIL', 'COASTAL_BUOY')
db.stations.find(
  { station_type: { $in: ["AGRO_SOIL", "COASTAL_BUOY"] } },
  { station_name: 1, station_type: 1 }
).toArray();

// 8. Querying Nested Sub-Documents Using Dot Notation ("parent.child"):
//    Always wrap dotted field paths in quotes!
db.stations.find(
  { "calibration.technician": "M. Benali" },
  { station_name: 1, calibration: 1 }
).toArray();

db.synoptic_timeseries.find(
  { "station_meta.station_id": 60390 },
  { _id: 0, obs_time: 1, temp_c: 1, pressure_hpa: 1, wind_speed_kt: 1, "diagnostics.battery_v": 1 }
).toArray();

// 9. Polymorphic Field Existence ($exists):
//    Find only telemetry documents that contain marine buoy wave data or agro soil data!
db.synoptic_timeseries.find({ marine_telemetry: { $exists: true } }).toArray();
db.synoptic_timeseries.find({ soil_profile: { $exists: true } }).toArray();

// 10. Querying Arrays (Match any document whose array contains a value):
//     Find stations equipped with a "VAISALA_RS41_SONDE" sensor:
db.stations.find(
  { sensors: "VAISALA_RS41_SONDE" },
  { station_name: 1, sensors: 1 }
).toArray();

//     Find CAP weather alerts affecting station 60390:
db.cap_alerts.find(
  { affected_stations: 60390 },
  { _id: 1, phenomenon: 1, severity: 1, affected_stations: 1, headline: 1 }
).toArray();

// 11. Sorting & Limiting (.sort() and .limit()):
//     Equivalent to: ORDER BY elevation_m DESC LIMIT 3
db.stations.find(
  {},
  { station_name: 1, climate_zone: 1, elevation_m: 1 }
).sort({ elevation_m: -1 }).limit(3).toArray();
```

---

## 3.3 Basic Create (`insertOne()` & `insertMany()`) in MongoDB

> [!IMPORTANT]
> **Schema Validation Note on `db.stations`:** Recall from [`day4/day4_weather_ops_mongo.js`](../day4/day4_weather_ops_mongo.js) that `db.stations` has a `$jsonSchema` validator requiring `_id` (`Int32`), `station_name` (`string`), `station_type` (`"SURFACE_AWS"`, `"COASTAL_BUOY"`, `"UPPER_AIR_RADIOSONDE"`, or `"AGRO_SOIL"`), `is_active` (`bool`), and `location` (`{ type: "Point", coordinates: [lon, lat] }`).

```javascript
// 📂 TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// 📜 PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

// 1. insertOne() — Insert a new Saharan station (WMO 60580: Ouargla - Ain Beida):
db.stations.insertOne({
  _id: Int32(60580),
  station_name: "Ouargla - Ain Beida",
  station_type: "SURFACE_AWS",
  climate_zone: "Arid",
  elevation_m: 141.0,
  is_active: true,
  location: { type: "Point", coordinates: [5.4128, 31.9172] }, // [longitude, latitude]!
  sensors: ["PT100_THERM", "DUST_PARTICLE_LASER"],
  calibration: {
    last_calibrated: ISODate("2026-10-01T00:00:00Z"),
    technician: "Y. Brahimi"
  }
});

// Verify the new station document:
db.stations.findOne({ _id: 60580 });

// 2. insertMany() — Insert 2 new telemetry readings for station 60580:
db.synoptic_timeseries.insertMany([
  {
    obs_time: ISODate("2026-10-06T12:00:00Z"),
    station_meta: { station_id: 60580, station_type: "SURFACE_AWS", climate_zone: "Arid" },
    temp_c: 35.4,
    dewpoint_c: 9.1,
    pressure_hpa: 1011.8,
    wind_speed_kt: 14.0,
    precip_1h_mm: 0.0,
    diagnostics: { battery_v: 13.6, door_open: false, firmware: "v4.2.1" }
  },
  {
    obs_time: ISODate("2026-10-06T15:00:00Z"),
    station_meta: { station_id: 60580, station_type: "SURFACE_AWS", climate_zone: "Arid" },
    temp_c: 37.1,
    dewpoint_c: 8.4,
    pressure_hpa: 1010.2,
    wind_speed_kt: 21.0,
    precip_1h_mm: 0.0,
    aerosol_telemetry: { pm10_ug_m3: 420, visibility_m: 1800 },
    diagnostics: { battery_v: 13.5, door_open: false, firmware: "v4.2.1" }
  }
]);

// Verify the 2 new time-series documents:
db.synoptic_timeseries.find({ "station_meta.station_id": 60580 }).toArray();
```

---

## 3.4 Basic Update (`updateOne()`, `updateMany()`, Upsert — `$set`, `$inc`, `$addToSet`, `$push`, `$pull`)

> [!WARNING]
> **Critical MongoDB Rule:** Always use atomic update operators (`$set`, `$inc`, `$push`, `$addToSet`, `$pull`) inside `updateOne()` / `updateMany()`!

```javascript
// 📂 TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// 📜 PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

// 1. $set — Update scalar and nested fields on station 60580:
db.stations.updateOne(
  { _id: 60580 },
  {
    $set: {
      elevation_m: 142.5,
      "calibration.technician": "S. Khelifi",
      "calibration.pressure_offset_hpa": 0.05
    }
  }
);

// 2. $addToSet & $push — Add a new sensor to the 'sensors' array (without duplicates):
db.stations.updateOne(
  { _id: 60580 },
  { $addToSet: { sensors: "SOLAR_PYRANOMETER" } }
);

// Verify the updated station document:
db.stations.findOne({ _id: 60580 });

// 3. $pull — Remove an item from an array:
db.stations.updateOne(
  { _id: 60580 },
  { $pull: { sensors: "SOLAR_PYRANOMETER" } }
);

// 4. $inc — Increment a numeric field in-place (e.g., bump max_observed_gust_kt by +2.5 kt):
db.cap_alerts.updateOne(
  { _id: "DZ-ONM-2026-10-05-002" },
  { $inc: { max_observed_gust_kt: 2.5 } }
);
// Revert it back by -2.5 kt:
db.cap_alerts.updateOne(
  { _id: "DZ-ONM-2026-10-05-002" },
  { $inc: { max_observed_gust_kt: -2.5 } }
);

// 5. Upsert ({ upsert: true }) — Insert if not found, or update if already exists:
db.cap_alerts.updateOne(
  { _id: "DZ-ONM-2026-10-06-TEST" },
  {
    $set: {
      issued_at: ISODate("2026-10-06T18:00:00Z"),
      expires_at: ISODate("2026-10-07T06:00:00Z"),
      phenomenon: "HEATWAVE",
      severity: "YELLOW",
      certainty: "LIKELY",
      affected_stations: [60580, 60680],
      max_observed_gust_kt: 22.0,
      headline: "High afternoon temperatures across southern arid stations"
    }
  },
  { upsert: true }
);

// Verify the upserted alert:
db.cap_alerts.findOne({ _id: "DZ-ONM-2026-10-06-TEST" });
```

---

## 3.5 Basic Delete (`deleteOne()` & `deleteMany()`) in MongoDB

```javascript
// 📂 TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// 📜 PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

// 1. deleteOne() — Delete the test CAP alert we created above:
db.cap_alerts.deleteOne({ _id: "DZ-ONM-2026-10-06-TEST" });

// 2. deleteMany() — Delete the 2 test telemetry documents for station 60580:
db.synoptic_timeseries.deleteMany({ "station_meta.station_id": 60580 });

// 3. deleteOne() — Delete the test station 60580 so 'weather_nosql' returns to its exact seed state:
db.stations.deleteOne({ _id: 60580 });

// Verify clean state (6 stations, 6 synoptic_timeseries, 3 soundings, 2 cap_alerts):
printjson({
  stations: db.stations.countDocuments(),
  synoptic_timeseries: db.synoptic_timeseries.countDocuments(),
  radiosonde_soundings: db.radiosonde_soundings.countDocuments(),
  cap_alerts: db.cap_alerts.countDocuments()
});
```

---

## 3.6 Basic Aggregation Pipeline (`$match` $\rightarrow$ `$group` $\rightarrow$ `$sort`) — MongoDB's `GROUP BY`

In SQL, you write `SELECT climate_zone, COUNT(*), AVG(elevation_m) FROM stations WHERE is_active = 1 GROUP BY climate_zone ORDER BY count DESC;`.  
In MongoDB, you pass an array of pipeline stages to `db.collection.aggregate([ ... ])`:

```javascript
// 📂 TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// 📜 PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

// 1. Group 'stations' by climate_zone (Equivalent to SQL GROUP BY climate_zone):
db.stations.aggregate([
  { $match: { is_active: true } },
  {
    $group: {
      _id: "$climate_zone",
      station_count: { $sum: 1 },
      avg_elevation_m: { $avg: "$elevation_m" },
      max_elevation_m: { $max: "$elevation_m" },
      station_names: { $push: "$station_name" }
    }
  },
  { $sort: { station_count: -1, max_elevation_m: -1 } }
]).toArray();

// 2. Group 'synoptic_timeseries' by station_id to compute mean temp and peak wind:
db.synoptic_timeseries.aggregate([
  {
    $group: {
      _id: "$station_meta.station_id",
      climate_zone: { $first: "$station_meta.climate_zone" },
      reading_count: { $sum: 1 },
      mean_temp_c: { $avg: "$temp_c" },
      max_wind_kt: { $max: "$wind_speed_kt" }
    }
  },
  { $sort: { max_wind_kt: -1 } }
]).toArray();

// 3. Flatten an Embedded Array ($unwind) — Show every 500 hPa and 300 hPa upper-air level across all balloon launches:
db.radiosonde_soundings.aggregate([
  { $unwind: "$vertical_levels" },
  { $match: { "vertical_levels.pressure_hpa": { $in: [500, 300] } } },
  {
    $project: {
      _id: 0,
      station_id: 1,
      station_name: 1,
      launch_time: 1,
      pressure_hpa: "$vertical_levels.pressure_hpa",
      height_m: "$vertical_levels.height_m",
      temp_c: "$vertical_levels.temp_c",
      wind_speed_kt: "$vertical_levels.wind_speed_kt"
    }
  },
  { $sort: { pressure_hpa: 1, wind_speed_kt: -1 } }
]).toArray();

// 4. Join Two Collections ($lookup — Equivalent to SQL LEFT JOIN):
//    Join 'synoptic_timeseries' with 'stations' on station_meta.station_id == _id:
db.synoptic_timeseries.aggregate([
  {
    $lookup: {
      from: "stations",
      localField: "station_meta.station_id",
      foreignField: "_id",
      as: "station_doc"
    }
  },
  { $unwind: "$station_doc" },
  {
    $project: {
      _id: 0,
      obs_time: 1,
      station_id: "$station_meta.station_id",
      station_name: "$station_doc.station_name",
      elevation_m: "$station_doc.elevation_m",
      temp_c: 1,
      wind_speed_kt: 1
    }
  },
  { $sort: { obs_time: -1, station_id: 1 } }
]).toArray();
```

---

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [📚 Reference Cards Index](./README.md) | [📘 Day 1 (SQLite)](../day1/day1_master_coursebook.md) | [🐘 Day 2 (PostgreSQL)](../day2/day2_master_coursebook.md) | [🍃 Day 4 (MongoDB)](../day4/day4_master_coursebook.md)
