# Architecture - Multi-GPU Grass Pipeline

This document describes the thesis-specific rendering and compute architecture. The underlying multi-GPU framework (device factory, cross-adapter fences, shared resources) comes from [Multi-GPU-Render-DX12](https://github.com/Mikhanil/Multi-GPU-Render-DX12).

## Pipeline overview

Each frame, grass goes through three stages:

1. **Wind simulation** (secondary GPU, compute queue) - optional Navier-Stokes field updates velocity/dye textures.
2. **Expand + cull** (secondary GPU, compute queue) - instance expansion from base blades, frustum culling, LOD selection, wind response sampling.
3. **Draw** (primary GPU, graphics queue) - tessellated LOD0 blades and billboard LOD1, lit with the main deferred/forward path.

Cross-adapter shared buffers carry expanded instance data from the compute adapter to the render adapter.

## CrossAdapterGrassEmitter

Central class: Common/CrossAdapterGrassEmitter.{h,cpp}.

| Responsibility | GPU | Notes |
|----------------|-----|-------|
| Wind field simulation | Secondary | WindFluidSimulator on compute queue |
| Instance expansion | Secondary | ComputeGrass.hlsl dispatch |
| Frustum / distance LOD | Secondary | Constants from main camera |
| Blade rendering | Primary | GrassDraw.hlsl, tessellation for LOD0 |

EnableShared() activates cross-adapter paths; single-GPU mode runs expand and draw on the same adapter.

## Wind simulation

WindFluidSimulator implements a classic **stable fluids** solver on a 2D grid (default 256x256):

| Pass | Shader | Purpose |
|------|--------|---------|
| Inject | WindFluidInject.hlsl | Wind origins, click impulses, obstacles |
| Advect | WindFluidAdvect.hlsl | Semi-Lagrangian advection |
| Divergence | WindFluidDivergence.hlsl | velocity divergence |
| Pressure | WindFluidPressure.hlsl | Jacobi iterations |
| Project | WindFluidProject.hlsl | Subtract pressure gradient |

## Grass LOD model

| Level | Representation | Wind response |
|-------|----------------|---------------|
| **LOD0** | Tessellated blade strips | Second-order dynamics + fluid/analytic wind |
| **LOD1** | Camera-facing billboards | Simpler displacement |

## Benchmark modes

| Flag | Behavior |
|------|----------|
| --perf-test | Single scenario, fixed duration sampling |
| --perf-sweep | Five load scenarios, writes grass-perf-sweep-results.csv |

Scenarios: aseline_mixed_lod, lod0_heavy, lod1_favoring, dense_mixed, ultra_dense_lod0_heavy.
