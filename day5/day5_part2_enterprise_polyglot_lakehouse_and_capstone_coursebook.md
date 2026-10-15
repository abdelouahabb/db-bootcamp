> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [⬅️ Day 5 (Part 1): Analytical OLAP & DuckDB](day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | [➡️ Final Assessment & Troubleshooting](bootcamp_capstone_troubleshooting_and_quiz.md) | [📚 Reference Cards](../reference_cards/README.md)

# Weather Forecast Engineering Database Bootcamp

## Day 5 (Part 2) Master Coursebook: Enterprise Meteorological Production Architecture, Real-Time Streaming, Polyglot Lakehouse & Capstone Lab

---

### Course & Session Overview

* **Target Audience:** Lead Meteorological Software Engineers, Weather Data Architects, Systems Infrastructure Engineers.
* **Core Philosophy:** Over Days 1 through 5 (Part 1), we explored individual database engines and storage formats:
  * **Day 1:** Declarative SQL foundations, hardware sentinels, 3VL logic, CTE pipelines, and window functions in SQLite.
  * **Day 2:** PostgreSQL storage engine internals, 8 KB page forensics, 23-byte MVCC headers, CPU alignment padding, WAL/Checkpoints, and the row-store I/O wall.
  * **Day 3:** High-throughput operational scaling with PostgreSQL Declarative Partitioning, BRIN indexing, PostGIS spatial geodesy, and `JSONB`.
  * **Day 4:** MongoDB document modeling for upper-air radiosonde soundings, polymorphic IoT sensor ingestion, native time-series bucketing, ESR indexing, and 3-Node Replica Set High Availability & Sharding.
  * **Day 5 (Part 1):** The Analytical OLAP Tier: vectorized execution in DuckDB, columnar Apache Parquet internals, Hive Lakehouse directory layout, and 4D atmospheric gridded continuum (`GRIB2`, `NetCDF4`, `Zarr`, `BUFR`).

  **In Day 5 (Part 2), we assemble the complete end-to-end National Meteorological Architecture.** We eliminate architectural silos by engineering a unified, polyglot production platform capable of ingesting 100,000 sensor pings per second, routing data dynamically to optimal operational and time-series engines, automating compaction into a columnar Parquet Lakehouse, and serving both real-time early warning alerts and 30-year climatological scans with sub-second latencies.
* **Execution Environment:**
  * Docker & Docker Compose v2+ ([docker-compose.polyglot-lakehouse.yml](../docker/docker-compose.polyglot-lakehouse.yml) and [docker-compose.ha-replicaset.yml](../docker/docker-compose.ha-replicaset.yml)):
    * **Eclipse Mosquitto (MQTT Broker)** for remote field sensor telemetry.
    * **Apache Kafka / Redpanda** for distributed, backpressured message streaming.
    * **PostgreSQL 16 + PostGIS 3.4** for relational metadata, geospatial geofences, and operational range-partitioned tables.
    * **MongoDB 7.0** for polymorphic sensor ingestion and native time-series bucketing.
    * **MinIO / Ceph RGW (S3-Compatible Object Store)** for gridded model rasters (`GRIB2`/`NetCDF4`/`Zarr`) and Parquet lake files.
  * Python 3.10+ execution environment with `confluent-kafka`, `paho-mqtt`, `psycopg2-binary`, `pymongo`, `duckdb`, `pyarrow`, `fastapi`, and `uvicorn`.
* **Companion Runnable Scripts in `day5/`:**
  * [simulate_edge_sensors.py](./simulate_edge_sensors.py) *(MQTT Edge Weather Telemetry Simulator)*
  * [stream_router.py](./stream_router.py) *(Dynamic MQTT $\rightarrow$ PostgreSQL + MongoDB Polyglot Router)*
  * [compact_hot_to_cold.py](./compact_hot_to_cold.py) *(Hot PostgreSQL $\rightarrow$ Cold Hive Parquet Compactor + DuckDB Verifier)*
  * [serving_api.py](./serving_api.py) *(Unified FastAPI Gateway over PostGIS, MongoDB, and DuckDB)*
  * [parquet_vs_csv_benchmark.py](./parquet_vs_csv_benchmark.py), [compact_small_parquet_files.py](./compact_small_parquet_files.py), [satellite_cog_int16_quantization.py](./satellite_cog_int16_quantization.py) *(Standalone Parquet & Satellite COG Benchmarks)*
  * [bootcamp_capstone_troubleshooting_and_quiz.md](./bootcamp_capstone_troubleshooting_and_quiz.md) *(15 Operational Troubleshooting Scenarios & 15 Final Quiz Questions)*

---

### Part 2 Schedule & Module Outline

```
┌─────────────────┬─────────────────────────────────────────────────────────────────┐
│ Module 0        │ The National Weather Architecture, Storage SLAs & Workload Map  │
├─────────────────┼─────────────────────────────────────────────────────────────────┤
│ Module 1        │ The Edge Ingestion & Event Streaming Tier (MQTT & Kafka)        │
├─────────────────┼─────────────────────────────────────────────────────────────────┤
│ Module 2        │ The Polyglot Stream Router (Dynamic PostgreSQL + MongoDB)       │
├─────────────────┼─────────────────────────────────────────────────────────────────┤
│ Module 3        │ The Cold Tier Downsampling Compactor (DuckDB + PyArrow + Detach)│
├─────────────────┼─────────────────────────────────────────────────────────────────┤
│ Module 4        │ The Vectorized Serving Tier & Sub-10ms FastAPI Gateway          │
├─────────────────┼─────────────────────────────────────────────────────────────────┤
│ Module 5        │ Capstone Disaster Lab: The Mediterranean Squall Line (Dellys)   │
└─────────────────┴─────────────────────────────────────────────────────────────────┘
```

---

## 0. Module 0: The National Weather Architecture, Storage SLAs & Workload Map

### 0.1 The Grand Unified Meteorological Architecture

Modern meteorological agencies process three distinct velocities and structures of data simultaneously. A single database technology cannot satisfy these requirements:

```
                            THE UNIFIED NATIONAL METEOROLOGICAL PLATFORM
                            
 ┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
 │ EDGE INGESTION TIER: Remote Automated Weather Stations, Doppler Radar Sites, Upper-Air Soundings  │
 │  • Local SQLite Buffer (weather_edge.db) survives 48-hour satellite/cellular sandstorm outages!  │
 └──────────────────────────────────┬────────────────────────────────────────────┬──────────────────┘
                                    │ Cellular / Satellite (MQTT / CoAP)         │ High-Bandwidth LAN
                                    ▼                                            ▼
                     ┌─────────────────────────────┐              ┌─────────────────────────────┐
                     │ Mosquitto Edge MQTT Broker  │              │ Doppler Radar FTP/HTTP Push │
                     └──────────────┬──────────────┘              └──────────────┬──────────────┘
                                    │ MQTT Bridge                                │ S3 Upload
                                    ▼                                            ▼
 ┌────────────────────────────────────────────────────────────────────────┐ ┌───────────────────┐
 │ DISTRIBUTED MESSAGE BROKER TIER: Apache Kafka / Redpanda Event Streams │ │ Cloud Object      │
 │  • Topic: 'telemetry.metar.raw'     (High-frequency operational pings) │ │ Storage           │
 │  • Topic: 'telemetry.polymorphic'   (Ultrasonic 3D, disdrometers)      │ │ (MinIO / Ceph RGW)│
 │  • Topic: 'alerts.critical.squall'  (Severe weather trigger bus)       │ │ • raw-radars/     │
 └──────────────────────────────────┬─────────────────────────────────────┘ │ • nwp-grib2-zarr/ │
                                    │                                       └─────────┬─────────┘
                                    ▼                                                 │
 ┌────────────────────────────────────────────────────────────────────────┐           │
 │ STREAM ROUTER & ETL WORKERS: Polyglot Routing Engine (Python / Rust)   │           │
 └───────┬──────────────────────────┬───────────────────────────────┬─────┘           │
         │                          │                               │                 │
         ▼                          ▼                               ▼                 ▼
 ┌──────────────────┐       ┌──────────────────┐            ┌───────────────────────────────────┐
 │ HOT OPERATIONAL  │       │ HOT POLYMORPHIC  │            │ COLD COLUMNAR ANALYTICAL LAKE     │
 │ RELATIONAL TIER  │       │ TIME-SERIES TIER │            │ (Apache Parquet + Hive Structure) │
 ├──────────────────┤       ├──────────────────┤            ├───────────────────────────────────┤
 │ PostgreSQL 16    │       │ MongoDB 7.0      │            │ climatology_lake/                 │
 │ + PostGIS 3.4    │       │ WiredTiger       │            │  ├── year=2026/                   │
 │ • Range Partitions       │ • Native Bucket  │   Batch    │  │   └── month=10/                │
 │ • BRIN & GiST    │       │   Compression    │ Compactor  │  │       └── data_0.zstd.parquet  │
 │ • Station Master │       │ • 3D Anemometers │ ─────────> │ • 10M rows in 140 ms              │
 │ • Active Alerts  │       │ • Soundings/Buoys│  (DuckDB)  │ • Predicate Pushdown              │
 └─────────┬────────┘       └─────────┬────────┘            └─────────────────┬─────────────────┘
           │                          │                                       │
           └──────────────────────────┼───────────────────────────────────────┘
                                      ▼
 ┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
 │ HIGH-PERFORMANCE SERVING TIER: FastAPI + Vectorized DuckDB Engine + Redis Caching                │
 │  • /api/v1/spatial/nearby-stations (PostGIS Geodesic ST_DWithin: < 2 ms)                         │
 │  • /api/v1/telemetry/anomalies     (MongoDB Polymorphic Aggregations: < 15 ms)                   │
 │  • /api/v1/climatology/summary     (DuckDB Direct Vectorized Parquet S3 Scans: < 80 ms)          │
 └──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

```mermaid
flowchart TD
    subgraph EdgeTier["1. Edge Sensing & Store-and-Forward Tier"]
        EDGE["Remote AWS, 3D Sonic Anemometers & Buoys\nLocal SQLite WAL Buffer (weather_edge.db)\n(simulate_edge_sensors.py)"]
        RADAR["Doppler Radar & Satellite Downlink\n(Meteosat SEVIRI / NWP GRIB2 / NetCDF4)"]
    end

    subgraph BrokerTier["2. Event Streaming & Backpressure Tier"]
        MQTT["Eclipse Mosquitto MQTT Broker (:1883)\nQoS 1 Persistent Sessions"]
        KAFKA["Redpanda / Apache Kafka (:9092)\nPartitioned Commit Logs"]
        ROUTER["Polyglot Stream Router\n(stream_router.py)"]
        EDGE -->|"MQTT QoS 1"| MQTT --> KAFKA --> ROUTER
    end

    subgraph HotTier["3. Hot Operational & Polymorphic Tier (0–90 Days)"]
        PG[("PostgreSQL 16 + PostGIS 3.4 (:5432)\n• Range Partitions & BRIN\n• GiST Spatial Station Registry\n• STAC Raster Catalog")]
        MG[("MongoDB 7.0 Replica Set (:27017)\n• Native Time-Series (system.buckets)\n• 3D Sonic Vectors & Radiosondes\n• 2dsphere Storm Polygons")]
        ROUTER ==>|"METAR_STANDARD\nBatch execute_values"| PG
        ROUTER ==>|"ULTRASONIC_3D\nbulk_write"| MG
    end

    subgraph ColdTier["4. Cold Columnar & Gridded Lakehouse (Ceph RGW / MinIO S3 :9000)"]
        COMPACT["Hot-to-Cold Compactor\n(compact_hot_to_cold.py)\nStrips -999.0 Sentinels + DETACH PARTITION"]
        PQ[("Hive-Partitioned ZSTD Parquet\nclimatology_lake/year=YYYY/month=MM/")]
        COG_ZARR[("Cloud-Native Rasters\n• Scaled UInt16 COGs (.tif)\n• 4D Zarr & Kerchunk (.zarr)")]
        PG -->|"Server-Side Cursor"| COMPACT ==>|"ZSTD + Dict"| PQ
        RADAR ==>|"xarray / rasterio"| COG_ZARR
        RADAR -.->|"STAC Footprint"| PG
    end

    subgraph ServingTier["5. Sub-10ms Unified Serving Tier"]
        API["FastAPI Gateway (:8000)\n(serving_api.py)\nPostGIS Pool + PyMongo + Vectorized DuckDB"]
        PG -->|"< 2 ms ST_DWithin"| API
        MG -->|"< 15 ms Anomalies"| API
        PQ & COG_ZARR ==>|"< 80 ms DuckDB SIMD\n& HTTP Byte-Range"| API
    end
```

### 0.2 Storage Tier Classification & SLA Matrix

| Dimension | Edge Buffer Tier | Hot Relational Operational Tier | Hot Polymorphic Telemetry Tier | Cold Columnar Lakehouse Tier | Gridded Binary Archive Tier |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Engine** | **SQLite 3 (WAL Mode)** | **PostgreSQL 16 + PostGIS** | **MongoDB 7.0 (Time-Series & Replica Set)** | **Apache Parquet via DuckDB** | **Ceph RGW / MinIO (S3) + Zarr / NetCDF4** |
| **Data Retained** | Rolling 7–14 days on logger | Current rolling 90 days | Current rolling 30–90 days (TTL) | Decades of historical records | Complete model runs (5+ years) |
| **Write Pattern** | Local single-file ACID transaction | Append-only partitioned stream / `COPY` | High-frequency bucketed insert | Scheduled multi-MB block flush | Monolithic / chunked object upload |
| **Target Latency** | $< 1\text{ ms}$ (Local Flash) | $< 5\text{ ms}$ (Transactional / Point) | $< 10\text{ ms}$ (Polymorphic JSON) | $< 100\text{ ms}$ (Multi-million scan) | Streaming HTTP byte-range fetch |
| **Query Pattern** | Store-and-forward sync | Spatial bounds, NWP verification, station status | Upper-air profiles, raw sensor drift, drop-sizes | 30-year climatology, `dbt` transformations | 4D vertical slicing ($u, v, t$) |
| **CAP Strategy** | Local ACID | **CP** (Quorum / Raft Patroni) | **AP / CP** (Tunable `w: 1` vs `w: "majority"`) | Immutable Object Storage | Immutable Object Storage |

---

### 0.3 Polyglot Workload Architecture Matrix: Which Engine Wins Where?

Use this reference matrix during architectural design reviews to select the right engine and features from Days 1–5 for each meteorological workload:

| # | Meteorological Workload | Best Engine | Why & Which Bootcamp Features to Configure |
| :--- | :--- | :--- | :--- |
| **1** | **On-board storage inside a solar-powered Saharan weather station** that loses satellite uplink for 48 hours during sandstorms | **SQLite** *(Day 1)* | Zero-daemon single file (`weather_edge.db`), tiny RAM footprint, ACID safe on sudden power loss (`PRAGMA journal_mode=WAL`), enforces local `CHECK` constraints before syncing upstream over MQTT. |
| **2** | **Operational WMO Surface Synoptic Store & NWP Forecast Verification** (`ECMWF` vs. `GFS` vs. `AROME` Bias/MAE) | **PostgreSQL + PostGIS** *(Days 2–3)* | Strict tabular schema (`TIMESTAMPTZ` in `UTC`, `NUMERIC`/`FLOAT4`), heavy multi-table `JOIN`s, Window Functions (`LAG` for $\Delta P_{3\text{h}}$), **Monthly Range Partitioning**, **BRIN indexes**, and **Concurrent Materialized Views**. |
| **3** | **Upper-Air Radiosonde Balloon Soundings** (each balloon records 50–100 vertical pressure levels + GPS drift path + QC audit array) | **MongoDB** *(Day 4)* | Bounded 1-to-Many array (`vertical_levels`) accessed as a single unit; queried with **`$elemMatch`** and analyzed across pressure surfaces with **`$unwind` + `$group`** and **ESR Compound Indexes**. |
| **4** | **Heterogeneous IoT Sensor Network** (3D Ultrasonic Anemometers, Marine Buoys with wave spectra, Agricultural 4-depth soil probes) | **MongoDB** *(Day 4)* | Polymorphic documents where each sensor type has custom nested sub-documents, stored in a **Native Time-Series Collection (`system.buckets`)** with automatic **`expireAfterSeconds` (TTL)** and compound Shard Key `{ station_id: 1, timestamp: 1 }`. |
| **5** | **Real-Time Radar Storm Cell Polygons & CAP Public Warning Bulletins** (finding affected stations/towns inside moving storm polygons) | **PostGIS / MongoDB** *(Days 3–4)* | Geodesic proximity (`ST_DWithin` on `GEOGRAPHY(Point, 4326)`) in PostGIS, or self-contained CAP alert documents in MongoDB with atomic `$max` gust tracking, `$addToSet` affected stations, and **`2dsphere` GeoJSON** (`$geoIntersects`) written with `w: "majority"`. |
| **6** | **Adding 5 optional hardware diagnostic fields (`battery_v`, `firmware`)** to an existing PostgreSQL synoptic table without migrating to a second database | **PostgreSQL `JSONB`** *(Day 3)* | When 90% of the workload is relational SQL and you just need flexible key-value diagnostics, a **`JSONB` column + `GIN` index (`@>`)** avoids running a separate NoSQL cluster! |
| **7** | **30-Year National Climatology Scans & `dbt` Analytical Marts** across 500+ million historical rows | **Apache Parquet + DuckDB** *(Day 5)* | **80–90% smaller** than row stores via ZSTD + Dictionary/RLE encoding; organized in **Hive directories (`year=YYYY/month=MM`)** on Ceph RGW / MinIO S3 and scanned at **10M+ rows in ~140 ms** via DuckDB AVX-512 SIMD vectors. |

---

### 0.4 Launching the Multi-Service Polyglot Lakehouse Docker Stack

All Docker Compose configurations and operational runbooks are located in `../docker/`:
* **[docker-compose.polyglot-lakehouse.yml](../docker/docker-compose.polyglot-lakehouse.yml):** Spins up **Eclipse Mosquitto (MQTT)**, **Redpanda (Kafka)**, **PostgreSQL 16 + PostGIS 3.4**, **MongoDB 7.0**, and **MinIO (S3 Object Storage)**.
* **[docker-compose.ha-replicaset.yml](../docker/docker-compose.ha-replicaset.yml):** Spins up **PostgreSQL 16 + PostGIS 3.4** alongside the **3-Node MongoDB 7.0 Replica Set (`rs_meteo`)** for High Availability failover testing.
* See **[docker_lab_guide.md](../docker/docker_lab_guide.md)** for full launch and Chaos Engineering instructions.

```bash
# Start the 5-service Polyglot Streaming Lakehouse stack:
docker compose -f ../docker/docker-compose.polyglot-lakehouse.yml up -d
docker compose -f ../docker/docker-compose.polyglot-lakehouse.yml ps
```

---

## 1. Module 1: The Edge Ingestion & Event Streaming Tier (MQTT & Kafka)

### 1.1 The Edge Dilemma: Why Remote Stations Use MQTT, Not SQL

Automated Weather Stations (AWS) deployed in the Tell Atlas mountains or the Sahara desert communicate across unreliable satellite uplinks or low-power 2G/LTE-M modems:
* **TCP Connection Overhead:** Opening a PostgreSQL connection requires a 3-way TCP handshake, TLS negotiation, authentication exchange, and backend worker fork. If a cellular connection drops every 30 seconds, relational connections time out, exhausting server sockets.
* **Payload Serialization Overhead:** Sending text SQL (`INSERT INTO raw_telemetry...`) consumes hundreds of bytes per packet.
* **The MQTT Protocol Solution:**
  * Uses a minimal **2-byte fixed header**.
  * Operates on a **Publish/Subscribe pattern** over persistent, lightweight TCP sessions.
  * Provides built-in **Quality of Service (QoS) levels**:
    * `QoS 0` (*At most once*): Routine, high-frequency wind pings.
    * `QoS 1` (*At least once*): Standard synoptic hourly observations.
    * `QoS 2` (*Exactly once*): Severe storm warnings and evacuation advisories.

### 1.2 Bridging Edge MQTT to Distributed Kafka

While MQTT handles thousands of unstable client connections from remote weather stations, it lacks partitioned storage, replayability, and consumer group scaling. We bridge MQTT messages into **Apache Kafka (Redpanda)**, transforming the edge stream into high-throughput, partitioned, durable commit logs:

```
                   Edge Telemetry Ingestion Flowchart
 ┌──────────────────────┐
 │ Remote Station AWS-1 │ ───┐
 └──────────────────────┘    │ MQTT Publish (QoS 1)
 ┌──────────────────────┐    │ Topic: "weather/telemetry/raw"
 │ Remote Station AWS-2 │ ───┼─────────────────────────────────┐
 └──────────────────────┘    │                                 ▼
 ┌──────────────────────┐    │                  ┌─────────────────────────────┐
 │ Sonic Anemometer 3D  │ ───┘                  │ Eclipse Mosquitto (Port 1883│
 └──────────────────────┘                       └──────────────┬──────────────┘
                                                               │
                                         MQTT Subscriber Worker│ (Zero packet loss)
                                                               ▼
                                                ┌─────────────────────────────┐
                                                │ Kafka Broker (Port 9092)    │
                                                │ Topic: "weather.telemetry"  │
                                                │ Partitions: 0, 1, 2, 3      │
                                                └─────────────────────────────┘
```

### 1.3 Edge Sensor Simulator Script ([simulate_edge_sensors.py](./simulate_edge_sensors.py))

This standalone Python script simulates 50 automated weather stations and high-frequency 3D sonic anemometers continuously publishing telemetry into the Mosquitto MQTT broker:

```python
#!/usr/bin/env python3
"""
Simulate High-Frequency Edge Weather Telemetry Stream over MQTT
Publishes:
  1. Standard METAR weather packets (Temp, Pres, Wind, Rain)
  2. Polymorphic Ultrasonic 3D wind velocity vectors
"""

import time
import json
import random
from datetime import datetime, timezone
import paho.mqtt.client as mqtt

MQTT_BROKER = "localhost"
MQTT_PORT = 1883
TOPIC_TELEMETRY = "weather/telemetry/raw"

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="Edge_Simulator")
print(f"[*] Connecting to Mosquitto Broker at {MQTT_BROKER}:{MQTT_PORT}...")
client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
client.loop_start()

stations = [f"AWS-{i:03d}" for i in range(1, 51)]
regions = ["COASTAL_MED", "TELL_ATLAS", "STEPPE_PLATEAU", "SAHARA_NORTH"]

print("[+] Edge Simulator running. Emitting telemetry packets (Press Ctrl+C to stop)...")
packet_count = 0

try:
    while True:
        station_id = random.choice(stations)
        region = regions[int(station_id.split("-")[1]) % len(regions)]
        now_iso = datetime.now(timezone.utc).isoformat()
        
        # 75% standard METAR packets, 25% polymorphic 3D sonic packets
        if random.random() < 0.75:
            # Standard Relational Telemetry
            # Injected Anomaly: AWS-013 occasionally emits -999.0 hardware sentinels
            temp = -999.0 if (station_id == "AWS-013" and random.random() < 0.15) else round(18.0 + random.gauss(0, 5.0), 2)
            pres = round(1013.25 + random.gauss(0, 8.0), 2)
            ws = round(max(0.0, random.weibullvariate(3.5, 1.8) * 2.0), 2)
            
            payload = {
                "sensor_type": "METAR_STANDARD",
                "station_id": station_id,
                "region": region,
                "timestamp": now_iso,
                "temperature": temp,
                "pressure": pres,
                "wind_speed": ws,
                "rain_accum_1m": round(random.expovariate(3.0), 2) if random.random() < 0.10 else 0.0
            }
        else:
            # Polymorphic Ultrasonic 3D Anemometer
            payload = {
                "sensor_type": "ULTRASONIC_3D",
                "station_id": station_id,
                "region": region,
                "timestamp": now_iso,
                "u_vector": round(random.uniform(-10.0, 15.0), 3),
                "v_vector": round(random.uniform(-10.0, 15.0), 3),
                "w_vector": round(random.uniform(-2.0, 2.0), 3),
                "turbulent_kinetic_energy": round(random.uniform(0.01, 0.45), 4)
            }
            
        client.publish(TOPIC_TELEMETRY, json.dumps(payload), qos=1)
        packet_count += 1
        
        if packet_count % 100 == 0:
            print(f"   -> Published {packet_count:,} packets to MQTT...")
        time.sleep(0.02) # ~50 packets/second

except KeyboardInterrupt:
    print(f"\n[+] Stopped. Total packets published: {packet_count:,}")
    client.loop_stop()
    client.disconnect()
```

---

## 2. Module 2: The Polyglot Stream Router (Dynamic Engine Dispatch)

### 2.1 The Architectural Mechanics of Polyglot Dispatch

Data should not be forced into a single database format. A streaming router inspects incoming events and directs them based on structure and query patterns:

```
                            Polyglot Dispatch Pipeline
                           ┌──────────────────────────┐
                           │ MQTT / Kafka Consumer    │
                           │ Topic: weather/telemetry │
                           └────────────┬─────────────┘
                                        │ Payload Inspection
                     ┌──────────────────┴──────────────────┐
                     ▼                                     ▼
        {"sensor_type": "METAR_STANDARD"}     {"sensor_type": "ULTRASONIC_3D"}
                     │                                     │
                     │ Strict Columnar Schema              │ Polymorphic Drift / Vectors
                     ▼                                     ▼
         ┌─────────────────────────┐           ┌─────────────────────────┐
         │ PostgreSQL 16 + PostGIS │           │ MongoDB 7.0             │
         │ Master Range-Partition  │           │ Native Time-Series      │
         │ raw_telemetry_partition │           │ weather_stream          │
         └─────────────────────────┘           └─────────────────────────┘
```

1. **Structured Synoptic Observations (`METAR_STANDARD`):**
   * Emitted to **PostgreSQL 16**.
   * Written to `raw_telemetry_partitioned`.
   * Directly linkable via relational foreign keys to the PostGIS `stations` registry.
2. **Polymorphic / Dynamic Sensor Payloads (`ULTRASONIC_3D`):**
   * Emitted to **MongoDB 7.0**.
   * Written to the native `weather_stream` time-series collection.
   * Leverages internal columnar bucketing without schema migration overhead.
3. **Dead-Letter Queue (DLQ):**
   * Any corrupted, malformed, or unparseable packets are routed to a dead-letter topic (`weather.telemetry.dlq`) for forensic audit without stalling the primary ingestion thread.

### 2.2 The Production Polyglot Router Script ([stream_router.py](./stream_router.py))

This production-grade worker consumes events from MQTT, batches them to minimize network and transaction round-trips, and commits them concurrently to PostgreSQL and MongoDB:

```python
#!/usr/bin/env python3
"""
Production Polyglot Stream Router (stream_router.py)
Consumes edge weather telemetry from MQTT, inspects sensor schemas,
and routes concurrently:
  - METAR_STANDARD -> PostgreSQL (Range-partitioned, PostGIS linked)
  - ULTRASONIC_3D  -> MongoDB (Native Time-Series Bucketed Collection)
"""

import json
import time
import psycopg2
from psycopg2.extras import execute_values
from pymongo import MongoClient, InsertOne
import paho.mqtt.client as mqtt

# Configuration
PG_DSN = "postgresql://postgres:postgres@localhost:5432/weather_ops_db"
MONGO_URI = "mongodb://localhost:27017/"
MQTT_BROKER = "localhost"
MQTT_PORT = 1883
TOPIC_SOURCE = "weather/telemetry/raw"

BATCH_SIZE = 100
FLUSH_INTERVAL_SEC = 1.0

# 1. Database Connections
print("[*] Connecting to PostgreSQL 16...")
pg_conn = psycopg2.connect(PG_DSN)
pg_conn.autocommit = True
pg_cur = pg_conn.cursor()

print("[*] Connecting to MongoDB 7.0...")
mongo_client = MongoClient(MONGO_URI)
mongo_db = mongo_client["weather_telemetry_db"]
mongo_ts_col = mongo_db["weather_stream"]

# Ensure target PostgreSQL schema & station registry are ready
pg_cur.execute("""
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS stations (
    station_id VARCHAR(10) PRIMARY KEY,
    station_name VARCHAR(100) NOT NULL,
    elevation_m REAL NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    geom GEOMETRY(Point, 4326)
);

CREATE INDEX IF NOT EXISTS idx_stations_geom ON stations USING GIST (geom);

INSERT INTO stations (station_id, station_name, elevation_m, is_active, geom)
VALUES
    ('AWS-001', 'Dellys Marine Cape', 12.0, TRUE, ST_SetSRID(ST_MakePoint(3.9130, 36.9172), 4326)),
    ('AWS-002', 'Algiers Dar El Beida', 25.0, TRUE, ST_SetSRID(ST_MakePoint(3.2154, 36.6910), 4326)),
    ('AWS-003', 'Tizi Ouzou Basin', 188.0, TRUE, ST_SetSRID(ST_MakePoint(4.0497, 36.7118), 4326)),
    ('AWS-013', 'Bouira Highland Station', 525.0, TRUE, ST_SetSRID(ST_MakePoint(3.9020, 36.3749), 4326))
ON CONFLICT (station_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS raw_telemetry_partitioned (
    recorded_at TIMESTAMPTZ NOT NULL,
    station_id VARCHAR(10) NOT NULL,
    temperature REAL,
    pressure REAL,
    wind_speed REAL,
    rain_accum_1m REAL
) PARTITION BY RANGE (recorded_at);

CREATE TABLE IF NOT EXISTS telemetry_y2026m10 PARTITION OF raw_telemetry_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');
    
CREATE TABLE IF NOT EXISTS telemetry_default PARTITION OF raw_telemetry_partitioned DEFAULT;
""")

batch_pg = []
batch_mongo = []
last_flush_time = time.time()
routed_total = 0

def flush_batches():
    global batch_pg, batch_mongo, last_flush_time, routed_total
    
    # Flush PostgreSQL Batch
    if batch_pg:
        query = """
        INSERT INTO raw_telemetry_partitioned (recorded_at, station_id, temperature, pressure, wind_speed, rain_accum_1m)
        VALUES %s;
        """
        execute_values(pg_cur, query, batch_pg)
        routed_total += len(batch_pg)
        batch_pg = []

    # Flush MongoDB Batch
    if batch_mongo:
        mongo_ts_col.bulk_write(batch_mongo, ordered=False)
        routed_total += len(batch_mongo)
        batch_mongo = []

    last_flush_time = time.time()

def on_message(client, userdata, msg):
    global batch_pg, batch_mongo
    try:
        data = json.loads(msg.payload.decode("utf-8"))
        sensor_type = data.get("sensor_type")

        if sensor_type == "METAR_STANDARD":
            batch_pg.append((
                data["timestamp"],
                data["station_id"],
                data["temperature"],
                data["pressure"],
                data["wind_speed"],
                data["rain_accum_1m"]
            ))
        elif sensor_type == "ULTRASONIC_3D":
            mongo_doc = {
                "timestamp": data["timestamp"],
                "metadata": {
                    "station_id": data["station_id"],
                    "region": data["region"],
                    "sensor_type": "ULTRASONIC_3D"
                },
                "u_vector": data["u_vector"],
                "v_vector": data["v_vector"],
                "w_vector": data["w_vector"],
                "turbulent_kinetic_energy": data["turbulent_kinetic_energy"]
            }
            batch_mongo.append(InsertOne(mongo_doc))

        if len(batch_pg) >= BATCH_SIZE or len(batch_mongo) >= BATCH_SIZE or (time.time() - last_flush_time) >= FLUSH_INTERVAL_SEC:
            flush_batches()
            print(f"   -> Successfully routed {routed_total:,} records across PostgreSQL & MongoDB...")

    except Exception as e:
        print(f"[!] Routing Error: {e}")

mqtt_sub = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="Polyglot_Router")
mqtt_sub.on_message = on_message
mqtt_sub.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
mqtt_sub.subscribe(TOPIC_SOURCE, qos=1)

