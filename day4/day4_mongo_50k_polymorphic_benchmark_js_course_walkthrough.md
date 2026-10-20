# Day 4 Course Walkthrough: `day4_mongo_50k_polymorphic_benchmark.js` — 50,000 Polymorphic Telemetry Benchmark, Bucket Pattern & `$unwind` Hardware Fault Diagnostics

[Home](../README.md) | [Portal](../bootcamp_portal.html) | [Day 4 Coursebook](./day4_master_coursebook.md) | [Blank VM Lab Guide](../VM_BLANK_LAB_FROM_SCRATCH_GUIDE.md) | [Original Script](./day4_mongo_50k_polymorphic_benchmark.js) | [Seed Script Walkthrough](./day4_weather_ops_mongo_js_course_walkthrough.md) | [Advanced Script Walkthrough](./day4_weather_ops_mongo_advanced_js_course_walkthrough.md)

---

## Architectural Overview

[`day4_mongo_50k_polymorphic_benchmark.js`](./day4_mongo_50k_polymorphic_benchmark.js) is a self-contained performance engineering and physical storage benchmark script targeting the **`weather_telemetry_db`** database. It synthesizes **50,000 polymorphic weather telemetry documents** across 50 Automated Weather Stations (`AWS-001` through `AWS-050`) spanning three Algerian climate regions (`COASTAL_MED`, `TELL_ATLAS`, `SAHARA_PLATEAU`) and four fundamentally different instrument classes.

The script executes five end-to-end architectural validations:

1. **Dual-Collection 50,000-Document Ingestion Benchmark:** Writes the exact same 50,000 polymorphic payloads in 5,000-document unordered batches into both a **Standard BSON Collection (`sensor_payloads`)** with compound ESR + Multikey indexes and a **Native MongoDB Time-Series Collection (`weather_stream`)** configured with `granularity: "seconds"`.
2. **Manual Bucket Pattern Atomic Upsert (`hourly_sensor_buckets`):** Demonstrates how to roll up high-frequency (1 Hz) readings into pre-aggregated hourly documents (`sample_count: { $lt: 3600 }`) using a single atomic `updateOne(..., { upsert: true })` combining `$setOnInsert`, `$push`, `$inc`, `$min`, and `$max`.
3. **Road Surface Radar Grip Safety Aggregation Pipeline:** Filters `ROAD_SURFACE_RADAR` sensors experiencing standing water (`water_film_height_mm > 0.5`), deduplicates reporting station IDs per region via `$addToSet` + `$size`, and ranks regional hydroplaning risk by `avg_grip_factor`.
4. **`$unwind` Hardware Fault Diagnostics Pipeline:** Isolates the ~6% of transmissions carrying `hardware_faults` arrays, unpacks multi-fault arrays via `$unwind`, and groups by composite `_id: { region, fault_code }` to identify the top 10 recurring hardware failures across the network.
5. **Physical Storage Compression Audit (`stats()`):** Compares uncompressed logical BSON size (`stdStats.size`), WiredTiger block-compressed disk size (`stdStats.storageSize`), B-Tree index overhead (`stdStats.totalIndexSize`), and native Time-Series columnar bucket footprint (`tsStats.storageSize`).

```mermaid
flowchart TD
    Gen["50,000 Polymorphic Payload Generator\n• 50 Stations (AWS-001..AWS-050)\n• 4 Sensor Classes (i % 4)\n• ~6% Hardware Fault Array Injection"]

    Gen -->|"insertMany(batch, {ordered: false})\nBATCH_SIZE = 5000"| Std["Standard Collection:\nsensor_payloads\n• 3 B-Tree / Multikey Indexes\n• Row-wise Snappy Block Compression"]
    Gen -->|"insertMany(batch, {ordered: false})\nBATCH_SIZE = 5000"| TS["Native Time-Series:\nweather_stream\n• timeField: timestamp | metaField: metadata\n• Columnar Zstandard Buckets"]

    Std --> Agg1["Pipeline 3: Road Surface Grip Safety\n$match -> $group ($addToSet) -> $project ($size) -> $sort"]
    Std --> Agg2["Pipeline 4: Hardware Fault Diagnostics\n$match -> $unwind -> $group -> $project -> $sort -> $limit 10"]
    Std & TS --> Audit["Section 5: Physical Storage Audit\nstdStats.storageSize vs tsStats.storageSize"]
```

---

## Section 1: 50,000-Document Polymorphic Telemetry Generator & Dual-Collection Ingestion (Lines 1–147)

### 1.1 Database Initialization, Dual-Collection Setup & Index Definitions (Lines 1–35)

