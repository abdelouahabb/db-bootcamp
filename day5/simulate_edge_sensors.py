#!/usr/bin/env python3
"""
Simulate High-Frequency Edge Weather Telemetry Stream over MQTT (simulate_edge_sensors.py)
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
        time.sleep(0.02)  # ~50 packets/second

except KeyboardInterrupt:
    print(f"\n[+] Stopped. Total packets published: {packet_count:,}")
    client.loop_stop()
    client.disconnect()
