#!/usr/bin/env python3
"""
Bootcamp Utility: Stream PostgreSQL Synoptic Weather Observations to Apache Parquet
Uses a server-side cursor (psycopg) + PyArrow ParquetWriter for constant low RAM usage.
"""

import os
try:
    import psycopg2 as pg_driver
except ImportError:
    import psycopg as pg_driver
import pyarrow as pa
import pyarrow.parquet as pq

PG_DSN = os.getenv("PG_DSN", "postgresql://postgres:postgres@localhost:5432/weather_ops")
OUTPUT_PARQUET = os.getenv("OUTPUT_PARQUET", "synoptic_observations_2026.parquet")
BATCH_SIZE = 50_000

WEATHER_ARROW_SCHEMA = pa.schema([
    ("station_id",    pa.int32()),
    ("obs_time",      pa.timestamp("us", tz="UTC")),
    ("temp_c",        pa.float32()),
    ("dewpoint_c",    pa.float32()),
    ("humidity_pct",  pa.float32()),
    ("pressure_hpa",  pa.float32()),
    ("wind_speed_kt", pa.float32()),
    ("precip_1h_mm",  pa.float32()),
    ("qc_flag",       pa.dictionary(pa.int8(), pa.string())),
])

QUERY = """
    SELECT
        station_id,
        obs_time,
        temp_c::FLOAT4,
        dewpoint_c::FLOAT4,
        humidity_pct::FLOAT4,
        pressure_hpa::FLOAT4,
        wind_speed_kt::FLOAT4,
        precip_1h_mm::FLOAT4,
        qc_flag
    FROM synoptic.observations
    ORDER BY obs_time, station_id
"""


def export_postgres_to_parquet() -> None:
    print(f"Connecting to PostgreSQL: {PG_DSN}")
    with pg_driver.connect(PG_DSN) as conn:
        with conn.cursor(name="meteo_parquet_stream") as cur:
            cur.itersize = BATCH_SIZE
            cur.execute(QUERY)

            with pq.ParquetWriter(
                OUTPUT_PARQUET,
                schema=WEATHER_ARROW_SCHEMA,
                compression="ZSTD",
                compression_level=6,
                use_dictionary=True,
                write_statistics=True,
            ) as writer:
                total_rows = 0
                while True:
                    rows = cur.fetchmany(BATCH_SIZE)
                    if not rows:
                        break
                    cols = list(zip(*rows))
                    batch = pa.RecordBatch.from_arrays(
                        [
                            pa.array(col, type=field.type)
                            for col, field in zip(cols, WEATHER_ARROW_SCHEMA)
                        ],
                        schema=WEATHER_ARROW_SCHEMA,
                    )
                    writer.write_batch(batch)
                    total_rows += len(rows)
                    print(f"  -> Streamed {total_rows:,} rows to {OUTPUT_PARQUET}")

    file_size_kb = os.path.getsize(OUTPUT_PARQUET) / 1024.0
    print(f"Done! Wrote {total_rows:,} rows ({file_size_kb:.1f} KB) to {OUTPUT_PARQUET}")


if __name__ == "__main__":
    export_postgres_to_parquet()