print("[+] Polyglot Stream Router active. Listening for MQTT streams...")
try:
    mqtt_sub.loop_forever()
except KeyboardInterrupt:
    flush_batches()
    print(f"\n[+] Router stopped cleanly. Total processed: {routed_total:,}")
    pg_conn.close()
    mongo_client.close()
```

---

## 3. Module 3: The Cold Tier Downsampling Pipeline (DuckDB & PyArrow)

### 3.1 The Lifecycle of Weather Telemetry: From Hot to Cold

Storing years of sub-minute telemetry inside PostgreSQL or MongoDB creates unnecessary costs:
1. **RAM Bloat:** Operational indexes (B-Trees) outgrow memory buffers.
2. **Storage Inefficiency:** PostgreSQL consumes $\approx 48\text{ bytes}$ per row; uncompressed MongoDB BSON consumes $\approx 120\text{ bytes}$ per document.
3. **The Solution:** A scheduled micro-batch compactor that reads closed time windows from PostgreSQL, strips in-band hardware sentinels (`-999.0`), transforms them into **Zstandard-compressed Apache Parquet** organized via **Hive Partitioning**, and safely drops the raw rows using `ALTER TABLE ... DETACH PARTITION` in $O(1)$ time.

```
                    Automated Hot-to-Cold Compaction
 ┌──────────────────────────────────────┐
 │ PostgreSQL Hot Operational Partition │ (telemetry_y2026m09: 10M rows)
 └──────────────────┬───────────────────┘
                    │ Vectorized SQL Extract (Server-Side Cursor / PyArrow)
                    │ Strips -999.0 sentinels in flight!
                    ▼
 ┌──────────────────────────────────────┐
 │ Zstandard Parquet Compaction Engine  │
 │  • Row Group Size: 250,000           │
 │  • Encodings: RLE + Dictionary       │
 └──────────────────┬───────────────────┘
                    │
                    ▼ Single sequential write pass
 ┌──────────────────────────────────────────────────────────────────────┐
 │ Cold Analytical Lakehouse (MinIO / S3 / Ceph Lake)                   │
 │ climatology_lake/year=2026/month=09/data_0.zstd.parquet              │
 └──────────────────────────────────────────────────────────────────────┘
                    │
                    ▼ Instant O(1) space reclamation
 ┌──────────────────────────────────────────────────────────────────────┐
 │ ALTER TABLE raw_telemetry_partitioned DETACH PARTITION telemetry_... │
 │ DROP TABLE telemetry_y2026m09;                                       │
 └──────────────────────────────────────────────────────────────────────┘
