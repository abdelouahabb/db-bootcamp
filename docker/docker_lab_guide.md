> **Navigation:** [Master README](../README.md) | [Interactive Portal](../bootcamp_portal.html) | [⬅ Day 4: MongoDB Replica Sets](../day4/day4_master_coursebook.md) | [Day 5: Polyglot Streaming Lakehouse](../day5/day5_part2_enterprise_polyglot_lakehouse_and_capstone_coursebook.md) | [Reference Cards](../reference_cards/README.md)

# Turnkey Docker Compose Lab Guide: 3-Node HA Replica Set & 5-Service Polyglot Streaming Lakehouse

**Companion Files:**
* [docker-compose.ha-replicaset.yml](./docker-compose.ha-replicaset.yml) *(Days 2–4: PostGIS 16 + 3-Node MongoDB 7.0 Replica Set `rs_meteo`)*
* [docker-compose.polyglot-lakehouse.yml](./docker-compose.polyglot-lakehouse.yml) *(Day 5 Capstone: Mosquitto MQTT + Redpanda Kafka + PostGIS 16 + MongoDB 7.0 + MinIO S3 + Adminer)*

---

## 1. Choosing Which Docker Stack to Launch

This directory provides **two turnkey Docker Compose topologies** so you can launch either the **Multi-Node High-Availability Replica Set Lab** (Days 2–4) or the **End-to-End Polyglot Streaming Lakehouse** (Day 5 Capstone) with a single command:

| Stack File | Services Included | When to Use |
| :--- | :--- | :--- |
| **[docker-compose.ha-replicaset.yml](./docker-compose.ha-replicaset.yml)** | • `weather-pg-primary` (`5432`)<br>• `weather-mongo-node1` (`27017`)<br>• `weather-mongo-node2` (`27018`)<br>• `weather-mongo-node3` (`27019`) | **Days 2, 3 & 4:** PostgreSQL internals, range partitioning, PostGIS, and MongoDB 3-Node Replica Set High Availability & Chaos Engineering failover testing. |
| **[docker-compose.polyglot-lakehouse.yml](./docker-compose.polyglot-lakehouse.yml)** | • `weather_mosquitto` (`1883` MQTT)<br>• `weather_kafka` (`9092` Redpanda)<br>• `weather_postgres` (`5432` PostGIS)<br>• `weather_mongodb` (`27017` Mongo 7)<br>• `weather_minio` (`9000`/`9001` S3)<br>• `weather_adminer` (`8080` Web UI) | **Day 5 Capstone:** Real-time MQTT edge telemetry simulation, dynamic polyglot routing (`stream_router.py`), hot-to-cold Parquet compaction (`compact_hot_to_cold.py`), and the FastAPI gateway (`serving_api.py`). |

> [!WARNING]
> **Production Pitfall (Port Sharing on `5432` and `27017`):**  
> Because both stacks bind host ports `5432` (PostgreSQL) and `27017` (MongoDB), always stop Stack A (`docker compose -f docker-compose.ha-replicaset.yml down`) before starting Stack B (`docker compose -f docker-compose.polyglot-lakehouse.yml up -d`).

---

## 2. Stack A: 3-Node HA Replica Set Lab (`docker-compose.ha-replicaset.yml`)

### 2.1 What Does `docker-compose.ha-replicaset.yml` Spin Up?

| Container Name | Image | Host Port | Role in Bootcamp |
| :--- | :--- | :--- | :--- |
| **`weather-pg-primary`** | `postgis/postgis:16-3.4` | `5432` | **Days 2 & 3:** PostgreSQL 16 + PostGIS 3.4 pre-tuned with `timezone=UTC`, `work_mem=32MB`, `random_page_cost=1.1`, and `pg_stat_statements`. Mounts bootcamp root at `/workspace`. |
| **`weather-mongo-node1`** | `mongo:7.0` | `27017` | **Day 4:** Primary node (`priority: 2`) of Replica Set `rs_meteo`. Mounts bootcamp root at `/workspace`. |
| **`weather-mongo-node2`** | `mongo:7.0` | `27018` | **Day 4 HA Lab:** Secondary failover standby (`priority: 1`) of Replica Set `rs_meteo`. |
| **`weather-mongo-node3`** | `mongo:7.0` | `27019` | **Day 4 HA Lab:** Dedicated analytics Secondary (`priority: 0`, tagged `workload: "analytics"`). |

### 2.2 Step-by-Step Quick Start (Stack A)

#### Step 1: Start All Containers
```bash
cd docker
docker compose -f docker-compose.ha-replicaset.yml up -d
docker compose -f docker-compose.ha-replicaset.yml ps
```

#### Step 2: Load Days 2 & 3 PostgreSQL + PostGIS Labs
```bash
# 1. Load Day 2 Multi-Schema Architecture & Synoptic Rows
docker exec -i weather-pg-primary psql -U postgres -d weather_ops -f /workspace/day2/weather_ops_pg.sql

# 2. Load Day 3 Monthly Partitions, BRIN/Partial/GIN Indexes & Materialized Views
docker exec -i weather-pg-primary psql -U postgres -d weather_ops -f /workspace/day3/day3_weather_advanced_pg.sql

# 3. Open interactive psql shell inside the container:
docker exec -it weather-pg-primary psql -U postgres -d weather_ops
```