```javascript
// ============================================================================
// DAY 4 BOOTCAMP: 50,000 POLYMORPHIC TELEMETRY BENCHMARK, BUCKET PATTERN &
//                 $UNWIND HARDWARE FAULT DIAGNOSTICS
// File: day4_mongo_50k_polymorphic_benchmark.js
// Usage: mongosh "mongodb://localhost:27017/weather_telemetry_db" day4_mongo_50k_polymorphic_benchmark.js
// ============================================================================

const DB_NAME = "weather_telemetry_db";
const TOTAL_DOCUMENTS = 50000;
const BATCH_SIZE = 5000;

const dbTarget = db.getSiblingDB(DB_NAME);

print(`[*] Initializing database: ${DB_NAME}...`);

// 1. Recreate Collections
dbTarget.sensor_payloads.drop();
dbTarget.weather_stream.drop();
dbTarget.hourly_sensor_buckets.drop();

// Create native time-series collection with columnar compression & 90-day TTL expiration
dbTarget.createCollection("weather_stream", {
  timeseries: {
    timeField: "timestamp",
    metaField: "metadata",
    granularity: "seconds"
  },
  expireAfterSeconds: 7776000
});

// Create ESR compound indexes on standard polymorphic collection
dbTarget.sensor_payloads.createIndex({ "metadata.station_id": 1, "timestamp": -1 });
dbTarget.sensor_payloads.createIndex({ "metadata.sensor_type": 1 });
dbTarget.sensor_payloads.createIndex({ "hardware_faults": 1 });
```

#### Deep-Dive Architectural Explanation

* **Lines 8–12 (Constants & Database Handle):**
  * Defines `DB_NAME = "weather_telemetry_db"`, `TOTAL_DOCUMENTS = 50000`, and `BATCH_SIZE = 5000`.
  * Stores the database handle in `const dbTarget = db.getSiblingDB(DB_NAME)` to isolate the 50,000-document benchmark from the operational `weather_nosql` database.
* **Lines 17–19 (Idempotent Teardown):**
  * Drops `sensor_payloads`, `weather_stream`, and `hourly_sensor_buckets` so every benchmark run starts with zero fragmentation and clean WiredTiger statistics.
* **Lines 22–29 (`weather_stream` Native Time-Series Collection):**
  * Configures `timeField: "timestamp"` and `metaField: "metadata"` (`{ station_id, region, sensor_type }`).
  * Sets **`granularity: "seconds"`** because the generator synthesizes high-frequency telemetry spaced ~2.5 seconds apart (`i * 2500` ms). Under `granularity: "seconds"`, WiredTiger closes internal buckets in `system.buckets.weather_stream` every **1 hour** of simulated time or every **1,000 measurements** (or 125 KB uncompressed size), whichever threshold is reached first.
  * Automatically creates a compound index on `(metadata, timestamp)` at the bucket level.
* **Lines 32–34 (Standard Collection Indexes on `sensor_payloads`):**
  * Creates three indexes on the standard BSON collection before ingestion so that the storage audit in Section 5 captures realistic production B-Tree index overhead (`totalIndexSize`):
    1. `{ "metadata.station_id": 1, "timestamp": -1 }`: Compound ESR index supporting equality lookups by station and descending chronological sorts.
    2. `{ "metadata.sensor_type": 1 }`: Single-field index on embedded sub-document key `metadata.sensor_type`, accelerating Stage 1 (`$match: { "metadata.sensor_type": "ROAD_SURFACE_RADAR" }`) of the Road Safety pipeline in Section 3.
    3. `{ "hardware_faults": 1 }`: Because `hardware_faults` is an array of fault code strings, MongoDB automatically converts this index into a **Multikey Index**, inserting an index entry for every individual element in `hardware_faults`.

---

### 1.2 Station Topology, Fault Catalog & 4-Class Polymorphic Payload Synthesis (Lines 36–128)

