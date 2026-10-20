-- ============================================================================
-- DAY 3 BOOTCAMP: ADVANCED PRODUCTION POSTGRESQL FOR WEATHER ENGINEERS
-- File: day3_weather_advanced_pg.sql
-- Prerequisite: Run after weather_ops_pg.sql (Day 2)
-- Usage: psql -d weather_ops -f day3_weather_advanced_pg.sql
-- ============================================================================

SET timezone = 'UTC';
SET datestyle = 'iso, ymd';
SET search_path TO synoptic, nwp, alerts, public;

-- ============================================================================
-- MODULE 1: DECLARATIVE TIME-SERIES PARTITIONING (PARTITION BY RANGE)
-- Splitting synoptic observations into monthly child partitions
-- ============================================================================
DROP TABLE IF EXISTS synoptic.observations_part CASCADE;

CREATE TABLE synoptic.observations_part (
    station_id     INTEGER      NOT NULL REFERENCES synoptic.stations(station_id),
    obs_time       TIMESTAMPTZ  NOT NULL,
    temp_c         NUMERIC(4,1),
    dewpoint_c     NUMERIC(4,1),
    humidity_pct   NUMERIC(4,1),
    pressure_hpa   NUMERIC(6,1),
    wind_speed_kt  NUMERIC(4,1),
    precip_1h_mm   NUMERIC(5,1),
    qc_flag        VARCHAR(15)  NOT NULL DEFAULT 'VALID',
    sensor_payload JSONB        DEFAULT '{}'::JSONB,
    PRIMARY KEY (obs_time, station_id) -- Partition key (obs_time) MUST be part of Primary/Unique Key
) PARTITION BY RANGE (obs_time);

-- Create Monthly Partitions (June 2026 through October 2026)
CREATE TABLE synoptic.obs_y2026m06 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE synoptic.obs_y2026m07 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');

CREATE TABLE synoptic.obs_y2026m08 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');

CREATE TABLE synoptic.obs_y2026m09 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE synoptic.obs_y2026m10 PARTITION OF synoptic.observations_part
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');

-- Default partition to catch any out-of-range timestamps so ingestion never fails
CREATE TABLE synoptic.obs_default PARTITION OF synoptic.observations_part DEFAULT;

-- Populate partitioned table from Day 2 observations + attach rich JSONB sensor telemetry
INSERT INTO synoptic.observations_part (
    station_id, obs_time, temp_c, dewpoint_c, humidity_pct,
    pressure_hpa, wind_speed_kt, precip_1h_mm, qc_flag, sensor_payload
)
SELECT
    station_id,
    obs_time,
    temp_c,
    dewpoint_c,
    humidity_pct,
    pressure_hpa,
    wind_speed_kt,
    precip_1h_mm,
    qc_flag,
    jsonb_build_object(
        'battery_v', ROUND((12.1 + RANDOM() * 1.4)::NUMERIC, 2),
        'solar_w_m2', CASE
            WHEN EXTRACT(HOUR FROM obs_time) BETWEEN 7 AND 18
            THEN ROUND((300 + RANDOM() * 650)::NUMERIC, 0)
            ELSE 0
        END,
        'gust_3s_kt', ROUND((wind_speed_kt * (1.15 + RANDOM() * 0.35))::NUMERIC, 1),
        'sensors', jsonb_build_array('PT100_THERM', 'CAP_HYGRO', 'ULTRASONIC_WIND'),
        'diagnostics', jsonb_build_object(
            'door_open', (RANDOM() > 0.995),
            'firmware', CASE WHEN station_id IN (60390, 60490) THEN 'v4.2.1' ELSE 'v3.9.0' END
        )
    )
FROM synoptic.observations;

-- ============================================================================
-- MODULE 2: ADVANCED INDEXING (BRIN, PARTIAL, COVERING & GIN)
-- ============================================================================

-- 1. BRIN Index (Block Range Index) on chronological time-series column
CREATE INDEX idx_obs_brin_time
ON synoptic.observations USING BRIN (obs_time) WITH (pages_per_range = 8);

-- 2. Standard B-Tree Index on obs_time (to compare disk size against BRIN!)
CREATE INDEX idx_obs_btree_time
ON synoptic.observations USING BTREE (obs_time);

-- 3. Partial Index: Only index anomalous ('SUSPECT' or 'ERRONEOUS') observations (~4% of rows)
CREATE INDEX idx_obs_suspect_only
ON synoptic.observations (station_id, obs_time)
WHERE qc_flag != 'VALID';

-- 4. Covering Index (INCLUDE) for Index-Only Scans on station temperature queries
CREATE INDEX idx_obs_station_time_covering
ON synoptic.observations (station_id, obs_time)
INCLUDE (temp_c, pressure_hpa, precip_1h_mm);

-- 5. GIN Index on JSONB sensor_payload for fast NoSQL-style containment queries (@>)
CREATE INDEX idx_obs_part_sensor_gin
ON synoptic.observations_part USING GIN (sensor_payload);