#### Step 3: Initialize the 3-Node MongoDB Replica Set (`rs_meteo`) & Load Day 4 Labs
```bash
# 1. Initialize the 3-node Replica Set (mongo-node1, mongo-node2, mongo-node3)
docker exec -it weather-mongo-node1 mongosh --eval '
rs.initiate({
  _id: "rs_meteo",
  members: [
    { _id: 0, host: "mongo-node1:27017", priority: 2, tags: { workload: "operational" } },
    { _id: 1, host: "mongo-node2:27017", priority: 1, tags: { workload: "operational" } },
    { _id: 2, host: "mongo-node3:27017", priority: 0, tags: { workload: "analytics" } }
  ]
});
'

# Wait ~5 seconds for mongo-node1 to win the election, then load Day 4 datasets:
sleep 5
docker exec -it weather-mongo-node1 mongosh weather_nosql /workspace/day4/day4_weather_ops_mongo.js
docker exec -it weather-mongo-node1 mongosh weather_nosql /workspace/day4/day4_weather_ops_mongo_advanced.js
```

### 2.3 Hands-On Chaos Engineering Lab: Simulating a Live Primary Node Crash!

Use this 2-minute live demo to show weather engineers how a 3-node Replica Set survives a sudden server crash with **zero data loss**:

```bash
# 1. Verify mongo-node1 is currently PRIMARY:
docker exec -it weather-mongo-node1 mongosh --quiet --eval "rs.status().members.map(m => ({name: m.name, state: m.stateStr}))"

# 2. SIMULATE POWER OUTAGE: Kill the Primary container (weather-mongo-node1)!
docker stop weather-mongo-node1

# 3. Wait ~10 seconds and ask mongo-node2 who the Primary is now!
# Notice mongo-node2 has automatically promoted itself to PRIMARY!
docker exec -it weather-mongo-node2 mongosh --quiet --eval "rs.status().members.map(m => ({name: m.name, state: m.stateStr}))"

# 4. Query your weather stations and radiosonde soundings on mongo-node2 — 100% online!
docker exec -it weather-mongo-node2 mongosh weather_nosql --quiet --eval "db.stations.countDocuments()"

# 5. Bring mongo-node1 back online — it automatically rejoins, catches up via Oplog, and reclaims Primary (priority: 2)!
docker start weather-mongo-node1
```

---

## 3. Stack B: 5-Service Polyglot Streaming Lakehouse (`docker-compose.polyglot-lakehouse.yml`)

### 3.1 What Does `docker-compose.polyglot-lakehouse.yml` Spin Up?

| Container Name | Image | Host Port(s) | Role in Day 5 Capstone |
| :--- | :--- | :--- | :--- |
| **`weather_mosquitto`** | `eclipse-mosquitto:2.0` | `1883` | Edge MQTT Broker receiving live station packets from `simulate_edge_sensors.py`. |
| **`weather_kafka`** | `redpanda:v23.3.10` | `9092`, `9644` | Zero-JVM Kafka-compatible distributed event streaming broker. |
| **`weather_postgres`** | `postgis/postgis:16-3.4` | `5432` | Hot Operational Relational & PostGIS store (`weather_ops_db`). |
| **`weather_mongodb`** | `mongo:7.0` | `27017` | Hot Polymorphic Time-Series store (`weather_telemetry_db.weather_stream`). |
| **`weather_minio`** | `minio/minio` | `9000` (S3), `9001` (UI) | S3-Compatible Lakehouse Object Store (`minioadmin` / `minioadmin`). |
| **`weather_adminer`** | `adminer:4.8.1` | `8080` | Web GUI for inspecting PostgreSQL tables in real time. |

### 3.2 Step-by-Step Quick Start (Stack B — Day 5 Capstone)

#### Step 1: Switch from Stack A to Stack B
```bash
cd docker

# Stop Stack A if running:
docker compose -f docker-compose.ha-replicaset.yml down

# Launch the 5-service Polyglot Lakehouse stack:
docker compose -f docker-compose.polyglot-lakehouse.yml up -d
docker compose -f docker-compose.polyglot-lakehouse.yml ps
```

#### Step 2: Run the End-to-End Day 5 Streaming, Compaction & FastAPI Pipeline
```bash
cd ../day5

# Terminal 1: Start the MQTT Edge Weather Telemetry Simulator
python3 simulate_edge_sensors.py

# Terminal 2: Start the Polyglot Stream Router (MQTT -> PostgreSQL + MongoDB)
python3 stream_router.py

# Terminal 3: Compact Hot PostgreSQL Partitions into Cold Hive Parquet + Verify with DuckDB
python3 compact_hot_to_cold.py

# Terminal 4: Launch the Unified Sub-10ms FastAPI Gateway (http://localhost:8000/docs)
python3 serving_api.py
```

---

> **Navigation:** [Master README](../README.md) | [Interactive Portal](../bootcamp_portal.html) | [⬅ Day 4: MongoDB Replica Sets](../day4/day4_master_coursebook.md) | [Day 5: Polyglot Streaming Lakehouse](../day5/day5_part2_enterprise_polyglot_lakehouse_and_capstone_coursebook.md) | [Reference Cards](../reference_cards/README.md)
