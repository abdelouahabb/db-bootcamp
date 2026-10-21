-- ============================================================================
-- DAY 3 BOOTCAMP: 5,000,000-ROW PARTITIONED TELEMETRY SEED, B-TREE VS BRIN
-- BENCHMARK & POSTGIS GEODESIC PROXIMITY QUERIES
-- File: day3_postgis_5m_benchmark.sql
-- Usage: psql -d postgres -f day3_postgis_5m_benchmark.sql
--    or: psql -U postgres -f day3_postgis_5m_benchmark.sql
-- ============================================================================

-- Create dedicated benchmark database if running standalone (or run inside existing DB)
SELECT 'CREATE DATABASE weather_ops_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'weather_ops_db')\gexec

\c weather_ops_db

SET timezone = 'UTC';
SET datestyle = 'iso, ymd';

-- ============================================================================
-- 1. ENABLE POSTGIS SPATIAL EXTENSION (OR WGS-84 GEODESIC SHIM IF BARE HOST)
-- ============================================================================
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'postgis') THEN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geometry' AND typtype = 'd') THEN
            DROP DOMAIN geometry CASCADE;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geography' AND typtype = 'd') THEN
            DROP DOMAIN geography CASCADE;
        END IF;
        CREATE EXTENSION IF NOT EXISTS postgis;
        RAISE NOTICE 'Native PostGIS extension enabled!';
    ELSE
        RAISE NOTICE 'PostGIS OS package not installed on host — enabling built-in WGS-84 Haversine geodesic fallback so all 5M-row Partitioning, BRIN, and Proximity queries execute cleanly!';
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geometry') THEN
            CREATE DOMAIN geometry AS point;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'geography') THEN
            CREATE DOMAIN geography AS point;
        END IF;
        EXECUTE $fn$
            CREATE OR REPLACE FUNCTION postgis_full_version() RETURNS text AS $body$
                SELECT 'WGS-84 Geodesic Fallback Mode (Use Docker postgis/postgis:16-3.4 for native GEOS/PROJ PostGIS)'::text;
            $body$ LANGUAGE sql IMMUTABLE;

            CREATE OR REPLACE FUNCTION ST_MakePoint(lon double precision, lat double precision) RETURNS point AS $body$
                SELECT point(lon, lat);
            $body$ LANGUAGE sql IMMUTABLE;

            CREATE OR REPLACE FUNCTION ST_SetSRID(pt point, srid int) RETURNS point AS $body$
                SELECT pt;
            $body$ LANGUAGE sql IMMUTABLE;

            CREATE OR REPLACE FUNCTION ST_Distance(p1 point, p2 point) RETURNS double precision AS $body$
                SELECT 2.0 * 6371008.8 * asin(sqrt(
                    power(sin(radians((p2[1] - p1[1]) / 2.0)), 2) +
                    cos(radians(p1[1])) * cos(radians(p2[1])) * power(sin(radians((p2[0] - p1[0]) / 2.0)), 2)
                ));
            $body$ LANGUAGE sql IMMUTABLE;

            CREATE OR REPLACE FUNCTION ST_DWithin(p1 point, p2 point, dist_m double precision) RETURNS boolean AS $body$
                SELECT ST_Distance(p1, p2) <= dist_m;
            $body$ LANGUAGE sql IMMUTABLE;
        $fn$;
    END IF;
END
$$;

-- Explicit verification of PostGIS spatial engine (or geodesic fallback)
SELECT postgis_full_version();