```javascript
const stationList = [];
for (let i = 1; i <= 50; i++) {
  stationList.push({
    id: "AWS-" + String(i).padStart(3, "0"),
    region: (i <= 15) ? "COASTAL_MED" : (i <= 35) ? "TELL_ATLAS" : "SAHARA_PLATEAU"
  });
}

const faultCatalog = [
  "ERR_BATTERY_UNDERVOLT",
  "ERR_HEATER_CIRCUIT_OPEN",
  "WARN_OPTICAL_LENS_DUST",
  "ERR_SONIC_TRANSDUCER_ASYNC",
  "WARN_SOLAR_REGULATOR_DROP"
];

const baseTime = new Date("2026-10-01T00:00:00Z").getTime();
let batchStandard = [];
let batchTimeSeries = [];
let totalInserted = 0;

print(`[*] Generating ${TOTAL_DOCUMENTS.toLocaleString()} polymorphic telemetry documents across 4 sensor classes...`);
const startTime = Date.now();

for (let i = 1; i <= TOTAL_DOCUMENTS; i++) {
  const station = stationList[Math.floor(Math.random() * stationList.length)];
  const docTime = new Date(baseTime + (i * 2500) + Math.floor(Math.random() * 500));
  const sensorCategory = i % 4; // 0: Standard, 1: Sonic 3D, 2: Disdrometer, 3: Road Sensor

  // Inject realistic hardware_faults arrays on ~6% of transmissions for $unwind diagnostics
  let faults = [];
  if (Math.random() < 0.06) {
    const f1 = faultCatalog[Math.floor(Math.random() * faultCatalog.length)];
    faults.push(f1);
    if (Math.random() < 0.25) {
      const f2 = faultCatalog[(faultCatalog.indexOf(f1) + 1) % faultCatalog.length];
      faults.push(f2);
    }
  }

  let payload = {};

  if (sensorCategory === 0) {
    // 1. Standard AWS Telemetry (METAR_STANDARD)
    payload = {
      timestamp: docTime,
      metadata: { station_id: station.id, region: station.region, sensor_type: "METAR_STANDARD" },
      temperature: Number((12.0 + Math.sin(i / 1000) * 14.0 + Math.random() * 2.0).toFixed(2)),
      pressure: Number((1013.25 + Math.cos(i / 2000) * 8.0 + Math.random() * 1.5).toFixed(2)),
      relative_humidity: Number((45.0 + Math.random() * 50.0).toFixed(1))
    };
  } else if (sensorCategory === 1) {
    // 2. 3D Ultrasonic Anemometer (ULTRASONIC_3D - 3D wind vectors, no scalar pressure)
    payload = {
      timestamp: docTime,
      metadata: { station_id: station.id, region: station.region, sensor_type: "ULTRASONIC_3D" },
      u_vector: Number((Math.random() * 15.0 - 5.0).toFixed(3)),
      v_vector: Number((Math.random() * 15.0 - 5.0).toFixed(3)),
      w_vector: Number((Math.random() * 2.0 - 1.0).toFixed(3)),
      turbulent_kinetic_energy: Number((Math.random() * 0.45).toFixed(4)),
      sonic_temperature: Number((14.0 + Math.random() * 10.0).toFixed(2))
    };
  } else if (sensorCategory === 2) {
    // 3. Optical Disdrometer / Present Weather (PRESENT_WEATHER_OPTICAL)
    const hasPrecip = Math.random() < 0.25;
    payload = {
      timestamp: docTime,
      metadata: { station_id: station.id, region: station.region, sensor_type: "PRESENT_WEATHER_OPTICAL" },
      visibility_meters: Math.floor(hasPrecip ? (300 + Math.random() * 2000) : (8000 + Math.random() * 2000)),
      precipitation_code_wmo: hasPrecip ? 61 : 0,
      drop_size_bins: hasPrecip
        ? [Math.floor(Math.random() * 10), Math.floor(Math.random() * 25), Math.floor(Math.random() * 5)]
        : [0, 0, 0]
    };
  } else {
    // 4. Road Surface Radar & Freeze Sensor (ROAD_SURFACE_RADAR)
    payload = {
      timestamp: docTime,
      metadata: { station_id: station.id, region: station.region, sensor_type: "ROAD_SURFACE_RADAR" },
      surface_temp: Number((8.0 + Math.random() * 15.0).toFixed(2)),
      subsurface_temp_5cm: Number((9.0 + Math.random() * 12.0).toFixed(2)),
      water_film_height_mm: Number((Math.random() * 1.5).toFixed(2)),
      grip_factor: Number((0.65 + Math.random() * 0.35).toFixed(2))
    };
  }

  if (faults.length > 0) {
    payload.hardware_faults = faults;
  }

  batchStandard.push(payload);
  batchTimeSeries.push(payload);
```

#### Deep-Dive Breakdown of the 4 Polymorphic Instrument Payloads

* **Lines 36–42 (Regional Station Allocation):**
  * Generates 50 stations (`AWS-001` to `AWS-050`) partitioned into 3 Algerian physiographic zones:
    * `AWS-001`..`AWS-015` (15 stations, 30%): `"COASTAL_MED"`
    * `AWS-016`..`AWS-035` (20 stations, 40%): `"TELL_ATLAS"`
    * `AWS-036`..`AWS-050` (15 stations, 30%): `"SAHARA_PLATEAU"`
* **Lines 63 & 78–120 (The 4 Sensor Classes — 12,500 Documents Each):**
  * Using `const sensorCategory = i % 4`, the loop generates exactly **12,500 documents** for each of the four sensor classes. Note how `.toFixed(n)` returns a string in JavaScript, so wrapping it in `Number(...)` ensures the telemetry values are stored as true BSON numeric types (`double`/`int`) rather than strings:

| `sensorCategory` | `metadata.sensor_type` | Count | Instrument Physics & Polymorphic Fields |
| :--- | :--- | :--- | :--- |
| **`0`** | `METAR_STANDARD` | 12,500 | Standard synoptic sensor suite: sinusoidal diurnal `temperature` ($-2^\circ\text{C}$ to $+28^\circ\text{C}$), barometric `pressure` around `1013.25 hPa`, and `relative_humidity` ($45.0\%$ to $95.0\%$). |
| **`1`** | `ULTRASONIC_3D` | 12,500 | 3-axis sonic anemometer for boundary-layer eddy covariance: orthogonal wind components `u_vector` (zonal East-West), `v_vector` (meridional North-South), `w_vector` (vertical updraft/downdraft $-1.0$ to $+1.0\text{ m/s}$), `turbulent_kinetic_energy` ($\text{TKE}$ in $\text{m}^2/\text{s}^2$), and acoustic virtual temperature `sonic_temperature`. |
| **`2`** | `PRESENT_WEATHER_OPTICAL` | 12,500 | Laser optical disdrometer: 25% precipitation probability (`hasPrecip`). Emits horizontal `visibility_meters` ($300\text{--}2300\text{ m}$ in rain vs $8000\text{--}10000\text{ m}$ clear), WMO Synop Code `precipitation_code_wmo` (`61` = continuous moderate rain, `0` = no precipitation), and a 3-element `drop_size_bins` array (`[small, medium, large]` hydrometeor counts). |
| **`3`** | `ROAD_SURFACE_RADAR` | 12,500 | Highway pavement condition radar: asphalt `surface_temp`, `subsurface_temp_5cm` ($5\text{ cm}$ below pavement), standing water thickness `water_film_height_mm` ($0.00\text{--}1.50\text{ mm}$), and tire friction coefficient `grip_factor` ($0.65\text{--}1.00$). |

* **Lines 65–74 & 122–124 (Sparse `hardware_faults` Array Injection):**
  * With a 6% probability (`Math.random() < 0.06`, ~3,000 documents out of 50,000), a document receives 1 fault from `faultCatalog`. Of those faulted documents, 25% (`Math.random() < 0.25`, ~750 documents) receive a second distinct fault code (`(faultCatalog.indexOf(f1) + 1) % faultCatalog.length`).
  * Crucially, Lines 122–124 (`if (faults.length > 0) { payload.hardware_faults = faults; }`) **only attach the `hardware_faults` field when a fault actually occurs**. The remaining ~94% of healthy transmissions omit `hardware_faults` completely, saving BSON key overhead on 47,000 documents!

---

### 1.3 High-Throughput Unordered Batch Ingestion (Lines 129–147)

```javascript
  if (batchStandard.length >= BATCH_SIZE) {
    dbTarget.sensor_payloads.insertMany(batchStandard, { ordered: false });
    dbTarget.weather_stream.insertMany(batchTimeSeries, { ordered: false });
    totalInserted += batchStandard.length;
    print(`   -> Ingested ${totalInserted.toLocaleString()} / ${TOTAL_DOCUMENTS.toLocaleString()} records...`);
    batchStandard = [];
    batchTimeSeries = [];
  }
}

if (batchStandard.length > 0) {
  dbTarget.sensor_payloads.insertMany(batchStandard, { ordered: false });
  dbTarget.weather_stream.insertMany(batchTimeSeries, { ordered: false });
  totalInserted += batchStandard.length;
}

const elapsedSec = ((Date.now() - startTime) / 1000).toFixed(2);
print(`[+] Complete! ${totalInserted.toLocaleString()} documents ingested in ${elapsedSec}s.`);
```

#### Why `BATCH_SIZE = 5000` with `{ ordered: false }` Maximizes WiredTiger Throughput
1. **Amortizing Network Round-Trip Latency:** Calling `insertOne()` 50,000 times inside a loop forces 50,000 synchronous TCP round-trips between `mongosh` and `mongod`. Buffering 5,000 documents per `insertMany()` call reduces the entire 50,000-document load to just **10 bulk wire-protocol batches** per collection.
2. **Parallel Bucket & Shard Routing (`{ ordered: false }`):**
   * By default, `insertMany()` executes with `{ ordered: true }`, which requires MongoDB to process documents strictly sequentially and abort on the first error.
   * Passing **`{ ordered: false }`** allows the MongoDB server (and `mongos` routers in sharded clusters) to reorder and group documents by `metaField` (`metadata`) when writing to the `weather_stream` Time-Series collection, packing measurements for the same station into the same in-memory bucket in a single lock acquisition.

---

## Section 2: Manual Bucket Pattern Atomic Upsert — `hourly_sensor_buckets` (Lines 148–181)

### Code Block

