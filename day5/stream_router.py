#!/usr/bin/env python3
"""
Production Polyglot Stream Router (stream_router.py)
Consumes edge weather telemetry from MQTT, inspects sensor schemas,
and routes concurrently:
  - METAR_STANDARD -> PostgreSQL (Range-partitioned, PostGIS linked)
  - ULTRASONIC_3D  -> MongoDB (Native Time-Series Bucketed Collection)
"""

import argparse
import json
import time
from datetime import datetime
import psycopg2
from psycopg2.extras import execute_values
from pymongo import MongoClient, InsertOne
import paho.mqtt.client as mqtt

parser = argparse.ArgumentParser(description="Polyglot Meteorological Stream Router")
parser.add_argument("--batch-size", type=int, default=100, help="Micro-batch flush threshold (default: 100)")
args, _ = parser.parse_known_args()

# Configuration
PG_DSN = "postgresql://postgres:postgres@localhost:5432/weather_ops_db"
MONGO_URI = "mongodb://localhost:27017/"
MQTT_BROKER = "localhost"
MQTT_PORT = 1883
TOPIC_SOURCE = "weather/telemetry/raw"

BATCH_SIZE = args.batch_size
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
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'postgis') THEN
        CREATE EXTENSION IF NOT EXISTS postgis;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geometry') THEN
            CREATE DOMAIN geometry AS point;
        END IF;
        CREATE OR REPLACE FUNCTION ST_MakePoint(lon double precision, lat double precision) RETURNS point AS $b$
            SELECT point(lon, lat);
        $b$ LANGUAGE sql IMMUTABLE;
        CREATE OR REPLACE FUNCTION ST_SetSRID(pt point, srid int) RETURNS point AS $b$
            SELECT pt;
        $b$ LANGUAGE sql IMMUTABLE;
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS stations (
    station_id VARCHAR(10) PRIMARY KEY,
    station_name VARCHAR(100) NOT NULL,
    elevation_m REAL NOT NULL,
    is_active BOOLEAN DEFAULT TRUE
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'stations' AND column_name = 'geom'
    ) THEN
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
            ALTER TABLE stations ADD COLUMN geom GEOMETRY(Point, 4326);
        ELSE
            ALTER TABLE stations ADD COLUMN geom geometry;
        END IF;
    END IF;
END
$$;

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
            # Scrub hardware sentinels (-9999.0 / -999.0) into SQL NULL (None)
            raw_temp = data.get("temperature")
            clean_temp = None if (raw_temp is not None and raw_temp <= -900.0) else raw_temp
            batch_pg.append((
                data["timestamp"],
                data["station_id"],
                clean_temp,
                data["pressure"],
                data["wind_speed"],
                data["rain_accum_1m"]
            ))
        elif sensor_type == "ULTRASONIC_3D":
            # Convert ISO string to BSON Date (required by MongoDB Native Time-Series collections!)
            ts_val = data["timestamp"]
            if isinstance(ts_val, str):
                ts_val = datetime.fromisoformat(ts_val.replace("Z", "+00:00"))
            mongo_doc = {
                "timestamp": ts_val,
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


# 2. Start MQTT Subscriber
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
