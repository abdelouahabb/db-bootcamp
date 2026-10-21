> **Navigation:** [Master README](../README.md) | [Interactive Portal](../bootcamp_portal.html) | [⬅ Day 3: PostgreSQL Scaling](../day3/day3_master_coursebook.md) | [Day 4 Coursebook](day4_master_coursebook.md) | [Day 5: Analytical OLAP & Lakehouse](../day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | [Reference Cards](../reference_cards/README.md)

# MongoDB Architecture, Storage Internals, High Availability (Replica Sets) & Sharding Reference Guide

**Target Audience:** Weather Forecast & Meteorological Systems Engineers  
**Bootcamp Context:** Deep-dive reference covering **BSON binary encoding**, **WiredTiger storage engine & cache checkpoints**, **3-node Replica Set consensus & `rs.*` administration**, **PyMongo read-preference workload isolation**, **Tunable CAP/PACELC durability**, **GridFS vs. Object Storage**, and **Multi-Node Sharded Clusters (`sh.*`)**.

---

## Executive Summary for Systems & Weather Engineers

Relational systems excel at structured schemas and relational joins. However, modern environmental monitoring networks produce heterogeneous, schema-drifting sensor packets (e.g., sonic anemometers emitting 3D wind velocity vectors vs. optical disdrometers emitting precipitation spectrum drop-size arrays vs. radiosonde balloons emitting 50-level vertical atmospheric profiles).

When relational tables attempt to accommodate these payloads via 150 nullable columns or inefficient Entity-Attribute-Value (EAV) models, tuple density collapses and write amplification spikes.

MongoDB addresses these workloads through **polymorphic BSON document storage**, **tunable CAP/PACELC consistency levels**, **native time-series bucket compression**, **built-in Raft-based Replica Set failover**, and **distributed horizontal sharding**.

---

## 1. Core Data Representation: BSON vs. JSON

While developers interact with MongoDB using standard JSON representations, MongoDB physically stores and indexes data in **BSON** (Binary JSON).

```text
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                                JSON vs. BSON                                │
 ├──────────────────────────────┬──────────────────────────────────────────────┤
 │ Textual JSON                 │ Binary BSON (Physical On-Disk Format)        │
 ├──────────────────────────────┼──────────────────────────────────────────────┤
 │ • Human readable (ASCII/UTF8)│ • Machine readable (typed binary payload)     │
 │ • Slow parsing & traversal   │ • Traversed via length prefixes in O(1)      │
 │ • No native Binary / Date    │ • Explicit types: UTC Date, Int32, Int64,    │
 │ • Numbers lack precision     │   Double, Decimal128, BinData, ObjectId      │
 │ • Space-heavy text numbers   │ • Fixed 8-byte IEEE 754 floats               │
 └──────────────────────────────┴──────────────────────────────────────────────┘
```

### 1.1 Fast Field Skipping via Length Prefixes
Unlike plain-text JSON (which forces the CPU to scan every character sequentially to locate the 10th field), BSON encodes explicit byte-length headers in front of every document, sub-document, and string. When a query inspects `{ "diagnostics.door_open": true }`, WiredTiger jumps directly across byte offsets without parsing preceding telemetry arrays.

### 1.2 The 16 MB Document Limit & Field Name Duplication Tax
* **Max Document Size:** MongoDB enforces a strict physical document limit of **16 MB**. This boundary prevents individual documents from consuming excessive RAM in the buffer pool or blocking network socket serialization pipelines.
  * *Antipattern Warning:* Never append continuous hourly observations into an unbounded array inside a single `station` document!
* **Field Name Duplication Tax:** Unlike relational systems where column names are defined once in catalog metadata (`pg_attribute`), **every BSON document carries its own field keys**.
  * Storing `{"temperature_celsius": 21.4}` repeated 100 million times wastes gigabytes on storing the ASCII string `"temperature_celsius"` in memory.
  * **Remediation:** Leverage **WiredTiger `zstd` block compression**, the **Manual Bucket Pattern**, or native **Time-Series Collections (`system.buckets.*`)**.

> [!WARNING]
> **Production Pitfall (The Unbounded Array 16 MB Crash):**  
> Never `$push` continuous 1-minute weather station observations into an array inside a single `station` document! Not only will it hit the hard `16 MB` BSON size ceiling (`BSONObjectTooLarge`), but WiredTiger must rewrite the entire multi-megabyte document on every 1-minute append, causing catastrophic disk I/O amplification. Always use Native Time-Series Collections (`system.buckets.*`) or bounded 1-hour bucket documents!

---

## 2. Storage Engine Internals: The WiredTiger Architecture

Since MongoDB 3.2, the default pluggable storage engine is **WiredTiger**. Unlike PostgreSQL (which rewrites an entire 8 KB heap tuple on every `UPDATE` and requires `VACUUM` to reclaim dead tuples), WiredTiger uses **Document-Level Concurrency** (via lock-free hazard pointers) and **Snappy / Zstandard (`zstd`) block compression**.

```text
                         WiredTiger Memory & Storage Architecture
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                               Total Host RAM                                │
 ├─────────────────────────────────────────────┬───────────────────────────────┤
 │ WiredTiger Internal Cache                   │ Linux OS Kernel Page Cache    │
 │ 50% of (Total RAM - 1 GB)                   │ Remaining ~50% of Host RAM    │
 ├─────────────────────────────────────────────┼───────────────────────────────┤
 │ • Uncompressed in-memory B-Tree pages       │ • Compressed disk page cache  │
 │ • Active dirty blocks awaiting checkpoint   │ • Zero-copy read buffer       │
 │ • Hazard pointers for lock-free read access │ • File system write-back      │
 └─────────────────────────────────────────────┴───────────────────────────────┘
                                       │
                                       ▼ Checkpoint (Every 60s or 2 GB dirty)
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ Storage Drive (NVMe / SSD)                                                  │
 │ ┌─────────────────────────┐  ┌────────────────────────────────────────────┐ │
 │ │ WiredTigerLog (Journal) │  │ collection-*.wt & index-*.wt (Data Files)  │ │
 │ │ Append-only sequential  │  │ Compressed via Snappy (default) or Zstd    │ │
 │ └─────────────────────────┘  └────────────────────────────────────────────┘ │
 └─────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 WiredTiger Cache Sizing & Eviction Thresholds
By default, WiredTiger allocates its internal cache as:

$$\text{Cache Size} = 0.50 \times (\text{Total RAM} - 1\text{ GB}) \quad (\text{minimum } 256\text{ MB})$$

* **Why not 100% of RAM?** WiredTiger relies on the Linux operating system page cache to hold compressed disk blocks. Uncompressing an 8 KB disk block into memory can inflate it to 20–32 KB. Holding uncompressed pages in the WiredTiger cache and compressed pages in the OS cache provides an optimal dual-tier memory hierarchy and leaves memory for aggregation pipeline stages.
* **Cache Eviction Triggers:**
  * When dirty cache bytes exceed **$5\%$** of the WiredTiger cache, background eviction threads spin up to flush dirty pages.
  * When dirty bytes exceed **$20\%$** (or total cache utilization reaches **$95\%$**), client application worker threads are forced to halt ingestion and participate in page eviction, introducing latency spikes on incoming sensor streams.

### 2.2 Write-Ahead Journaling & The Checkpoint Mechanism
* **Checkpoints:** Every **60 seconds** (or when 2 GB of dirty journal data accumulates), WiredTiger writes a consistent snapshot of all modified B-Tree pages to the `.wt` data files on disk.
* **The Journal (`WiredTigerLog`):** If power cuts between 60-second checkpoints, the `.wt` data files are up to 60 seconds stale. To guarantee ACID durability, MongoDB writes an append-only sequential redo log (the **Journal**, compressed via `zstd` or `snappy`).
* **Crash Recovery:** On reboot after an unclean shutdown, WiredTiger locates the last consistent checkpoint metadata in `WiredTiger.turtle` and replays all journal records forward from that checkpoint timestamp.

---

## 3. High Availability: 3-Node Replica Sets & Consensus Mechanics

Unlike PostgreSQL (which requires external orchestration tools like `Patroni` + `etcd` + `HAProxy` for automated failover), **MongoDB has Raft-based consensus, automated elections, and smart client-driver failover built directly into `mongod` and the official MongoDB drivers!**

### 3.1 Standard 3-Node Weather Center Replica Set (`rs_meteo`)
- **`mongo-node1` (Primary — `priority: 2`):** Accepts all writes (`synoptic_timeseries`, `radiosonde_soundings`, `cap_alerts`) and records every operation into `local.oplog.rs` (the **Oplog**).
- **`mongo-node2` (Secondary — `priority: 1`):** Replicates the Primary's Oplog continuously and is the preferred failover standby if `mongo-node1` goes down.
- **`mongo-node3` (Secondary — `priority: 0`, Tagged `{ workload: "analytics" }`):** Cannot become Primary (`priority: 0`), ensuring heavy upper-air aggregation pipelines and climatology queries run exclusively on `mongo-node3` without ever impacting live telemetry ingestion!

```mermaid
flowchart TB
    subgraph Drivers["Smart MongoDB Client Drivers (Python / Node / Compass)"]
        ING["Telemetry & BUFR Ingest\n(w: 'majority', retryWrites: true)"]
        ANA["Forecaster Aggregations\n(readPreference: 'secondary',\ntagSet: { workload: 'analytics' })"]
    end

    subgraph ReplicaSet["3-Node MongoDB Replica Set (rs_meteo)"]
        M1[("mongo-node1:27017\nPRIMARY (priority: 2)\nlocal.oplog.rs")]
        M2[("mongo-node2:27017\nSECONDARY (priority: 1)\nFailover Standby")]
        M3[("mongo-node3:27017\nSECONDARY (priority: 0)\nTagged: workload=analytics")]
    end

    ING ==>|"All Writes"| M1
    ANA ==>|"Analytical Reads"| M3
    M1 ==>|"Oplog Stream"| M2 & M3
    M1 <-->|"2s Heartbeats & Election Votes"| M2 & M3
```

### 3.2 Election Mechanics & Raft Quorum
* **Majority Quorum Formula:** To elect a Primary or sustain Primary status, a network partition must maintain a strict mathematical majority of voting nodes:

$$\text{Quorum Majority} = \left\lfloor \frac{N}{2} \right\rfloor + 1$$

  * In a 3-node replica set: $\lfloor 3/2 \rfloor + 1 = 2$ votes are required.
  * In a 5-node replica set: $\lfloor 5/2 \rfloor + 1 = 3$ votes are required.
* **Heartbeats & Election Timeouts:** Every node sends a heartbeat to peers every **2 seconds**. If `mongo-node1` fails to respond within **`electionTimeoutMillis` (default 10 seconds)**, `mongo-node2` and `mongo-node3` hold an election (`2 out of 3` majority vote) and promote `mongo-node2` to **Primary**.
* **Zero `HAProxy` Required:** Because the application connection string lists all 3 nodes (`mongodb://mongo-node1,mongo-node2,mongo-node3/?replicaSet=rs_meteo&retryWrites=true`), the client driver automatically discovers the new Primary and retries any in-flight write with zero manual intervention.
* **Why Even Numbers of Voting Nodes Are Prohibited:** A 2-node cluster has a quorum of 2. If one node drops, the remaining node has only 1 vote ($1 < 2$), cannot achieve a majority, and immediately steps down to read-only. Always deploy odd-numbered voting topologies ($3, 5, 7$).

### 3.3 The Oplog (`local.oplog.rs`) & Idempotency
* The **Oplog** (Operations Log) is a fixed-size capped collection residing in each node's `local` database.
* Every write modifying data on the Primary produces an **idempotent** operation entry. For example, an application command `{ $inc: { sample_count: 1 } }` is translated in the Oplog into an explicit `$set` of the resulting value so replaying an Oplog entry multiple times always yields the exact same document state.

### 3.4 The Rollback Hazard (Why `w: 1` Is Dangerous for Severe Weather Alerts)
What occurs if a Primary accepts writes with `w: 1` (acknowledged in Primary RAM before reaching Secondaries) and abruptly loses power or gets isolated by a network partition?
1. The remaining two Secondaries form a majority, elect a new Primary, and continue accepting writes on a new election term.
2. When the old Primary powers back on and rejoins, it discovers its local Oplog contains writes that never replicated to the new Primary.
3. **The Rollback:** The old Primary reverts its divergent `w: 1` writes, extracts the discarded documents into `.bson` files inside a local `rollback/` directory, and syncs its state to the new Primary.
4. **Meteorological Impact:** If life-safety CAP flash flood alerts were written with `w: 1`, those alerts vanish from the active collection after failover! Always enforce **`w: "majority", j: true`** for critical alerts and station metadata.

---

## 4. Step-by-Step: Deploying & Operating a 3-Node Replica Set

### 4.1 Step 1: Configure `/etc/mongod.conf` on All 3 Nodes (`10.20.2.11`, `.12`, `.13`)

1. Generate a shared Keyfile so the 3 `mongod` nodes can authenticate to each other:
   ```bash
   openssl rand -base64 756 > /etc/mongodb-keyfile
   chmod 400 /etc/mongodb-keyfile
   chown mongodb:mongodb /etc/mongodb-keyfile
   ```

2. Add network, security, and replication settings to `/etc/mongod.conf` on all 3 servers:
   ```yaml
   net:
     port: 27017
     bindIp: 127.0.0.1,10.20.2.11   # Use each node's respective IP

   security:
     keyFile: /etc/mongodb-keyfile

   replication:
     replSetName: "rs_meteo"
     oplogSizeMB: 20480             # 20 GB Oplog (holds 48-72h of bursty synoptic/radar writes!)
   ```

### 4.2 Step 2: Initialize the Replica Set in `mongosh` (Connect to `mongo-node1`)

```javascript
// Initialize the 3-node Replica Set with custom priorities and analytics workload tags!
rs.initiate({
  _id: "rs_meteo",
  members: [
    {
      _id: 0,
      host: "10.20.2.11:27017",
      priority: 2,                  // Preferred Primary
      tags: { dc: "algiers_main", workload: "operational" }
    },
    {
      _id: 1,
      host: "10.20.2.12:27017",
      priority: 1,                  // Hot Standby (becomes Primary if .11 fails)
      tags: { dc: "algiers_main", workload: "operational" }
    },
    {
      _id: 2,
      host: "10.20.2.13:27017",
      priority: 0,                  // Dedicated Analytics Replica (never becomes Primary!)
      tags: { dc: "oran_dr", workload: "analytics" }
    }
  ]
});
```

### 4.3 Step 3: Multi-Node Replica Set Administration & Failover Commands (`rs.*`)

```javascript
// 1. Check overall cluster health, current Primary, node states, and heartbeat latency:
rs.status();

// 2. Check Oplog Window (How many hours a Secondary can stay offline before needing a full resync!):
rs.printReplicationInfo();
// Example output:
// configured oplog size:   20480MB
// log length start to end: 214500secs (59.58hrs)

// 3. Check exact replication lag in seconds for every Secondary node:
rs.printSecondaryReplicationInfo();

// 4. PLANNED ZERO-DOWNTIME MAINTENANCE (Step Down the Primary):
// Forces mongo-node1 to hand over Primary leadership to mongo-node2 in ~1 second!
rs.stepDown(60); // Do not re-run for Primary for 60 seconds

// 5. Add a 4th node (e.g., a Hidden Delayed Node to protect against accidental drop() mistakes!):
rs.add({
  host: "10.20.2.14:27017",
  priority: 0,
  hidden: true,                     // Invisible to client applications
  secondaryDelaySecs: 3600          // Trails 1 hour behind Primary (saves you if someone drops a collection!)
});

// 6. Dynamically change node priorities or tags without restarting mongod:
var cfg = rs.conf();
cfg.members[1].priority = 3;        // Make node 1 the new preferred Primary
rs.reconfig(cfg);
```

---

## 5. Tunable CAP / PACELC & PyMongo Workload Isolation

MongoDB allows developers to tune consistency, durability, and latency per operation or connection using **Write Concerns (`w`)**, **Read Concerns (`rc`)**, and **Read Preferences**.

```text
                        Tunable Consistency Spectrum
                        
    WRITE CONCERNS (w)                               READ CONCERNS (rc)
 ┌─────────────────────────────────┐               ┌─────────────────────────────────┐
 │ w: 0                            │               │ "available" / "local"           │
 │ Fire-and-forget; no network ACK │               │ Returns current node memory.    │
 │ (High loss risk; maximum speed) │               │ Fast, but risk of dirty reads.  │
 ├─────────────────────────────────┤               ├─────────────────────────────────┤
 │ w: 1                            │               │ "majority"                      │
 │ Acknowledged by Primary memory. │               │ Returns data acknowledged by    │
 │ (Default. Fast, vulnerable to   │               │ a quorum; immune to rollbacks.  │
 │  split-brain rollback)          │               ├─────────────────────────────────┤
 ├─────────────────────────────────┤               │ "linearizable"                  │
 │ w: "majority"                   │               │ Enforces serializability; waits │
 │ Acknowledged by quorum nodes.   │               │ for primary to verify its lease.│
 │ (Zero rollback; ACID guarantee) │               ├─────────────────────────────────┤
 ├─────────────────────────────────┤               │ "snapshot"                      │
 │ j: true                         │               │ Point-in-time multi-document    │
 │ Redo journal flushed to NVMe.   │               │ transaction isolation.          │
 └─────────────────────────────────┘               └─────────────────────────────────┘
```

### 5.1 Read Preferences: Directing Analytical Load
* **`primary` (Default):** All reads query the primary node. Guarantees latest reads when paired with `"majority"` or `"linearizable"` read concern.
* **`primaryPreferred`:** Queries the primary unless unavailable, falling back to secondaries.
* **`secondary` / `secondaryPreferred`:** Routes reads to secondary nodes. Essential for heavy analytical reporting queries so long-running scans never degrade primary sensor ingestion.
* **`nearest`:** Routes reads to the replica node with the lowest network ping latency.

### 5.2 Meteorological Policy Mapping: CAP / PACELC Choices

| Meteorological Workload | CAP Strategy | Write Concern | Read Concern | Read Preference |
| :--- | :--- | :--- | :--- | :--- |
| **Emergency Disaster / Cyclone Alerts (`cap_alerts`)** | **CP** (Consistency Priority) | `w: "majority", j: true` | `"linearizable"` | `primary` |
| **High-Frequency Ingest ($1\text{ Hz}$ Sonic Wind)** | **AP** (Availability Priority) | `w: 1, j: false` | `"local"` | `primary` |
| **Public Mobile Weather App Reads** | **AP** (Latency Priority) | N/A (Read) | `"available"` | `nearest` |
| **Historical Climatological Summaries** | **AP** (Offloaded Read) | N/A (Read) | `"majority"` | `secondaryPreferred` (Tagged `analytics`) |

### 5.3 Routing Operational Writes vs. Forecaster Analytics in Python (`pymongo`)
Use the Replica Set connection URI and **Read Preference Tag Sets** so heavy climatology queries run strictly on `mongo-node3` (`workload: "analytics"`):

```python
from pymongo import MongoClient
from pymongo.read_preferences import SecondaryPreferred

# Connect to the 3-node Replica Set (driver auto-discovers topology & failovers)
URI = (
    "mongodb://weather_eng:StrongPass@10.20.2.11:27017,10.20.2.12:27017,10.20.2.13:27017/"
    "weather_nosql?replicaSet=rs_meteo&retryWrites=true&w=majority"
)
client = MongoClient(URI)

# 1. Operational Write Handle (Routes strictly to current Primary with majority durability):
ops_db = client.get_database("weather_nosql")

# 2. Forecaster Analytics Handle (Routes strictly to mongo-node3 tagged workload='analytics'!):
analytics_pref = SecondaryPreferred(tag_sets=[{"workload": "analytics"}])
analytics_db = client.get_database("weather_nosql", read_preference=analytics_pref)

# Heavy radiosonde aggregation runs 100% on mongo-node3 (10.20.2.13)!
result = list(analytics_db.radiosonde_soundings.aggregate([
    {"$unwind": "$vertical_levels"},
    {"$group": {"_id": "$vertical_levels.pressure_hpa", "avg_temp": {"$avg": "$vertical_levels.temp_c"}}}
]))
```

---

## 6. Time-Series Handling: Native Collections & The Manual Bucket Pattern

High-frequency environmental monitoring networks recording $10\text{ Hz}$ wind turbulence quickly generate hundreds of millions of individual documents.

### 6.1 The Anti-Pattern: One Document per Ping
Storing 1 flat document per reading incurs a 16-byte internal record allocation, `_id` B-Tree index overhead, and repeated field-name serialization on every reading, causing severe WiredTiger cache thrashing.

### 6.2 Strategy A: The Manual Bucket Pattern
Group multiple temporal readings for a sensor into an hourly pre-aggregated document with summary min/max/sum headers:

```json
{
  "_id": "AWS-001_2026-10-04_H12",
  "station_id": "AWS-001",
  "bucket_start": "2026-10-04T12:00:00Z",
  "bucket_end": "2026-10-04T12:59:59Z",
  "sample_count": 3600,
  "summary": { "min_w": 0.2, "max_w": 18.4, "sum_w": 14200.5 },
  "measurements": [
    { "sec": 0, "w": 4.1 },
    { "sec": 1, "w": 4.3 },
    { "sec": 2, "w": 3.9 }
  ]
}
```

### 6.3 Strategy B: Native Time-Series Collections (MongoDB 5.0+)
MongoDB automates bucket compression internally via `timeseries` collections:

```javascript
db.createCollection("synoptic_timeseries", {
   timeseries: {
      timeField: "obs_time",
      metaField: "station_meta",
      granularity: "hours" // "seconds", "minutes", or "hours"
   },
   expireAfterSeconds: 7776000 // 90-day automated TTL expiration
});
```

* **How It Operates Internally:**
  1. Incoming inserts look like standard individual documents to your application.
  2. WiredTiger groups documents sharing the exact same `metaField` into hidden, compressed internal buckets (`system.buckets.synoptic_timeseries`) with `control.min` and `control.max` headers (functioning like a built-in BRIN index!).
  3. Columns within buckets are stored as contiguous arrays compressed via Run-Length Encoding (RLE), Delta-of-Delta encoding, and `zstd`, reducing on-disk storage footprint by **$80\text{–}90\%$**.

---

## 7. Binary Storage & Large Rasters: GridFS vs. Object Storage

BSON documents are strictly limited to $16\text{ MB}$. However, meteorological pipelines generate binary blobs that exceed this limit:
* High-resolution Doppler Radar volume scans ($30\text{–}100\text{ MB}$).
* Full-disk geostationary satellite imagery (Meteosat SEVIRI/FCI channels, $50\text{–}200\text{ MB}$).
* Numerical Weather Prediction (NWP) GRIB2 / NetCDF model files ($500\text{ MB}\text{–}5\text{ GB}$).

### 7.1 GridFS Physical Architecture
**GridFS** splits large files into discrete $255\text{ KB}$ segments across two collections (`fs.files` and `fs.chunks`):

```text
                            GridFS Storage Model
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                         Input Binary File: radar_sweep_1200.raw (45 MB)     │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                         Chunked into 255 KB Segments
                                        │
           ┌────────────────────────────┴────────────────────────────┐
           ▼                                                         ▼
 ┌─────────────────────────────────┐       ┌─────────────────────────────────┐
 │ fs.files Collection             │       │ fs.chunks Collection            │
 ├─────────────────────────────────┤       ├─────────────────────────────────┤
 │ {                               │       │ [Chunk 0: 255 KB raw binary]    │
 │   "_id": ObjectId("abc123"),    │<──────┤ [Chunk 1: 255 KB raw binary]    │
 │   "filename": "radar_1200.raw", │       │ [Chunk 2: 255 KB raw binary]    │
 │   "length": 47185920,           │       │ ...                             │
 │   "chunkSize": 261120,          │       │ [Chunk 180: 120 KB raw binary]  │
 │   "uploadDate": ISODate(...),   │       │                                 │
 │   "metadata": {                 │       │ Index: { files_id: 1, n: 1 }    │
 │     "site": "ALGIERS_RADAR",    │       │ (Ensures deterministic retrieval│
 │     "band": "C-BAND"            │       │  and streaming byte-range seeks)│
 │   }                             │       │                                 │
 │ }                               │       │                                 │
 └─────────────────────────────────┘       └─────────────────────────────────┘
```

### 7.2 Architectural Trade-Off: GridFS vs. Dedicated Object Storage (S3 / MinIO)

| Engineering Criterion | MongoDB GridFS | Dedicated Object Storage (MinIO / S3 / Ceph) |
| :--- | :--- | :--- |
| **Metadata Locality** | **Superior:** File metadata, spatial bounds, and binary bytes reside in the exact same transactional database cluster. | **Decoupled:** Requires keeping metadata/URLs in MongoDB and binary bytes in an external S3 bucket. |
| **Read/Write Throughput** | **Lower:** All reads pass through MongoDB BSON deserialization and WiredTiger cache layers. | **Superior:** High-speed parallel streaming directly over HTTP/S3 API; optimized for multi-gigabyte byte streams. |
| **WiredTiger Cache Pollution** | **High Risk:** Streaming gigabytes of radar arrays through GridFS fills the WiredTiger cache, evicting hot station indexes! | **Zero:** Never pollutes the operational database RAM cache. |
| **Operational Recommendation** | Use GridFS only for small-to-medium operational blobs ($< 50\text{ MB}$) requiring unified backup/replication with metadata. | Use **S3 / MinIO** for massive NWP/satellite rasters ($> 50\text{ MB}$ GRIB2, NetCDF, Zarr), storing only the searchable metadata + S3 URI in MongoDB! |

---

## 8. Horizontal Scaling: Multi-Node Sharded Clusters (`sh.*`) & The Shard Key Dilemma

When your meteorological archive grows beyond **10–20 TB** or write throughput exceeds what one Primary server's NVMe disk can handle, deploy a **MongoDB Sharded Cluster**.

### 8.1 The 3 Components of a Production Sharded Cluster
1. **Shards (Each Shard is a 3-Node Replica Set!):** Hold a horizontal slice ($64\text{ MB}$ / $128\text{ MB}$ chunks) of the sharded collections (`rs_shard1`, `rs_shard2`, `rs_shard3`).
2. **Config Server Replica Set (`CSRS` — 3 Nodes):** Stores the authoritative cluster metadata catalog (which Shard holds which `[station_id, obs_time]` chunk range).
3. **`mongos` Stateless Query Routers (2+ Processes):** Applications connect to `mongos` instead of directly to `mongod`. `mongos` consults the Config Servers and routes queries directly to the target Shard(s).

```mermaid
flowchart TB
    subgraph Apps["Weather Applications & Ingest Scripts"]
        A1["Python / mongosh Clients"]
    end

    subgraph Routers["Stateless Query Routers (mongos)"]
        MS1["mongos Router 1 (:27017)"]
        MS2["mongos Router 2 (:27017)"]
    end

    subgraph ConfigRS["Config Server Replica Set (3 Nodes)"]
        CS["CSRS: Stores Chunk Map\n[station_id, obs_time] -> Shard"]
    end

    subgraph Shards["Horizontal Data Shards (Each is a 3-Node Replica Set!)"]
        S1[("Shard 1 (rs_shard1)\n3x mongod nodes\nStations 60000..60399")]
        S2[("Shard 2 (rs_shard2)\n3x mongod nodes\nStations 60400..60599")]
        S3[("Shard 3 (rs_shard3)\n3x mongod nodes\nStations 60600..60999")]
    end

    A1 --> MS1 & MS2
    MS1 & MS2 <--> CS
    MS1 & MS2 ==> S1 & S2 & S3
```

### 8.2 The Shard Key Dilemma on Weather Telemetry
Selecting the **Shard Key** is the most critical architectural decision in a sharded cluster (see **[Day 4 Master Coursebook — §5.4 Black Box 4D](./day4_master_coursebook.md)** for the full 4-pattern Shard Key decision matrix and diagrams):
1. **Trap 1 — Monotonic Key (`{ obs_time: 1 }`):** Routes $100\%$ of live cluster writes to the single shard holding `MaxKey` (**Write Hotspot**).
2. **Trap 2 — Purely Hashed Key (`{ obs_time: "hashed" }`):** Forces a **Scatter-Gather Scan** across every shard on time-range queries.
3. **Trap 3 — Low Cardinality (`{ sensor_type: 1 }`):** Creates un-splittable **Jumbo Chunks** (`> 64 MB`).
4. **Production Solution — Compound Key (`{ "station_meta.station_id": 1, obs_time: 1 }`):** Distributes live writes across all shards simultaneously while keeping each station's chronological history contiguous for targeted single-shard range scans.

### 8.3 Essential Sharding Administration Commands (Run on `mongos`)

```javascript
// 1. Register each 3-node Replica Set as a Shard in the cluster:
sh.addShard("rs_shard1/10.20.3.11:27018,10.20.3.12:27018,10.20.3.13:27018");
sh.addShard("rs_shard2/10.20.4.11:27018,10.20.4.12:27018,10.20.4.13:27018");
sh.addShard("rs_shard3/10.20.5.11:27018,10.20.5.12:27018,10.20.5.13:27018");

// 2. Enable sharding on the 'weather_nosql' database:
sh.enableSharding("weather_nosql");

// 3. Shard 'radiosonde_soundings' using a Compound Shard Key (Station ID + Launch Time):
sh.shardCollection(
  "weather_nosql.radiosonde_soundings",
  { station_id: 1, launch_time: 1 }
);

// 4. Shard native Time-Series collection 'synoptic_timeseries' on metaField + timeField:
sh.shardCollection(
  "weather_nosql.synoptic_timeseries",
  { "station_meta.station_id": 1, obs_time: 1 }
);

// 5. Inspect shard distribution, chunk balance, and data size per Shard:
sh.status();
db.radiosonde_soundings.getShardDistribution();
```

### 8.4 Critical Weather Tuning: Schedule the Chunk Balancer Outside `00Z` / `12Z` Ingest Windows!
When one Shard grows larger than others, MongoDB's background **Balancer** migrates chunks between Shards. Never let the Balancer consume disk/network I/O while `00Z` or `12Z` NWP & radiosonde batches are ingesting:

```javascript
// Restrict the Sharded Cluster Balancer to run ONLY between 03:00 UTC and 05:30 UTC
// (quiet synoptic hours between the 00Z and 06Z runs!):
use config;
db.settings.updateOne(
  { _id: "balancer" },
  {
    $set: {
      activeWindow: {
        start: "03:00",
        stop:  "05:30"
      }
    }
  },
  { upsert: true }
);

// Verify balancer state and active window:
sh.getBalancerState();
sh.isBalancerRunning();
```

> [!TIP]
> **Production Engineering Tip (Balancer Window Scheduling):**  
> Scheduling the MongoDB Chunk Balancer between `03:00` and `05:30 UTC` is critical in meteorological operations: `00Z` and `12Z` are the global WMO synoptic and radiosonde release windows when ingestion spikes $10\times$. Restricting chunk migrations to quiet inter-synoptic hours prevents network and disk I/O contention during live forecast runs!

---

## 9. Storage & Execution Forensics Quick Commands

```javascript
// 1. Inspect collection sizes, uncompressed BSON size, and compressed WiredTiger disk footprint:
db.sensor_payloads.stats();

// 2. Profile query execution plans, index usage (IXSCAN vs COLLSCAN), and examined-to-returned ratios:
db.sensor_payloads.find({
    "metadata.station_id": "AWS-001",
    "timestamp": { $gte: ISODate("2026-10-04T00:00:00Z") }
}).explain("executionStats");

// 3. Check WiredTiger cache utilization, dirty bytes, and read/write ticket concurrency:
db.serverStatus().wiredTiger.cache;
db.serverStatus().wiredTiger.concurrentTransactions;
```

---

## 10. Side-by-Side Summary: Multi-Node PostgreSQL vs. Multi-Node MongoDB

| HA / Multi-Node Feature | PostgreSQL 16 (`Patroni` + `etcd` + `HAProxy`) | MongoDB 7 (Replica Sets & Sharded Clusters) |
| :--- | :--- | :--- |
| **Replication Log** | Physical WAL (`$PGDATA/pg_wal`) | Logical idempotent Oplog (`local.oplog.rs`) |
| **Consensus & Failover** | External **`Patroni` + 3-node `etcd`** (< 10s failover) | **Built-in Raft-like election** across `mongod` nodes (< 10s failover) |
| **Client Routing** | **`HAProxy`** (Port 5000 RW / Port 5001 RO) + `PgBouncer` | **Smart Multi-Host Driver URI** (`replicaSet=rs_meteo`) or **`mongos`** |
| **Scaling Reads** | Add Asynchronous **Hot Standby Read Replicas** (`hot_standby_feedback = on`) | Add Secondary nodes + **`readPreference: "secondaryPreferred"` & Tag Sets** |
| **Scaling Writes Across Nodes** | Vertical scaling + Partitioning (or Citus extension) | **Native Horizontal Sharding** (`sh.shardCollection`) across multiple Replica Sets |

---

> **Navigation:** [Master README](../README.md) | [Interactive Portal](../bootcamp_portal.html) | [⬅ Day 3: PostgreSQL Scaling](../day3/day3_master_coursebook.md) | [Day 4 Coursebook](day4_master_coursebook.md) | [Day 5: Analytical OLAP & Lakehouse](../day5/day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | [Reference Cards](../reference_cards/README.md)