```javascript
// ============================================================================
// 2. Manual Bucket Pattern Demonstration (Upserting High-Frequency Readings)
// ============================================================================
print("\n[*] Demonstrating Manual Bucket Pattern Upsert (hourly_sensor_buckets)...");
const sampleReadings = [
  { sec: 0, w: 4.1, temp: 18.2 },
  { sec: 1, w: 4.6, temp: 18.2 },
  { sec: 2, w: 5.2, temp: 18.3 },
  { sec: 3, w: 3.9, temp: 18.1 }
];

sampleReadings.forEach(r => {
  dbTarget.hourly_sensor_buckets.updateOne(
    {
      _id: "AWS-001_2026-10-04_H12",
      sample_count: { $lt: 3600 }
    },
    {
      $setOnInsert: {
        station_id: "AWS-001",
        bucket_start: ISODate("2026-10-04T12:00:00Z"),
        bucket_end: ISODate("2026-10-04T12:59:59Z")
      },
      $push: { measurements: r },
      $inc: { sample_count: 1, "summary.sum_w": r.w },
      $min: { "summary.min_w": r.w },
      $max: { "summary.max_w": r.w }
    },
    { upsert: true }
  );
});

printjson(dbTarget.hourly_sensor_buckets.findOne({ _id: "AWS-001_2026-10-04_H12" }));
```

### Deep-Dive Architectural Explanation: How the Manual Bucket Pattern Works

While native Time-Series collections handle bucketing automatically, engineers frequently implement the **Manual Bucket Pattern** when they need custom deterministic `_id` keys, real-time pre-aggregated `summary` sub-documents updated on every write, or strict sub-document array size governance.

Every single 1-second sensor reading (`r`) executes the exact same idempotent `updateOne(filter, update, { upsert: true })` statement:

1. **The Filter Predicate (`_id` + Capacity Guard, Lines 161–164):**
   * `_id: "AWS-001_2026-10-04_H12"`: Deterministic composite primary key encoding `<station_id>_<YYYY-MM-DD>_H<hour>`.
   * `sample_count: { $lt: 3600 }`: **Bounded Array Guard**. Because 1 hour contains $3,600\text{ seconds}$, this predicate guarantees that `measurements` never grows beyond 3,600 elements—preventing unbounded document growth toward MongoDB's 16 MB BSON limit.
2. **`$setOnInsert` (Lines 166–170):**
   * On the very first reading of the hour (`sec: 0`), no document matches `_id: "AWS-001_2026-10-04_H12"`. Because `{ upsert: true }` is enabled, MongoDB creates the bucket document and executes `$setOnInsert` once to initialize immutable header fields (`station_id`, `bucket_start`, `bucket_end`). On all subsequent 3,599 readings (`sec: 1..3599`), `$setOnInsert` is skipped.
3. **`$push: { measurements: r }` (Line 171):**
   * Appends the raw 1-second reading sub-document `{ sec, w, temp }` to the `measurements` array in $O(1)$ amortized memory time.
4. **`$inc: { sample_count: 1, "summary.sum_w": r.w }` (Line 172):**
   * Atomically increments the document counter `sample_count` by `1` and adds the current wind speed `r.w` to the running sum `summary.sum_w`. Why maintain both `sample_count` and `summary.sum_w`? Because any dashboard can compute the exact hourly mean wind speed on read ($\text{mean} = \text{sum\_w} / \text{sample\_count} = 17.8 / 4 = 4.45\text{ m/s}$) without scanning the `measurements` array!
5. **`$min: { "summary.min_w": r.w }` & `$max: { "summary.max_w": r.w }` (Lines 173–174):**
   * Compares `r.w` against the existing `summary.min_w` and `summary.max_w` values inside WiredTiger and updates them only if `r.w` sets a new hourly minimum (`3.9`) or peak gust (`5.2`). On initial upsert (`sec: 0`), both initialize to `4.1`.

#### Resulting Pre-Aggregated Bucket Document (Line 180 Output)

```javascript
{
  _id: 'AWS-001_2026-10-04_H12',
  bucket_end: ISODate('2026-10-04T12:59:59.000Z'),
  bucket_start: ISODate('2026-10-04T12:00:00.000Z'),
  measurements: [
    { sec: 0, w: 4.1, temp: 18.2 },
    { sec: 1, w: 4.6, temp: 18.2 },
    { sec: 2, w: 5.2, temp: 18.3 },
    { sec: 3, w: 3.9, temp: 18.1 }
  ],
  sample_count: 4,
  station_id: 'AWS-001',
  summary: { sum_w: 17.8, min_w: 3.9, max_w: 5.2 }
}
```

---

## Section 3: Multi-Stage Aggregation — Road Safety & Reduced Grip Analytics (Lines 182–213)

