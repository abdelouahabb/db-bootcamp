#!/usr/bin/env python3
"""
Parquet vs. CSV Meteorological Benchmarking & Forensics Lab (parquet_vs_csv_benchmark.py)
Measures physical file sizes, write timings, compression ratios (Uncompressed, Snappy, ZSTD
with Dictionary Encoding), and DuckDB vectorized analytical scan speeds over 1,000,000 rows.
"""

import os
import time
import duckdb
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

TOTAL_ROWS = 1_000_000
CSV_FILE = "weather_1m.csv"
PQ_RAW = "weather_1m_raw.parquet"
PQ_SNAPPY = "weather_1m_snappy.parquet"
PQ_ZSTD = "weather_1m_zstd.parquet"

print("=================================================================")
print(f"  BENCHMARK: PARQUET VS. CSV OVER {TOTAL_ROWS:,} WEATHER RECORDS   ")
print("=================================================================")

# 1. Synthesize 1,000,000 Meteorological Records
print("[*] Generating synthetic meteorological vectors in memory...")
np.random.seed(42)
station_pool = np.array([f"AWS-{i:03d}" for i in range(1, 51)])
region_pool = np.array(["COASTAL_MED", "TELL_ATLAS", "STEPPE_PLATEAU", "SAHARA_NORTH"])

base_timestamp = np.datetime64("2026-01-01T00:00:00", "ms")
time_deltas = np.arange(TOTAL_ROWS, dtype="timedelta64[s]")
timestamps = base_timestamp + time_deltas

stations = np.random.choice(station_pool, size=TOTAL_ROWS)
regions = np.random.choice(region_pool, size=TOTAL_ROWS)
temperatures = np.round(np.random.normal(loc=18.5, scale=7.5, size=TOTAL_ROWS).astype(np.float32), 2)
pressures = np.round(np.random.normal(loc=1013.25, scale=10.0, size=TOTAL_ROWS).astype(np.float32), 2)
wind_speeds = np.round(np.random.weibull(a=2.0, size=TOTAL_ROWS).astype(np.float32) * 6.0, 2)
rain_accum = np.where(
    np.random.random(TOTAL_ROWS) < 0.08,
    np.round(np.random.exponential(scale=2.5, size=TOTAL_ROWS).astype(np.float32), 2),
    0.0
)

arrow_schema = pa.schema([
    ("station_id", pa.string()),
    ("region", pa.string()),
    ("recorded_at", pa.timestamp("ms")),
    ("temperature", pa.float32()),
    ("pressure", pa.float32()),
    ("wind_speed", pa.float32()),
    ("rain_accum", pa.float32())
])

table = pa.Table.from_arrays([
    pa.array(stations),
    pa.array(regions),
    pa.array(timestamps),
    pa.array(temperatures),
    pa.array(pressures),
    pa.array(wind_speeds),
    pa.array(rain_accum)
], schema=arrow_schema)

df = table.to_pandas()

# 2. Write CSV
print(f"[*] Writing {CSV_FILE}...")
t0 = time.time()
df.to_csv(CSV_FILE, index=False)
csv_write_time = time.time() - t0

# 3. Write Uncompressed Parquet
print(f"[*] Writing {PQ_RAW} (Uncompressed)...")
t0 = time.time()
pq.write_table(table, PQ_RAW, compression="none", row_group_size=250_000)
pq_raw_write_time = time.time() - t0

# 4. Write Snappy Parquet (Dictionary Encoded)
print(f"[*] Writing {PQ_SNAPPY} (Snappy + Dictionary Encoding)...")
t0 = time.time()
pq.write_table(
    table,
    PQ_SNAPPY,
    compression="snappy",
    row_group_size=250_000,
    use_dictionary=["station_id", "region"]
)
pq_snappy_write_time = time.time() - t0

# 5. Write ZSTD Parquet (Dictionary Encoded + ZSTD Level 7)
print(f"[*] Writing {PQ_ZSTD} (Zstandard Level 7 + Dictionary Encoding)...")
t0 = time.time()
pq.write_table(
    table,
    PQ_ZSTD,
    compression="zstd",
    compression_level=7,
    row_group_size=250_000,
    use_dictionary=["station_id", "region"]
)
pq_zstd_write_time = time.time() - t0

# 6. Physical Size Audit
size_csv = os.path.getsize(CSV_FILE) / (1024 * 1024)
size_raw = os.path.getsize(PQ_RAW) / (1024 * 1024)
size_snappy = os.path.getsize(PQ_SNAPPY) / (1024 * 1024)
size_zstd = os.path.getsize(PQ_ZSTD) / (1024 * 1024)

print("\n================== PHYSICAL DISK AUDIT ==================")
print(f"  • Raw CSV File Size             : {size_csv:6.2f} MB (1.00x baseline | Write: {csv_write_time:.2f}s)")
print(f"  • Uncompressed Parquet Size     : {size_raw:6.2f} MB ({size_csv/size_raw:4.2f}x savings  | Write: {pq_raw_write_time:.2f}s)")
print(f"  • Snappy Parquet Size (Default) : {size_snappy:6.2f} MB ({size_csv/size_snappy:4.2f}x savings  | Write: {pq_snappy_write_time:.2f}s)")
print(f"  • Zstandard Parquet Size (ZSTD) : {size_zstd:6.2f} MB ({size_csv/size_zstd:4.2f}x savings  | Write: {pq_zstd_write_time:.2f}s)")
print("=========================================================\n")

# 7. DuckDB Analytical Scan Benchmark
con = duckdb.connect()

def benchmark_scan(name, source_expr):
    query = f"""
    SELECT 
        ROUND(AVG(temperature), 2) AS mean_temp,
        ROUND(MAX(wind_speed), 2) AS max_gust
    FROM {source_expr}
    WHERE temperature > -50.0;
    """
    timings = []
    for _ in range(5):
        t_start = time.time()
        con.execute(query).fetchall()
        timings.append(time.time() - t_start)
    best_time_ms = min(timings) * 1000
    print(f"  Scan Benchmark -> {name:20} : {best_time_ms:6.2f} ms")

print("[*] Running DuckDB Analytical Query: AVG(temp), MAX(wind) over 1,000,000 rows...")
benchmark_scan("CSV File", f"read_csv_auto('{CSV_FILE}')")
benchmark_scan("Parquet Uncompressed", f"read_parquet('{PQ_RAW}')")
benchmark_scan("Parquet Snappy", f"read_parquet('{PQ_SNAPPY}')")
benchmark_scan("Parquet ZSTD", f"read_parquet('{PQ_ZSTD}')")

# 8. Parquet Metadata Inspection
print("\n================== PARQUET METADATA FORENSICS ==================")
meta_query = f"""
SELECT 
    row_group_id,
    path_in_schema AS column_name,
    encodings,
    stats_min,
    stats_max,
    stats_null_count
FROM parquet_column_metadata('{PQ_ZSTD}')
WHERE path_in_schema IN ('station_id', 'temperature')
LIMIT 4;
"""
print(con.execute(meta_query).fetchdf().to_string(index=False))
print("================================================================\n")
