// ============================================================================
// DAY 4 BOOTCAMP: MONGODB & NOSQL FUNDAMENTALS FOR WEATHER FORECAST ENGINEERS
// File: day4_weather_ops_mongo.js
// Usage: mongosh weather_nosql day4_weather_ops_mongo.js
// ============================================================================

db = db.getSiblingDB("weather_nosql");

// Clean slate for repeatable labs
db.stations.drop();
db.radiosonde_soundings.drop();
db.cap_alerts.drop();
db.synoptic_timeseries.drop();

print("=== 1. Creating 'stations' Collection with $jsonSchema Physical Validation ===");
db.createCollection("stations", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "station_name", "station_type", "location", "is_active"],
      properties: {
        _id: { bsonType: ["int", "long", "double"], description: "WMO 5-digit station ID" },
        station_name: { bsonType: "string" },
        station_type: { enum: ["SURFACE_AWS", "COASTAL_BUOY", "UPPER_AIR_RADIOSONDE", "AGRO_SOIL"] },
        is_active: { bsonType: "bool" },
        location: {
          bsonType: "object",
          required: ["type", "coordinates"],
          properties: {
            type: { enum: ["Point"] },
            coordinates: {
              bsonType: "array",
              minItems: 2,
              maxItems: 2,
              description: "GeoJSON [longitude, latitude] order!"
            }
          }
        }
      }
    }
  }
});

// Seed Polymorphic Weather Stations (AWS, Coastal Buoy, Agro Station, Upper-Air Station)
db.stations.insertMany([
  {
    _id: 60390,
    station_name: "Algiers - Dar El Beida",
    station_type: "UPPER_AIR_RADIOSONDE",
    climate_zone: "Mediterranean",
    elevation_m: 25.0,
    is_active: true,
    location: { type: "Point", coordinates: [3.2154, 36.6910] }, // [lon, lat]!
    sensors: ["PT100_THERM", "CAP_HYGRO", "ULTRASONIC_WIND", "VAISALA_RS41_SONDE"],
    calibration: { last_calibrated: ISODate("2026-09-01T00:00:00Z"), technician: "M. Benali", pressure_offset_hpa: -0.1 }
  },
  {
    _id: 60490,
    station_name: "Oran - Es Senia",
    station_type: "SURFACE_AWS",
    climate_zone: "Mediterranean",
    elevation_m: 90.0,
    is_active: true,
    location: { type: "Point", coordinates: [-0.6212, 35.6239] },
    sensors: ["PT100_THERM", "CAP_HYGRO", "TIPPING_BUCKET_RAIN"],
    calibration: { last_calibrated: ISODate("2026-08-15T00:00:00Z"), technician: "A. Mansouri", pressure_offset_hpa: 0.0 }
  },
  {
    _id: 60419,
    station_name: "Constantine - El Khroub",
    station_type: "AGRO_SOIL",
    climate_zone: "Highland",
    elevation_m: 694.0,
    is_active: true,
    location: { type: "Point", coordinates: [6.6203, 36.2760] },
    sensors: ["PT100_THERM", "SOIL_MOISTURE_ARRAY", "LEAF_WETNESS"],
    soil_depths_cm: [10, 30, 50, 100],
    calibration: { last_calibrated: ISODate("2026-07-20T00:00:00Z"), technician: "K. Toumi" }
  },
  {
    _id: 60571,
    station_name: "Bechar - Ouakda",
    station_type: "SURFACE_AWS",
    climate_zone: "Arid",
    elevation_m: 811.0,
    is_active: true,
    location: { type: "Point", coordinates: [-2.2699, 31.6457] },
    sensors: ["PT100_THERM", "DUST_PARTICLE_LASER", "SOLAR_PYRANOMETER"],
    dust_storm_threshold_ug_m3: 500
  },
  {
    _id: 60680,
    station_name: "Tamanrasset - Aguenar",
    station_type: "UPPER_AIR_RADIOSONDE",
    climate_zone: "Arid",
    elevation_m: 1377.0,
    is_active: true,
    location: { type: "Point", coordinates: [5.4510, 22.8115] },
    sensors: ["PT100_THERM", "ULTRASONIC_WIND", "VAISALA_RS41_SONDE", "GCR_RADIATION"]
  },
  {
    _id: 60901,
    station_name: "Algiers Bay Marine Buoy #1",
    station_type: "COASTAL_BUOY",
    climate_zone: "Maritime",
    elevation_m: 0.0,
    is_active: true,
    location: { type: "Point", coordinates: [3.3500, 36.8500] },
    buoy_specs: { hull_type: "3m_Discus", mooring_depth_m: 120, wave_sensor: "Accelerometer_3D" }
  }
]);