```

### 3.2 Automated Lake Compactor Script ([compact_hot_to_cold.py](./compact_hot_to_cold.py))

This standalone Python script extracts closed records from PostgreSQL, compacts them into our Hive-partitioned Parquet data lake using **PyArrow and DuckDB**, verifies data integrity, and outputs the exact partition retirement commands:

```python
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

print("\n================== OPERATIONAL RETIREMENT COMMAND ==================")
print("To reclaim PostgreSQL disk space instantly with ZERO dead-tuple bloat:")
print("  ALTER TABLE raw_telemetry_partitioned DETACH PARTITION telemetry_y2026m10 CONCURRENTLY;")
print("  DROP TABLE telemetry_y2026m10;")
print("====================================================================\n")
```

> [!WARNING]
> **Production Pitfall (Archiving Un-Sanitized `-999.0` Sentinels into Immutable Parquet):**  
> Once a monthly partition is compacted into immutable ZSTD Parquet files on Ceph RGW / S3, updating a single corrupted row requires rewriting the entire multi-hundred-megabyte Parquet file! Always strip in-band hardware sentinels (`WHERE temperature > -900.0` or `NULLIF(temperature, -999.0)`) *in flight* inside `compact_hot_to_cold.py` so your Parquet zone-map `stats_min` metadata is never poisoned by `-999.0`.

---

## 4. Module 4: The Vectorized Serving Tier & Sub-10ms APIs

### 4.1 Bridging SQL Engines to User Applications

The end-user dashboard (aviation pilots, civil defense directors, public weather apps) must never issue direct, heavy analytical queries against a production transactional database:
* **The Anti-Pattern:** A web frontend running `SELECT AVG(temp) FROM raw_telemetry WHERE...` against the hot primary PostgreSQL server, creating buffer pool thrashing and lock contention.
* **The Production Tier:**
  1. **Spatial Proximity Queries:** Handled by **PostGIS** via Indexed Geodesic Lookups (`ST_DWithin`: $< 2\text{ ms}$).
  2. **Real-Time Sensor Drift & Turbulence:** Handled by **MongoDB** time-series queries ($< 15\text{ ms}$).
  3. **Historical Climatological Normals:** Handled by **DuckDB** querying Parquet Lakehouse files directly from disk or S3 with vectorized SIMD speed ($< 50\text{ ms}$).

### 4.2 The Unified Meteorological FastAPI Server ([serving_api.py](./serving_api.py))

This production-grade API gateway provides three endpoints using connection pools and vectorized query execution:

```python
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

