# Contributions map

Separates **upstream framework** from **fork-specific thesis work**.

Older git authors may appear as `матвей` / `averseble`.  
Upstream: https://github.com/Mikhanil/Multi-GPU-Render-DX12  
Third-party: [NOTICE.md](NOTICE.md) · Run notes: [README.md](README.md)

## Ownership (high level)

| Area | Scope |
|------|--------|
| Multi-GPU DX12 framework (devices, queues, cross-adapter helpers, most sample apps) | Upstream (Mikhanil / PEPEngine) |
| Grass LOD + cross-adapter expand/cull | This fork |
| Wind fluid + wind gradient tooling | This fork |
| Perf test / `--perf-sweep` CSV harness | This fork |
| `MGPU-GrassSim` demo + portfolio docs | This fork |

## Commit → feature

| Commit | Summary | Why it matters | Key paths |
|--------|---------|----------------|-----------|
| `59a5acd` | `initcom 1` | Vendor-style baseline dump (upstream + early grass) | Whole tree |
| `8f23143` | ImGui hybrid GPU adapter stats | Adapter stats while iterating | ImGui / device query |
| `9df1f4c` | Fix ImGui DX12 init | Stable DX12 debug UI | ImGui init / heaps |
| `c568f85` | Fix grass world-space rendering | Correct world-space constants | Grass emitter / draw |
| `5dedf37` | Move grass expand/cull to secondary GPU | Core multi-GPU split | `CrossAdapterGrassEmitter.*` |
| `ff7a48d` | LOD0 tessellation + ImGui controls | LOD0 + runtime knobs | `GrassDraw.hlsl`, ImGui |
| `873c3cb` | FPS limiter ImGui toggle | Fair viewing / bench | App timing |
| `8586e7c` | Separate grass LOD settings | Per-LOD tuning | LOD settings |
| `a10e27f` | Billboard size fix | LOD1 correctness | Billboard path |
| `f150908` | `performanceTestMode` | Automated benchmark / CSV | `Hybrid*App` perf modes |
| `c6e0382` / `260ac54` | Wind gradient / Navier–Stokes wind | GPU wind + research iteration | `WindFluidSimulator.*`, `WindFluid*.hlsl` |
| `ac419f1` | Object transform ImGui settings | Scene iteration tooling | ImGui scene |
| `bbe03d0` | Stability fixes | Loader/window/render hardening | Multiple paths |
| `a928359` | Portfolio README + cleanup | Docs; removed personal scripts | `README.md`, `docs/ARCHITECTURE.md` |
| `901c791` | Extract `MGPU-GrassSim` | Thesis demo vs upstream particles | `MGPU-GrassSim/*` |

Primary files and CLI flags: [README.md](README.md) §3. Sweep numbers: same file.
