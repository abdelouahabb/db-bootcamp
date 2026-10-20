# Dedicated MongoDB NoSQL Basics & CRUD Guide (`find`, `insertOne`, `updateOne`, `deleteOne`, `aggregate`)

> **Navigation:** [Bootcamp README](./README.md) | [SQL Basics & CRUD Guide](./SQL_BASICS_CRUD_GUIDE.md) | [Interactive Portal](./bootcamp_portal.html) | [Day 4 Master Coursebook](./day4/day4_master_coursebook.md) | [Day 4 MongoDB Cheatsheet](./day4/day4_mongodb_complete_cheatsheet.md)

---

## 1. Purpose of This Dedicated MongoDB NoSQL Basics Guide

Before diving into BSON binary encoding, `$jsonSchema` validation traps, Time-Series bucket internals, or 3-node Replica Set elections, every attendee needs **100% fluency in the core daily MongoDB (`mongosh`) commands to inspect databases, query documents, filter nested objects and arrays, insert, update, delete, and aggregate data (`CRUD`)** on the exact MongoDB databases used on Day 4 of this bootcamp.

Every single `mongosh` block in this guide is **copy-and-paste runnable** against the actual Day 4 MongoDB databases:
- **Part I — Operational WMO & Radiosonde Database (`weather_nosql`)** seeded by [`day4/day4_weather_ops_mongo.js`](./day4/day4_weather_ops_mongo.js) and [`day4/day4_weather_ops_mongo_advanced.js`](./day4/day4_weather_ops_mongo_advanced.js)
- **Part II — 50,000-Document Polymorphic Sensor Database (`weather_telemetry_db`)** seeded by [`day4/day4_mongo_50k_polymorphic_benchmark.js`](./day4/day4_mongo_50k_polymorphic_benchmark.js)

---

## 2. Master MongoDB Orientation Map: Which Database, JS Script & Collections Am I Using?

| Day 4 JS Seed Script | How to Seed & Connect from Terminal | Target MongoDB Database | Exact Collections & Document Fields Inside |
| :--- | :--- | :--- | :--- |
| **1. [`day4/day4_weather_ops_mongo.js`](./day4/day4_weather_ops_mongo.js)**<br/>*(Main Operational Seed)* | ```bash\ncd day4\nmongosh weather_nosql day4_weather_ops_mongo.js\nmongosh weather_nosql\n``` | **`weather_nosql`**<br/>*(Switch in `mongosh`: `use weather_nosql`)* | • **`db.stations`** (`6` docs): `_id` *(Int32: `60390`..)*, `station_name`, `station_type`, `climate_zone`, `elevation_m`, `is_active`, `location` *(GeoJSON `[lon, lat]`)*, `sensors` *(Array)*, `calibration`, `buoy_specs`, `soil_depths_cm`<br/>• **`db.synoptic_timeseries`** (`6` docs): `obs_time`, `station_meta` *(`station_id`, `station_type`, `climate_zone`)*, `temp_c`, `dewpoint_c`, `pressure_hpa`, `wind_speed_kt`, `precip_1h_mm`, `soil_profile`, `marine_telemetry`, `aerosol_telemetry`, `diagnostics`<br/>• **`db.radiosonde_soundings`** (`3` docs): `station_id`, `station_name`, `launch_time`, `sonde_serial`, `burst_altitude_m`, `cape_j_kg`, `k_index`, `vertical_levels` *(Array of pressure levels)*<br/>• **`db.cap_alerts`** (`2` docs): `_id` *(String)*, `issued_at`, `expires_at`, `phenomenon`, `severity`, `certainty`, `affected_stations` *(Array)*, `max_observed_gust_kt`, `headline` |
| **2. [`day4/day4_weather_ops_mongo_advanced.js`](./day4/day4_weather_ops_mongo_advanced.js)**<br/>*(Geospatial & Aggregations)* | ```bash\ncd day4\nmongosh weather_nosql day4_weather_ops_mongo_advanced.js\n``` | **`weather_nosql`**<br/>*(Switch in `mongosh`: `use weather_nosql`)* | • **`db.storm_polygons`** (`2` docs): `_id`, `storm_name`, `valid_from`, `valid_until`, `max_reflectivity_dbz`, `vil_kg_m2`, `footprint` *(GeoJSON `Polygon`)*<br/>• **`db.upper_air_climatology`** (`6` docs): `_id` *(`station_id`, `pressure_hpa`)*, `sample_count`, `mean_temp_c`, `max_wind_kt`, `mean_height_m` |
| **3. [`day4/day4_mongo_50k_polymorphic_benchmark.js`](./day4/day4_mongo_50k_polymorphic_benchmark.js)**<br/>*(50k Polymorphic Benchmark)* | ```bash\ncd day4\nmongosh "mongodb://localhost:27017/weather_telemetry_db" day4_mongo_50k_polymorphic_benchmark.js\nmongosh weather_telemetry_db\n``` | **`weather_telemetry_db`**<br/>*(Switch in `mongosh`: `use weather_telemetry_db`)* | • **`db.sensor_payloads`** (`50,000` docs): `metadata.station_id`, `metadata.sensor_type` *(`METAR_STANDARD`, `ULTRASONIC_3D`, `PRESENT_WEATHER_OPTICAL`, `ROAD_SURFACE_RADAR`)*, `metadata.region`, `timestamp`, `hardware_faults`, `temperature`, `pressure`, `relative_humidity`, `turbulent_kinetic_energy`, `visibility_meters`, `surface_temp`, `subsurface_temp_5cm`, `water_film_height_mm`, `grip_factor`<br/>• **`db.weather_stream`** (`50,000` docs in Native Time-Series collection)<br/>• **`db.hourly_sensor_buckets`** (Hourly Manual Bucket Pattern docs) |

