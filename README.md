# Multi-GPU Grass Simulation (DX12)

This repository section documents the grass simulation benchmark for single-GPU vs multi-GPU execution.

## Grass Performance Sweep (Single GPU vs Multi GPU)

The table below summarizes benchmark results collected with the automated sweep mode (`--perf-sweep`).

| Scenario | Single FPS | Multi FPS | FPS Gain | Gain % | Speedup |
|---|---:|---:|---:|---:|---:|
| baseline_mixed_lod | 49.27 | 88.82 | +39.55 | +80.27% | 1.80x |
| lod0_heavy | 44.67 | 92.75 | +48.08 | +107.63% | 2.08x |
| lod1_favoring | 43.92 | 81.08 | +37.16 | +84.61% | 1.85x |
| dense_mixed | 20.50 | 50.92 | +30.42 | +148.39% | 2.48x |
| ultra_dense_lod0_heavy | 13.25 | 32.69 | +19.44 | +146.72% | 2.47x |
| **Overall (arithmetic mean)** | **34.32** | **69.25** | **+34.93** | **+113.52%** | **2.14x** |

Across all tested scenarios, multi-GPU outperformed single-GPU, with speedups from **1.80x** to **2.48x**.

## How To Run Grass Benchmark

1. Build `MGPU-Particles` (`Debug|x64` or `Release|x64`).
2. Run: `MGPU-Particles.exe --perf-sweep`
3. Read results from: `x64/Debug/grass-perf-sweep-results.csv` (or corresponding output folder for your build config).

<img width="426" height="240" alt="GrassFieldDemoGif" src="https://github.com/user-attachments/assets/408b4aaf-7d13-4f00-9cfc-66b44cdf1a80" />
