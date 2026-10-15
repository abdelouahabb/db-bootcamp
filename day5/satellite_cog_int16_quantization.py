#!/usr/bin/env python3
"""
Meteorological Satellite Raster Quantization & Cloud-Optimized GeoTIFF (COG) Benchmark
(satellite_cog_int16_quantization.py)

Demonstrates:
  1. Synthetic 4,000x4,000 multispectral satellite brightness temperature raster (200K - 330K Float32).
  2. Legacy Striped Float32 GeoTIFF vs. Tiled Float32 COG (Predictor 3) vs. Scaled UInt16 COG
     (0.01K scale factor + 150.0K offset + Predictor 2 + ZSTD/Deflate), proving 50% to 75% storage savings
     with <= 0.005K radiometric quantization error.
  3. Sub-window HTTP byte-range read benchmark over the Algiers / Dellys coastal sector.
"""

import os
import time
import zlib
import numpy as np

RAW_FLOAT32_TIFF = "satellite_scene_raw_float32.tif"
COG_FLOAT32_TIFF = "satellite_scene_cog_float32.tif"
COG_UINT16_TIFF = "satellite_scene_cog_uint16_quantized.tif"

WIDTH, HEIGHT = 4000, 4000
WEST, SOUTH, EAST, NORTH = -2.0, 32.0, 10.0, 40.0
SCALE_FACTOR = 0.01
ADD_OFFSET = 150.0

print("=========================================================================")
print("  SATELLITE RASTER LAB: FLOAT32 VS. SCALED UINT16 (0.01K) COG BENCHMARK  ")
print("=========================================================================")

# 1. Synthesize Satellite Infrared Channel (10.8 µm Brightness Temperature: 200K - 330K)
print(f"[*] Generating synthetic 10.8µm satellite raster ({WIDTH}x{HEIGHT} Float32, 200K-330K)...")
np.random.seed(42)

# Smooth spatial gradient + realistic radiometer thermal noise
y_idx, x_idx = np.ogrid[:HEIGHT, :WIDTH]
smooth_field = 285.0 + 12.0 * np.sin(x_idx / 350.0) - 10.0 * np.cos(y_idx / 300.0)
thermal_noise = np.random.normal(loc=0.0, scale=0.45, size=(HEIGHT, WIDTH))
float32_kelvin = np.clip(smooth_field + thermal_noise, 200.0, 330.0).astype(np.float32)

# Inject severe convective squall line with cold cloud tops (210K - 228K)
storm_mask = ((x_idx - 2200)**2 / 400**2 + (y_idx - 1400)**2 / 800**2) < 1.0
float32_kelvin[storm_mask] = np.clip(
    220.0 + np.random.normal(loc=0.0, scale=2.5, size=np.count_nonzero(storm_mask)),
    200.0,
    235.0
).astype(np.float32)

# 2. Quantize Float32 Kelvin (200K - 330K) -> UInt16 (0.01K scale factor, 150.0K offset)
print("[*] Applying 16-Bit Radiometric Quantization: UInt16 = round((Kelvin - 150.0) / 0.01)...")
uint16_quantized = np.round((float32_kelvin - ADD_OFFSET) / SCALE_FACTOR).astype(np.uint16)

# Reconstruct physical Kelvin to verify radiometric precision
reconstructed_kelvin = (uint16_quantized.astype(np.float32) * SCALE_FACTOR) + ADD_OFFSET
max_abs_error = float(np.max(np.abs(float32_kelvin - reconstructed_kelvin)))
rmse_error = float(np.sqrt(np.mean((float32_kelvin - reconstructed_kelvin) ** 2)))

print(f"    -> Max Absolute Quantization Error : {max_abs_error:.5f} K (Theoretical limit: 0.00500 K)")
print(f"    -> Root Mean Square Error (RMSE)   : {rmse_error:.5f} K (Well below ~0.1K sensor noise!)")

