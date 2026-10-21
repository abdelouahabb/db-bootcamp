> **Navigation:** [Master README](../README.md) | [Interactive Portal](../bootcamp_portal.html) | [⬅ Day 3: PostgreSQL Scaling](../day3/day3_master_coursebook.md) | [Day 4 Coursebook](day4_master_coursebook.md) | [Day 5: Analytical OLAP & Lakehouse](../day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | [Reference Cards](../reference_cards/README.md)

# Day 4 Complete Cheatsheet: MongoDB CLI, SQL-to-MQL Translator, Time-Series, Aggregations, Geospatial `2dsphere` & `ESR` Indexing

**Bootcamp:** Weather Forecast & Meteorological Data Engineering (5-Day Intensive — Unified Best-of-Both Edition)  
**Companion to:**
- [../MONGODB_NOSQL_BASICS_CRUD_GUIDE.md](../MONGODB_NOSQL_BASICS_CRUD_GUIDE.md) — **Dedicated MongoDB NoSQL Basics & CRUD Guide (`find`, `insertOne`, `insertMany`, `updateOne`, `deleteOne`, `aggregate`)**
- [../POSTGIS_VS_MONGODB_GEOSPATIAL_AND_PARTITIONING_CHEATSHEET.md](../POSTGIS_VS_MONGODB_GEOSPATIAL_AND_PARTITIONING_CHEATSHEET.md) — **Dedicated Side-by-Side Cheatsheet: PostgreSQL `PostGIS` vs. MongoDB `2dsphere` & `PARTITION BY RANGE` vs. MongoDB Time-Series / Sharding**
- [day4_master_coursebook.md](./day4_master_coursebook.md)
- [day4_mongodb_architecture_ha_and_sharding_guide.md](./day4_mongodb_architecture_ha_and_sharding_guide.md)
- [day4_weather_ops_mongo.js](./day4_weather_ops_mongo.js) (`weather_nosql`: `stations`, `radiosonde_soundings`, `synoptic_timeseries`, `cap_alerts`)
- [day4_weather_ops_mongo_advanced.js](./day4_weather_ops_mongo_advanced.js) (`weather_nosql`: `storm_polygons`, `upper_air_climatology`, `2dsphere` & `idx_sonde_esr` indexes)
- [day4_mongo_50k_polymorphic_benchmark.js](./day4_mongo_50k_polymorphic_benchmark.js) (`weather_telemetry_db`: `sensor_payloads`, `weather_stream`, `hourly_sensor_buckets`)

---

## 1. Installing MongoDB Community Server & `mongosh`

### Option A: Ubuntu / Debian (Official MongoDB 7.0+ APT Repo)
```bash
sudo apt-get install -y gnupg curl
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
   sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

sudo apt-get update
sudo apt-get install -y mongodb-org

sudo systemctl enable --now mongod
sudo systemctl status mongod
```

### Option B: Docker (Fastest Local Lab Setup)
```bash
docker run -d \
  --name weather-mongo \
  -p 27017:27017 \
  -e TZ=UTC \
  -v mongo_weather_data:/data/db \
  mongo:7.0
```

### Running the Day 4 Seed & Benchmark Scripts
```bash
# 1. Operational stations, radiosonde soundings, time-series & CAP alerts
mongosh weather_nosql day4_weather_ops_mongo.js

# 2. Geospatial 2dsphere storm polygons, ESR indexes & upper-air aggregations
mongosh weather_nosql day4_weather_ops_mongo_advanced.js

# 3. 50,000-document polymorphic telemetry benchmark & hardware fault diagnostics
mongosh "mongodb://localhost:27017/weather_telemetry_db" day4_mongo_50k_polymorphic_benchmark.js

# Launch interactive shell
mongosh weather_nosql
```

---

## 2. Recommended `mongod.conf` Settings for Weather Workloads

Default config path on Linux: `/etc/mongod.conf`

```yaml
storage:
  dbPath: /var/lib/mongodb
  wiredTiger:
    engineConfig:
      # Allocate ~50% of (Total RAM - 1GB) to WiredTiger uncompressed cache.
      # On a 32GB server, 15GB is ideal; OS cache uses the remaining RAM for compressed blocks.
      cacheSizeGB: 15
      # Use zstd for best compression ratio (70%+) on repetitive weather telemetry!
      journalCompressor: zstd
    collectionConfig:
      blockCompressor: zstd

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
  timeStampFormat: iso8601-utc   # Mandatory UTC timestamps in server logs!

operationProfiling:
  mode: slowOp
  slowOpThresholdMs: 250         # Log queries taking > 250ms
```

---

## 3. SQL-to-MongoDB (`mongosh`) Translator for Weather Engineers

| Operation | PostgreSQL (SQL) | MongoDB (`mongosh`) |
| :--- | :--- | :--- |
| **Select All** | `SELECT * FROM stations;` | `db.stations.find()` |
| **Filter Equality** | `WHERE station_id = 60390` | `db.stations.find({ _id: 60390 })` |
| **Projection** | `SELECT station_name, elevation_m FROM ...` | `db.stations.find({}, { _id: 0, station_name: 1, elevation_m: 1 })` |
| **Range (`BETWEEN`)** | `WHERE temp_c BETWEEN 20 AND 35` | `db.synoptic_timeseries.find({ temp_c: { $gte: 20, $lte: 35 } })` |
| **`IN` List** | `WHERE climate_zone IN ('Arid', 'Highland')` | `db.stations.find({ climate_zone: { $in: ["Arid", "Highland"] } })` |
| **Logical `OR`** | `WHERE visibility < 1000 OR tke > 0.35` | `db.sensor_payloads.find({ $or: [{ visibility_meters: { $lt: 1000 } }, { turbulent_kinetic_energy: { $gt: 0.35 } }] })` |
| **Check `NULL` / Missing** | `WHERE soil_profile IS NOT NULL` | `db.synoptic_timeseries.find({ soil_profile: { $exists: true, $ne: null } })` |
| **Nested Object Filter** | `WHERE sensor_payload #>> '{diagnostics,door_open}' = 'true'` | `db.synoptic_timeseries.find({ "diagnostics.door_open": true })` |
| **Array Element Match** | `JOIN launch_levels ON ... WHERE p=500 AND wind>=60` | `db.radiosonde_soundings.find({ vertical_levels: { $elemMatch: { pressure_hpa: 500, wind_speed_kt: { $gte: 60 } } } })` |
| **Sort & Limit** | `ORDER BY wind_speed_kt DESC LIMIT 5` | `db.synoptic_timeseries.find().sort({ wind_speed_kt: -1 }).limit(5)` |
| **Update Specific Field** | `UPDATE stations SET is_active = true WHERE ...` | `db.stations.updateOne({ _id: 60402 }, { $set: { is_active: true } })` |
| **Update Peak Value** | `SET max_gust = GREATEST(max_gust, 43.5)` | `db.cap_alerts.updateOne({ _id: "..." }, { $max: { max_observed_gust_kt: 43.5 } })` |
| **Append to Array** | *(Requires child table `INSERT` or `jsonb_insert`)* | `db.cap_alerts.updateOne({ _id: "..." }, { $push: { updates: { note: "..." } } })` |
| **Unique Array Append** | *(Requires `DISTINCT` or unique child constraint)* | `db.cap_alerts.updateOne({ _id: "..." }, { $addToSet: { affected_stations: 60402 } })` |
| **Positional Array Update** | `UPDATE launch_levels SET dewpoint = -7.9 WHERE ...` | `db.radiosonde_soundings.updateOne({ station_id: 60680, "vertical_levels.pressure_hpa": 700 }, { $set: { "vertical_levels.$.dewpoint_c": -7.9 } })` |
| **Idempotent Upsert** | `INSERT ... ON CONFLICT DO UPDATE` | `db.stations.updateOne({ _id: 60390 }, { $set: { ... } }, { upsert: true })` |

### 3.1 Demystifying the `{ field: null }` Query Trap & `$jsonSchema` (Black Box 4A)
* **`$jsonSchema` Validation Rule:** Just like SQL's `NOT NULL` vs. `CHECK`, MongoDB separates **Key Presence** (`required: ["station_id", "temp_c"]`) from **Value Type/Domain** (`properties: { temp_c: { bsonType: "double" } }`). If a field is in `properties` with `bsonType: "double"` (and no `"null"` in `bsonType`), omitting the key entirely **passes** validation unless it is in `required`, whereas sending `{ temp_c: null }` **fails** validation (`null` is BSON Type `10`, not `"double"`).
* **The 4-Pattern MQL Null vs. Missing Field Query Matrix:**

| Query Pattern | Matches `{ temp_c: 24.5 }`? | Matches `{ temp_c: null }` (Explicit Null)? | Matches `{}` (Missing Key)? | Meteorological Use Case |
| :--- | :---: | :---: | :---: | :--- |
| **`{ temp_c: null }`** *(Ambiguous Default!)* | No | ** YES** | ** YES** | Catching all records lacking a temperature reading (whether omitted or explicitly `null`). |
| **`{ temp_c: { $type: 10 } }`** *(or `bsonType: "null"`)* | No | ** YES** | No | Finding stations that **have** a thermistor installed (`temp_c` key exists) but experienced a **sensor dropout (`null`)**. |
| **`{ temp_c: { $exists: false } }`** | No | No | ** YES** | Finding polymorphic stations (e.g., rain-only gauges) that **never send** a `temp_c` key. |
| **`{ temp_c: { $exists: true, $ne: null } }`** | ** YES** | No | No | Filtering for **present, non-null** readings before running math in `$project`. |

---

## 4. Native Time-Series Collection, Manual Buckets & TTL Quick Reference

```javascript
// 1. Create a compressed columnar Time-Series Collection with 90-day auto-expiration
db.createCollection("synoptic_timeseries", {
  timeseries: {
    timeField: "obs_time",       // Mandatory BSON ISODate() field
    metaField: "station_meta",   // Station identifier/metadata object used for bucketing
    granularity: "hours"         // "seconds" (1h span) | "minutes" (24h span) | "hours" (30d span)
  },
  expireAfterSeconds: 7776000    // Automatically delete buckets older than 90 days
});

// 2. Inspect physical columnar buckets under the hood
db.system.buckets.synoptic_timeseries.findOne();

// 3. Manual Bucket Pattern Upsert (Pre-aggregating 1Hz readings into 1-hour document buckets)
db.hourly_sensor_buckets.updateOne(
  { _id: "AWS-001_2026-10-04_H12", sample_count: { $lt: 3600 } },
  {
    $setOnInsert: {
      station_id: "AWS-001",
      bucket_start: ISODate("2026-10-04T12:00:00Z"),
      bucket_end: ISODate("2026-10-04T12:59:59Z")
    },
    $push: { measurements: { sec: 0, w: 4.1, temp: 18.2 } },
    $inc: { sample_count: 1, "summary.sum_w": 4.1 },
    $min: { "summary.min_w": 4.1 },
    $max: { "summary.max_w": 4.1 }
  },
  { upsert: true }
);
```

---

## 5. MongoDB Aggregation Pipeline Stages (`db.collection.aggregate([...])`)

| Stage | SQL Equivalent | Meteorological Use Case & Example |
| :--- | :--- | :--- |
| **`$match`** | `WHERE` | Filter early using indexes: `{ $match: { station_id: 60390, cape_j_kg: { $gte: 500 } } }` |
| **`$unwind`** | `UNNEST(array)` | Flatten upper-air radiosonde pressure levels or fault arrays: `{ $unwind: "$vertical_levels" }` |
| **`$addFields`** | Computed Column | Calculate dewpoint spread: `{ $addFields: { spread_c: { $subtract: ["$temp_c", "$dewpoint_c"] } } }` |
| **`$group`** | `GROUP BY` | Group by pressure level (`_id: "$vertical_levels.pressure_hpa"`) with `$avg`, `$min`, `$max`, `$sum`, `$addToSet` |
| **`$project`** | `SELECT` | Pick/rename fields & round numbers: `{ $project: { _id: 0, avg_temp: { $round: ["$avg_temp", 1] } } }` |
| **`$lookup`** | `LEFT JOIN` | Join time-series observations with `stations` collection metadata |
| **`$sort` / `$limit`** | `ORDER BY` / `LIMIT` | `{ $sort: { wind_speed_kt: -1 } }, { $limit: 10 }` |
| **`$merge`** | `MATERIALIZED VIEW` | Save aggregated climatology into a target collection (`{ $merge: { into: "upper_air_climatology" } }`) |

### 5.1 Demystifying `$unwind`: Default `INNER JOIN` vs. `preserveNullAndEmptyArrays` `LEFT JOIN` (Black Box 4B)
| `$unwind` Syntax | SQL Equivalent | Document with `[A, B]` | Document with `[]` (Empty) or `null` / Missing | When to Use |
| :--- | :--- | :--- | :--- | :--- |
| **`{ $unwind: "$hardware_faults" }`** | `INNER JOIN UNNEST(...)` | Emits 2 docs | **SILENTLY DROPPED (`0` docs)** | Fault-only reports where healthy stations (`[]`) should be excluded. |
| **`{ $unwind: { path: "$hardware_faults", preserveNullAndEmptyArrays: true } }`** | `LEFT JOIN UNNEST(...)` | Emits 2 docs | **PRESERVED (`1` doc with `hardware_faults: null`)** | **Fleet-wide health dashboards** where healthy stations (`0` faults) must remain in the denominator! |

---

## 6. Geospatial Meteorology (`2dsphere` Indexes & GeoJSON)

> [!IMPORTANT]
> **Production Pitfall (GeoJSON Coordinate Order & Closed Polygon Rings):**  
> GeoJSON coordinates are **always `[longitude, latitude]`** (`[-180..180, -90..90]`), never `[lat, lon]`! Furthermore, the first and last coordinate pair of a `Polygon` exterior ring **must be identical** to close the loop, or `createIndex({ footprint: "2dsphere" })` will reject the document with a geometry validation error.

```javascript
// 1. Create a 2dsphere index on Point or Polygon fields
db.stations.createIndex({ location: "2dsphere" });
db.storm_polygons.createIndex({ footprint: "2dsphere" });

// 2. Proximity Search ($geoNear): Find stations within 250 km of a cyclone center
db.stations.aggregate([
  {
    $geoNear: {
      near: { type: "Point", coordinates: [3.30, 36.80] }, // [lon, lat]
      distanceField: "distance_km",
      maxDistance: 250000,          // Meters (250 km)
      distanceMultiplier: 0.001,    // Output in km
      spherical: true
    }
  }
]);

// 3. Polygon Containment ($geoWithin): Find all stations inside a radar storm cell polygon
db.stations.find({
  location: {
    $geoWithin: {
      $geometry: {
        type: "Polygon",
        coordinates: [[[2.5, 35.8], [7.2, 35.8], [7.2, 37.1], [2.5, 37.1], [2.5, 35.8]]]
      }
    }
  }
});

// 4. Polygon Intersection ($geoIntersects): Which storm polygon covers a specific airport?
db.storm_polygons.find({
  footprint: {
    $geoIntersects: {
      $geometry: { type: "Point", coordinates: [6.6203, 36.2760] }
    }
  }
});
```

---

## 7. Indexing Strategy: The `ESR` Rule & `explain("executionStats")`

### The `ESR` (Equality $\rightarrow$ Sort $\rightarrow$ Range) Compound Index Rule
When indexing a query like:
*"Find soundings for **`station_id = 60390`** (Equality), ordered by **`launch_time DESC`** (Sort), where **`cape_j_kg >= 500`** (Range)"*

```javascript
// Always order index keys: 1st Equality, 2nd Sort, 3rd Range!
db.radiosonde_soundings.createIndex({
  station_id: 1,     // E: Equality (pins exact B-Tree partition)
  launch_time: -1,   // S: Sort (eliminates blocking 100MB RAM SORT stage!)
  cape_j_kg: 1       // R: Range (evaluates inequality within pre-sorted branch)
}, { name: "idx_sonde_esr" });

// Multikey Index (Automatically indexes every element of an array field):
db.cap_alerts.createIndex({ affected_stations: 1 });
```

### Reading `.explain("executionStats")`
| Metric / Stage | PostgreSQL (`EXPLAIN ANALYZE`) | MongoDB (`explain("executionStats")`) |
| :--- | :--- | :--- |
| Full Table / Collection Scan | `Seq Scan` | `COLLSCAN` (missing index!) |
| B-Tree Index Scan | `Index Scan` | `IXSCAN` $\rightarrow$ `FETCH` |
| Index-Only Covered Scan | `Index Only Scan (Heap Fetches: 0)` | `PROJECTION_COVERED` (`totalDocsExamined: 0`) |
| In-Memory Sort (Slow!) | `Sort (Sort Method: external merge)` | `SORT` stage (aborts if > 100MB RAM unless indexed!) |

- **Efficiency Check:** `executionStats.nReturned` should be as close as possible to `executionStats.totalKeysExamined` and `executionStats.totalDocsExamined`.

> [!TIP]
> **Execution Plan Verification Tip (Spotting the Blocking `SORT` Stage):**  
> Compare `.explain("executionStats")` on a query with a misordered index (`{ station_id: 1, cape_j_kg: 1, launch_time: -1 }`) against the proper ESR index (`{ station_id: 1, launch_time: -1, cape_j_kg: 1 }`). With the ESR key order, the blocking in-memory `SORT` stage vanishes completely from `winningPlan`.

---

## 8. Replica Set Failover, `w: 1` Rollback Hazard & Shard Key Decision Matrix (Black Boxes 4C & 4D)

### 8.1 PostgreSQL (`Patroni`) vs. MongoDB (`Replica Set`) Failover & The `w: 1` Rollback Trap (Black Box 4C)
* **Built-In Raft Election vs. External Patroni/etcd:** While PostgreSQL streams physical 8 KB WAL bytes and relies on external `Patroni` + `etcd` + `HAProxy` for failover, a 3-node MongoDB Replica Set replicates logical idempotent BSON ops via `local.oplog.rs`, runs a **built-in Raft election** (`electionTimeoutMillis: 10000`), and relies on **topology-aware smart drivers (`replicaSet=rs_meteo&retryWrites=true`)** to auto-route writes to the new Primary in $< 10\text{s}$ without external proxies.
* **Why `w: 1` Causes Post-Failover Rollbacks (`rollback/` BSON files):** If Primary `node1` acknowledges a write with `{ w: 1 }` and loses power 30 ms later *before* `node2`/`node3` pull that oplog entry, `node2` is elected Primary without that document. When `node1` recovers, it **deletes ("rolls back")** its unreplicated `w: 1` writes! Always use **`{ w: "majority", j: true }`** for life-safety `cap_alerts` and `stations` (`RPO = 0`, zero rollbacks).

### 8.2 The 4-Pattern MongoDB Shard Key Decision Matrix (Black Box 4D)
| Pattern | Shard Key Declaration | Live Write Distribution | Station + Time Range Query (`station_id = X AND obs_time BETWEEN ...`) | Risk of Jumbo Chunks? | Engineering Verdict |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **1. Monotonic Timestamp** *(Anti-Pattern)* | `{ obs_time: 1 }` *(or `ObjectId`)* | ** 100% on 1 Shard (`MaxKey` Hotspot!)** — All new writes hit the single highest chunk. | Broadcasts across all stations in that time chunk. | Low | **NEVER USE for live telemetry.** Turns a 10-shard cluster into a 1-shard bottleneck. |
| **2. Low-Cardinality Enum** *(Anti-Pattern)* | `{ station_type: 1 }` or `{ radar_site_id: 1 }` *(4–8 values)* | Capped at 4–8 chunks total. | Scatter-Gather unless `station_type` is in every query. | ** YES (Fatal Jumbo Chunks!)** | **NEVER USE alone.** Chunks with identical key values cannot be split past 64 MB. |
| **3. Hashed Single Key** | `{ station_id: "hashed" }` *(or `{ obs_time: "hashed" }`)* | ** 100% Evenly Distributed** via MD5 hash. | `station_id: "hashed"` targets 1 shard for equality, **but `obs_time: "hashed"` forces Scatter-Gather on EVERY time-range query!** | Low | Use `{ sensor_uuid: "hashed" }` only for point lookups; **never hash `obs_time`**. |
| **4. Compound Prefix + Time** *(Production Gold Standard)* | **`{ "station_meta.station_id": 1, obs_time: 1 }`** | ** Evenly Distributed** across all shards simultaneously by `station_id`. | ** Targeted Single-Shard Scan!** `station_id` pins 1 shard; `obs_time: 1` scans contiguous chronological pages! | **Zero** (`obs_time` splits any large station) | **MANDATORY for meteorological time-series, radiosondes & radar scans.** |

---

## 9. Cross-Engine Comparison: SQLite vs. PostgreSQL vs. MongoDB

| Dimension | SQLite (Edge Tier) | PostgreSQL 16 (Relational & Spatial Core) | MongoDB 7 (Polymorphic & Time-Series Document Tier) |
| :--- | :--- | :--- | :--- |
| **Engine Model** | Serverless single-file (`weather_ops.db`) | Client-Server Relational + `JSONB` + `PostGIS` | Distributed Document & Time-Series (`mongod` / `mongos`) |
| **Storage Internals** | B-Tree pages in 1 file + WAL mode | 8KB Heap Pages (`ctid`), TOAST, MVCC (`xmin`/`xmax`) | WiredTiger compressed BSON blocks (`zstd`) & `system.buckets` |
| **Concurrency** | 1 writer at a time (file/WAL lock) | MVCC (readers/writers never block) + `autovacuum` | Document-level locking (hazard pointers) + in-place updates |
| **Time-Series Scale** | Up to ~10–50 GB local edge buffer | **Declarative Range Partitioning** + **BRIN Indexes** | **Native Time-Series Collections** + **TTL Expiration** + **Sharding** |
| **Ideal Weather Use Case** | Remote AWS/buoy local buffer surviving satellite outages | Official WMO synoptic archive, NWP verification (`JOIN`s, Window Functions $\Delta P_{3\text{h}}$) | Upper-air radiosonde profiles (`vertical_levels` arrays), polymorphic buoys/agro/3D-sonic IoT, GeoJSON storm alerts |

---

> **Navigation:** [Master README](../README.md) | [Interactive Portal](../bootcamp_portal.html) | [⬅ Day 3: PostgreSQL Scaling](../day3/day3_master_coursebook.md) | [Day 4 Coursebook](day4_master_coursebook.md) | [Day 5: Analytical OLAP & Lakehouse](../day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | [Reference Cards](../reference_cards/README.md)