-- ============================================================================
-- 2. CREATE SPATIAL WEATHER STATIONS MASTER REGISTRY TABLE
-- ============================================================================
DROP TABLE IF EXISTS stations CASCADE;
CREATE TABLE stations (
    station_id   VARCHAR(10) PRIMARY KEY,
    station_name VARCHAR(64) NOT NULL,
    latitude     DOUBLE PRECISION NOT NULL,
    longitude    DOUBLE PRECISION NOT NULL,
    elevation_m  REAL NOT NULL,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        ALTER TABLE stations ADD COLUMN geom GEOMETRY(Point, 4326);
    ELSE
        ALTER TABLE stations ADD COLUMN geom geometry;
    END IF;
END
$$;

-- Fix PRNG seed so all 50 station coordinates are 100% deterministic across machines
SELECT setseed(0.42);

-- Seed 50 Meteorological Stations across Northern Algeria
INSERT INTO stations (station_id, station_name, latitude, longitude, elevation_m, is_active)
SELECT 
    'AWS-' || LPAD(g::TEXT, 3, '0'),
    CASE g
        WHEN 1 THEN 'Algiers Port Marine'
        WHEN 2 THEN 'Boumerdes Coastal Point'
        WHEN 3 THEN 'Dellys Cape Lighthouse'
        WHEN 4 THEN 'Tizi Ouzou Valley'
        WHEN 5 THEN 'Bejaia Gulf Airport'
        WHEN 6 THEN 'Jijel Achouat Ridge'
        WHEN 7 THEN 'Oran Marine Terminal'
        WHEN 8 THEN 'Constantine Plateau'
        ELSE 'AWS Regional Station ' || LPAD(g::TEXT, 3, '0')
    END,
    ROUND((35.5 + (random() * 2.0))::numeric, 4),
    ROUND((2.0 + (random() * 5.0))::numeric, 4),
    ROUND((10.0 + (random() * 1200.0))::numeric, 1),
    TRUE
FROM generate_series(1, 50) AS g;

-- Pin precise ground-truth coordinates & elevations for all 8 named Algerian stations
UPDATE stations SET latitude = 36.7538, longitude =  3.0588, elevation_m =  12.0 WHERE station_id = 'AWS-001'; -- Algiers Port
UPDATE stations SET latitude = 36.7664, longitude =  3.4772, elevation_m =  18.0 WHERE station_id = 'AWS-002'; -- Boumerdes Coastal
UPDATE stations SET latitude = 36.9172, longitude =  3.9130, elevation_m =  85.0 WHERE station_id = 'AWS-003'; -- Dellys Cape
UPDATE stations SET latitude = 36.7118, longitude =  4.0459, elevation_m = 189.0 WHERE station_id = 'AWS-004'; -- Tizi Ouzou
UPDATE stations SET latitude = 36.7559, longitude =  5.0699, elevation_m =   6.0 WHERE station_id = 'AWS-005'; -- Bejaia Airport
UPDATE stations SET latitude = 36.7950, longitude =  5.8736, elevation_m =  11.0 WHERE station_id = 'AWS-006'; -- Jijel Achouat
UPDATE stations SET latitude = 35.6971, longitude = -0.6308, elevation_m =  22.0 WHERE station_id = 'AWS-007'; -- Oran Marine
UPDATE stations SET latitude = 36.2760, longitude =  6.6200, elevation_m = 694.0 WHERE station_id = 'AWS-008'; -- Constantine Plateau

-- Construct WGS-84 spatial point geometry (X = longitude, Y = latitude) from exact station coordinates
UPDATE stations
SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326);

-- Create Spatial Index on Station Geometries (GiST: Generalized Search Tree)
CREATE INDEX idx_stations_gist_geom ON stations USING GIST (geom);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        CREATE INDEX idx_stations_gist_geog ON stations USING GIST ((geom::geography));
    END IF;
END
$$;

-- ============================================================================
-- 3. CREATE DECLARATIVE PARTITIONED MASTER TABLE (ALIGNED COLUMNS)
-- ============================================================================
DROP TABLE IF EXISTS raw_telemetry_partitioned CASCADE;
CREATE TABLE raw_telemetry_partitioned (
    -- 8-Byte Types First (Offset 0-8)
    recorded_at    TIMESTAMPTZ NOT NULL,
    -- 4-Byte / Variable Types Second (Offset 8-28)
    station_id     VARCHAR(10) NOT NULL,
    temperature    REAL,
    pressure       REAL,
    wind_speed     REAL,
    rain_accum_1m  REAL,
    -- 2-Byte Types
    wind_direction SMALLINT,
    CONSTRAINT fk_station FOREIGN KEY (station_id) REFERENCES stations(station_id)
) PARTITION BY RANGE (recorded_at);

-- ============================================================================
-- 4. CREATE EXPLICIT MONTHLY CHILD PARTITIONS
-- ============================================================================
CREATE TABLE telemetry_y2026m09 PARTITION OF raw_telemetry_partitioned
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE telemetry_y2026m10 PARTITION OF raw_telemetry_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');

CREATE TABLE telemetry_y2026m11 PARTITION OF raw_telemetry_partitioned
    FOR VALUES FROM ('2026-11-01 00:00:00+00') TO ('2026-12-01 00:00:00+00');

