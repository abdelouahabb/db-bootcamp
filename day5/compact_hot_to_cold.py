#!/usr/bin/env python3
"""
Automated Hot-to-Cold Data Lake Compactor (compact_hot_to_cold.py)
Migrates closed operational records from PostgreSQL into an optimized 
Hive-partitioned Apache Parquet Lakehouse (ZSTD-compressed, dictionary-encoded).
"""

import os
import time
import psycopg2
import duckdb
import pyarrow as pa
import pyarrow.parquet as pq

PG_DSN = "postgresql://postgres:postgres@localhost:5432/weather_ops_db"
LAKE_ROOT = "climatology_lake"

print("=================================================================")
print("  HOT-TO-COLD LAKE COMPACTION: POSTGRESQL -> APACHE PARQUET      ")
print("=================================================================")

# 1. Connect to PostgreSQL and fetch target rows using server-side cursor
print("[*] Connecting to PostgreSQL operational store...")
pg_conn = psycopg2.connect(PG_DSN)

start_time = time.time()
query = """
SELECT 
    station_id,
    recorded_at,
    temperature,
    pressure,
    wind_speed,
    rain_accum_1m,
    EXTRACT(YEAR FROM recorded_at)::INT AS year,
    EXTRACT(MONTH FROM recorded_at)::INT AS month
FROM raw_telemetry_partitioned
WHERE temperature > -900.0; -- In-flight sentinel elimination!
"""

print("[*] Streaming operational records via server-side cursor...")
with pg_conn.cursor(name="lake_cur") as cursor:
    cursor.itersize = 250000
    cursor.execute(query)

    rows = cursor.fetchall()
    print(f"[+] Loaded {len(rows):,} records from PostgreSQL into host RAM.")

if not rows:
    print("[!] No records available to compact. Run seeder/router first.")
    exit(0)

# 2. Convert to PyArrow Table
print("[*] Transforming tuples into Arrow Columnar RecordBatches...")
schema = pa.schema([
    ("station_id", pa.string()),
    ("recorded_at", pa.timestamp("ms", tz="UTC")),
    ("temperature", pa.float32()),
    ("pressure", pa.float32()),
    ("wind_speed", pa.float32()),
    ("rain_accum_1m", pa.float32()),
    ("year", pa.int32()),
    ("month", pa.int32())
])

stations = [r[0] for r in rows]
times = [r[1] for r in rows]
temps = [r[2] for r in rows]
press = [r[3] for r in rows]
winds = [r[4] for r in rows]
rains = [r[5] for r in rows]
years = [r[6] for r in rows]
months = [r[7] for r in rows]

table = pa.Table.from_arrays([
    pa.array(stations),
    pa.array(times, type=pa.timestamp("ms", tz="UTC")),
    pa.array(temps, type=pa.float32()),
    pa.array(press, type=pa.float32()),
    pa.array(winds, type=pa.float32()),
    pa.array(rains, type=pa.float32()),
    pa.array(years, type=pa.int32()),
    pa.array(months, type=pa.int32())
], schema=schema)

# 3. Write to Hive-Partitioned Parquet Dataset with Zstandard Compression
print(f"[*] Compacting into Columnar Lakehouse at '{LAKE_ROOT}'...")
pq.write_to_dataset(
    table,
    root_path=LAKE_ROOT,
    partition_cols=["year", "month"],
    compression="zstd",
    compression_level=7,
    row_group_size=250000,
    use_dictionary=["station_id"]
)

compaction_time = time.time() - start_time
print(f"[+] Compaction complete in {compaction_time:.2f}s.")

# 4. Forensic Verification using DuckDB
print("\n[*] Validating Cold Lakehouse using DuckDB Vectorized Scans...")
con = duckdb.connect()
audit_sql = f"""
SELECT 
    year, 
    month, 
    COUNT(*) AS records_stored,
    ROUND(AVG(temperature), 2) AS mean_temp,
    ROUND(MAX(wind_speed), 2) AS peak_gust
FROM read_parquet('{LAKE_ROOT}/**/*.parquet', hive_partitioning=true, union_by_name=true)
GROUP BY year, month
ORDER BY year DESC, month DESC;
"""
print(con.execute(audit_sql).fetchdf().to_string(index=False))

# 5. O(1) Instant Partition Retirement Command (Instructional)
print("\n================== OPERATIONAL RETIREMENT COMMAND ==================")
print("To reclaim PostgreSQL disk space instantly with ZERO dead-tuple bloat:")
print("  ALTER TABLE raw_telemetry_partitioned DETACH PARTITION telemetry_y2026m10 CONCURRENTLY;")
print("  DROP TABLE telemetry_y2026m10;")
print("====================================================================\n")