### Code Block

```javascript
// ============================================================================
// 3. Multi-Stage Aggregation: Road Safety & Reduced Grip Analytics
// ============================================================================
print("\n[*] Running Road Surface Radar Safety Aggregation Pipeline...");
const roadSafetyReport = dbTarget.sensor_payloads.aggregate([
  {
    $match: {
      "metadata.sensor_type": "ROAD_SURFACE_RADAR",
      water_film_height_mm: { $gt: 0.5 }
    }
  },
  {
    $group: {
      _id: "$metadata.region",
      stations_reporting: { $addToSet: "$metadata.station_id" },
      avg_grip_factor: { $avg: "$grip_factor" },
      min_road_temp: { $min: "$surface_temp" },
      sample_count: { $sum: 1 }
    }
  },
  {
    $project: {
      _id: 1,
      total_stations: { $size: "$stations_reporting" },
      avg_grip_factor: { $round: ["$avg_grip_factor", 2] },
      min_road_temp: { $round: ["$min_road_temp", 2] },
      sample_count: 1
    }
  },
  { $sort: { avg_grip_factor: 1 } }
]).toArray();
printjson(roadSafetyReport);
```

### Stage-by-Stage Technical Breakdown

1. **Stage 1 — `$match` (Lines 187–192):**
   * Filters the 50,000 polymorphic documents down to only `metadata.sensor_type: "ROAD_SURFACE_RADAR"` (12,500 documents, leveraging the `{ "metadata.sensor_type": 1 }` B-Tree index created on Line 33) and further restricts to wet-pavement observations where `water_film_height_mm: { $gt: 0.5 }` (~8,333 documents, since `water_film_height_mm` is uniformly distributed across $[0.0, 1.5]\text{ mm}$).
   * Placing `$match` as the very first stage reduces the number of documents flowing into `$group` by **~83%**.
2. **Stage 2 — `$group` with `$addToSet` Distinct Set Accumulation (Lines 193–201):**
   * Groups by `_id: "$metadata.region"` (`"COASTAL_MED"`, `"TELL_ATLAS"`, `"SAHARA_PLATEAU"`).
   * **`stations_reporting: { $addToSet: "$metadata.station_id" }`:** MongoDB's `$group` stage does not have a SQL `COUNT(DISTINCT station_id)` accumulator. Instead, `$addToSet` collects unique `station_id` strings into an in-memory mathematical set array (ignoring duplicates), which is then counted in the next stage using `$size`.
   * Computes `avg_grip_factor` (`$avg`), `min_road_temp` (`$min`), and wet-observation `sample_count` (`$sum: 1`).
3. **Stage 3 — `$project` with `$size` and `$round` (Lines 202–210):**
   * `total_stations: { $size: "$stations_reporting" }`: Converts the deduplicated array of station IDs into an integer count (`15` for `COASTAL_MED`, `20` for `TELL_ATLAS`, `15` for `SAHARA_PLATEAU`) and drops the bulky `stations_reporting` array from the final output.
   * Rounds `avg_grip_factor` and `min_road_temp` to 2 decimal places (`$round: [..., 2]`).
4. **Stage 4 — `$sort: { avg_grip_factor: 1 }` (Line 211):**
   * Sorts ascending (`1`) so the region with the lowest tire-pavement friction (`avg_grip_factor`) appears first.

---

## Section 4: Multi-Stage Aggregation — `$unwind` Hardware Fault Diagnostics (Lines 215–246)

### Code Block

```javascript
// ============================================================================
// 4. Multi-Stage Aggregation: $unwind Hardware Fault Diagnostics
// ============================================================================
print("\n[*] Running $unwind Hardware Fault Diagnostics Pipeline across 50,000 payloads...");
const faultDiagnostics = dbTarget.sensor_payloads.aggregate([
  { $match: { hardware_faults: { $exists: true, $not: { $size: 0 } } } },
  { $unwind: "$hardware_faults" },
  {
    $group: {
      _id: {
        region: "$metadata.region",
        fault_code: "$hardware_faults"
      },
      occurrences: { $sum: 1 },
      affected_stations: { $addToSet: "$metadata.station_id" },
      latest_occurrence: { $max: "$timestamp" }
    }
  },
  {
    $project: {
      _id: 0,
      region: "$_id.region",
      fault_code: "$_id.fault_code",
      occurrences: 1,
      affected_station_count: { $size: "$affected_stations" },
      latest_occurrence: 1
    }
  },
  { $sort: { occurrences: -1 } },
  { $limit: 10 }
]).toArray();
printjson(faultDiagnostics);
```

### Stage-by-Stage Technical Breakdown