PG_DSN = "postgresql://postgres:postgres@localhost:5432/weather_ops_db"
pg_pool = SimpleConnectionPool(minconn=2, maxconn=10, dsn=PG_DSN)
mongo_client = MongoClient("mongodb://localhost:27017/")
mongo_db = mongo_client["weather_telemetry_db"]

@app.get("/api/v1/spatial/nearby-stations")
def get_nearby_stations(lat: float = 36.75, lon: float = 3.05, radius_km: float = 50.0):
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

@app.get("/api/v1/telemetry/anomalies")
def get_sensor_anomalies():
    col = mongo_db["weather_stream"]
    cursor = col.find({
        "$or": [
            {"turbulent_kinetic_energy": {"$gt": 0.35}},
            {"visibility_meters": {"$lt": 1000}}
        ]
    }, {"_id": 0}).sort("timestamp", -1).limit(10)
    return list(cursor)

@app.get("/api/v1/climatology/summary")
def get_climatology_summary(year: int = 2026):
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
```

> [!TIP]
> **Instructor Live Demo Tip (Interactive Swagger UI at `:8000/docs`):**  
> During the Capstone Lab, open `http://localhost:8000/docs` in the browser! Letting attendees trigger the PostGIS geodesic search, the MongoDB turbulence anomaly query, and the DuckDB Parquet lakehouse scan from one unified OpenAPI interface brings all 5 days of the bootcamp together visually.