-- ============================================================================
-- MODULE 4: MATERIALIZED VIEW FOR NWP MODEL VERIFICATION DASHBOARD
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS nwp.mv_daily_model_verification;

CREATE MATERIALIZED VIEW nwp.mv_daily_model_verification AS
SELECT
    f.model_name,
    f.station_id,
    s.station_name,
    DATE_TRUNC('day', f.valid_time)::DATE                       AS valid_date,
    COUNT(*)                                                    AS verified_runs,
    ROUND(AVG(f.pred_temp_c - o.temp_c), 2)                     AS temp_bias_c,
    ROUND(AVG(ABS(f.pred_temp_c - o.temp_c)), 2)                AS temp_mae_c,
    ROUND(AVG(ABS(f.pred_wind_kt - o.wind_speed_kt)), 2)        AS wind_mae_kt
FROM nwp.forecasts f
INNER JOIN synoptic.observations o
    ON o.station_id = f.station_id
   AND o.obs_time   = f.valid_time
INNER JOIN synoptic.stations s
    ON s.station_id = f.station_id
GROUP BY f.model_name, f.station_id, s.station_name, DATE_TRUNC('day', f.valid_time)::DATE
WITH DATA;

-- Unique index required to enable REFRESH MATERIALIZED VIEW CONCURRENTLY!
CREATE UNIQUE INDEX idx_mv_daily_verif_unique
ON nwp.mv_daily_model_verification (model_name, station_id, valid_date);

-- Automatically enable PostGIS (or WGS-84 geodesic fallback) and populate synoptic.stations.geog & geom
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'postgis') THEN
        CREATE EXTENSION IF NOT EXISTS postgis;
        ALTER TABLE synoptic.stations ADD COLUMN IF NOT EXISTS geog GEOGRAPHY(Point, 4326);
        ALTER TABLE synoptic.stations ADD COLUMN IF NOT EXISTS geom GEOMETRY(Point, 4326);
        UPDATE synoptic.stations
        SET geog = ST_SetSRID(ST_MakePoint(longitude::float8, latitude::float8), 4326)::GEOGRAPHY,
            geom = ST_SetSRID(ST_MakePoint(longitude::float8, latitude::float8), 4326);
        CREATE INDEX IF NOT EXISTS idx_stations_geog_gist ON synoptic.stations USING GIST (geog);
        CREATE INDEX IF NOT EXISTS idx_stations_geom_gist ON synoptic.stations USING GIST (geom);
        RAISE NOTICE 'PostGIS enabled and synoptic.stations.geog + geom populated!';
    ELSE
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geometry') THEN
            CREATE DOMAIN public.geometry AS point;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geography') THEN
            CREATE DOMAIN public.geography AS point;
        END IF;
        EXECUTE $fn$
            CREATE OR REPLACE FUNCTION public.ST_MakePoint(lon double precision, lat double precision) RETURNS point AS $body$
                SELECT point(lon, lat);
            $body$ LANGUAGE sql IMMUTABLE;
            CREATE OR REPLACE FUNCTION public.ST_SetSRID(pt point, srid int) RETURNS point AS $body$
                SELECT pt;
            $body$ LANGUAGE sql IMMUTABLE;
            CREATE OR REPLACE FUNCTION public.ST_Distance(p1 point, p2 point) RETURNS double precision AS $body$
                SELECT 2.0 * 6371008.8 * asin(sqrt(
                    power(sin(radians((p2[1] - p1[1]) / 2.0)), 2) +
                    cos(radians(p1[1])) * cos(radians(p2[1])) * power(sin(radians((p2[0] - p1[0]) / 2.0)), 2)
                ));
            $body$ LANGUAGE sql IMMUTABLE;
            CREATE OR REPLACE FUNCTION public.ST_DWithin(p1 point, p2 point, dist_m double precision) RETURNS boolean AS $body$
                SELECT public.ST_Distance(p1, p2) <= dist_m;
            $body$ LANGUAGE sql IMMUTABLE;
        $fn$;
        ALTER TABLE synoptic.stations ADD COLUMN IF NOT EXISTS geog public.geography;
        ALTER TABLE synoptic.stations ADD COLUMN IF NOT EXISTS geom public.geometry;
        UPDATE synoptic.stations
        SET geog = public.ST_SetSRID(public.ST_MakePoint(longitude::float8, latitude::float8), 4326),
            geom = public.ST_SetSRID(public.ST_MakePoint(longitude::float8, latitude::float8), 4326);
        CREATE INDEX IF NOT EXISTS idx_stations_geog_gist ON synoptic.stations USING GIST (geog);
        CREATE INDEX IF NOT EXISTS idx_stations_geom_gist ON synoptic.stations USING GIST (geom);
        RAISE NOTICE 'WGS-84 geodesic fallback enabled and synoptic.stations.geog + geom populated!';
    END IF;
END
$$;

VACUUM ANALYZE;
