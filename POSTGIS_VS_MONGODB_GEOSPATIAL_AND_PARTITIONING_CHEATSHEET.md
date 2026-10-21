> **Navigation:** [Bootcamp README](./README.md) | [SQL Basics & CRUD Guide](./SQL_BASICS_CRUD_GUIDE.md) | [MongoDB NoSQL Basics & CRUD Guide](./MONGODB_NOSQL_BASICS_CRUD_GUIDE.md) | [Interactive Portal](./bootcamp_portal.html) | [Day 3 Coursebook](./day3/day3_master_coursebook.md) | [Day 4 Coursebook](./day4/day4_master_coursebook.md)

# Dedicated Cheatsheet: PostgreSQL `PostGIS` vs. MongoDB `2dsphere` Geospatial & PostgreSQL Table Partitioning vs. MongoDB Time-Series / Sharding Equivalents

**Purpose of This Document:**  
This dedicated side-by-side engineering cheatsheet compares the two biggest production scaling and spatial subsystems across **Day 3 (PostgreSQL 16 + PostGIS 3.4)** and **Day 4 (MongoDB 7.0)**:
1. **Part I — Spatial Meteorology (`PostGIS` vs. MongoDB `2dsphere`):** Coordinate order rules, spherical geodesy (`GEOGRAPHY` vs. `GEOMETRY` vs. `GeoJSON`), physical spatial index internals (`GiST R-Tree` vs. `2dsphere Google S2 B-Tree`), and side-by-side runnable queries for radial proximity (`ST_DWithin` vs. `$geoNear`), storm polygon containment (`ST_Covers` vs. `$geoWithin`), and reverse intersection (`ST_Intersects` vs. `$geoIntersects`).
2. **Part II — Time-Series Partitioning (`PARTITION BY RANGE` vs. MongoDB's 4 Equivalents):** Why MongoDB does not use SQL-style `PARTITION BY RANGE` on a single server, how MongoDB solves the exact same 5 physical problems via **Native Time-Series Collections (`system.buckets.*`)**, **Manual Bucketing**, **Bucket-Level TTL (`expireAfterSeconds`)**, and **Horizontal Range/Zone Sharding (`sh.shardCollection`)**, plus side-by-side runnable recipes and the critical partitioning/shard-key traps.

---

# PART I: Spatial Meteorology — PostgreSQL `PostGIS` (Day 3) vs. MongoDB `2dsphere` (Day 4)

## 1.1 First-Principles Mental Model: How `PostGIS GiST` vs. MongoDB `2dsphere` Work Under the Hood

```text
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │       SPATIAL INDEXING INTERNALS: POSTGIS GiST (R-TREE) vs. MONGODB 2DSPHERE (S2)      │
 ├───────────────────────────────────────────┬────────────────────────────────────────────┤
 │ POSTGRESQL + POSTGIS (USING GIST)         │ MONGODB 7.0 (createIndex: "2dsphere")      │
 ├───────────────────────────────────────────┼────────────────────────────────────────────┤
 │ • Data Types: GEOGRAPHY (WGS84 Ellipsoid) │ • Data Format: RFC 7946 GeoJSON Objects    │
 │   vs. GEOMETRY (Planar Cartesian SRIDs)   │   ({ type: "Point", coordinates: [lon,lat]})│
 │ • Index Structure: Hierarchical R-Tree of │ • Index Structure: Decomposes shapes into  │
 │   Minimum Bounding Rectangles (MBR boxes) │   Google S2 Spherical Cell IDs (hierarchical│
 │   stored directly in 8 KB GiST pages.     │   64-bit geohash integers) stored inside a │
 │ • Two-Step Search:                        │   standard WiredTiger B-Tree index!        │
 │   1. GiST R-Tree bounding-box filter      │ • Native Compound Support:                 │
 │   2. Exact spheroidal trigonometry check  │   Can combine scalar B-Tree keys + S2 cells│
 │      on candidate rows (ST_DWithin)       │   in 1 index: { station_type:1, loc:"2dsphere"}│
 └───────────────────────────────────────────┴────────────────────────────────────────────┘
```

## 1.2 Head-to-Head Architectural Matrix: `PostGIS` vs. MongoDB `2dsphere`

| Spatial Dimension | PostgreSQL 16 + `PostGIS 3.4` (`Day 3`) | MongoDB 7.0 `GeoJSON` + `2dsphere` (`Day 4`) |
| :--- | :--- | :--- |
| **1. Installation & Setup** | External OS package + SQL extension required:<br/>`sudo apt install postgresql-16-postgis-3`<br/>`CREATE EXTENSION IF NOT EXISTS postgis;` | **Built-in natively** inside the core `mongod` binary (zero extensions to install). |
| **2. Coordinate Order Rule** | **`ST_MakePoint(longitude, latitude)`**<br/>Strictly **`(X, Y) = (lon, lat)`**! | **`coordinates: [longitude, latitude]`**<br/>Strictly **`[X, Y] = [lon, lat]`**! |
| **3. Earth Geodesy Model** | **Two distinct spatial types:**<br/>• **`GEOGRAPHY(Point, 4326)`**: Spherical/ellipsoidal Earth (WGS84), distances in **meters**, zero distortion.<br/>• **`GEOMETRY(Point, srid)`**: Planar Cartesian grid, distances in degrees (if 4326) or projected meters across **8,000+ EPSG SRIDs**. | **`2dsphere` index on RFC 7946 GeoJSON:**<br/>• Models the **WGS84 spherical Earth** directly; distances are always in **meters**.<br/>• Legacy `2d` index exists only for flat Cartesian `[x, y]` pairs. |
| **4. Physical Index Structure** | **`USING GIST (geog)`**<br/>Builds a hierarchical **R-Tree** of 2D/3D Minimum Bounding Rectangles (`MBR`) stored in 8 KB heap/index pages. | **`createIndex({ location: "2dsphere" })`**<br/>Decomposes shapes into **Google S2 spherical geometry cells** (hierarchical geohash integer tokens) stored inside a standard **WiredTiger B-Tree**! |
| **5. Compound Non-Spatial + Spatial Index** | Requires installing `CREATE EXTENSION btree_gist;` to combine scalar equality (`station_type`) and spatial `GiST` in one index. | **Supported out-of-the-box:**<br/>`db.stations.createIndex({ station_type: 1, location: "2dsphere" })` combines standard B-Tree prefix keys with S2 cell tokens in one index! |
| **6. Closed Polygon Ring Rule** | In `POLYGON((lon1 lat1, lon2 lat2, ..., lon1 lat1))`, the **first and last vertex must be identical** to close the ring. | In `{ type: "Polygon", coordinates: [[[lon1, lat1], ..., [lon1, lat1]]] }`, the **first and last `[lon, lat]` pair must be identical**. |

> [!WARNING]
> **The #1 Meteorological Spatial Bug in Both Engines — Swapping `(Latitude, Longitude)`:**  
> Forecasters verbally state coordinates as *"36.75°N, 3.05°E"* (`lat, lon`), whereas **both `PostGIS` and `MongoDB GeoJSON` strictly require `(X, Y) = (longitude, latitude)`** (`[-180..180, -90..90]`). Passing `(36.7538, 3.0588)` places Algiers in the **Indian Ocean off Somalia (`3.05°N, 36.75°E`)**, causing every Algeria proximity or storm polygon query to return `0` stations!

---

## 1.3 Spatial Operator Rosetta Stone (1-to-1 Translator)

| Spatial Operation | PostgreSQL `PostGIS` Function (`Day 3`) | MongoDB `MQL` / Aggregation Operator (`Day 4`) |
| :--- | :--- | :--- |
| **Construct a Point (`WGS84`)** | `ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography` | `{ type: "Point", coordinates: [lon, lat] }` |
| **Construct a Polygon (`WGS84`)** | `ST_GeogFromText('POLYGON((lon1 lat1, lon2 lat2, lon3 lat3, lon1 lat1))')` | `{ type: "Polygon", coordinates: [[[lon1, lat1], [lon2, lat2], [lon3, lat3], [lon1, lat1]]] }` |
| **Create Spatial Index** | `CREATE INDEX idx_geog ON synoptic.stations USING GIST (geog);` | `db.stations.createIndex({ location: "2dsphere" });` |
| **Radial Proximity Search** *(Stations within $R$ meters, sorted by distance)* | `WHERE ST_DWithin(geog, target_pt, R_meters)`<br/>`ORDER BY ST_Distance(geog, target_pt) ASC` | `db.stations.aggregate([{ $geoNear: { near: target_pt, maxDistance: R_meters, distanceField: "dist_m", spherical: true } }])`<br/>*(or `.find({ location: { $nearSphere: { $geometry: target_pt, $maxDistance: R_meters } } })`)* |
| **Polygon Containment** *(Which point stations lie inside a storm polygon?)* | `WHERE ST_Covers(storm.footprint, station.geog)`<br/>*(or `ST_Within(station.geom, storm.geom)`)* | `db.stations.find({ location: { $geoWithin: { $geometry: storm.footprint } } })` |
| **Reverse Intersection** *(Which storm polygons cover a given point/corridor?)* | `WHERE ST_Intersects(storm.footprint, target_pt)` | `db.storm_polygons.find({ footprint: { $geoIntersects: { $geometry: target_pt } } })` |

---

## 1.4 Side-by-Side Runnable Spatial Recipes (PostgreSQL `psql` vs. MongoDB `mongosh`)

### Recipe 1: Radial Proximity Search — *"Find All Stations Within 250 km of an Offshore Mesocyclone `[3.30E, 36.80N]`"*

#### A. PostgreSQL `PostGIS` (`weather_ops` database — seeded by `day2/weather_ops_pg.sql` + `day3/day3_weather_advanced_pg.sql`)
```sql
-- TARGET DATABASE: PostgreSQL 'weather_ops' (psql -d weather_ops)
-- PREREQUISITE SCRIPTS: day2/weather_ops_pg.sql and day3/day3_weather_advanced_pg.sql

SELECT
    station_id,
    station_name,
    climate_zone,
    ROUND((ST_Distance(
        geog,
        ST_SetSRID(ST_MakePoint(3.30, 36.80), 4326)::geography
    ) / 1000.0)::NUMERIC, 1) AS distance_km
FROM synoptic.stations
WHERE is_active = TRUE
  AND ST_DWithin(
      geog,
      ST_SetSRID(ST_MakePoint(3.30, 36.80), 4326)::geography,
      250000 -- 250,000 meters = 250 km
  )
ORDER BY distance_km ASC;
```

#### B. MongoDB `2dsphere` (`weather_nosql` database — seeded by `day4/day4_weather_ops_mongo.js` + `day4/day4_weather_ops_mongo_advanced.js`)
```javascript
// TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// PREREQUISITE SCRIPTS: day4/day4_weather_ops_mongo.js and day4/day4_weather_ops_mongo_advanced.js

db = db.getSiblingDB("weather_nosql"); // Switches to 'weather_nosql' in both interactive mongosh and .js scripts

db.stations.aggregate([
  {
    $geoNear: {
      near: { type: "Point", coordinates: [3.30, 36.80] }, // [longitude, latitude]
      distanceField: "distance_km",
      maxDistance: 250000,          // 250,000 meters = 250 km
      distanceMultiplier: 0.001,    // Convert meters to kilometers
      query: { is_active: true },
      spherical: true
    }
  },
  {
    $project: {
      _id: 1,
      station_name: 1,
      station_type: 1,
      climate_zone: 1,
      distance_km: { $round: ["$distance_km", 1] }
    }
  }
]).toArray();
```

#### Verified Side-by-Side Result (Identical Geodesic Distances in Both Engines!):
```text
 station_id / _id | station_name               | climate_zone  | distance_km
------------------+----------------------------+---------------+-------------
 60390            | Algiers - Dar El Beida     | Mediterranean |        14.3
 60901            | Algiers Bay Marine Buoy #1 | Maritime      |        23.0  (MongoDB coastal buoy)
 60402            | Bejaia - Soummam           | Mediterranean |       158.1
```

---

### Recipe 2: Polygon Containment & Reverse Intersection — *"Stations Inside Radar Storm Cell Alpha (`CELL-MED-20261006-A`)"*

Both `day3/day3_weather_advanced_pg.sql` (`alerts.storm_polygons`) and `day4/day4_weather_ops_mongo_advanced.js` (`db.storm_polygons`) seed the exact same two GeoJSON/WKT storm polygons:
- **`CELL-MED-20261006-A` (`Mediterranean Convective System Alpha`):** Closed ring `POLYGON((2.5 35.8, 7.2 35.8, 7.2 37.1, 2.5 37.1, 2.5 35.8))` (`58.5 dBZ`)
- **`CELL-SAH-20261006-B` (`Southern Erg Haboob Dust Front`):** Closed ring `POLYGON((1.5 22.0, 6.5 22.0, 6.5 28.0, 1.5 28.0, 1.5 22.0))` (`34.0 dBZ`)

#### A. PostgreSQL `PostGIS` (`ST_Covers` & `ST_Intersects` on `alerts.storm_polygons`)
```sql
-- TARGET DATABASE: PostgreSQL 'weather_ops' (psql -d weather_ops)
-- PREREQUISITE SCRIPTS: day2/weather_ops_pg.sql and day3/day3_weather_advanced_pg.sql

-- 1. Polygon Containment (ST_Covers — PostGIS equivalent of MongoDB $geoWithin):
--    Find all synoptic stations inside Radar Storm Cell 'CELL-MED-20261006-A'
SELECT
    s.station_id,
    s.station_name,
    s.climate_zone,
    s.longitude,
    s.latitude
FROM synoptic.stations s
INNER JOIN alerts.storm_polygons p
    ON ST_Covers(p.footprint, s.geog)
WHERE p.storm_id = 'CELL-MED-20261006-A'
ORDER BY s.station_id;

-- 2. Reverse Intersection (ST_Intersects — PostGIS equivalent of MongoDB $geoIntersects):
--    Which active storm polygon currently covers Constantine Airport [6.6203E, 36.2760N]?
SELECT
    storm_id,
    storm_name,
    max_reflectivity_dbz,
    vil_kg_m2
FROM alerts.storm_polygons
WHERE ST_Intersects(
    footprint,
    ST_SetSRID(ST_MakePoint(6.6203, 36.2760), 4326)::geography
);
```

#### B. MongoDB `2dsphere` (`$geoWithin` & `$geoIntersects` on `db.storm_polygons`)
```javascript
// TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// PREREQUISITE SCRIPTS: day4/day4_weather_ops_mongo.js and day4/day4_weather_ops_mongo_advanced.js

db = db.getSiblingDB("weather_nosql"); // Switches to 'weather_nosql' in both interactive mongosh and .js scripts

// 1. Polygon Containment ($geoWithin — MongoDB equivalent of PostGIS ST_Covers):
//    Find all stations inside Radar Storm Cell 'CELL-MED-20261006-A'
var medStorm = db.storm_polygons.findOne({ _id: "CELL-MED-20261006-A" });

db.stations.find(
  {
    location: {
      $geoWithin: {
        $geometry: medStorm.footprint
      }
    }
  },
  { _id: 1, station_name: 1, station_type: 1, climate_zone: 1 }
).toArray();

// 2. Reverse Intersection ($geoIntersects — MongoDB equivalent of PostGIS ST_Intersects):
//    Which active storm polygon currently covers Constantine Airport [6.6203E, 36.2760N]?
db.storm_polygons.find(
  {
    footprint: {
      $geoIntersects: {
        $geometry: { type: "Point", coordinates: [6.6203, 36.2760] }
      }
    }
  },
  { _id: 1, storm_name: 1, max_reflectivity_dbz: 1, vil_kg_m2: 1 }
).toArray();
```

#### Verified Side-by-Side Result:
- **Query 1 (`ST_Covers` / `$geoWithin`):** Returns the northern stations inside `[2.5..7.2E, 35.8..37.1N]`: **`60390` (Algiers)**, **`60402` (Bejaia)**, **`60419` (Constantine)** (plus **`60901` Algiers Bay Marine Buoy** in MongoDB).
- **Query 2 (`ST_Intersects` / `$geoIntersects`):** Returns **`CELL-MED-20261006-A` (`Mediterranean Convective System Alpha`, `58.5 dBZ`, `vil_kg_m2: 42.0`)**.

---

## 1.5 Engineering Decision Matrix: When to Choose `PostGIS` vs. MongoDB `2dsphere`

| Workload / Requirement | Winner | Why? |
| :--- | :---: | :--- |
| **Constructive Geometry Math** (`ST_Buffer` 25 km corridor around a flight path, `ST_Intersection` area in $\text{km}^2$, `ST_Union`, Voronoi polygons) | **PostgreSQL `PostGIS`** | MongoDB `2dsphere` only *queries* existing shapes (`$geoNear`, `$geoWithin`, `$geoIntersects`); it cannot *construct* or clip new geometries inside the database. |
| **Custom Regional Map Projections (`ST_Transform` across EPSG SRIDs), 3D Altitude (`PointZ`), or In-Database Raster Grids (`postgis_raster`)** | **PostgreSQL `PostGIS`** | `PostGIS` supports 8,000+ coordinate reference systems (UTM, Lambert Conformal Conic, Polar Stereographic); MongoDB `2dsphere` only supports WGS84 `(lon, lat)`. |
| **Ingesting Native GeoJSON Alert Polygons (WMO CAP Bulletins), Buoy Drifts & Polymorphic IoT Payloads with Zero Schema Changes** | **MongoDB `2dsphere`** | GeoJSON documents insert directly without WKT/EWKB conversion, and `{ station_type: 1, location: "2dsphere" }` combines B-Tree + spatial filtering in a single index. |

---

# PART II: Table Partitioning in PostgreSQL (`PARTITION BY RANGE`) vs. MongoDB's 4 Partitioning Equivalents

## 2.1 First-Principles Mental Model: *"Does MongoDB Have `PARTITION BY RANGE`?"*

* **In PostgreSQL (`Day 3`):**  
  `CREATE TABLE synoptic.observations_part (...) PARTITION BY RANGE (obs_time);` splits a single logical table into **separate physical child tables (`relfilenode` files) per month** (`obs_y2026m06` .. `obs_y2026m10`) on the same server.
* **In MongoDB (`Day 4`):**  
  On a single Replica Set, MongoDB does **not** have a DDL command like `CREATE COLLECTION ... PARTITION BY RANGE` that creates monthly `.wt` sub-files inside one collection.
* **Why? Because MongoDB solves the 5 physical goals of PostgreSQL partitioning using 4 specialized native mechanisms:**

```text
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │       HOW POSTGRESQL vs. MONGODB SOLVE HIGH-VOLUME TIME-SERIES SCALING                 │
 ├───────────────────────────────────────────┬────────────────────────────────────────────┤
 │ POSTGRESQL 16 (Day 3)                     │ MONGODB 7.0 (Day 4)                        │
 ├───────────────────────────────────────────┼────────────────────────────────────────────┤
 │ 1. Declarative Range Partitioning         │ 1. Native Time-Series Collections          │
 │    (PARTITION BY RANGE (obs_time))        │    (system.buckets.* Columnar Buckets)     │
 │    -> Splits rows into monthly heap files │    -> Packs ~1,000 readings into 1 bucket  │
 ├───────────────────────────────────────────┼────────────────────────────────────────────┤
 │ 2. BRIN Index (pages_per_range = 64)      │ 2. Bucket control.min / control.max Headers│
 │    -> Stores [min, max] per 64 blocks     │    -> Built-in Zone Maps on every bucket!  │
 ├───────────────────────────────────────────┼────────────────────────────────────────────┤
 │ 3. DETACH PARTITION + DROP TABLE          │ 3. Time-Series expireAfterSeconds (TTL)    │
 │    -> O(1) file unlink (0 dead tuples)    │    -> Drops entire expired buckets at once │
 ├───────────────────────────────────────────┼────────────────────────────────────────────┤
 │ 4. Tablespaces / Distributed Citus        │ 4. Range & Zone Sharding (mongos)          │
 │    -> Moves partitions across disks/nodes │    -> Splits into 64MB Chunks across Shards│
 └───────────────────────────────────────────┴────────────────────────────────────────────┘
```

---

## 2.2 Master Mapping Matrix: PostgreSQL Partitioning vs. MongoDB Equivalents

| Engineering Problem Solved by Partitioning | PostgreSQL 16 Solution (`Day 3`) | MongoDB 7.0 Equivalent / Alternative (`Day 4`) | Physical Storage & Execution Comparison |
| :--- | :--- | :--- | :--- |
| **1. Keep Active Index Small in RAM**<br/>*(100M flat rows blow out B-Tree RAM cache)* | **Monthly Child Partitions** (`obs_y2026m10` owns its own small local B-Tree that stays 100% in `shared_buffers`) | **Native Time-Series Collections (`timeseries` $\rightarrow$ `system.buckets.*`)** *or* **Manual Bucket Pattern** | Instead of indexing every single telemetry ping, MongoDB packs up to **1,000 chronological readings per station into 1 compressed columnar bucket document** (or 3,600 readings/hour in the Manual Bucket Pattern), shrinking index entries by **$100\times\text{–}1,000\times$** and disk size by **80–90%**! |
| **2. Skip Irrelevant Time Windows**<br/>*(Don't scan June–September when querying October)* | **Query Planner Partition Pruning** + **`BRIN` Index** (`[min, max]` per 64 heap pages) | **Bucket `control.min` / `control.max` Zone-Map Pruning** + **Compound Index `{ "station_meta.station_id": 1, obs_time: 1 }`** | Every document in `system.buckets.synoptic_timeseries` stores `control.min.obs_time` and `control.max.obs_time` headers—working identically to PostgreSQL's **`BRIN` block-range summary + Partition Pruning**! |
| **3. Purge Expired Data Without `DELETE` Bloat**<br/>*(Deleting millions of old rows fragments pages)* | **`ALTER TABLE ... DETACH PARTITION CONCURRENTLY` + `DROP TABLE`** ($O(1)$ Linux filesystem unlink in `< 10 ms`) | **Time-Series `expireAfterSeconds` (Bucket-Level TTL Drop)** | In a Native Time-Series collection (`expireAfterSeconds: 7776000`), the background TTL thread checks `control.max.obs_time` and **drops entire compressed bucket documents at once** (never deleting individual measurements one-by-one!). |
| **4. Distribute Data Across Multiple Servers / Disks** | Declarative Partitioning across Tablespaces (or **Citus** distributed partitions) | **Horizontal Range Sharding (`sh.shardCollection`)** on **`{ "station_meta.station_id": 1, obs_time: 1 }`** | Splits the collection into `64 MB` contiguous key-range **Chunks** across multiple Replica Set **Shards**. When a query includes `station_id` + `obs_time`, the `mongos` router performs **Targeted Chunk Pruning** (routing only to the matching shard). |
| **5. Tiered Hot NVMe vs. Cold Archival Storage** *(or strict $O(1)$ `.wt` file drop on 1 node)* | `ALTER TABLE obs_y2026m06 SET TABLESPACE cold_hdd;` *(or Day 5 Parquet Lakehouse offload)* | **Zone Sharding (`sh.addShardToZone` + `sh.updateZoneKeyRange`)** *or* **Time-Windowed Collections (`obs_2026_09`)** | **Zone Sharding** pins recent time ranges to NVMe shards and older ranges to archival shards. On a single non-sharded Replica Set where an operator strictly wants $O(1)$ Linux filesystem unlink (`DROP TABLE` equivalent), applications write to monthly collections (`obs_2026_09`, `obs_2026_10`) and call `db.obs_2026_06.drop()` to unlink the `.wt` file immediately. |

---

## 2.3 Side-by-Side Runnable Partitioning & Time-Series Recipes

### Recipe 1: Creating Partitioned / Time-Series Storage, Inspecting Buckets & Verifying Pruning

#### A. PostgreSQL `PARTITION BY RANGE` + `BRIN` (`weather_ops` database)
```sql
-- TARGET DATABASE: PostgreSQL 'weather_ops' (psql -d weather_ops)
-- PREREQUISITE SCRIPTS: day2/weather_ops_pg.sql and day3/day3_weather_advanced_pg.sql

-- 1. Inspect the monthly child partitions of synoptic.observations_part:
SELECT
    inhrelid::regclass                               AS partition_name,
    pg_size_pretty(pg_total_relation_size(inhrelid)) AS total_size,
    (SELECT reltuples::BIGINT FROM pg_class WHERE oid = inhrelid) AS estimated_rows
FROM pg_inherits
WHERE inhparent = 'synoptic.observations_part'::regclass
ORDER BY partition_name;

-- 2. Create a new monthly child partition for November 2026 [2026-11-01, 2026-12-01):
CREATE TABLE IF NOT EXISTS synoptic.obs_y2026m11 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');

-- 3. Insert a November observation and prove PostgreSQL routed it to synoptic.obs_y2026m11:
INSERT INTO synoptic.observations_part (station_id, obs_time, temp_c, pressure_hpa, qc_flag)
VALUES (60390, '2026-11-01 00:00:00+00', 18.2, 1016.5, 'VALID')
ON CONFLICT (obs_time, station_id) DO NOTHING;

SELECT tableoid::regclass AS physical_partition, station_id, obs_time, temp_c
FROM synoptic.observations_part
WHERE obs_time >= '2026-11-01 00:00:00+00';

-- 4. Verify Partition Pruning via EXPLAIN (only obs_y2026m10 is scanned; m06..m09 & m11 are skipped!):
EXPLAIN (COSTS OFF)
SELECT station_id, AVG(temp_c), SUM(precip_1h_mm)
FROM synoptic.observations_part
WHERE obs_time >= '2026-10-05 00:00:00+00'
  AND obs_time <  '2026-10-07 00:00:00+00'
GROUP BY station_id;
```

#### B. MongoDB Native Time-Series Buckets + TTL & Manual Bucket Pattern (`weather_nosql` & `weather_telemetry_db`)
```javascript
// TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

db = db.getSiblingDB("weather_nosql"); // Switches to 'weather_nosql' in both interactive mongosh and .js scripts

// 1. Inspect how synoptic_timeseries is configured with Native Time-Series + 90-day TTL:
db.getCollectionInfos({ name: "synoptic_timeseries" });

// 2. Compare logical observation count vs. physical compressed WiredTiger buckets on disk:
printjson({
  logical_observations: db.synoptic_timeseries.countDocuments(),
  physical_buckets_on_disk: db.system.buckets.synoptic_timeseries.countDocuments()
});

// 3. Peek inside a physical bucket in system.buckets.synoptic_timeseries:
//    Notice 'control.min' and 'control.max' — MongoDB's built-in BRIN / Partition Zone Maps!
db.system.buckets.synoptic_timeseries.findOne({ "meta.station_id": 60390 });

// 4. Switch to 'weather_telemetry_db' (seeded by day4_mongo_50k_polymorphic_benchmark.js)
//    to compare 50,000 flat BSON docs vs. Time-Series Buckets vs. Manual Hourly Buckets:
db = db.getSiblingDB("weather_telemetry_db"); // Switches to 'weather_telemetry_db' in both interactive mongosh and .js scripts

printjson({
  flat_collection_docs: db.sensor_payloads.countDocuments(),
  timeseries_logical_docs: db.weather_stream.countDocuments(),
  manual_hourly_bucket_docs: db.hourly_sensor_buckets.countDocuments()
});

// Inspect 1 Manual Hourly Bucket document (pre-aggregated summary.min_w / max_w + measurements array):
db.hourly_sensor_buckets.findOne();
```

---

### Recipe 2: Zero-Bloat Lifecycle Management (`DETACH / ATTACH PARTITION` vs. `Manual Bucket Upsert` & `Zone Sharding`)

#### A. PostgreSQL: Detaching & Re-Attaching a Monthly Partition Without Blocking Queries
```sql
-- TARGET DATABASE: PostgreSQL 'weather_ops' (psql -d weather_ops)
-- PREREQUISITE SCRIPTS: day2/weather_ops_pg.sql and day3/day3_weather_advanced_pg.sql

-- 1. Detach the empty June 2026 partition from the parent table:
--    In production, DETACH PARTITION CONCURRENTLY allows you to archive/export the detached
--    table to Parquet (Day 5) and DROP TABLE in <10ms with ZERO dead tuples!
ALTER TABLE synoptic.observations_part
    DETACH PARTITION synoptic.obs_y2026m06;

-- Verify synoptic.obs_y2026m06 is now a standalone table (not listed in pg_inherits):
SELECT inhrelid::regclass AS remaining_partitions
FROM pg_inherits
WHERE inhparent = 'synoptic.observations_part'::regclass
ORDER BY remaining_partitions;

-- 2. Re-attach synoptic.obs_y2026m06 so your lab database stays in its exact initial state:
ALTER TABLE synoptic.observations_part
    ATTACH PARTITION synoptic.obs_y2026m06
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
```

#### B. MongoDB: Atomic Manual Bucket Pattern Upsert & Horizontal Range / Zone Sharding Reference
```javascript
// TARGET DATABASE: MongoDB 'weather_telemetry_db' (mongosh weather_telemetry_db)
// PREREQUISITE SCRIPT: day4/day4_mongo_50k_polymorphic_benchmark.js

db = db.getSiblingDB("weather_telemetry_db"); // Switches to 'weather_telemetry_db' in both interactive mongosh and .js scripts

// 1. Manual Bucket Pattern Upsert: Group high-frequency readings into 1 hourly document per station
//    (Reduces index entries by 3,600x and maintains live min/max/sum headers on every write!)
db.hourly_sensor_buckets.updateOne(
  { _id: "AWS-001_2026-10-06_H14" },
  {
    $setOnInsert: {
      station_id: "AWS-001",
      bucket_start: ISODate("2026-10-06T14:00:00Z"),
      bucket_end: ISODate("2026-10-06T14:59:59Z")
    },
    $push: { measurements: { sec: 10, w: 6.4, temp: 21.3 } },
    $inc: { sample_count: 1, "summary.sum_w": 6.4 },
    $min: { "summary.min_w": 6.4 },
    $max: { "summary.max_w": 6.4 }
  },
  { upsert: true }
);

db.hourly_sensor_buckets.findOne({ _id: "AWS-001_2026-10-06_H14" });

// Clean up the test bucket so 'weather_telemetry_db' stays at its exact seed count:
db.hourly_sensor_buckets.deleteOne({ _id: "AWS-001_2026-10-06_H14" });

// 2. Horizontal Cluster Partitioning & Zone Sharding Reference (Executed on 'mongos' router):
//    A) Shard the collection using a Compound Prefix + Time key (NEVER monotonic { obs_time: 1 } alone!):
//       sh.shardCollection("weather_nosql.synoptic_timeseries", { "station_meta.station_id": 1, obs_time: 1 });
//
//    B) Zone Sharding (MongoDB's equivalent of PostgreSQL Partition Tablespaces):
//       sh.addShardToZone("shard_nvme_01", "MEDITERRANEAN_HOT");
//       sh.addShardToZone("shard_hdd_archive", "SAHARA_ARCHIVE");
//       sh.updateZoneKeyRange(
//         "weather_nosql.synoptic_timeseries",
//         { "station_meta.station_id": 60390, obs_time: MinKey },
//         { "station_meta.station_id": 60499, obs_time: MaxKey },
//         "MEDITERRANEAN_HOT"
//       );
```

---

## 2.4 The 2 Critical Partitioning & Sharding Traps ("Black Box" Summary)

| Engine | The Trap | Why It Fails | The Production Rule |
| :--- | :--- | :--- | :--- |
| **1. PostgreSQL `PARTITION BY RANGE` (`Black Box 3A`)** | Declaring `PRIMARY KEY (obs_id)` on a table partitioned by `PARTITION BY RANGE (obs_time)` *(or using `'2026-10-31 23:59:59'` as the upper bound)*. | 1. PostgreSQL has **no global cross-partition B-Tree index** (each monthly partition has its own local B-Tree so `DETACH PARTITION` stays $O(1)$).<br/>2. `'23:59:59'` leaves a 1-second gap (`23:59:59.500` crashes ingestion!). | 1. **Always include the partition key (`obs_time`) in `PRIMARY KEY` / `UNIQUE`**: `PRIMARY KEY (obs_time, station_id)`.<br/>2. Always use **half-open bounds $[A, B)$**: `FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00')`. |
| **2. MongoDB Horizontal Sharding (`Black Box 4D`)** | Using PostgreSQL's single-column timestamp habit (`{ obs_time: 1 }`) as a **MongoDB Shard Key** (`sh.shardCollection(..., { obs_time: 1 })`). | In range sharding, the highest chunk holds `[T_latest, MaxKey)`. Since every live weather observation has $T_{\text{now}} > T_{\text{latest}}$, sharding on `{ obs_time: 1 }` routes **100% of live cluster writes to 1 single shard (`MaxKey` hotspot)**! | **Never shard purely on `{ obs_time: 1 }`!** Always lead with a high-cardinality prefix followed by time:<br/>**`sh.shardCollection("weather_nosql.synoptic_timeseries", { "station_meta.station_id": 1, obs_time: 1 })`**<br/>*(Distributes live writes across all shards by station while keeping each station's time-series contiguous for targeted range reads!)* |

---

> **Navigation:** [Bootcamp README](./README.md) | [SQL Basics & CRUD Guide](./SQL_BASICS_CRUD_GUIDE.md) | [MongoDB NoSQL Basics & CRUD Guide](./MONGODB_NOSQL_BASICS_CRUD_GUIDE.md) | [Interactive Portal](./bootcamp_portal.html) | [Day 3 Coursebook](./day3/day3_master_coursebook.md) | [Day 4 Coursebook](./day4/day4_master_coursebook.md)