---

## 5. Module 5: Capstone Disaster Lab: The Mediterranean Squall Line Approaching Dellys Cape

### 5.1 Capstone Scenario: Severe Squall Line Approaching Dellys Cape

```
                       The Dellys Cape Squall Line Event
                                  
      08:00 AM                        11:30 AM                        14:00 PM
  [Normal Sea Breeze]             [Squall Advance]               [System Recovery]
  • Press: 1014 hPa               • Press: 998 hPa (Plunge!)      • Press: 1010 hPa
  • Wind: 8.5 m/s                 • Wind: 28.4 m/s (Gale Gust)    • Wind: 11.2 m/s
  • Temp: 22.4°C                  • Temp: 14.1°C (Drop)           • Temp: 17.5°C
  • Normal IoT Pings              • High TKE Turbulence           • Hot rows compacted
                                  • Instant Alert Bus             • Parquet Lake archived
```

#### Objective
Attendees execute an end-to-end operational disaster scenario:
1. Ingest simulated squall line telemetry through MQTT.
2. Route the data concurrently to PostgreSQL (`METAR_STANDARD`) and MongoDB (`ULTRASONIC_3D`).
3. Detect the barometric pressure plunge ($\Delta P \le -4\text{ hPa}$) in PostgreSQL via window functions (`LAG`).
4. Issue an automated spatial alert via PostGIS (`ST_DWithin`) to all marine ports and stations within $40\text{ km}$ of Dellys Cape (`3.9130°E, 36.9172°N`).
5. Run the hot-to-cold batch compactor to archive the storm observations into the Parquet lakehouse.
6. Verify that DuckDB and the FastAPI gateway can query the archived storm history in milliseconds.

