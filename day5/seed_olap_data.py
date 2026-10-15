#!/usr/bin/env python3
"""
Day 5 OLAP & Gridded Meteorological Benchmark Seeder (seed_olap_data.py)
Generates:
  1. 10,000,000 observations stored in a partitioned Apache Parquet lake (~220 MB)
  2. A 4D gridded Numerical Weather Prediction (NWP) NetCDF4 file (~15 MB)
Execution Time: ~15-25 seconds depending on CPU.
"""

import os
import shutil
import time
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq
import xarray as xr
import pandas as pd

PARQUET_LAKE_DIR = "climatology_lake"
TOTAL_RECORDS = 10_000_000
BATCH_SIZE = 1_000_000

print("=================================================================")
print("  DAY 5: SYNTHESIZING OLAP PARQUET LAKE & 4D NWP NETCDF RASTER   ")
print("=================================================================")

# 1. Generate Partitioned Climatology Parquet Lake (10,000,000 Rows)
if os.path.exists(PARQUET_LAKE_DIR):
    shutil.rmtree(PARQUET_LAKE_DIR)
os.makedirs(PARQUET_LAKE_DIR, exist_ok=True)

print(f"[*] Generating {TOTAL_RECORDS:,} observations into Parquet Lake...")
start_time = time.time()

station_ids = np.array([f"AWS-{i:04d}" for i in range(1, 501)])
regions = np.array(["COASTAL_MED", "TELL_ATLAS", "HIGHLANDS_CHOTTS", "SAHARA_NORTH"])

arrow_schema = pa.schema([
    ("station_id", pa.string()),
    ("region", pa.string()),
    ("recorded_at", pa.timestamp("ms")),
    ("temperature", pa.float32()),
    ("pressure", pa.float32()),
    ("wind_speed", pa.float32()),
    ("relative_humidity", pa.float32()),
    ("solar_radiation_wm2", pa.float32()),
    ("year", pa.int32()),
    ("month", pa.int32())
])

num_batches = TOTAL_RECORDS // BATCH_SIZE
base_timestamp = np.datetime64("2016-01-01T00:00:00", "ms")

for batch_idx in range(num_batches):
    t0 = time.time()
    random_seconds = np.random.randint(0, 10 * 365 * 86400, size=BATCH_SIZE, dtype=np.int64)
    timestamps = base_timestamp + (random_seconds * 1000).astype("timedelta64[ms]")

    dates = pd.to_datetime(timestamps)
    years = dates.year.to_numpy(dtype=np.int32)
    months = dates.month.to_numpy(dtype=np.int32)

    station_picks = np.random.choice(station_ids, size=BATCH_SIZE)
    region_picks = np.random.choice(regions, size=BATCH_SIZE)
    temperatures = np.round(np.random.normal(loc=18.5, scale=8.0, size=BATCH_SIZE).astype(np.float32), 2)
    pressures = np.round(np.random.normal(loc=1013.25, scale=12.0, size=BATCH_SIZE).astype(np.float32), 2)
    wind_speeds = np.round(np.random.weibull(a=1.8, size=BATCH_SIZE).astype(np.float32) * 5.5, 2)
    humidity = np.round(np.random.uniform(15.0, 95.0, size=BATCH_SIZE).astype(np.float32), 1)
    solar_rad = np.round(np.maximum(0.0, np.random.normal(loc=450.0, scale=300.0, size=BATCH_SIZE)).astype(np.float32), 1)

    table = pa.Table.from_arrays([
        pa.array(station_picks),
        pa.array(region_picks),
        pa.array(timestamps),
        pa.array(temperatures),
        pa.array(pressures),
        pa.array(wind_speeds),
        pa.array(humidity),
        pa.array(solar_rad),
        pa.array(years),
        pa.array(months)
    ], schema=arrow_schema)

    pq.write_to_dataset(
        table,
        root_path=PARQUET_LAKE_DIR,
        partition_cols=["year"],
        compression="snappy",
        use_dictionary=["station_id", "region"],
        row_group_size=250_000
    )
    print(f"   -> Batch {batch_idx + 1}/{num_batches} written ({BATCH_SIZE:,} rows in {time.time() - t0:.2f}s)...")

parquet_duration = time.time() - start_time
print(f"[+] Parquet Lake complete: {TOTAL_RECORDS:,} rows in {parquet_duration:.2f}s.")

# 2. Generate 4D NWP Model Output (NetCDF4 / CF-1.8 Compliant)
NETCDF_FILE = "nwp_forecast_algeria.nc"
print(f"\n[*] Generating 4-Dimensional NWP Model Grid: '{NETCDF_FILE}'...")

times = pd.date_range("2026-10-04T00:00:00", periods=24, freq="1h")
pressure_levels = np.array([1000, 925, 850, 700, 500, 300, 200], dtype=np.int32)
lats = np.linspace(34.0, 38.0, 41, dtype=np.float32)
lons = np.linspace(1.0, 8.0, 71, dtype=np.float32)

grid_shape = (len(times), len(pressure_levels), len(lats), len(lons))

level_lapse = np.array([293.15, 288.15, 283.15, 273.15, 252.15, 230.15, 218.15])
base_t = np.broadcast_to(level_lapse[None, :, None, None], grid_shape).copy()
t_noise = np.random.normal(0, 1.5, size=grid_shape).astype(np.float32)
temperature_grid = (base_t + t_noise).astype(np.float32)

base_z = np.array([100, 750, 1450, 3000, 5500, 9200, 11800], dtype=np.float32)
geopotential_grid = np.broadcast_to(base_z[None, :, None, None], grid_shape).copy()

u_wind = np.random.normal(loc=12.0, scale=8.0, size=grid_shape).astype(np.float32)
v_wind = np.random.normal(loc=-3.0, scale=6.0, size=grid_shape).astype(np.float32)

ds = xr.Dataset(
    data_vars={
        "t": (["time", "level", "latitude", "longitude"], temperature_grid, {"units": "K", "long_name": "Air Temperature"}),
        "gh": (["time", "level", "latitude", "longitude"], geopotential_grid, {"units": "gpm", "long_name": "Geopotential Height"}),
        "u": (["time", "level", "latitude", "longitude"], u_wind, {"units": "m s**-1", "long_name": "U-Wind"}),
        "v": (["time", "level", "latitude", "longitude"], v_wind, {"units": "m s**-1", "long_name": "V-Wind"}),
    },
    coords={
        "time": times,
        "level": (["level"], pressure_levels, {"units": "hPa"}),
        "latitude": (["latitude"], lats, {"units": "degrees_north"}),
        "longitude": (["longitude"], lons, {"units": "degrees_east"}),
    },
    attrs={
        "title": "High-Resolution Operational NWP Forecast - Northern Algeria",
        "institution": "National Meteorological Service",
        "Conventions": "CF-1.8"
    }
)

encoding = {var: {"zlib": True, "complevel": 4} for var in ds.data_vars}
ds.to_netcdf(NETCDF_FILE, engine="netcdf4", encoding=encoding)
print(f"[+] NetCDF4 Raster written successfully: '{NETCDF_FILE}' ({os.path.getsize(NETCDF_FILE) / 1024 / 1024:.2f} MB).")
print("=================================================================\n")
