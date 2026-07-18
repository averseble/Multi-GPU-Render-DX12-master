# NOTICE — Third-party code and assets

Third-party material in this repository. Fork-specific work:
[CONTRIBUTIONS.md](CONTRIBUTIONS.md). Run notes / reviewer focus: [README.md](README.md).

## Base engine / framework (upstream)

| Item | Source | Notes |
|------|--------|--------|
| Multi-GPU DX12 / PEPEngine samples | [Mikhanil/Multi-GPU-Render-DX12](https://github.com/Mikhanil/Multi-GPU-Render-DX12) | Devices, queues, descriptors, PSO helpers, cross-adapter utilities, shared-resource sample apps |
| Typical baseline trees | `Graphics/`, `Allocator/`, large parts of `Common/` (app/scene/particle core), `MGPU-Particles/`, `MGPU-IMGUI/`, `MGPU-Noise/`, `MGPU-SFR/`, `MGPU-ShadowMap/`, `MGPU-SimpleSample/`, `SingleGPU/` | Upstream unless listed in CONTRIBUTIONS.md |
| Architecture diagrams | `Readme/*.png` | From upstream docs |

## Microsoft / DirectX helpers

| File / package | Source |
|----------------|--------|
| `Utils/d3dx12.h` | Microsoft DirectX helpers |
| `Utils/d3dUtil.h` (selected math helpers) | Comments cite [DirectX-Graphics-Samples MiniEngine](https://github.com/Microsoft/DirectX-Graphics-Samples) |
| DirectXTK12 / DirectXMesh / DirectXTex | NuGet: `directxtk12_uwp`, `directxmesh_uwp`, `directxtex_uwp` |
| WinPixEventRuntime | NuGet (Microsoft PIX) |

## Other libraries

| Item | Source | Location |
|------|--------|----------|
| Dear ImGui | [ocornut/imgui](https://github.com/ocornut/imgui) | `Submodule/imgui` |
| Assimp | assimp | NuGet `assimp-v143` |

## Third-party scene assets

Folders under `MGPU-GrassSim/Data/Objects/` are third-party / educational demo
meshes and textures. Licenses in-tree are incomplete; a minimal Data pack
(grass + simple geometry) is safer for a strict submission zip.

| Folder | Examples |
|--------|----------|
| `DoomSlayer/` | doommarine mesh/textures |
| `Nanosuit/` | nanosuit mesh/textures |
| `P-Body/` | Portal-style robot assets |
| `Atlas/` | ballbot / Atlas-style assets |
| `DesertDragon/`, `Griffon/`, `GriffonOld/`, `MOUNTAIN_DRAGON/` | creature FBX/textures |
| `StoneGolem/` | golem mesh/textures |
| `Temple/` | temple / castle FBX + TGA |

Stock / demo textures under `MGPU-GrassSim/Data/Textures/` (including grass
textures used by the feature) should be treated as third-party unless noted
otherwise.