---

## 3. SQL-to-MongoDB (`mongosh`) Side-by-Side Translator Table

| Database Operation | SQL (`SQLite` / `PostgreSQL`) | MongoDB NoSQL (`mongosh`) |
| :--- | :--- | :--- |
| **Show All Databases** | `\l` (psql) / `.databases` (sqlite3) | `show dbs` |
| **Check Current Active Database** | `SELECT current_database();` | `db.getName()` |
| **Switch Database** | `\c weather_ops` | `use weather_nosql` |
| **List All Tables / Collections** | `\dt` / `.tables` | `show collections` |
| **Show 1 Sample Row / Document** | `SELECT * FROM stations LIMIT 1;` | `db.stations.findOne()` |
| **Show All Rows / Documents** | `SELECT * FROM stations;` | `db.stations.find().toArray()` |
| **Select Specific Columns (Projection)** | `SELECT station_name, climate_zone FROM stations;` | `db.stations.find({}, { station_name: 1, climate_zone: 1 })` |
| **Filter Exact Match (`=`)** | `SELECT * FROM stations WHERE climate_zone = 'Arid';` | `db.stations.find({ climate_zone: "Arid" })` |
| **Filter Greater / Less Than (`>=`, `<`)** | `SELECT * FROM stations WHERE elevation_m >= 500;` | `db.stations.find({ elevation_m: { $gte: 500 } })` |
| **Filter Range (`BETWEEN`)** | `SELECT * FROM synoptic_timeseries WHERE wind_speed_kt BETWEEN 20 AND 35;` | `db.synoptic_timeseries.find({ wind_speed_kt: { $gte: 20, $lte: 35 } })` |
| **Filter Set Membership (`IN`)** | `SELECT * FROM stations WHERE station_type IN ('AGRO_SOIL', 'COASTAL_BUOY');` | `db.stations.find({ station_type: { $in: ["AGRO_SOIL", "COASTAL_BUOY"] } })` |
| **Sort & Limit (`ORDER BY` + `LIMIT`)** | `SELECT * FROM stations ORDER BY elevation_m DESC LIMIT 3;` | `db.stations.find().sort({ elevation_m: -1 }).limit(3)` |
| **Count Rows / Documents** | `SELECT COUNT(*) FROM stations WHERE is_active = TRUE;` | `db.stations.countDocuments({ is_active: true })` |
| **Insert 1 Row / Document** | `INSERT INTO stations VALUES (...);` | `db.stations.insertOne({ _id: Int32(60580), ... })` |
| **Insert Multiple Rows / Documents** | `INSERT INTO synoptic_timeseries VALUES (...), (...);` | `db.synoptic_timeseries.insertMany([ { ... }, { ... } ])` |
| **Update Scalar Field (`SET`)** | `UPDATE stations SET elevation_m = 142.5 WHERE _id = 60580;` | `db.stations.updateOne({ _id: 60580 }, { $set: { elevation_m: 142.5 } })` |
| **Increment Number (`SET x = x + 2.5`)** | `UPDATE cap_alerts SET max_observed_gust_kt = max_observed_gust_kt + 2.5 WHERE ...;` | `db.cap_alerts.updateOne({ _id: "..." }, { $inc: { max_observed_gust_kt: 2.5 } })` |
| **Delete 1 or Many (`DELETE FROM`)** | `DELETE FROM stations WHERE _id = 60580;` | `db.stations.deleteOne({ _id: 60580 })` / `deleteMany({ ... })` |
| **Aggregate (`GROUP BY`)** | `SELECT climate_zone, COUNT(*) FROM stations GROUP BY climate_zone;` | `db.stations.aggregate([{ $group: { _id: "$climate_zone", count: { $sum: 1 } } }])` |

