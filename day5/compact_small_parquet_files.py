#!/usr/bin/env python3
"""
Automated Hive Partition Compaction & Small Files Problem Lab (compact_small_parquet_files.py)
Simulates an over-partitioned "Small Files" telemetry data lake (hundreds of tiny ~1-10 KB
Parquet files) and compacts them into optimal ZSTD-compressed, dictionary-encoded Parquet
row groups using PyArrow and DuckDB, measuring storage and scan latency improvements.
"""

import os
import shutil
import time
import duckdb
import pyarrow as pa
import pyarrow.dataset as ds
import pyarrow.parquet as pq

RAW_DIR = "fragmented_lake"
COMPACTED_DIR = "compacted_lake"
NUM_TINY_FILES = 200
ROWS_PER_TINY_FILE = 500  # 200 files * 500 rows = 100,000 rows split across 200 tiny files

print("=================================================================")
print("  LAKEHOUSE COMPACTION LAB: SOLVING THE 'SMALL FILES PROBLEM'    ")
print("=================================================================")

# 1. Synthesize an Over-Partitioned "Small Files" Anti-Pattern
print(f"[*] Generating fragmented data lake ({NUM_TINY_FILES} tiny files of {ROWS_PER_TINY_FILE} rows each)...")
if os.path.exists(RAW_DIR):
    shutil.rmtree(RAW_DIR)
os.makedirs(RAW_DIR, exist_ok=True)

schema = pa.schema([
    ("station_id", pa.string()),
    ("recorded_at", pa.timestamp("ms")),
    ("temperature", pa.float32()),
    ("wind_speed", pa.float32()),
    ("year", pa.int32()),
    ("month", pa.int32())
])

base_time = 1790900000000
for i in range(NUM_TINY_FILES):
    table = pa.Table.from_arrays([
        pa.array([f"AWS-{(j % 50) + 1:03d}" for j in range(ROWS_PER_TINY_FILE)]),
        pa.array([base_time + ((i * ROWS_PER_TINY_FILE + j) * 1000) for j in range(ROWS_PER_TINY_FILE)], type=pa.timestamp("ms")),
        pa.array([18.5 + (j % 5) * 0.4 for j in range(ROWS_PER_TINY_FILE)], type=pa.float32()),
        pa.array([5.2 + (j % 3) * 1.1 for j in range(ROWS_PER_TINY_FILE)], type=pa.float32()),
        pa.array([2026] * ROWS_PER_TINY_FILE, type=pa.int32()),
        pa.array([10] * ROWS_PER_TINY_FILE, type=pa.int32())
    ], schema=schema)

    part_dir = os.path.join(RAW_DIR, f"year=2026/month=10/batch_{i:03d}")
    os.makedirs(part_dir, exist_ok=True)
    pq.write_table(table, os.path.join(part_dir, "tiny_part.parquet"), compression="snappy")

# 2. Audit Helper Function
def audit_lake(root_path):
    total_files = 0
    total_bytes = 0
    for root, _, files in os.walk(root_path):
        for f in files:
            if f.endswith(".parquet"):
                total_files += 1
                total_bytes += os.path.getsize(os.path.join(root, f))
    avg_size_kb = (total_bytes / total_files / 1024) if total_files else 0
    return total_files, total_bytes / (1024 * 1024), avg_size_kb

files_before, mb_before, avg_kb_before = audit_lake(RAW_DIR)
print(f"  • Before Compaction : {files_before:3d} files | {mb_before:6.2f} MB total | Avg Size: {avg_kb_before:6.1f} KB/file")

# 3. Compact Using PyArrow Dataset API
print("\n[*] Executing automated partition compaction into ZSTD Row Groups...")
t0 = time.time()
dataset = ds.dataset(RAW_DIR, format="parquet", partitioning="hive")

# Scan the fragmented dataset into a unified Arrow table sorted by station_id & recorded_at
consolidated_table = dataset.to_table().sort_by([("station_id", "ascending"), ("recorded_at", "ascending")])

if os.path.exists(COMPACTED_DIR):
    shutil.rmtree(COMPACTED_DIR)

pq.write_to_dataset(
    consolidated_table,
    root_path=COMPACTED_DIR,
    partition_cols=["year", "month"],
    compression="zstd",
    compression_level=7,
    row_group_size=250_000,
    use_dictionary=["station_id"]
)
duration = time.time() - t0

files_after, mb_after, avg_kb_after = audit_lake(COMPACTED_DIR)
print(f"  • After Compaction  : {files_after:3d} file(s) | {mb_after:6.2f} MB total | Avg Size: {avg_kb_after:6.1f} KB/file")
print(f"[+] Compaction complete in {duration:.2f}s. Storage reduced by {((mb_before - mb_after)/mb_before)*100:.1f}%!")

# 4. Benchmark DuckDB Scan Speed: 200 Tiny Files vs. 1 Compacted ZSTD File
con = duckdb.connect()

def benchmark_duckdb_scan(label, glob_pattern):
    query = f"""
    SELECT station_id, COUNT(*), ROUND(AVG(temperature), 2), ROUND(MAX(wind_speed), 2)
    FROM read_parquet('{glob_pattern}', hive_partitioning=true)
    GROUP BY station_id;
    """
    timings = []
    for _ in range(5):
        t_start = time.time()
        con.execute(query).fetchall()
        timings.append(time.time() - t_start)
    print(f"  DuckDB Scan -> {label:32} : {min(timings)*1000:6.2f} ms")

print("\n================== DUCKDB QUERY LATENCY AUDIT ==================")
benchmark_duckdb_scan(f"Fragmented Lake ({NUM_TINY_FILES} tiny files)", f"{RAW_DIR}/**/*.parquet")
benchmark_duckdb_scan("Compacted Lake (1 ZSTD file)", f"{COMPACTED_DIR}/**/*.parquet")
print("================================================================\n")