---

### 5.2 Capstone Execution Runbook

#### Step 1: Run the Edge Simulator
Open Terminal 1 and start the edge simulator:
```bash
python3 simulate_edge_sensors.py
```

#### Step 2: Start the Polyglot Router
Open Terminal 2 and launch the stream router:
```bash
python3 stream_router.py
```
*Observe:* The router receives packets from MQTT, batching METAR observations into PostgreSQL and 3D turbulence observations into MongoDB simultaneously.

#### Step 3: Execute the Severe Storm Detection Query
Open Terminal 3, connect to PostgreSQL, and run the real-time barometric drop detector:
```bash
psql -U postgres -h localhost -d weather_ops_db -c "
WITH tendency_stream AS (
    SELECT 
        station_id,
        recorded_at,
        pressure,
        wind_speed,
        LAG(pressure, 3) OVER (
            PARTITION BY station_id 
            ORDER BY recorded_at
        ) AS baseline_pressure
    FROM raw_telemetry_partitioned
    WHERE recorded_at >= NOW() - INTERVAL '1 hour'
)
SELECT 
    station_id,
    recorded_at,
    baseline_pressure,
    pressure AS current_pressure,
    ROUND((pressure - baseline_pressure)::numeric, 2) AS delta_p_hpa,
    wind_speed
FROM tendency_stream
WHERE baseline_pressure IS NOT NULL
  AND (pressure - baseline_pressure) <= -4.0
ORDER BY delta_p_hpa ASC
LIMIT 5;
"
```

