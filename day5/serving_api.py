#!/usr/bin/env python3
"""
Unified Meteorological Serving Gateway (serving_api.py)
Endpoints:
  1. GET /api/v1/spatial/nearby-stations  (PostGIS Geodesic ST_DWithin)
  2. GET /api/v1/telemetry/anomalies     (MongoDB Polymorphic Aggregations)
  3. GET /api/v1/climatology/summary     (DuckDB Vectorized Parquet Scan)
"""

from fastapi import FastAPI, HTTPException
import psycopg2
from psycopg2.pool import SimpleConnectionPool
from pymongo import MongoClient
import duckdb
import uvicorn

app = FastAPI(
    title="National Weather Operational Serving API",
    description="Sub-10ms Polyglot Serving Tier combining PostGIS, MongoDB, and DuckDB",
    version="1.0.0"
)

# Connection Pools
PG_DSN = "postgresql://postgres:postgres@localhost:5432/weather_ops_db"
pg_pool = SimpleConnectionPool(minconn=2, maxconn=10, dsn=PG_DSN)
mongo_client = MongoClient("mongodb://localhost:27017/")
mongo_db = mongo_client["weather_telemetry_db"]


# 1. PostGIS Endpoint: Spatial Proximity Search
@app.get("/api/v1/spatial/nearby-stations")
def get_nearby_stations(lat: float = 36.75, lon: float = 3.05, radius_km: float = 50.0):
    """
    Finds all active stations within radius_km of a geographic coordinate
    using PostGIS ST_DWithin over the WGS 84 ellipsoid.
    """
    conn = pg_pool.getconn()
    try:
        with conn.cursor() as cur:
            query = """
            SELECT 
                station_id,
                station_name,
                elevation_m,
                ROUND((ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography) / 1000.0)::numeric, 2) AS distance_km
            FROM stations
            WHERE is_active = TRUE
              AND ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, %s * 1000)
            ORDER BY distance_km ASC;
            """
            cur.execute(query, (lon, lat, lon, lat, radius_km))
            results = cur.fetchall()
            return [
                {"station_id": r[0], "name": r[1], "elevation_m": r[2], "distance_km": float(r[3])}
                for r in results
            ]
    finally:
        pg_pool.putconn(conn)


# 2. MongoDB Endpoint: Real-Time Polymorphic Sensor Anomalies
@app.get("/api/v1/telemetry/anomalies")
def get_sensor_anomalies():
    """
    Scans the MongoDB polymorphic stream for extreme turbulence or reduced visibility.
    """
    col = mongo_db["weather_stream"]
    cursor = col.find({
        "$or": [
            {"turbulent_kinetic_energy": {"$gt": 0.35}},
            {"visibility_meters": {"$lt": 1000}}
        ]
    }, {"_id": 0}).sort("timestamp", -1).limit(10)

    return list(cursor)


# 3. DuckDB Endpoint: Vectorized Analytical Climatology
@app.get("/api/v1/climatology/summary")
def get_climatology_summary(year: int = 2026):
    """
    Executes a vectorized SIMD scan over the Cold Parquet Lakehouse
    using DuckDB in-process execution with zero database socket locks.
    """
    con = duckdb.connect()
    parquet_path = "climatology_lake/**/*.parquet"

    query = f"""
    SELECT 
        COALESCE(region, 'OPERATIONAL_COMPACTED') AS region,
        COUNT(*) AS total_samples,
        ROUND(AVG(temperature), 2) AS mean_temperature,
        ROUND(MAX(wind_speed), 2) AS peak_wind_gust
    FROM read_parquet('{parquet_path}', hive_partitioning=true, union_by_name=true)
    WHERE year = {year}
    GROUP BY 1
    ORDER BY mean_temperature DESC;
    """
    try:
        df = con.execute(query).fetchdf()
        return df.to_dict(orient="records")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