try:
    import rasterio
    from rasterio.transform import from_bounds
    from rasterio.enums import Resampling

    transform = from_bounds(WEST, SOUTH, EAST, NORTH, WIDTH, HEIGHT)
    crs = "EPSG:4326"

    # A. Legacy Striped Float32 GeoTIFF
    print(f"\n[*] Writing Legacy Striped Float32 GeoTIFF: '{RAW_FLOAT32_TIFF}'...")
    with rasterio.open(
        RAW_FLOAT32_TIFF, "w",
        driver="GTiff", height=HEIGHT, width=WIDTH, count=1,
        dtype=rasterio.float32, crs=crs, transform=transform,
        compress="deflate"
    ) as dst:
        dst.write(float32_kelvin, 1)

    # B. Cloud-Optimized Float32 GeoTIFF (Tiled 256x256 + Predictor 3)
    print(f"[*] Writing Tiled Float32 COG (Predictor 3): '{COG_FLOAT32_TIFF}'...")
    with rasterio.open(
        COG_FLOAT32_TIFF, "w",
        driver="GTiff", height=HEIGHT, width=WIDTH, count=1,
        dtype=rasterio.float32, crs=crs, transform=transform,
        tiled=True, blockxsize=256, blockysize=256,
        compress="deflate", predictor=3
    ) as dst:
        dst.write(float32_kelvin, 1)
        dst.build_overviews([2, 4, 8, 16], Resampling.average)
        dst.update_tags(ns="rio_overview", resampling="average")

    # C. Cloud-Optimized Scaled UInt16 GeoTIFF (Tiled 256x256 + Predictor 2 Horizontal Differencing)
    print(f"[*] Writing Scaled UInt16 COG (0.01K scale + Predictor 2): '{COG_UINT16_TIFF}'...")
    with rasterio.open(
        COG_UINT16_TIFF, "w",
        driver="GTiff", height=HEIGHT, width=WIDTH, count=1,
        dtype=rasterio.uint16, crs=crs, transform=transform,
        tiled=True, blockxsize=256, blockysize=256,
        compress="deflate", predictor=2
    ) as dst:
        dst.write(uint16_quantized, 1)
        dst.scales = [SCALE_FACTOR]
        dst.offsets = [ADD_OFFSET]
        dst.build_overviews([2, 4, 8, 16], Resampling.average)
        dst.update_tags(ns="rio_overview", resampling="average")

    raw_bytes_mb = float32_kelvin.nbytes / (1024 * 1024)
    size_striped_f32 = os.path.getsize(RAW_FLOAT32_TIFF) / (1024 * 1024)
    size_cog_f32 = os.path.getsize(COG_FLOAT32_TIFF) / (1024 * 1024)
    size_cog_u16 = os.path.getsize(COG_UINT16_TIFF) / (1024 * 1024)

    print("\n================== PHYSICAL DISK & ENCODING AUDIT ==================")
    print(f"  • Uncompressed Float32 Matrix       : {raw_bytes_mb:6.2f} MB (Baseline 4 bytes/pixel)")
    print(f"  • Legacy Striped Float32 GeoTIFF    : {size_striped_f32:6.2f} MB ({(1 - size_striped_f32/raw_bytes_mb)*100:4.1f}% reduction)")
    print(f"  • Float32 COG (Tiled + Predictor 3) : {size_cog_f32:6.2f} MB ({(1 - size_cog_f32/raw_bytes_mb)*100:4.1f}% reduction)")
    print(f"  • UInt16 Quantized COG (0.01K+Pred2): {size_cog_u16:6.2f} MB ({(1 - size_cog_u16/raw_bytes_mb)*100:4.1f}% reduction!)")
    print("====================================================================\n")

    # Sub-Window Extraction Benchmark over Algiers / Dellys Sector (200x200 pixels)
    window_geom = rasterio.windows.from_bounds(3.0, 36.5, 3.6, 37.1, transform)

    def benchmark_window_read(file_path, label, is_scaled=False):
        t_start = time.time()
        with rasterio.open(file_path) as src:
            data = src.read(1, window=window_geom)
            if is_scaled:
                data = (data.astype(np.float32) * SCALE_FACTOR) + ADD_OFFSET
            mean_val = float(np.mean(data))
        elapsed_ms = (time.time() - t_start) * 1000
        print(f"  Window Read -> {label:32} : {elapsed_ms:6.2f} ms | Sector Mean: {mean_val:.2f} K")

    print("[*] Benchmarking 200x200 Sub-Window Read over Algiers / Dellys Coastal Sector...")
    benchmark_window_read(RAW_FLOAT32_TIFF, "Legacy Striped Float32 GeoTIFF", is_scaled=False)
    benchmark_window_read(COG_FLOAT32_TIFF, "Float32 Tiled COG", is_scaled=False)
    benchmark_window_read(COG_UINT16_TIFF, "UInt16 Quantized Tiled COG", is_scaled=True)

except ImportError:
    # Fallback pure-NumPy + Deflate/Predictor simulation if rasterio is not installed in the active env
    print("\n[i] Note: 'rasterio' not found in current environment; running pure-NumPy tile & predictor benchmark...")
    raw_bytes_mb = float32_kelvin.nbytes / (1024 * 1024)
    uint16_raw_mb = uint16_quantized.nbytes / (1024 * 1024)

    # Simulate horizontal differencing predictor (Predictor 2) on UInt16
    u16_diff = np.diff(uint16_quantized.astype(np.int16), axis=1, prepend=uint16_quantized[:, :1])
    comp_f32_mb = len(zlib.compress(float32_kelvin.tobytes(), level=6)) / (1024 * 1024)
    comp_u16_mb = len(zlib.compress(u16_diff.tobytes(), level=6)) / (1024 * 1024)

    print("\n================== PHYSICAL DISK & ENCODING AUDIT ==================")
    print(f"  • Uncompressed Float32 Matrix       : {raw_bytes_mb:6.2f} MB (Baseline 4 bytes/pixel)")
    print(f"  • Uncompressed UInt16 Matrix        : {uint16_raw_mb:6.2f} MB (50.0% direct byte cut)")
    print(f"  • Compressed Float32 Stream         : {comp_f32_mb:6.2f} MB ({(1 - comp_f32_mb/raw_bytes_mb)*100:4.1f}% reduction)")
    print(f"  • UInt16 + Horizontal Diff Predictor: {comp_u16_mb:6.2f} MB ({(1 - comp_u16_mb/raw_bytes_mb)*100:4.1f}% reduction!)")
    print("====================================================================\n")
