# Hive Partitioning & Data Lakehouse Architecture Reference Card

## Physical Directory Topologies, Metadata Pruning, The Small Files Problem, and Modern Table Formats

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./02_duckdb_vectorized_olap_vs_sqlite.md) | **Card 03 of 13** | [Next Card ➡️](./04_meteorological_gridded_formats_cog_zarr_netcdf_grib_bufr.md)

## 🧭 Quick-Jump Table of Contents

- [Executive Summary for Systems & Meteorological Engineers](#executive-summary-for-systems--meteorological-engineers)
- [1. Physical Directory Anatomy of Hive Partitioning](#1-physical-directory-anatomy-of-hive-partitioning)
  - [1.1 Virtual Column Synthesis](#11-virtual-column-synthesis)
- [2. Directory Pruning Mechanics](#2-directory-pruning-mechanics)
  - [2.1 The Two-Phase Pruning Pipeline](#21-the-two-phase-pruning-pipeline)
  - [2.2 S3 / Cloud Object Storage Impact](#22-s3--cloud-object-storage-impact)
- [3. The "Small Files Problem" & Sizing Rules](#3-the-small-files-problem--sizing-rules)
  - [3.1 The Mechanical Penalties of Small Files](#31-the-mechanical-penalties-of-small-files)
  - [3.2 Sizing Rules of Thumb](#32-sizing-rules-of-thumb)
- [4. Partitioning vs. Bucketing vs. Z-Ordering / Sorting](#4-partitioning-vs-bucketing-vs-z-ordering--sorting)
- [5. Modern Table Formats: Beyond Plain Hive Directories](#5-modern-table-formats-beyond-plain-hive-directories)
  - [5.1 The Limitations of Plain Hive](#51-the-limitations-of-plain-hive)
  - [5.2 The Modern Standard: Apache Iceberg & Hidden Partitioning](#52-the-modern-standard-apache-iceberg--hidden-partitioning)
- [6. Lakehouse Maintenance: Automated File Compaction & Pruning Lab](#6-lakehouse-maintenance-automated-file-compaction--pruning-lab)
  - [6.1 Compaction Script (`compact_lake_partitions.py`)](#61-compaction-script-compact_lake_partitionspy)
- [7. Summary Checklist: Hive Partitioning Rules](#7-summary-checklist-hive-partitioning-rules)

---

### Executive Summary for Systems & Meteorological Engineers

In large-scale environmental monitoring and climatological data lakes, storing billions of continuous telemetry records in a single flat directory creates an unmanageable I/O and metadata bottleneck. Filesystem directory lookups degrade to linear scans, cloud object storage API rate limits are quickly exceeded, and query engines must list hundreds of thousands of irrelevant objects before executing a query.

The **Hive Partitioning Scheme** (originally designed for the Apache Hadoop/Hive ecosystem and now standardized across DuckDB, Apache Spark, Trino, and Presto) solves this problem by structuring data into deterministic, key-value filesystem directory hierarchies.

This reference guide provides an architectural breakdown of:
1. **Physical Directory Topologies:** Key-value directory paths, path parsing, and multi-tier partitioning schemas.
2. **Directory Pruning Mechanics:** How query planners bypass operating system directory traversals and cloud storage listings.
3. **The "Small Files Problem" & Sizing Rules:** Metadata saturation, object storage GET latency, and automated file compaction patterns.
4. **Partitioning vs. Bucketing vs. Z-Ordering:** When to partition by directory, when to hash-bucket, and when to sort column pages.
5. **Modern Table Formats Evolution:** From legacy Hive Metastore manifests to modern metadata specifications (Apache Iceberg, Delta Lake).
6. **Production Python & DuckDB Lake Maintenance:** Automated compaction, partition health auditing, and pruning verification.

---

## 1. Physical Directory Anatomy of Hive Partitioning

Hive partitioning encodes table attributes directly into the directory path names using an explicit `key=value` naming convention:

```
                            Hive Partitioning Directory Tree
 climatology_lake/
 ├── year=2024/
 │   ├── month=09/
 │   │   ├── region=COASTAL_MED/
 │   │   │   ├── part-000.parquet
 │   │   │   └── part-001.parquet
 │   │   └── region=TELL_ATLAS/
 │   │       └── part-000.parquet
 │   └── month=10/
 │       └── region=COASTAL_MED/
 │           └── part-000.parquet
 └── year=2025/
     └── month=01/
         └── region=SAHARA_NORTH/
             └── part-000.parquet
```

### 1.1 Virtual Column Synthesis
When a vectorized query engine (DuckDB, Spark, Arrow) scans a Hive-partitioned directory tree:
* It parses the path strings using regular expressions matching the `key=value` pattern.
* The directory keys (`year`, `month`, `region`) are **synthesized as virtual columns** in the query engine's memory table.
* **Storage Deduplication:** Because `year`, `month`, and `region` are embedded in the filesystem path, they do not need to be physically stored inside the underlying Parquet or ORC data files, eliminating gigabytes of redundant column data on disk.

```
                    Path Parsing to Virtual Schema Vector
 File Path: "climatology_lake/year=2026/month=10/part_0.parquet"
 
   Parsed Directory Path                      In-Memory Data Vector
 ┌──────────────────────┐                     ┌─────────────┬───────┬───────┐
 │ year  = 2026         │ ──────────────────> │ station_id  │ year  │ month │
 │ month = 10           │ (Virtual Columns)   ├─────────────┼───────┼───────┤
 └──────────────────────┘                     │ AWS-001     │ 2026  │ 10    │
   Physical File Payload                      │ AWS-002     │ 2026  │ 10    │
 ┌──────────────────────┐                     └─────────────┴───────┴───────┘
 │ station_id, temp, ws │ ──────────────────>
 └──────────────────────┘
```

---

## 2. Directory Pruning Mechanics

### 2.1 The Two-Phase Pruning Pipeline
When an analyst executes an analytical query:
```sql
SELECT AVG(temperature) 
FROM read_parquet('climatology_lake/**/*.parquet', hive_partitioning=true)
WHERE year = 2026 AND month = 10;
```

The query engine executes directory pruning **prior to reading file contents**:

```
                         Directory Pruning Flowchart
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ 1. Query AST Evaluation: Identify filters on virtual partition keys         │
 │    Predicate: (year = 2026 AND month = 10)                                  │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ 2. Directory Enumeration: Match filesystem globs against predicate         │
 │    • MATCH:    climatology_lake/year=2026/month=10/part_*.parquet           │
 │    • PRUNED:   climatology_lake/year=2024/... [SKIPPED AT FS LEVEL]         │
 │    • PRUNED:   climatology_lake/year=2025/... [SKIPPED AT FS LEVEL]         │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ 3. Physical I/O Dispatch: Open ONLY matching Parquet file handles           │
 │    Zero file handles or HTTP requests allocated for non-matching folders.   │
 └─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 S3 / Cloud Object Storage Impact
On local POSIX filesystems (ext4, XFS), directory pruning eliminates directory inode scans. On cloud object stores (Amazon S3, Google Cloud Storage, MinIO), the impact is even more pronounced:
* S3 is a flat key-value store with no native nested directories; directory paths are simulated via string prefixes (`prefix = "climatology_lake/year=2026/month=10/"`).
* Directory pruning restricts the `s3:ListObjectsV2` HTTP API request strictly to the surviving prefix.
* Bypasses hundreds of thousands of remote HTTP list calls, dropping metadata latency from 30 seconds to **under 50 milliseconds**.

---

## 3. The "Small Files Problem" & Sizing Rules

The most common architectural failure in telemetry data lakes is **over-partitioning**.

```
                              The Partitioning Spectrum
 ┌─────────────────────────────┬─────────────────────────────┬─────────────────────────────┐
 │ Over-Partitioned (Anti-Pat) │ Production Target Zone      │ Under-Partitioned           │
 │ (e.g., minute=MM/second=SS) │ (e.g., year=YYYY/month=MM)  │ (Single flat directory)     │
 ├─────────────────────────────┼─────────────────────────────┼─────────────────────────────┤
 │ • Millions of < 1 MB files  │ • 128 MB to 512 MB files    │ • Monolithic multi-GB files │
 │ • Metadata dominates RAM    │ • Optimal compression ratio │ • No directory pruning      │
 │ • S3 GET billing explosion  │ • Fits L3 / Thread memory   │ • High seek latencies       │
 │ • Inode & file handle crash │ • Fast parallel chunk scans │ • Stranded single-thread I/O│
 └─────────────────────────────┴─────────────────────────────┴─────────────────────────────┘
```

### 3.1 The Mechanical Penalties of Small Files
1. **Metadata Overhead Ratio:** A $64\text{ KB}$ Parquet file contains approximately $8\text{ KB}$ of Thrift metadata and dictionary headers. Metadata consumes $>12\%$ of total storage space.
2. **Loss of Columnar Compression:** Encodings like Run-Length Encoding (RLE) and Delta-of-Delta temporal compression require large contiguous sample sets ($> 100,000$ rows) to achieve high compression ratios. In tiny files, entropy remains high.
3. **HTTP Overhead in Cloud Lakes:** S3 charges per 1,000 `GET` requests. Fetching 10,000 tiny files ($1\text{ MB}$ each) incurs 10,000 HTTP connection handshakes and round-trip latencies, compared to a single streaming request for a $100\text{ MB}$ file.

### 3.2 Sizing Rules of Thumb
* **Target File Size:** Aim for **$128\text{ MB}$ to $512\text{ MB}$** per Parquet file.
* **Target Row Group Size:** Configure Row Groups between **$128\text{ MB}$ and $256\text{ MB}$** uncompressed ($\approx 250,000$ to $1,000,000$ rows).
* **Partition Granularity Rule:** Partition by coarse temporal attributes (`year=YYYY/month=MM`). Never partition by day, hour, or minute unless individual hours produce gigabytes of data.

---

## 4. Partitioning vs. Bucketing vs. Z-Ordering / Sorting

Modern lakehouses combine three hierarchical data layout strategies:

| Technique | Physical Mechanism | Primary Use Case | Query Benefit |
| :--- | :--- | :--- | :--- |
| **Partitioning** | Filesystem directory paths (`year=2026/month=10/`). | Coarse, low-cardinality filters (`year`, `month`, `region`). | Coarse-grained directory pruning without reading file headers. |
| **Bucketing (Clustering)** | Hash-partitioning rows into fixed $N$ files based on hash: `hash(station_id) % 16`. | High-cardinality join keys (`station_id`). | Accelerates joins between massive tables; identical hashes reside in matching files. |
| **Z-Ordering / Sorting** | Physical row ordering within Parquet row groups by space-filling curve. | Multi-dimensional range queries (`latitude`, `longitude`, `timestamp`). | Tightens Parquet min/max statistics, enabling maximum Row Group skipping. |

```
                       The 3-Tier Lakehouse Layout Strategy
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ Level 1: Directory Partitioning                                             │
 │ path: climatology_lake/year=2026/month=10/                                  │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ Level 2: Station Hash Bucketing                                             │
 │ file: bucket_004.parquet  (stores hash(station_id) % 16 == 4)               │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ Level 3: Row Group Sorting / Z-Order                                        │
 │ Row Group 0: Sorted by (recorded_at, temperature)                           │
 │   - Page Min/Max: 2026-10-01 to 2026-10-03 (Enables precise Page Skipping) │
 └─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Modern Table Formats: Beyond Plain Hive Directories

While raw Hive directory trees are universal, production data lakehouses increasingly run on metadata table specifications:

```
                            Table Format Evolution
 ┌──────────────────────────────────┐      ┌──────────────────────────────────┐
 │ Plain Hive Directory Partitioning │ ───> │ Modern Lakehouse (Apache Iceberg)│
 └──────────────────────────────────┘      └──────────────────────────────────┘
   • No ACID guarantees                      • Full ACID transactions & snapshots
   • Listing files requires directory scan   • Manifest files track exact byte files
   • Partition schema is frozen              • Hidden Partitioning & Schema Evolution
   • Concurrent writes cause corruption      • Safe multi-writer optimistic concurrency
```

### 5.1 The Limitations of Plain Hive
* **No ACID Transactions:** An append job interrupted halfway leaves partial Parquet files that pollute subsequent reads.
* **Slow Directory Listing:** Queries over 10 years of data must list thousands of folders using filesystem system calls.
* **Rigid Partitioning:** Changing the partition strategy from monthly to daily requires a complete data rewrite.

### 5.2 The Modern Standard: Apache Iceberg & Hidden Partitioning
In **Apache Iceberg**, query engines read immutable JSON/Avro metadata manifests instead of scanning directories:
* **Hidden Partitioning:** Users write `WHERE recorded_at >= '2026-10-01'`; Iceberg automatically calculates partition offsets without exposing virtual partition keys to user SQL.
* **Snapshot Isolation:** Readers never see partial writes; write operations commit atomically by updating the root metadata pointer.

---

## 6. Lakehouse Maintenance: Automated File Compaction & Pruning Lab

This executable Python script demonstrates how to audit an over-partitioned "small files" telemetry directory and compact it into optimized $128\text{ MB}$ Hive-partitioned files using PyArrow.

### 6.1 Compaction Script (`compact_lake_partitions.py`)

```python
#!/usr/bin/env python3
"""
Automated Hive Partition Compaction & Audit Tool
Detects fragmented tiny files across a data lake and compacts them into
production-sized Parquet files with optimal row groups and dictionary encodings.
"""

import os
import shutil
import time
import pyarrow as pa
import pyarrow.dataset as ds
import pyarrow.parquet as pq

RAW_DIR = "fragmented_lake"
COMPACTED_DIR = "compacted_lake"

# 1. Synthesize an Over-Partitioned "Small Files" Anti-Pattern
print("[*] Generating fragmented data lake (anti-pattern simulation)...")
os.makedirs(RAW_DIR, exist_ok=True)

schema = pa.schema([
    ("station_id", pa.string()),
    ("recorded_at", pa.timestamp("ms")),
    ("temperature", pa.float32()),
    ("wind_speed", pa.float32()),
    ("year", pa.int32()),
    ("month", pa.int32())
])

# Write 50 tiny files of 2,000 rows each (Anti-Pattern)
base_time = 1790900000000
for i in range(50):
    n_rows = 2000
    table = pa.Table.from_arrays([
        pa.array([f"AWS-{j:03d}" for j in range(n_rows)]),
        pa.array([base_time + (j * 1000) for j in range(n_rows)], type=pa.timestamp("ms")),
        pa.array([18.5 + (j % 5) for j in range(n_rows)], type=pa.float32()),
        pa.array([5.2 + (j % 3) for j in range(n_rows)], type=pa.float32()),
        pa.array([2026] * n_rows, type=pa.int32()),
        pa.array([10] * n_rows, type=pa.int32())
    ], schema=schema)

    part_dir = os.path.join(RAW_DIR, f"year=2026/month=10/run_{i:02d}")
    os.makedirs(part_dir, exist_ok=True)
    pq.write_table(table, os.path.join(part_dir, "data.parquet"), compression="snappy")

# 2. Audit Fragmented Lake
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
print(f"  • Before Compaction: {files_before} files | {mb_before:.2f} MB total | Avg Size: {avg_kb_before:.1f} KB/file")

# 3. Compact Using PyArrow Dataset API
print("\n[*] Executing automated partition compaction...")
t0 = time.time()
dataset = ds.dataset(RAW_DIR, format="parquet", partitioning="hive")

# Scan the entire fragmented dataset into unified memory table
consolidated_table = dataset.to_table()

# Re-write into clean Hive partition directories with 250,000-row row groups
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
print(f"  • After Compaction : {files_after} file(s) | {mb_after:.2f} MB total | Avg Size: {avg_kb_after:.1f} KB/file")
print(f"[+] Compaction complete in {duration:.2f}s. Storage reduced by {((mb_before - mb_after)/mb_before)*100:.1f}%.")
```

---

## 7. Summary Checklist: Hive Partitioning Rules

```text
================================================================================
             HIVE PARTITIONING & LAKEHOUSE CHECKLIST
================================================================================
 1. Key-Value Syntax    : Always use key=value/ paths (e.g., year=2026/month=10/).
                          Allows query engines to parse keys as virtual columns.
 2. Coarse Granularity  : Partition by Year, Month, or Region. NEVER by Second,
                          Minute, or High-Cardinality Sensor ID.
 3. Target File Size    : Maintain Parquet files between 128 MB and 512 MB.
 4. Compact Regularly   : Merge high-frequency streaming writes into large files
                          to prevent S3 metadata throttling and restore RLE compression.
 5. Pushdown Verification: Run EXPLAIN on your queries to verify that non-matching
                          directories are pruned prior to physical data reads.
================================================================================
```
---

### 🔗 Reference Library Navigation

> **Navigation:** [🏠 Bootcamp Home](../README.md) | [📚 Reference Cards Index](./README.md) | [🌐 Interactive Portal](../bootcamp_portal.html)  
> **Card Sequence:** [⬅️ Previous Card](./02_duckdb_vectorized_olap_vs_sqlite.md) | **Card 03 of 13** | [Next Card ➡️](./04_meteorological_gridded_formats_cog_zarr_netcdf_grib_bufr.md) | [⬆️ Back to Top](#hive-partitioning--data-lakehouse-architecture-reference-card)
