// ============================================================================
// DAY 4 BOOTCAMP: MONGODB AGGREGATIONS, GEOSPATIAL (2DSPHERE), INDEXING & SHARDING
// File: day4_weather_ops_mongo_advanced.js
// Prerequisite: Run after day4_weather_ops_mongo.js
// Usage: mongosh weather_nosql day4_weather_ops_mongo_advanced.js
// ============================================================================

db = db.getSiblingDB("weather_nosql");

db.storm_polygons.drop();
db.upper_air_climatology.drop();

print("=== 1. Creating 2dsphere Geospatial Index on stations.location ===");
db.stations.createIndex({ location: "2dsphere" });

print("=== 2. Creating 'storm_polygons' Collection with GeoJSON Warning Polygons ===");
db.storm_polygons.insertMany([
  {
    _id: "CELL-MED-20261006-A",
    storm_name: "Mediterranean Convective System Alpha",
    detected_at: ISODate("2026-10-06T00:00:00Z"),
    max_reflectivity_dbz: 58.5,
    vil_kg_m2: 42.0, // Vertically Integrated Liquid (Hail indicator)
    motion_vector: { direction_deg: 245, speed_kt: 22 },
    // GeoJSON Polygon enclosing Northern Central/Eastern Algeria (Algiers, Bejaia, Setif, Constantine)
    footprint: {
      type: "Polygon",
      coordinates: [[
        [2.50, 35.80],
        [7.20, 35.80],
        [7.20, 37.10],
        [2.50, 37.10],
        [2.50, 35.80] // First and last coordinate MUST match to close a GeoJSON ring!
      ]]
    }
  },
  {
    _id: "CELL-SAH-20261005-B",
    storm_name: "Western Erg Haboob Dust Front",
    detected_at: ISODate("2026-10-05T18:00:00Z"),
    max_reflectivity_dbz: 32.0,
    aerosol_optical_depth: 2.8,
    motion_vector: { direction_deg: 210, speed_kt: 35 },
    footprint: {
      type: "Polygon",
      coordinates: [[
        [-3.50, 30.50],
        [-1.00, 30.50],
        [-1.00, 32.50],
        [-3.50, 32.50],
        [-3.50, 30.50]
      ]]
    }
  }
]);

db.storm_polygons.createIndex({ footprint: "2dsphere" });

print("=== 3. Creating Compound Index Following the ESR (Equality, Sort, Range) Rule ===");
db.radiosonde_soundings.createIndex(
  { station_id: 1, launch_time: -1, cape_j_kg: 1 },
  { name: "idx_sonde_esr" }
);

print("=== 4. Running Sample Aggregation Pipeline: Isobaric Pressure Surface Summary ===");
var levelSummary = db.radiosonde_soundings.aggregate([
  { $unwind: "$vertical_levels" },
  {
    $group: {
      _id: "$vertical_levels.pressure_hpa",
      soundings_count: { $sum: 1 },
      avg_height_m:    { $avg: "$vertical_levels.height_m" },
      avg_temp_c:      { $avg: "$vertical_levels.temp_c" },
      max_wind_kt:     { $max: "$vertical_levels.wind_speed_kt" }
    }
  },
  {
    $project: {
      _id: 0,
      pressure_hpa: "$_id",
      soundings_count: 1,
      avg_height_m: { $round: ["$avg_height_m", 0] },
      avg_temp_c:   { $round: ["$avg_temp_c", 1] },
      max_wind_kt:  1
    }
  },
  { $sort: { pressure_hpa: -1 } }
]).toArray();

printjson(levelSummary);
print("=== Day 4 Advanced MongoDB Setup Complete! ===");