print("=== 2. Creating 'radiosonde_soundings' (Nested Vertical Atmospheric Profiles) ===");
// Demonstrates WHY Document Model shines: each balloon launch has an array of vertical pressure levels!
db.radiosonde_soundings.insertMany([
  {
    station_id: 60390,
    station_name: "Algiers - Dar El Beida",
    launch_time: ISODate("2026-10-06T00:00:00Z"),
    sonde_serial: "RS41-V294810",
    burst_altitude_m: 31420,
    cape_j_kg: 1450, // High convective available potential energy (Thunderstorm risk!)
    k_index: 34,
    vertical_levels: [
      { pressure_hpa: 1000, height_m: 110,   temp_c: 18.5, dewpoint_c: 16.8, wind_dir_deg: 280, wind_speed_kt: 24 },
      { pressure_hpa: 850,  height_m: 1480,  temp_c: 11.2, dewpoint_c: 9.5,  wind_dir_deg: 295, wind_speed_kt: 38 },
      { pressure_hpa: 700,  height_m: 3090,  temp_c: 1.4,  dewpoint_c: -1.2, wind_dir_deg: 300, wind_speed_kt: 46 },
      { pressure_hpa: 500,  height_m: 5680,  temp_c: -16.8,dewpoint_c: -24.0,wind_dir_deg: 310, wind_speed_kt: 64 },
      { pressure_hpa: 300,  height_m: 9380,  temp_c: -42.5,dewpoint_c: -55.0,wind_dir_deg: 315, wind_speed_kt: 95 }
    ],
    qc_audit_log: [
      { checked_at: ISODate("2026-10-06T01:45:00Z"), step: "AUTO_GROSS_LIMIT", status: "PASSED" }
    ]
  },
  {
    station_id: 60390,
    station_name: "Algiers - Dar El Beida",
    launch_time: ISODate("2026-10-06T12:00:00Z"),
    sonde_serial: "RS41-V294855",
    burst_altitude_m: 32100,
    cape_j_kg: 320,
    k_index: 18,
    vertical_levels: [
      { pressure_hpa: 1000, height_m: 135,   temp_c: 24.4, dewpoint_c: 14.9, wind_dir_deg: 320, wind_speed_kt: 12 },
      { pressure_hpa: 850,  height_m: 1515,  temp_c: 13.0, dewpoint_c: 4.2,  wind_dir_deg: 330, wind_speed_kt: 18 },
      { pressure_hpa: 700,  height_m: 3130,  temp_c: 3.8,  dewpoint_c: -12.0,wind_dir_deg: 335, wind_speed_kt: 25 },
      { pressure_hpa: 500,  height_m: 5760,  temp_c: -14.2,dewpoint_c: -32.0,wind_dir_deg: 340, wind_speed_kt: 42 },
      { pressure_hpa: 300,  height_m: 9510,  temp_c: -39.8,dewpoint_c: -58.0,wind_dir_deg: 345, wind_speed_kt: 68 }
    ],
    qc_audit_log: [
      { checked_at: ISODate("2026-10-06T13:40:00Z"), step: "AUTO_GROSS_LIMIT", status: "PASSED" }
    ]
  },
  {
    station_id: 60680,
    station_name: "Tamanrasset - Aguenar",
    launch_time: ISODate("2026-10-06T12:00:00Z"),
    sonde_serial: "RS41-V299102",
    burst_altitude_m: 28900,
    cape_j_kg: 80,
    k_index: 10,
    vertical_levels: [
      { pressure_hpa: 850,  height_m: 1540,  temp_c: 34.5, dewpoint_c: 2.1,  wind_dir_deg: 180, wind_speed_kt: 16 },
      { pressure_hpa: 700,  height_m: 3210,  temp_c: 18.2, dewpoint_c: -8.4, wind_dir_deg: 210, wind_speed_kt: 22 },
      { pressure_hpa: 500,  height_m: 5890,  temp_c: -7.5, dewpoint_c: -29.0,wind_dir_deg: 245, wind_speed_kt: 35 },
      { pressure_hpa: 300,  height_m: 9710,  temp_c: -33.0,dewpoint_c: -52.0,wind_dir_deg: 260, wind_speed_kt: 58 }
    ],
    qc_audit_log: []
  }
]);

print("=== 3. Creating Native MongoDB Time-Series Collection ('synoptic_timeseries') ===");
// MongoDB 5.0+ Native Time-Series Collection with automatic columnar bucketing & 90-day TTL expiration
db.createCollection("synoptic_timeseries", {
  timeseries: {
    timeField: "obs_time",
    metaField: "station_meta",
    granularity: "hours"
  },
  expireAfterSeconds: 7776000 // Automatically expire raw telemetry older than 90 days!
});