#### Step 4: Dispatch PostGIS Evacuation Geofence
For every station detected in Step 3, identify all adjacent coastal ports and infrastructure within a $40\text{ km}$ geodetic buffer of Dellys Cape (`3.9130, 36.9172`):
```bash
psql -U postgres -h localhost -d weather_ops_db -c "
SELECT 
    station_id,
    station_name,
    elevation_m,
    ROUND((ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(3.9130, 36.9172), 4326)::geography) / 1000.0)::numeric, 2) AS dist_to_squall_center_km
FROM stations
WHERE is_active = TRUE
  AND ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint(3.9130, 36.9172), 4326)::geography, 40000)
ORDER BY dist_to_squall_center_km ASC;
"
```

#### Step 5: Execute Automated Lakehouse Compaction
Archive the completed storm dataset into the columnar lakehouse:
```bash
python3 compact_hot_to_cold.py
```

#### Step 6: Verify Serving via the FastAPI Gateway
Launch the unified serving API:
```bash
python3 serving_api.py
```

In another terminal, test all three tiers of the production serving architecture:
```bash
# 1. Test Spatial Proximity (PostGIS)
curl -s "http://localhost:8000/api/v1/spatial/nearby-stations?lat=36.91&lon=3.91&radius_km=30" | jq .

# 2. Test Real-time Polymorphic Turbulence (MongoDB)
curl -s "http://localhost:8000/api/v1/telemetry/anomalies" | jq .

# 3. Test Vectorized Climatological Analytics (DuckDB + Parquet)
curl -s "http://localhost:8000/api/v1/climatology/summary?year=2026" | jq .
```

