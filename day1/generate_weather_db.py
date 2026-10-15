#!/usr/bin/env python3
"""
Weather Telemetry Database Generator for Day 1 SQLite Labs
Generates a realistic 250,000-row SQLite database in ~2-3 seconds.
Zero external dependencies (uses standard library sqlite3).
"""

import sqlite3
import random
import math
from datetime import datetime, timedelta, timezone

DB_FILE = "weather_telemetry.db"
TOTAL_OBSERVATIONS = 250_000
NUM_STATIONS = 50
BATCH_SIZE = 10_000

def create_database():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # High-throughput SQLite PRAGMAs for fast ingestion
    cur.execute("PRAGMA journal_mode = OFF;")
    cur.execute("PRAGMA synchronous = OFF;")
    cur.execute("PRAGMA cache_size = 100000;")

    cur.execute("DROP TABLE IF EXISTS raw_telemetry;")
    cur.execute("DROP TABLE IF EXISTS stations;")

    cur.execute("""
    CREATE TABLE stations (
        station_id TEXT PRIMARY KEY,
        station_name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        elevation_m REAL NOT NULL,
        is_active INTEGER NOT NULL
    );
    """)

    cur.execute("""
    CREATE TABLE raw_telemetry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        station_id TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        temperature REAL,
        pressure REAL,
        wind_speed REAL,
        wind_direction INTEGER,
        rain_accum_1m REAL,
        FOREIGN KEY(station_id) REFERENCES stations(station_id)
    );
    """)

    # 1. Seed 50 Weather Stations
    print(f"[*] Seeding {NUM_STATIONS} weather stations...")
    stations = []
    station_ids = [f"AWS-{i:03d}" for i in range(1, NUM_STATIONS + 1)]
    
    for s_id in station_ids:
        lat = round(35.0 + random.uniform(0.0, 4.0), 4)
        lon = round(3.0 + random.uniform(0.0, 5.0), 4)
        elev = round(random.uniform(50.0, 1800.0), 1)
        name = f"Station-{s_id} (Elev {int(elev)}m)"
        stations.append((s_id, name, lat, lon, elev, 1))

    cur.executemany("INSERT INTO stations VALUES (?, ?, ?, ?, ?, ?);", stations)

    # 2. Generate 250,000 observations over the last 48 hours
    print(f"[*] Generating {TOTAL_OBSERVATIONS:,} telemetry records...")
    now = datetime.now(timezone.utc)
    base_time = now - timedelta(hours=48)
    total_seconds = 48 * 3600

    telemetry_batch = []
    
    for row_idx in range(1, TOTAL_OBSERVATIONS + 1):
        s_id = random.choice(station_ids)
        
        # Time distribution across the 48-hour window
        seconds_offset = int((row_idx / TOTAL_OBSERVATIONS) * total_seconds)
        seconds_offset = max(0, min(total_seconds, seconds_offset + random.randint(-60, 60)))
        rec_time = base_time + timedelta(seconds=seconds_offset)
        rec_time_str = rec_time.strftime("%Y-%m-%d %H:%M:%S")

        # Injected Anomaly 4: Outage on AWS-033 (simulate 6-hour dropped communication)
        while s_id == "AWS-033" and (15 * 3600 <= seconds_offset <= 21 * 3600):
            s_id = random.choice(station_ids)

        # Baseline physical models
        hour_float = rec_time.hour + (rec_time.minute / 60.0)
        diurnal_cycle = math.sin((hour_float - 9.0) * math.pi / 12.0)
        temp = round(16.0 + (diurnal_cycle * 8.0) + random.gauss(0, 1.2), 2)
        pressure = round(1013.25 - (diurnal_cycle * 2.0) + random.gauss(0, 0.8), 2)
        wind_speed = max(0.0, round(random.weibullvariate(3.5, 1.8), 2))
        wind_dir = random.randint(0, 359)
        rain = round(random.expovariate(4.0), 2) if random.random() < 0.08 else 0.0

        # Injected Anomaly 1: Stations with high sentinel failure rates (AWS-013, AWS-042)
        if s_id in ("AWS-013", "AWS-042") and random.random() < 0.18:
            temp = -999.0
            pressure = -999.0 if random.random() < 0.5 else pressure
            wind_speed = -999.0 if random.random() < 0.5 else wind_speed

        # Injected Anomaly 2: Frontal passage / pressure plunge on AWS-007 and AWS-018
        if s_id in ("AWS-007", "AWS-018") and (now - rec_time).total_seconds() < 12 * 3600:
            drop_factor = (12 * 3600 - (now - rec_time).total_seconds()) / (12 * 3600)
            pressure = round(pressure - (drop_factor * 8.5), 2)
            wind_speed = round(wind_speed + (drop_factor * 18.0), 2)

        # Injected Anomaly 3: Thermal inversion / sensor spike anomaly on AWS-025
        if s_id == "AWS-025" and 35000 < seconds_offset < 35500:
            temp = round(temp + 8.5, 2)

        telemetry_batch.append((s_id, rec_time_str, temp, pressure, wind_speed, wind_dir, rain))

        if len(telemetry_batch) >= BATCH_SIZE:
            cur.executemany("""
                INSERT INTO raw_telemetry (station_id, recorded_at, temperature, pressure, wind_speed, wind_direction, rain_accum_1m)
                VALUES (?, ?, ?, ?, ?, ?, ?);
            """, telemetry_batch)
            telemetry_batch = []

    if telemetry_batch:
        cur.executemany("""
            INSERT INTO raw_telemetry (station_id, recorded_at, temperature, pressure, wind_speed, wind_direction, rain_accum_1m)
            VALUES (?, ?, ?, ?, ?, ?, ?);
        """, telemetry_batch)

    # 3. Create baseline indexes
    print("[*] Creating baseline indexes...")
    cur.execute("CREATE INDEX idx_telemetry_station_time ON raw_telemetry (station_id, recorded_at);")
    cur.execute("CREATE INDEX idx_telemetry_time ON raw_telemetry (recorded_at);")

    conn.commit()
    conn.close()
    print(f"[+] Complete. Database initialized: '{DB_FILE}' ({TOTAL_OBSERVATIONS:,} rows).")

if __name__ == "__main__":
    create_database()
