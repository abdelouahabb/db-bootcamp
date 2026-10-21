// ============================================================================
// DAY 4 BOOTCAMP: 50,000 POLYMORPHIC TELEMETRY BENCHMARK, BUCKET PATTERN &
//                 $UNWIND HARDWARE FAULT DIAGNOSTICS
// File: day4_mongo_50k_polymorphic_benchmark.js
// Usage: mongosh "mongodb://localhost:27017/weather_telemetry_db" day4_mongo_50k_polymorphic_benchmark.js
// ============================================================================

var DB_NAME = "weather_telemetry_db";
var TOTAL_DOCUMENTS = 50000;
var BATCH_SIZE = 5000;

var dbTarget = db.getSiblingDB(DB_NAME);

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

var stationList = [];
for (let i = 1; i <= 50; i++) {
  stationList.push({
    id: "AWS-" + String(i).padStart(3, "0"),
    region: (i <= 15) ? "COASTAL_MED" : (i <= 35) ? "TELL_ATLAS" : "SAHARA_PLATEAU"
  });
}

var faultCatalog = [
  "ERR_BATTERY_UNDERVOLT",
  "ERR_HEATER_CIRCUIT_OPEN",
  "WARN_OPTICAL_LENS_DUST",
  "ERR_SONIC_TRANSDUCER_ASYNC",
  "WARN_SOLAR_REGULATOR_DROP"
];

var baseTime = new Date("2026-10-01T00:00:00Z").getTime();
var batchStandard = [];
var batchTimeSeries = [];
var totalInserted = 0;

print(`[*] Generating ${TOTAL_DOCUMENTS.toLocaleString()} polymorphic telemetry documents across 4 sensor classes...`);
var startTime = Date.now();

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
  batchTimeSeries.push({ ...payload });

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

var elapsedSec = ((Date.now() - startTime) / 1000).toFixed(2);
print(`[+] Complete! ${totalInserted.toLocaleString()} documents ingested in ${elapsedSec}s.`);

// ============================================================================
// 2. Manual Bucket Pattern Demonstration (Upserting High-Frequency Readings)
// ============================================================================
print("\n[*] Demonstrating Manual Bucket Pattern Upsert (hourly_sensor_buckets)...");
var sampleReadings = [
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

// ============================================================================
// 3. Multi-Stage Aggregation: Road Safety & Reduced Grip Analytics
// ============================================================================
print("\n[*] Running Road Surface Radar Safety Aggregation Pipeline...");
var roadSafetyReport = dbTarget.sensor_payloads.aggregate([
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

// ============================================================================
// 4. Multi-Stage Aggregation: $unwind Hardware Fault Diagnostics
// ============================================================================
print("\n[*] Running $unwind Hardware Fault Diagnostics Pipeline across 50,000 payloads...");
var faultDiagnostics = dbTarget.sensor_payloads.aggregate([
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

// ============================================================================
// 5. Storage Compression Audit (Standard BSON vs. Native Columnar Buckets)
// ============================================================================
print("\n================== STORAGE METRICS COMPARISON ==================");
var stdStats = dbTarget.sensor_payloads.stats();
var tsStats = dbTarget.weather_stream.stats();

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