1. **Stage 1 — Sparse Array Filter (`$match`, Line 220):**
   * `{ hardware_faults: { $exists: true, $not: { $size: 0 } } }` filters out the ~94% (~47,000) of healthy telemetry documents that do not carry a `hardware_faults` field (or have an empty array), passing only the ~3,000 faulted documents into `$unwind`.
2. **Stage 2 — `{ $unwind: "$hardware_faults" }` (Line 221):**
   * For documents with 1 fault code, `$unwind` emits 1 document where `hardware_faults` is now a scalar string (e.g., `"ERR_BATTERY_UNDERVOLT"`).
   * For the ~25% of faulted documents carrying 2 fault codes, `$unwind` emits 2 separate documents—one for each fault code—yielding ~3,750 unwound fault event records.
3. **Stage 3 — Composite Key Grouping (`$group`, Lines 222–231):**
   * Groups by a **composite sub-document key**: `_id: { region: "$metadata.region", fault_code: "$hardware_faults" }` ($3\text{ regions} \times 5\text{ fault codes} = 15\text{ composite groups}$).
   * Accumulates total fault `occurrences: { $sum: 1 }`, unique impacted stations via `affected_stations: { $addToSet: "$metadata.station_id" }`, and the most recent failure timestamp via `latest_occurrence: { $max: "$timestamp" }`.
4. **Stage 4 — Flattening Composite `_id` (`$project`, Lines 232–241):**
   * Suppresses `_id: 0`, promotes `"$_id.region"` and `"$_id.fault_code"` to top-level keys, and computes `affected_station_count: { $size: "$affected_stations" }`.
5. **Stages 5 & 6 — Top-N Ranking (`$sort` + `$limit: 10`, Lines 243–244):**
   * Sorts by `occurrences: -1` (descending) and limits the cursor to the top 10 regional fault hotspots. When `$sort` immediately precedes `$limit`, MongoDB's aggregation optimizer coalesces them into a bounded **Top-K Heap Sort**, maintaining only 10 documents in memory during sorting.

---

## Section 5: Physical Storage Compression Audit — `stats()` (Lines 248–268)

### Code Block

```javascript
// ============================================================================
// 5. Storage Compression Audit (Standard BSON vs. Native Columnar Buckets)
// ============================================================================
print("\n================== STORAGE METRICS COMPARISON ==================");
const stdStats = dbTarget.sensor_payloads.stats();
const tsStats = dbTarget.weather_stream.stats();

print(`Standard Collection ("sensor_payloads"):`);
print(`  • Document Count  : ${stdStats.count}`);
print(`  • Data Size       : ${(stdStats.size / 1024 / 1024).toFixed(2)} MB (Uncompressed BSON)`);
print(`  • Storage Size    : ${(stdStats.storageSize / 1024 / 1024).toFixed(2)} MB (WiredTiger Block Compressed)`);
print(`  • Total Index Size: ${(stdStats.totalIndexSize / 1024 / 1024).toFixed(2)} MB`);

print(`\nNative Time-Series Collection ("weather_stream"):`);
print(`  • Document Count  : ${tsStats.count}`);
print(`  • Storage Size    : ${(tsStats.storageSize / 1024 / 1024).toFixed(2)} MB (Columnar Buckets)`);
if (tsStats.storageSize > 0) {
  print(`  • Compression Gain: ${(stdStats.storageSize / tsStats.storageSize).toFixed(2)}x physical disk savings!`);
}
print("================================================================\n");
```

### Deep-Dive Breakdown of WiredTiger Storage Metrics

Understanding the difference between `size`, `storageSize`, and `totalIndexSize` returned by `.stats()` (bytes divided by $1024 \times 1024$ to convert to MiB/MB) is critical for capacity planning:

| Metric Expression | Physical Meaning in WiredTiger | Typical Benchmark Value (50,000 Docs) |
| :--- | :--- | :--- |
| **`stdStats.count`** | Total logical BSON documents in `sensor_payloads`. | `50000` |
| **`stdStats.size`** | **Uncompressed Logical BSON Size in RAM:** Total bytes occupied by all 50,000 BSON documents when decompressed in the WiredTiger internal memory cache (including repeated field names like `"timestamp"`, `"metadata"`, `"water_film_height_mm"` in every document). | **`~8.85 MB`** |
| **`stdStats.storageSize`** | **WiredTiger Block-Compressed Disk Footprint:** Actual bytes allocated on disk for `sensor_payloads` after WiredTiger applies row-wise **Snappy** block compression to 32 KB pages. | **`~2.55 MB`** |
| **`stdStats.totalIndexSize`** | **Total B-Tree Index Footprint:** Sum of disk/memory bytes consumed by the 4 indexes on `sensor_payloads`: `_id_`, `{ "metadata.station_id": 1, "timestamp": -1 }`, `{ "metadata.sensor_type": 1 }`, and `{ "hardware_faults": 1 }`. Notice that index size (`~2.45 MB`) is nearly as large as the compressed collection data itself! | **`~2.45 MB`** |
| **`tsStats.storageSize`** | **Columnar Time-Series Bucket Disk Footprint:** Physical disk space consumed by `system.buckets.weather_stream`. Because measurements sharing the same `metadata` are transposed into contiguous columnar arrays and compressed with **delta encoding + Run-Length Encoding (RLE) + Zstandard**, repeated field names and per-document `_id` entries vanish. | **`~0.65 MB` – `0.85 MB`** (**`3.0x` to `4.0x` physical disk savings**; over **`6x` savings** when including index overhead!) |

