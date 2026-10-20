# Reference Card 00: SQL & MongoDB CRUD Fundamentals Hub & Cross-Engine Rosetta Stone

> **Navigation:** [Bootcamp README](../README.md) | [SQL Basics & CRUD Guide](../SQL_BASICS_CRUD_GUIDE.md) | [MongoDB NoSQL Basics Guide](../MONGODB_NOSQL_BASICS_CRUD_GUIDE.md) | [Interactive Portal](../bootcamp_portal.html) | [Reference Cards Index](./README.md)

---

## 1. Dedicated Root-Level Guides for SQL Basics & MongoDB NoSQL Basics

To give attendees two standalone, single-purpose hands-on playbooks without mixing SQL and NoSQL syntax in one document, the complete runnable CRUD tutorials are organized into two dedicated root-level guides:

| Dedicated Guide (Root Directory) | Engines & Databases Covered | Core Operations Covered |
| :--- | :--- | :--- |
| **1. [`SQL_BASICS_CRUD_GUIDE.md`](../SQL_BASICS_CRUD_GUIDE.md)**<br/>*(Dedicated SQL Basics Playbook — Days 1, 2 & 3)* | • **Day 1 SQLite:** `day1/weather_ops.db` (`stations`, `observations`, `forecasts`, `weather_alerts`) & `day1/weather_telemetry.db` (`raw_telemetry`, `250,000` rows)<br/>• **Days 2–3 PostgreSQL:** `weather_ops` (`synoptic.*`, `nwp.*`, `alerts.*`) & `weather_ops_db` (`5,000,000` rows) | • CLI inspection (`.tables`, `PRAGMA table_info`, `\dt+`, `\d+`)<br/>• `SELECT`, projections, math aliases, `DISTINCT`<br/>• `WHERE` (`=`, `!=`, `>=`, `BETWEEN`, `IN`, `LIKE`/`ILIKE`, `AND`/`OR`, `IS NULL`)<br/>• `ORDER BY`, `LIMIT`, `OFFSET`<br/>• `COUNT`, `MIN`, `MAX`, `AVG`, `SUM`, `GROUP BY`, `HAVING`, `INNER JOIN`, `LEFT JOIN`<br/>• `INSERT INTO`, `ON CONFLICT DO UPDATE` (Upsert), `UPDATE`, `DELETE`, `ON DELETE CASCADE`, and PostgreSQL `RETURNING` |
| **2. [`MONGODB_NOSQL_BASICS_CRUD_GUIDE.md`](../MONGODB_NOSQL_BASICS_CRUD_GUIDE.md)**<br/>*(Dedicated MongoDB NoSQL Basics Playbook — Day 4)* | • **Day 4 Operational MongoDB:** `weather_nosql` (`stations`, `synoptic_timeseries`, `radiosonde_soundings`, `cap_alerts`, `storm_polygons`)<br/>• **Day 4 50k Benchmark MongoDB:** `weather_telemetry_db` (`sensor_payloads`, `weather_stream`, `hourly_sensor_buckets`) | • `mongosh` navigation (`show dbs`, `use`, `db.getName()`, `show collections`, `countDocuments()`)<br/>• `findOne()`, `find()`, field projections (`1` / `0`), `.sort()`, `.limit()`, `.skip()`<br/>• Query operators (`$gt`, `$gte`, `$lt`, `$lte`, `$in`, `$or`, `$exists`, `$elemMatch`, nested `"parent.child"` dot notation)<br/>• `insertOne()` (with `$jsonSchema` compliance) & `insertMany()`<br/>• `updateOne()` & `updateMany()` (`$set`, `$inc`, `$addToSet`, `$push`, `$pull`, `{ upsert: true }`)<br/>• `deleteOne()` & `deleteMany()`<br/>• `aggregate()` pipelines (`$match`, `$group`, `$sort`, `$unwind`, `$lookup`) |

---

## 2. The Cross-Engine CRUD Rosetta Stone (`SQLite` vs. `PostgreSQL` vs. `MongoDB`)

| Operation | Day 1: SQLite (`sqlite3`) | Days 2–3: PostgreSQL (`psql`) | Day 4: MongoDB (`mongosh`) |
| :--- | :--- | :--- | :--- |
| **Check Current DB / File** | `.databases` | `\conninfo` | `db.getName()` / `show dbs` |
| **Switch DB / File** | `.open weather_ops.db` | `\c weather_ops` | `use weather_nosql` |
| **List Tables / Collections** | `.tables` | `\dt+ synoptic.*` (or `\dt *.*`) | `show collections` |
| **Inspect Schema / Sample Doc** | `.schema stations`<br/>`PRAGMA table_info('stations');` | `\d+ synoptic.stations` | `db.stations.findOne()` |
| **Show All Rows / Documents** | `SELECT * FROM stations;` | `SELECT * FROM synoptic.stations;` | `db.stations.find()` |
| **Show Specific Columns (Projection)** | `SELECT station_id, station_name FROM stations;` | `SELECT station_id, station_name FROM synoptic.stations;` | `db.stations.find({}, { station_name: 1 })` |
| **Filter (`WHERE` / Query Filter)** | `SELECT * FROM stations WHERE climate_zone = 'Arid';` | `SELECT * FROM synoptic.stations WHERE climate_zone = 'Arid';` | `db.stations.find({ climate_zone: "Arid" })` |
| **Sort & Limit (`ORDER BY` / `LIMIT`)** | `SELECT * FROM stations ORDER BY elevation_m DESC LIMIT 3;` | `SELECT * FROM synoptic.stations ORDER BY elevation_m DESC LIMIT 3;` | `db.stations.find().sort({ elevation_m: -1 }).limit(3)` |
| **Count Rows / Documents** | `SELECT COUNT(*) FROM observations;` | `SELECT COUNT(*) FROM synoptic.observations;` | `db.synoptic_timeseries.countDocuments()` |
| **Create (`INSERT` / `insertOne`)** | `INSERT INTO stations VALUES (...);` | `INSERT INTO synoptic.stations VALUES (...) RETURNING *;` | `db.stations.insertOne({ ... })` |
| **Update (`UPDATE` / `updateOne`)** | `UPDATE stations SET is_active = 1 WHERE station_id = 60402;` | `UPDATE synoptic.stations SET is_active = TRUE WHERE station_id = 60402 RETURNING *;` | `db.stations.updateOne({ _id: 60390 }, { $set: { is_active: true } })` |
| **Delete (`DELETE` / `deleteOne`)** | `DELETE FROM weather_alerts WHERE alert_id = 4;` | `DELETE FROM alerts.weather_alerts WHERE alert_id = 4 RETURNING *;` | `db.cap_alerts.deleteOne({ _id: "DZ-ONM-2026-10-05-002" })` |

---

> **Navigation:** [Open `SQL_BASICS_CRUD_GUIDE.md`](../SQL_BASICS_CRUD_GUIDE.md) | [Open `MONGODB_NOSQL_BASICS_CRUD_GUIDE.md`](../MONGODB_NOSQL_BASICS_CRUD_GUIDE.md) | [Reference Cards Index](./README.md)
