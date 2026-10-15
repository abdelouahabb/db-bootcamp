# Python Database Integration Cheatsheet for Weather Engineers (`sqlite3`, `duckdb`, `psycopg3`, `GeoPandas`, `PyMongo`)

**Target Audience:** Weather Forecast & Meteorological Data Engineers  
**Bootcamp Context:** Connecting Python data-science & operational ingestion scripts safely and efficiently to all 4 engines (`SQLite`, `DuckDB`, `PostgreSQL/PostGIS`, `MongoDB`)

---

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./10_query_execution_plan_forensics_and_explain.md) | **Card 11 of 13** | [Next Card ➡️](./12_dbeaver_and_mongodb_compass_gui_workflows.md)

## 🧭 Quick-Jump Table of Contents

- [1. Golden Rules for Python + Weather Databases](#1-golden-rules-for-python--weather-databases)
- [2. Day 1: Python + `sqlite3` (Built-In Standard Library)](#2-day-1-python--sqlite3-built-in-standard-library)
- [3. Day 1: Python + `duckdb` (Zero-Copy DataFrame & Parquet Analytics)](#3-day-1-python--duckdb-zero-copy-dataframe--parquet-analytics)
- [4. Days 2 & 3: Python + PostgreSQL (`psycopg` v3 & Connection Pooling)](#4-days-2--3-python--postgresql-psycopg-v3--connection-pooling)
  - [4.1 Production Connection Pool + Safe `UPSERT` Batching](#41-production-connection-pool--safe-upsert-batching)
  - [4.2 Loading `PostGIS` Spatial Weather Data Directly into `GeoPandas`](#42-loading-postgis-spatial-weather-data-directly-into-geopandas)
- [5. Days 4 & 5: Python + MongoDB (`PyMongo`)](#5-days-4--5-python--mongodb-pymongo)

---

## 1. Golden Rules for Python + Weather Databases

1. **NEVER use Python `f-strings` or `%` formatting to put variables into SQL!**
   - ❌ `cur.execute(f"SELECT * FROM stations WHERE station_name = '{name}'")` (Vulnerable to SQL injection & breaks on quotes like `'M'Sila'`).
   - ✅ Always pass parameters as a tuple (`?` in SQLite/DuckDB, `%s` in `psycopg3`).
2. **NEVER loop over 50,000 DataFrame rows calling `cur.execute("INSERT ...")` one by one!**
   - Use `executemany()`, `cur.copy()` (PostgreSQL), `duckdb.sql("INSERT INTO ... SELECT * FROM df")`, or `collection.insert_many()` (MongoDB).
3. **Always use Context Managers (`with ...:`)** so connections and transactions commit or roll back cleanly on exceptions.

---

## 2. Day 1: Python + `sqlite3` (Built-In Standard Library)

```python
import sqlite3
import pandas as pd

# 1. Connect with context manager & enable Foreign Keys!
with sqlite3.connect("weather_ops.db") as conn:
    conn.execute("PRAGMA foreign_keys = ON;")

    # 2. Safe Parameterized Query (? placeholders)
    cur = conn.execute(
        """
        SELECT station_id, obs_time, temp_c, wind_speed_kt
        FROM observations
        WHERE station_id = ? AND temp_c >= ?
        ORDER BY obs_time DESC
        """,
        (60390, 20.0),
    )
    for row in cur.fetchall():
        print(row)

    # 3. Load SQL query directly into a Pandas DataFrame
    df = pd.read_sql_query(
        "SELECT * FROM forecasts WHERE model_name = ?",
        conn,
        params=("ECMWF-HRES",),
        parse_dates=["init_time", "valid_time"],
    )
```

---

## 3. Day 1: Python + `duckdb` (Zero-Copy DataFrame & Parquet Analytics)

DuckDB can query a **Pandas or Polars DataFrame variable in your Python script by its variable name** directly inside SQL with **zero memory copying**!

```python
import duckdb
import polars as pl

# Suppose 'station_df' is an in-memory Polars or Pandas DataFrame in your Python script:
station_df = pl.DataFrame({
    "station_id": [60390, 60419, 60680],
    "region":     ["North Coast", "East Highland", "Deep South"]
})

# DuckDB can JOIN your in-memory Python DataFrame ('station_df') directly with a disk Parquet file!
result_arrow = duckdb.sql("""
    SELECT
        s.region,
        COUNT(*)              AS n_obs,
        ROUND(AVG(o.temp_c), 1) AS mean_temp_c
    FROM 'synoptic_observations_2026.parquet' o
    INNER JOIN station_df s USING (station_id)
    GROUP BY s.region
""").pl()  # .pl() returns a Polars DataFrame, .df() returns Pandas, .arrow() returns PyArrow!

print(result_arrow)
```

---

## 4. Days 2 & 3: Python + PostgreSQL (`psycopg` v3 & Connection Pooling)

Install modern `psycopg` (v3) and its connection pool:
```bash
pip install "psycopg[binary,pool]" geopandas sqlalchemy
```

### 4.1 Production Connection Pool + Safe `UPSERT` Batching
```python
from datetime import datetime, timezone
from psycopg_pool import ConnectionPool

PG_DSN = "postgresql://postgres:meteo_password@localhost:5432/weather_ops"

# Create a reusable thread-safe connection pool (min 2, max 10 connections)
pool = ConnectionPool(conninfo=PG_DSN, min_size=2, max_size=10)

def ingest_synoptic_batch(readings: list[tuple]):
    upsert_sql = """
        INSERT INTO synoptic.observations (
            station_id, obs_time, temp_c, pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (station_id, obs_time) DO UPDATE SET
            temp_c        = EXCLUDED.temp_c,
            pressure_hpa  = EXCLUDED.pressure_hpa,
            wind_speed_kt = EXCLUDED.wind_speed_kt,
            precip_1h_mm  = EXCLUDED.precip_1h_mm,
            qc_flag       = EXCLUDED.qc_flag;
    """
    with pool.connection() as conn:
        with conn.cursor() as cur:
            # executemany() in psycopg3 uses pipeline batching automatically!
            cur.executemany(upsert_sql, readings)
        conn.commit()

# Example batch
batch = [
    (60390, datetime(2026, 10, 7, 6, 0, tzinfo=timezone.utc), 20.4, 1015.2, 12.0, 0.0, "VALID"),
    (60419, datetime(2026, 10, 7, 6, 0, tzinfo=timezone.utc), 15.8, 1016.0,  8.0, 1.2, "VALID"),
]
ingest_synoptic_batch(batch)
```

### 4.2 Loading `PostGIS` Spatial Weather Data Directly into `GeoPandas`
```python
import geopandas as gpd
from sqlalchemy import create_engine

engine = create_engine("postgresql+psycopg://postgres:meteo_password@localhost:5432/weather_ops")

# Read PostGIS GEOGRAPHY/GEOMETRY query directly into a spatial GeoDataFrame!
gdf = gpd.read_postgis(
    sql="""
        SELECT
            s.station_id,
            s.station_name,
            s.geog::geometry AS geom,
            ROUND(AVG(o.temp_c), 1) AS mean_temp_c
        FROM synoptic.stations s
        JOIN synoptic.observations o USING (station_id)
        GROUP BY s.station_id, s.station_name, s.geog
    """,
    con=engine,
    geom_col="geom",
    crs="EPSG:4326",
)

# Plot interactive map or export to GeoParquet!
gdf.to_parquet("stations_climatology_geoparquet.parquet")
```

---

## 5. Days 4 & 5: Python + MongoDB (`PyMongo`)

```bash
pip install pymongo
```

```python
from datetime import datetime, timezone
from pymongo import MongoClient, UpdateOne

# Connect to Replica Set with automatic retryWrites and majority durability
client = MongoClient(
    "mongodb://localhost:27017/?replicaSet=rs_meteo&retryWrites=true&w=majority"
)
db = client["weather_nosql"]

# 1. Bulk Idempotent Upserts using bulk_write(UpdateOne(..., upsert=True))
ops = [
    UpdateOne(
        {"_id": "DZ-ONM-2026-10-07-001"},
        {
            "$setOnInsert": {"issued_at": datetime.now(timezone.utc), "phenomenon": "HIGH_WIND", "severity": "ORANGE"},
            "$max": {"max_observed_gust_kt": 46.0},
            "$addToSet": {"affected_stations": {"$each": [60390, 60901]}},
        },
        upsert=True,
    )
]
result = db.cap_alerts.bulk_write(ops)
print(f"Upserted: {result.upserted_count}, Modified: {result.modified_count}")

# 2. Run a Geospatial + Aggregation Pipeline and load directly into Pandas
pipeline = [
    {"$unwind": "$vertical_levels"},
    {"$match": {"vertical_levels.pressure_hpa": 500}},
    {
        "$project": {
            "_id": 0,
            "station_id": 1,
            "launch_time": 1,
            "temp_500hpa_c": "$vertical_levels.temp_c",
            "wind_500hpa_kt": "$vertical_levels.wind_speed_kt",
        }
    },
]
sonde_500hpa_docs = list(db.radiosonde_soundings.aggregate(pipeline))
```

---

### 🔗 Reference Library Navigation

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./10_query_execution_plan_forensics_and_explain.md) | **Card 11 of 13** | [Next Card ➡️](./12_dbeaver_and_mongodb_compass_gui_workflows.md) | [⬆️ Back to Top](#python-database-integration-cheatsheet-for-weather-engineers-sqlite3-duckdb-psycopg3-geopandas-pymongo)