---

## 6. Bootcamp Master Architectural Synthesis

Over the past five days, we deconstructed and rebuilt the complete data architecture of a modern national meteorological agency:

```
================================================================================
                    THE 5-DAY ARCHITECTURAL SYNTHESIS
================================================================================
 Day 1 (SQL Foundations)    : Set-based declarative thinking, Three-Valued Logic,
                              handling in-band hardware sentinels (-9999.0 / -999.0)
                              with NULLIF and CASE WHEN, and analyzing sensor streams
                              using Window Functions (LAG, ROW_NUMBER).
                              
 Day 2 (Postgres Internals) : Demystified the 8 KB page block, 23-byte MVCC headers,
                              Tuple Tetris byte alignment, WAL/Checkpoints, and proved
                              the 9.5x I/O amplification of row-stores on analytics.
                              
 Day 3 (Operational Scale)  : Scaled PostgreSQL with Declarative Range Partitioning,
                              BRIN indexes (99% smaller than B-Trees), PostGIS
                              geodetics, Concurrent Materialized Views, and JSONB.
                              
 Day 4 (MongoDB & NoSQL HA) : Modeled nested upper-air radiosonde soundings ($elemMatch,
                              $unwind), native time-series bucketing, 2dsphere GeoJSON,
                              ESR compound indexes, 3-Node Replica Set HA, and Sharding.
                              
 Day 5 (OLAP & Lakehouse)   : Vectorized SIMD query execution with DuckDB, Apache Parquet
                              internals, Hive lake topologies, 4D atmospheric grids
                              (GRIB2, NetCDF4, Zarr, BUFR), and the complete polyglot
                              pipeline: Edge MQTT -> Kafka -> Router -> PG/Mongo ->
                              Parquet Compactor -> Sub-10ms FastAPI Serving Tier.
================================================================================
```

### Final Instructor Closing Address

> *"Congratulations, engineers. You have transitioned from viewing databases as generic storage boxes to understanding their physical reality: disk blocks, CPU vector registers, memory caches, and network consensus.*
>
> *You know why a row-store fails at 100 million rows, why a B-Tree thrashes your memory, why `DELETE` never returns bytes to Linux, why hardware transmits `-9999.0`, and why DuckDB can scan an entire year of data in the time PostgreSQL takes to parse a query plan.*
>
> *You now hold the blueprints to design, operate, scale, and protect the mission-critical weather data systems of your nation. Build with precision, respect the physics of storage, and never let a hardware sentinel corrupt your science."*

---

> **Navigation:** [🏠 Master README](../README.md) | [🌐 Interactive Portal](../bootcamp_portal.html) | [⬅️ Day 5 (Part 1): Analytical OLAP & DuckDB](day5_part1_olap_duckdb_parquet_and_gridded_data_coursebook.md) | [➡️ Final Assessment & Troubleshooting](bootcamp_capstone_troubleshooting_and_quiz.md) | [📚 Reference Cards](../reference_cards/README.md)