CREATE TABLE telemetry_y2026m12 PARTITION OF raw_telemetry_partitioned
    FOR VALUES FROM ('2026-12-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

CREATE TABLE telemetry_default PARTITION OF raw_telemetry_partitioned DEFAULT;

-- ============================================================================
-- 5. INGEST 5,000,000 SYNTHETIC OBSERVATIONS ACROSS SEPT-DEC 2026
-- ============================================================================
SELECT setseed(0.42);

INSERT INTO raw_telemetry_partitioned (
    recorded_at, station_id, temperature, pressure, wind_speed, wind_direction, rain_accum_1m
)
SELECT 
    TIMESTAMP WITH TIME ZONE '2026-09-01 00:00:00+00' + (g * INTERVAL '2.1 seconds'),
    'AWS-' || LPAD((1 + (random() * 49)::INT)::TEXT, 3, '0'),
    ROUND((14.0 + (sin(g / 5000.0) * 12.0) + (random() * 3.0))::numeric, 2)::REAL,
    ROUND((1013.25 + (cos(g / 8000.0) * 8.0) + (random() * 1.5))::numeric, 2)::REAL,
    ROUND((random() * 22.0)::numeric, 2)::REAL,
    (random() * 359)::SMALLINT,
    CASE WHEN random() < 0.05 THEN ROUND((random() * 4.5)::numeric, 2)::REAL ELSE 0.0 END
FROM generate_series(1, 5000000) AS g;

-- ============================================================================
-- 6. ATTACH BRIN INDEX TO MASTER PARTITIONED TABLE (PROPAGATES TO CHILDREN)
-- ============================================================================
CREATE INDEX idx_telemetry_brin_time 
    ON raw_telemetry_partitioned 
    USING BRIN (recorded_at) 
    WITH (pages_per_range = 64);

ANALYZE stations;
ANALYZE raw_telemetry_partitioned;

-- ============================================================================
-- 7. VERIFY PARTITION ROW DISTRIBUTION & PRUNING
-- ============================================================================
SELECT 
    c.relname AS partition_name,
    pg_size_pretty(pg_relation_size(c.oid)) AS heap_size,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
    c.reltuples::BIGINT AS estimated_rows
FROM pg_class c
JOIN pg_inherits i ON i.inhrelid = c.oid
JOIN pg_class parent ON parent.oid = i.inhparent
WHERE parent.relname = 'raw_telemetry_partitioned'
ORDER BY c.relname;

EXPLAIN (COSTS OFF)
SELECT 
    station_id, 
    ROUND(AVG(temperature)::numeric, 2) AS avg_temp,
    MAX(wind_speed) AS max_gust
FROM raw_telemetry_partitioned
WHERE recorded_at >= '2026-10-15 00:00:00+00' 
  AND recorded_at <  '2026-10-16 00:00:00+00'
GROUP BY station_id;

-- ============================================================================
-- 8. LAB 1 BENCHMARK: B-TREE VS. BRIN ON OCTOBER PARTITION (1.27M ROWS)
-- ============================================================================
\timing on
CREATE INDEX idx_oct_btree ON telemetry_y2026m10 (recorded_at);
CREATE INDEX idx_oct_brin  ON telemetry_y2026m10 USING BRIN (recorded_at) WITH (pages_per_range = 64);
\timing off

SELECT 
    relname AS index_name,
    pg_size_pretty(pg_relation_size(c.oid)) AS index_size,
    pg_relation_size(c.oid) AS exact_bytes
FROM pg_class c
WHERE relname IN ('idx_oct_btree', 'idx_oct_brin')
ORDER BY pg_relation_size(c.oid) DESC;

-- ============================================================================
-- 9. LAB 2 BENCHMARK: POSTGIS GEODESIC PROXIMITY (ST_DWithin) & TEMPORAL JOIN
-- ============================================================================

-- 9A. Stations within 40 km of an advancing squall line offshore Dellys Cape (36.95N, 3.90E)
SELECT 
    station_id,
    station_name,
    elevation_m,
    latitude,
    longitude,
    ROUND((ST_Distance(
        geom::geography, 
        ST_SetSRID(ST_MakePoint(3.9000, 36.9500), 4326)::geography
    ) / 1000.0)::numeric, 2) AS distance_km
FROM stations
WHERE is_active = TRUE
  AND ST_DWithin(
      geom::geography, 
      ST_SetSRID(ST_MakePoint(3.9000, 36.9500), 4326)::geography, 
      40000 -- Radius in meters (40 km)
  )
ORDER BY distance_km ASC, station_id ASC;

-- 9B. Join stations within 50 km of Boumerdes (36.7664N, 3.4772E) with October 2026 telemetry
WITH nearby_stations AS (
    SELECT 
        station_id,
        station_name,
        ROUND((ST_Distance(
            geom::geography, 
            ST_SetSRID(ST_MakePoint(3.4772, 36.7664), 4326)::geography
        ) / 1000.0)::numeric, 2) AS dist_km
    FROM stations
    WHERE ST_DWithin(
        geom::geography, 
        ST_SetSRID(ST_MakePoint(3.4772, 36.7664), 4326)::geography, 
        50000 -- 50 km
    )
)
SELECT 
    ns.station_id,
    ns.station_name,
    ns.dist_km,
    ROUND(AVG(t.temperature)::numeric, 2) AS oct_mean_temp,
    MAX(t.wind_speed) AS oct_peak_gust
FROM nearby_stations ns
JOIN raw_telemetry_partitioned t 
  ON t.station_id = ns.station_id
WHERE t.recorded_at >= '2026-10-01 00:00:00+00' 
  AND t.recorded_at <  '2026-11-01 00:00:00+00'
GROUP BY ns.station_id, ns.station_name, ns.dist_km
ORDER BY ns.dist_km ASC, ns.station_id ASC;