// Seed Polymorphic Synoptic & Buoy & Agro Telemetry into Time-Series Collection
db.synoptic_timeseries.insertMany([
  // Algiers AWS (60390)
  {
    obs_time: ISODate("2026-10-05T18:00:00Z"),
    station_meta: { station_id: 60390, station_type: "UPPER_AIR_RADIOSONDE", climate_zone: "Mediterranean" },
    temp_c: 23.1, dewpoint_c: 17.5, pressure_hpa: 1013.8, wind_speed_kt: 19.0, precip_1h_mm: 2.4,
    diagnostics: { battery_v: 13.2, door_open: false, firmware: "v4.2.1" }
  },
  {
    obs_time: ISODate("2026-10-06T00:00:00Z"),
    station_meta: { station_id: 60390, station_type: "UPPER_AIR_RADIOSONDE", climate_zone: "Mediterranean" },
    temp_c: 18.5, dewpoint_c: 16.8, pressure_hpa: 1011.5, wind_speed_kt: 28.0, precip_1h_mm: 18.6,
    diagnostics: { battery_v: 12.6, door_open: false, firmware: "v4.2.1" }
  },
  {
    obs_time: ISODate("2026-10-06T06:00:00Z"),
    station_meta: { station_id: 60390, station_type: "UPPER_AIR_RADIOSONDE", climate_zone: "Mediterranean" },
    temp_c: 17.9, dewpoint_c: 16.1, pressure_hpa: 1012.0, wind_speed_kt: 22.0, precip_1h_mm: 6.2,
    diagnostics: { battery_v: 12.4, door_open: true, firmware: "v4.2.1" }
  },
  // Constantine Agro-Soil Station (60419) — Notice extra soil_profile sub-document!
  {
    obs_time: ISODate("2026-10-06T00:00:00Z"),
    station_meta: { station_id: 60419, station_type: "AGRO_SOIL", climate_zone: "Highland" },
    temp_c: 15.1, dewpoint_c: 13.5, pressure_hpa: 1012.2, wind_speed_kt: 34.0, precip_1h_mm: 24.0,
    soil_profile: { temp_10cm_c: 16.4, moisture_10cm_pct: 38.5, moisture_30cm_pct: 29.0, leaf_wetness_idx: 9.2 },
    diagnostics: { battery_v: 12.1, door_open: false, firmware: "v3.9.0" }
  },
  // Algiers Bay Marine Buoy (60901) — Notice extra marine_telemetry sub-document!
  {
    obs_time: ISODate("2026-10-06T00:00:00Z"),
    station_meta: { station_id: 60901, station_type: "COASTAL_BUOY", climate_zone: "Maritime" },
    temp_c: 20.4, pressure_hpa: 1011.2, wind_speed_kt: 31.0,
    marine_telemetry: { sea_surface_temp_c: 22.8, sig_wave_height_m: 3.4, peak_wave_period_s: 8.5, salinity_psu: 37.6 },
    diagnostics: { battery_v: 11.7, solar_charging: false }
  },
  // Bechar Arid Dust Station (60571)
  {
    obs_time: ISODate("2026-10-05T18:00:00Z"),
    station_meta: { station_id: 60571, station_type: "SURFACE_AWS", climate_zone: "Arid" },
    temp_c: 31.4, dewpoint_c: 6.0, pressure_hpa: 1010.5, wind_speed_kt: 38.0, precip_1h_mm: 0.0,
    aerosol_telemetry: { pm10_ug_m3: 840, pm25_ug_m3: 195, visibility_m: 400 },
    diagnostics: { battery_v: 13.4, door_open: false, firmware: "v3.9.0" }
  }
]);

print("=== 4. Creating 'cap_alerts' (Common Alerting Protocol Nested Bulletins) ===");
db.cap_alerts.insertMany([
  {
    _id: "DZ-ONM-2026-10-05-001",
    issued_at: ISODate("2026-10-05T20:30:00Z"),
    expires_at: ISODate("2026-10-06T12:00:00Z"),
    phenomenon: "FLASH_FLOOD",
    severity: "RED",
    certainty: "OBSERVED",
    affected_stations: [60390, 60419],
    max_observed_gust_kt: 34.0,
    headline: "Severe convective thunderstorm cell producing >20mm/h rainfall",
    updates: []
  },
  {
    _id: "DZ-ONM-2026-10-05-002",
    issued_at: ISODate("2026-10-05T15:00:00Z"),
    expires_at: ISODate("2026-10-06T06:00:00Z"),
    phenomenon: "SANDSTORM",
    severity: "ORANGE",
    certainty: "LIKELY",
    affected_stations: [60571],
    max_observed_gust_kt: 38.0,
    headline: "Strong SW winds raising dense dust and reducing visibility <500m",
    updates: []
  }
]);

print("=== Day 4 MongoDB 'weather_nosql' Seed Complete! ===");