---

# PART I: MongoDB NoSQL Basics on `weather_nosql` (`day4_weather_ops_mongo.js`)

## 1.1 Connecting & Inspecting Collections in `mongosh` ("Show Me the Documents!")

First, seed `weather_nosql` (if you haven't already) and open `mongosh`:

```bash
cd day4
mongosh weather_nosql day4_weather_ops_mongo.js
mongosh weather_nosql
```

Run inside `mongosh`:

```javascript
// TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

// 1. Show all databases on the MongoDB server and verify your active database:
show dbs;
db.getName();

// 2. List all collections in 'weather_nosql':
show collections;

// 3. Count documents in all 4 collections:
printjson({
  stations: db.stations.countDocuments(),
  synoptic_timeseries: db.synoptic_timeseries.countDocuments(),
  radiosonde_soundings: db.radiosonde_soundings.countDocuments(),
  cap_alerts: db.cap_alerts.countDocuments()
});

// 4. Inspect a single sample document from each collection using findOne():
db.stations.findOne();
db.synoptic_timeseries.findOne();
db.radiosonde_soundings.findOne();
db.cap_alerts.findOne();
```

---

## 1.2 Basic Read (`find()` & `findOne()`) — Filtering, Projection, Nested Fields, Arrays & Sorting

In MongoDB:
- `db.collection.find(<filter>, <projection>)` is the equivalent of `SELECT <projection> FROM collection WHERE <filter>`.
- `.sort({ field: 1 })` = `ORDER BY field ASC` (`-1` = `DESC`).
- `.limit(N)` = `LIMIT N` and `.skip(N)` = `OFFSET N`.

```javascript
// TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

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

// 8. Logical AND / OR ($and, $or):
//    Find stations that are either in the 'Highland' climate zone OR above 1,000 meters:
db.stations.find(
  {
    $or: [
      { climate_zone: "Highland" },
      { elevation_m: { $gt: 1000 } }
    ]
  },
  { station_name: 1, climate_zone: 1, elevation_m: 1 }
).toArray();

// 9. Querying Nested Sub-Documents Using Dot Notation ("parent.child"):
//    Always wrap dotted field paths in quotes!
db.stations.find(
  { "calibration.technician": "M. Benali" },
  { station_name: 1, calibration: 1 }
).toArray();

db.synoptic_timeseries.find(
  { "station_meta.station_id": 60390 },
  { _id: 0, obs_time: 1, temp_c: 1, pressure_hpa: 1, wind_speed_kt: 1, "diagnostics.battery_v": 1 }
).toArray();

// 10. Polymorphic Field Existence ($exists):
//     Find only telemetry documents that contain marine buoy wave data or agro soil data!
db.synoptic_timeseries.find({ marine_telemetry: { $exists: true } }).toArray();
db.synoptic_timeseries.find({ soil_profile: { $exists: true } }).toArray();

// 11. Querying Arrays (Match any document whose array contains a value):
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

// 12. Querying Arrays of Objects with $elemMatch:
//     Find radiosonde balloon launches where the 500 hPa level had wind_speed_kt >= 55:
db.radiosonde_soundings.find(
  {
    vertical_levels: {
      $elemMatch: { pressure_hpa: 500, wind_speed_kt: { $gte: 55 } }
    }
  },
  { _id: 0, station_id: 1, station_name: 1, launch_time: 1, cape_j_kg: 1 }
).toArray();

// 13. Sorting & Limiting (.sort() and .limit()):
//     Equivalent to: ORDER BY elevation_m DESC LIMIT 3
db.stations.find(
  {},
  { station_name: 1, climate_zone: 1, elevation_m: 1 }
).sort({ elevation_m: -1 }).limit(3).toArray();
```

---

## 1.3 Basic Create (`insertOne()` & `insertMany()`) in MongoDB

> [!IMPORTANT]
> **Schema Validation Note on `db.stations`:** Recall from [`day4/day4_weather_ops_mongo.js`](./day4/day4_weather_ops_mongo.js) that `db.stations` has a `$jsonSchema` validator requiring `_id` (`Int32`), `station_name` (`string`), `station_type` (`"SURFACE_AWS"`, `"COASTAL_BUOY"`, `"UPPER_AIR_RADIOSONDE"`, or `"AGRO_SOIL"`), `is_active` (`bool`), and `location` (`{ type: "Point", coordinates: [lon, lat] }`).

```javascript
// TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

// Safe pre-cleanup in case you run this insert block more than once:
db.stations.deleteOne({ _id: 60580 });
db.synoptic_timeseries.deleteMany({ "station_meta.station_id": 60580 });

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

## 1.4 Basic Update (`updateOne()`, `updateMany()`, Upsert — `$set`, `$inc`, `$addToSet`, `$push`, `$pull`)

> [!WARNING]
> **Critical MongoDB Rule:** Always use atomic update operators (`$set`, `$inc`, `$push`, `$addToSet`, `$pull`) inside `updateOne()` / `updateMany()`!

```javascript
// TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

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

// 2. $addToSet — Add a new sensor to the 'sensors' array (without duplicates):
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

## 1.5 Basic Delete (`deleteOne()` & `deleteMany()`) in MongoDB

```javascript
// TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

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

## 1.6 Basic Aggregation Pipeline (`$match` -> `$group` -> `$sort`) — MongoDB's `GROUP BY` & `JOIN`

In SQL, you write `SELECT climate_zone, COUNT(*), AVG(elevation_m) FROM stations WHERE is_active = 1 GROUP BY climate_zone ORDER BY count DESC;`.  
In MongoDB, you pass an array of pipeline stages to `db.collection.aggregate([ ... ])`:

```javascript
// TARGET DATABASE: MongoDB 'weather_nosql' (mongosh weather_nosql)
// PREREQUISITE SCRIPT: day4/day4_weather_ops_mongo.js

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

# PART II: Exploring the 50,000-Document Polymorphic Database (`weather_telemetry_db`)

When you run [`day4/day4_mongo_50k_polymorphic_benchmark.js`](./day4/day4_mongo_50k_polymorphic_benchmark.js), MongoDB creates a second database named **`weather_telemetry_db`** containing `50,000` polymorphic sensor documents across 4 instrument types (`METAR_STANDARD`, `ULTRASONIC_3D`, `PRESENT_WEATHER_OPTICAL`, `ROAD_SURFACE_RADAR`).

```bash
cd day4
mongosh "mongodb://localhost:27017/weather_telemetry_db" day4_mongo_50k_polymorphic_benchmark.js
mongosh weather_telemetry_db
```

Run inside `mongosh`:

```javascript
// TARGET DATABASE: MongoDB 'weather_telemetry_db' (mongosh weather_telemetry_db)
// PREREQUISITE SCRIPT: day4/day4_mongo_50k_polymorphic_benchmark.js

use weather_telemetry_db;
show collections;

// 1. Count total documents across the 3 collections:
printjson({
  sensor_payloads: db.sensor_payloads.countDocuments(),
  weather_stream: db.weather_stream.countDocuments(),
  hourly_sensor_buckets: db.hourly_sensor_buckets.countDocuments()
});

// 2. Inspect 1 sample document from each of the 4 polymorphic sensor types:
db.sensor_payloads.findOne({ "metadata.sensor_type": "METAR_STANDARD" });
db.sensor_payloads.findOne({ "metadata.sensor_type": "ULTRASONIC_3D" });
db.sensor_payloads.findOne({ "metadata.sensor_type": "PRESENT_WEATHER_OPTICAL" });
db.sensor_payloads.findOne({ "metadata.sensor_type": "ROAD_SURFACE_RADAR" });

// 3. Count how many documents exist per sensor_type using aggregate():
db.sensor_payloads.aggregate([
  {
    $group: {
      _id: "$metadata.sensor_type",
      doc_count: { $sum: 1 }
    }
  },
  { $sort: { doc_count: -1 } }
]).toArray();

// 4. Filter ROAD_SURFACE_RADAR sensors for wet road / reduced grip risk (water_film_height_mm > 1.0 and grip_factor < 0.75):
db.sensor_payloads.find(
  {
    "metadata.sensor_type": "ROAD_SURFACE_RADAR",
    water_film_height_mm: { $gt: 1.0 },
    grip_factor: { $lt: 0.75 }
  },
  {
    _id: 0,
    "metadata.station_id": 1,
    timestamp: 1,
    surface_temp: 1,
    subsurface_temp_5cm: 1,
    water_film_height_mm: 1,
    grip_factor: 1
  }
).sort({ grip_factor: 1 }).limit(5).toArray();
```

---

> **Navigation:** [Bootcamp README](./README.md) | [SQL Basics & CRUD Guide](./SQL_BASICS_CRUD_GUIDE.md) | [Interactive Portal](./bootcamp_portal.html) | [Day 4 Master Coursebook](./day4/day4_master_coursebook.md) | [Day 4 MongoDB Cheatsheet](./day4/day4_mongodb_complete_cheatsheet.md)