---

## Expected Terminal Output

Executing `mongosh "mongodb://localhost:27017/weather_telemetry_db" day4_mongo_50k_polymorphic_benchmark.js` produces the following output:

```text
[*] Initializing database: weather_telemetry_db...
[*] Generating 50,000 polymorphic telemetry documents across 4 sensor classes...
   -> Ingested 5,000 / 50,000 records...
   -> Ingested 10,000 / 50,000 records...
   -> Ingested 15,000 / 50,000 records...
   -> Ingested 20,000 / 50,000 records...
   -> Ingested 25,000 / 50,000 records...
   -> Ingested 30,000 / 50,000 records...
   -> Ingested 35,000 / 50,000 records...
   -> Ingested 40,000 / 50,000 records...
   -> Ingested 45,000 / 50,000 records...
   -> Ingested 50,000 / 50,000 records...
[+] Complete! 50,000 documents ingested in 1.42s.

[*] Demonstrating Manual Bucket Pattern Upsert (hourly_sensor_buckets)...
{
  _id: 'AWS-001_2026-10-04_H12',
  bucket_end: ISODate('2026-10-04T12:59:59.000Z'),
  bucket_start: ISODate('2026-10-04T12:00:00.000Z'),
  measurements: [
    { sec: 0, w: 4.1, temp: 18.2 },
    { sec: 1, w: 4.6, temp: 18.2 },
    { sec: 2, w: 5.2, temp: 18.3 },
    { sec: 3, w: 3.9, temp: 18.1 }
  ],
  sample_count: 4,
  station_id: 'AWS-001',
  summary: { sum_w: 17.8, min_w: 3.9, max_w: 5.2 }
}

[*] Running Road Surface Radar Safety Aggregation Pipeline...
[
  {
    _id: 'COASTAL_MED',
    sample_count: 2514,
    total_stations: 15,
    avg_grip_factor: 0.82,
    min_road_temp: 8.01
  },
  {
    _id: 'TELL_ATLAS',
    sample_count: 3318,
    total_stations: 20,
    avg_grip_factor: 0.83,
    min_road_temp: 8.0
  },
  {
    _id: 'SAHARA_PLATEAU',
    sample_count: 2491,
    total_stations: 15,
    avg_grip_factor: 0.83,
    min_road_temp: 8.01
  }
]

[*] Running $unwind Hardware Fault Diagnostics Pipeline across 50,000 payloads...
[
  {
    occurrences: 318,
    latest_occurrence: ISODate('2026-10-02T10:42:18.112Z'),
    region: 'TELL_ATLAS',
    fault_code: 'ERR_BATTERY_UNDERVOLT',
    affected_station_count: 20
  },
  {
    occurrences: 309,
    latest_occurrence: ISODate('2026-10-02T10:43:05.409Z'),
    region: 'TELL_ATLAS',
    fault_code: 'WARN_OPTICAL_LENS_DUST',
    affected_station_count: 20
  }
  // ... (Top 10 regional fault groups ordered by occurrences descending)
]

================== STORAGE METRICS COMPARISON ==================
Standard Collection ("sensor_payloads"):
  • Document Count  : 50000
  • Data Size       : 8.84 MB (Uncompressed BSON)
  • Storage Size    : 2.54 MB (WiredTiger Block Compressed)
  • Total Index Size: 2.42 MB

Native Time-Series Collection ("weather_stream"):
  • Document Count  : 50000
  • Storage Size    : 0.72 MB (Columnar Buckets)
  • Compression Gain: 3.53x physical disk savings!
================================================================
```

---

[Home](../README.md) | [Portal](../bootcamp_portal.html) | [Day 4 Coursebook](./day4_master_coursebook.md) | [Blank VM Lab Guide](../VM_BLANK_LAB_FROM_SCRATCH_GUIDE.md) | [Original Script](./day4_mongo_50k_polymorphic_benchmark.js) | [Seed Script Walkthrough](./day4_weather_ops_mongo_js_course_walkthrough.md) | [Advanced Script Walkthrough](./day4_weather_ops_mongo_advanced_js_course_walkthrough.md)
