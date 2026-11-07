# Horizon iOS Memory Strategy

> **Path convention.** This repository keeps the upstream Horizon snapshot in `horizon/`. Source paths cited below (`crates/...`, `tools/...`, `docs/benchmark.md`, `research-lock.json`, `CLAUDE.md`, ...) are relative to `horizon/`. Paths under `docs/ios-evidence/` and the three `docs/IOS_*.md` files are relative to the repository root.

**Status:** analysis and plan. No code changed. No on-device measurement exists yet.
**Base:** `77af961`. Target device for first work: iPhone 12 (A14, 4 GB RAM).
**Labels:** VERIFIED (read in source or run here), INFERRED (follows from verified facts), UNRESOLVED (needs a device or a decision).

## 0. Ground rules

1. **No invented limits.** This document sets no memory cap and promises no frame rate. iOS decides how much an app may use, dynamically, and it varies with the device, OS version, other apps, and the app's entitlements. Budgets are an **output of measurement** (milestone M6), recorded per device.
2. **Targets here are relative and procedural** ("reduce X versus the M6 baseline", "stay below the headroom iOS reports") until a device gives absolute numbers.
3. **Estimates are labelled estimates.** GPU figures from wgpu or from Horizon's own accounting are not the same as the figure iOS enforces, and must never be presented as a total.
4. Measure first, change second, one variable at a time, on the same device state, with before/after in the evidence folder.

---

## 1. What iOS measures, and what Horizon measures today

### 1.1 Gap A: the process metric is wrong for iOS (VERIFIED in code, INFERRED about iOS)

| | Horizon today | What iOS cares about |
|---|---|---|
| Source | `horizon-threads/src/process_memory.rs`. On Apple: `proc_pidinfo(PROC_PIDTASKINFO).pti_resident_size` | The process's **physical footprint** (`phys_footprint` from `task_info` with `TASK_VM_INFO`), which the Xcode memory gauge reports and which jetsam decisions are based on. Also `os_proc_available_memory()` for remaining headroom |
| iOS availability | `proc_pidinfo` and `proc_taskinfo` are **absent** from the `libc` crate for iOS: compile error (blocker B4, reproduced) | `task_info` and `os_proc_available_memory` are available to apps |
| Meaning | Resident pages | Footprint includes dirty memory, compressed memory, and memory attributed to the process by graphics and IOKit/IOSurface. **The exact accounting formula is not something I verified**; confirm on device |

`docs/benchmark.md:13` documents the same limit on desktop: "On Apple Silicon the GPU shares RAM and no per-process figure is available." Horizon's benchmark compares **RSS**. On iOS, RSS cannot be the success metric.

**Action (M2):** add an iOS implementation reporting `phys_footprint` and `os_proc_available_memory`. Keep RSS where available as a secondary column. Validate by allocating a known amount (for example 200 MiB of touched pages and a 200 MiB GPU buffer), observing both counters move, then freeing.

### 1.2 Gap B: no GPU-by-label on Metal (VERIFIED)

`Renderer::gpu_memory_by_label` (`gfx.rs:2477`) returns data only where wgpu exposes an allocator report: "Vulkan and DirectX 12; none on Metal and OpenGL". On iOS the call will return `None`.

**Mitigation that already exists:** `Renderer::gpu_census()` (`gfx.rs:2441-2476`) reports Horizon's own accounting of its biggest GPU resources, independent of backend:

`section_arena_pages`, `translucent_arena_pages`, `sorted_index_pages`, `near_section_vertices`, `far_tile_vertices`, `quad_indices`, `block_sprites`, `pbr_maps`, `flat_draws`, `visibility_buffer`.

Two accessors also exist: `section_vertex_bytes()` (arena capacity versus bytes in use) and `cpu_census()` (renderer bookkeeping heaps). `horizon-ctl memory` (`game/memory.rs`) assembles these, plus allocator commit/peak and client/server column counts.

**Gaps in that census (INFERRED from the list):** it does not appear to include the depth buffer, swapchain images, post-process/HDR targets, the GUI atlas, entity/skin textures, or shadow/OIT targets. These must be added or measured with Instruments, or iOS footprint will exceed the sum of the census. The difference is the "unexplained" bucket, and shrinking it is part of M2/M7.

**Independent cross-check on device:** Xcode's Memory Graph and Instruments' *Allocations*, *VM Tracker*, and *Metal System Trace / Metal Resource* tools. Use these to audit the census rather than trusting either alone.

---

## 2. Inventory of memory consumers in the engine

Everything below was read in source this session. Sizes are **limits and structures**, not measurements.

### 2.1 Chunk and world data (CPU)

| Item | Where | Finding |
|---|---|---|
| Representation | `chunk.rs:556` `Chunk { sections: Vec<Arc<Section>>, surface/motion_blocking: OnceLock<Box<[i16;256]>>, ... }` | Palette-compressed (`horizon_core::paletted::PalettedContainer`); sections are `Arc` with copy-on-write for the worker snapshots (VERIFIED). A full overworld column is 24 sections (-64..320) |
| Per-chunk extras | `block_entities`, `block_names`, post-processing marks, `lit` flags | Grow with content |
| Residency policy | `streaming.rs` (4,510 lines); radius from `render_distance` (default 12, max 128: `options_file.rs:92,165`) | Chunk count grows roughly with the square of the radius. On a phone the default and cap need to be far lower. The right numbers come from M6 |
| Eviction | Chunks leave when out of range (`gone`, `streaming.rs:1254`) | Behaviour under fast movement and teleports was not tested |
| Server-side copies | `server_terrain.rs`, `integrated.rs`, `memory.rs` reports `server_columns` and `shared_with_server` | **Singleplayer runs an integrated server thread with its own columns.** Client and server share some sections (`shared_with_server`) but not all. The duplication ratio is UNRESOLVED and a prime target to measure |
| LAN host state | `lan/hub*.rs` | Present in the same process if hosting. Disable on iOS builds unless wanted |

### 2.2 Meshing and streaming queues

| Item | Where | Finding |
|---|---|---|
| Worker pool | `horizon-threads/jobs.rs`, `streaming.rs` | `HORIZON_WORKER_THREADS` caps; `default_workers()` = (min(cores, perf cores)) - 1, at least 1 |
| In-flight bounds | `streaming.rs:1816-2117` | Generation `workers*3`; decoration `workers*2`; lighting `workers*4`; meshing `workers*32`. Bounded and proportional to workers (VERIFIED). Good: no unbounded queue found in this path |
| Mesh buffer reuse | `streaming.rs:346-366` | Pool of reusable mesh buffers, **16 MiB / 128 entries** (`BYTES`, `COUNT`), "workers use this pool; frames never wait for its lock"; `IDLE_RELEASE` 5 s drops retained capacity (`streaming.rs:26,905`) |
| Section copy limit, compaction | `gfx.rs:821,826` | `SECTION_COPY_LIMIT` 64 MiB, `COMPACT_BUDGET` 32 MiB: per-frame work budgets, not residency |
| Light | `light.rs` | Queue capacity cap 65,536 (`MAX_QUEUE_CAPACITY`) |
| Test coverage | `streaming.rs` tests: `bounded_submission_takes_the_nearest_first`, `mesh_pool_reuses_capacity_with_clean_geometry_state` | Behaviour is pinned by tests |

**Reading:** the CPU-side streaming is already designed with back-pressure and reuse. Tuning is a matter of scale factors, not redesign. The unmeasured risk is **peak** memory when a burst of jobs completes together.

### 2.3 GPU geometry (the arena)

| Item | Where | Finding |
|---|---|---|
| Design | `gfx/arena.rs`: one vertex buffer for all terrain sections, in pages; sections own ranges; indirect multi-draw | Efficient for draw calls; memory is held as large pages |
| Page size | `PAGE_BYTES = 256 MiB` (`arena.rs:14`), `LARGE_PAGE_BYTES` about 2 GiB (`:18`), both clamped to the device's `max_buffer_size` (and storage-binding size for storage arenas) in `with_usage` (`:175-199`) | A **ceiling per page, not a fixed allocation** (VERIFIED: pages grow and shrink) |
| Initial size | The section arena is created with `capacity = 1 << 20` vertices (`gfx.rs:4495-4500`); at the 24-byte `TerrainVertex` stride that is exactly 24 MiB (stride derived from `mesher.rs:69-81`: `pos` 3xf32 = 12 B, `uv` 2xu16 = 4 B, `layer` u16 = 2 B, `light` u16 = 2 B, `color` u32 = 4 B) | VERIFIED capacity; so the 256 MiB figure is **only the ceiling of a page, not the starting allocation** |
| Growth | `grown(current, len)` is "twice theirs, or `PAGE_BYTES` more; at least the first page's" (`arena.rs:418-423`, `:523`) | **Doubling growth can overshoot** on a 4 GB device: a page that has outgrown ~100 MiB of use may be sized toward 256 MiB. How it actually behaves under a real traversal is UNRESOLVED |
| Shrink and compact | `oversized()` (`:427`), `sparsest()`, `COMPACT_MIN_FREE` 128 MiB, `SHRINK_MIN_BYTES` 64 MiB | Existing machinery returns memory when pages are mostly empty. The thresholds are desktop-scaled: a page must be at least 64 MiB to shrink, and 128 MiB free to compact. **On a phone these thresholds may never trigger** |
| Spill | `create(..., spill)` falls back to system memory with `MAPPABLE_PRIMARY_BUFFERS` when video memory is full | On iOS GPU and CPU memory are the same unified pool, so "spilling" does not free anything and the "video memory full" signal may never fire; **iOS will jetsam instead**. INFERRED |
| Vertex format | `TerrainVertex` is `repr(C)`, 24 bytes (`mesher.rs:69-81`), already quantised: 16-bit UVs, 16-bit fixed-point light, packed RGBA8 colour | VERIFIED. Only the 3xf32 position (12 of 24 bytes) is uncompressed. Packing it to 16-bit section-relative fixed point could save up to a third, but that touches the mesher, WGSL shaders and every consumer; a speculative gain until the arena is shown to dominate footprint |

**Strategy:** first obtain the real arena size curve from M6 (bytes versus render distance). Then pick a mobile page size and growth step, and lower the shrink/compact thresholds proportionally. The code paths exist; only constants and a platform profile are needed. Do not replace the arena.

### 2.4 Textures and atlases

| Item | Where | Finding |
|---|---|---|
| Block sprites | `gfx.rs` `sprite_textures`, texture arrays with layer splitting | `check_layers` / `layer_split` already adapt to `max_texture_array_layers`; Android reports reducing atlas sprites when it does not fit. Mip chain memory was not computed |
| Mips | `docs/animated-sprite-mips-benchmark.md`, `tools/bench_sprite_mips.rs` | Mip generation has been benchmarked upstream for time; memory trade-off per resolution pack is UNRESOLVED |
| Metal-specific terrain path | `gfx.rs:4492-4494`: `mesher::group_parts(backend == Metal)`; comment: "Metal draws solid terrain in two passes (`split_solid`)" | VERIFIED. Horizon's Metal path is already exercised on macOS and special-cased, which is a point in favour of the renderer on iOS; it is also a second code path whose memory behaviour should be compared with Vulkan's |
| GUI atlas | `hud.rs` | Pixels are kept **LZ4-compressed after upload** (`lz4_flex`, `pack_pixels`): an existing memory optimisation (VERIFIED) |
| Depth | `Depth32Float` is used 54 times across the render crate | Full-screen `Depth32Float` at the phone's native resolution is a fixed cost. Consider rendering scale as a mobile setting. Cost figure needs calculation per resolution |
| Render targets | `Rgba16Float` (12 uses), `Rgba32Uint` (8), etc. | Mostly shader-pack / post-processing paths. Disable shader packs on iOS |
| Entity/skin/pack textures | `hud.rs`, `models/`, `cit_*` | Each has local caps (`MAX_FETCHED_PIXELS` 4096x4096 in `hud.rs:187`; `custom_sky` `TEXEL_BUDGET` 64 MiB; `cit_glint` `MAX_BYTES` 64 MiB). Resource packs are user-supplied and can be large |
| Decode copies | `png`, `zune-jpeg`, `image-webp` | Whether decoded source images are retained after upload is UNRESOLVED; audit `hud.rs`/`pack_*.rs` |

### 2.5 Audio

`audio.rs:151` `CACHE_BYTES = 64 MiB` LRU of **decoded** f32 samples; the comment says it was previously unbounded ("up to 1.4 GiB of samples"). Sounds on disk are about 380 MB (OGG). Decoding to f32 inflates considerably. 64 MiB is likely high for a 4 GB device; make it a mobile setting and drop it on a memory warning. VERIFIED structure, value to tune.

### 2.6 Features with large optional footprints (disable on iOS)

| Feature | Bound found | Plan |
|---|---|---|
| `bluemap.rs` far terrain from a web map | `MAX_TILE_BYTES` 192 MiB, `MAX_TILES` 2048, `MAX_CHUNKS` 4096 | Compile out or default off |
| `lod.rs` far tiles ("Distant Horizons"-style) | `MAX_SAVED` 1024, `MAX_REFRESHED` 64 | Default off until measured; it may be a good memory/quality trade at low render distances, so evaluate rather than assume |
| Shader packs (OptiFine GLSL via naga, `.hshader`) | Many large RGBA16F/32F targets | Default off; compile out if the binary size matters |
| Particles | `MAX_PARTICLES` 16,384 | Lower on mobile |
| Dynamic lights | `dynamic_light::MAX` 16 | Fine |
| Telemetry, Discord, friends tunnel | Small | Remove for store builds (policy, not memory) |

### 2.7 Persistence

- Worlds are vanilla Anvil region files. Chunks are read and written incrementally, not whole-world (VERIFIED by structure: `horizon-world` regions, `generation_saves.rs` test). Full load/save buffer bounds were not traced; `LevelStorageAccess.estimateDiskSpace` exists via `fs4`.
- `docs/save-batch-entities.md` and `scheduled-ticks.md` exist and indicate save batching work; not read in depth.
- Atomicity on suspension: the lifecycle section of the roadmap (M4) requires verifying that a kill during a save cannot corrupt a region. **UNRESOLVED.**

### 2.8 Allocator and fragmentation

| Fact | Source |
|---|---|
| Global allocator is **mimalloc** (`horizon-threads::Allocator`), `#[global_allocator]` in `horizon-client/src/main.rs` unless `system-allocator` or `alloc-census` | VERIFIED |
| `configure_allocator()` sets `mi_option_purge_delay = 0` so free pages return at once; documented: with the default delay "the game held a quarter more memory than with the system heap; without it a few percent, and generation keeps most of its speed-up" | VERIFIED comment (`lib.rs:357-372`); measured on desktop |
| `release_free_memory()` runs `mi_collect(true)` and a platform release (`malloc_trim` on glibc, zone pressure relief on macOS) | VERIFIED (`:408-420`) |
| `allocator_commit()` reads `mi_process_info` (commit and peak commit) | VERIFIED |
| `system-allocator` removes the global allocator but **`horizon-threads` still links `libmimalloc-sys` and calls it** | VERIFIED. It is not a true opt-out, which matters for A/B tests |
| `alloc-census` feature adds a 16-byte tag per block and reports live heap by startup step, span, job and thread (`horizon-ctl memory`, `heap_by_tag_mb`) | VERIFIED. **A ready-made heap profiler** |

`release()` has a `target_vendor = "apple"` arm that calls `malloc_zone_pressure_relief(NULL, 0)` (`lib.rs:426-436`), so it is selected for iOS too. It is a private-ish libc symbol declared by hand; whether it exists and does anything for an iOS app is UNRESOLVED (a missing symbol would be a link error, which M1 will reveal). `malloc_trim` is glibc-only and not relevant.

### 2.9 Threads

| Fact | Source |
|---|---|
| `worker_count()` = `available_parallelism`, overridable by `HORIZON_WORKER_THREADS` | `horizon-threads/lib.rs:16-30` |
| `default_workers()` counts only Apple performance cores via `sysctlbyname("hw.perflevel0.physicalcpu")` | `lib.rs:48-75`, motivated by a measured p99 improvement on an M4 (#11294) |
| Other pools: far decoration a third; `hud.rs:480,1272` image decode threads; `lan/io_pool.rs`; `pack_post.rs` | various |
| Thread stacks | Not audited. Rust default for spawned threads is 2 MiB; iOS secondary-thread default for pthreads is 512 KB. `build.rs` sets an 8 MB main stack **only on Windows** | UNRESOLVED |

### 2.10 Interplay: unified memory on iPhone

On iOS the CPU heap, GPU buffers and textures draw from one physical pool, and the app is killed when its footprint passes a per-device threshold. Consequences for this engine:
1. A "streamed to GPU then dropped on CPU" design wins; a "kept on both sides" design costs double. Check whether per-section mesh data is retained on the CPU after upload (`resident_sections` in `cpu_census` suggests bookkeeping only, but the vertex data retention was not traced). UNRESOLVED.
2. Doubling growth in the arena and large mappable buffers translate directly into footprint.
3. `IDLE_RELEASE` (5 s, `streaming.rs:26`) is how long a streaming worker idles before it returns its **generator scratch buffers** (`ChunkGenerator::idle`); it is separate from the mesh pool, which only caps retained capacity (16 MiB / 128 meshes). Both are desktop-scaled; shorter release on mobile is cheap to try.

---

## 3. Measurement plan for a physical iPhone

### 3.1 Instruments and tools (to run on device, not simulator)

| Question | Tool |
|---|---|
| Total footprint over time, leaks, abandoned memory | Xcode Debug Navigator memory gauge; Instruments *Allocations* and *Leaks* |
| Dirty/swapped/compressed breakdown, IOSurface/graphics attribution | Instruments *VM Tracker* |
| Metal buffer and texture sizes by object | Xcode GPU Frame Capture and *Metal System Trace*, plus the Metal debugger's resource view |
| GPU time, bandwidth, occupancy | Metal System Trace, GPU counters |
| CPU hot spots | Instruments *Time Profiler* |
| Thermal and energy | Instruments *Energy Log*, `ProcessInfo.thermalState`, *Thermal State* track |
| Jetsam events | Device logs (`JetsamEvent-*.ips`) under Settings > Privacy & Security > Analytics Data; MetricKit `MXMemoryMetric` and `MXAppExitMetric` |
| Allocator tags | Horizon's `alloc-census` build plus `horizon-ctl memory` (control socket; over USB it needs forwarding or a shell command channel, UNRESOLVED) |
| Frame times | Horizon's own `FramerateLimiter`/timing spans (`spans.rs`, `gfx/timing.rs` using `TIMESTAMP_QUERY` where Metal exposes it) |

### 3.2 Telemetry to add or adapt (from the brief, mapped to code)

| Required signal | Existing hook | Needed |
|---|---|---|
| Physical footprint over time | none | New: `task_info` on iOS (M2) |
| Headroom | none | New: `os_proc_available_memory()` |
| Peak during startup, join, explore, teleport, shutdown | `benchmark.rs` metrics, `startup::step` spans | Extend report with phase markers |
| Heap stats | `allocator_commit`, `alloc-census` | Reuse |
| GPU bytes by category | `gpu_census()` | Extend (depth, targets, atlas, entity textures) |
| Chunk counts: loaded, visible, meshing, queued, evicted | `streaming` internals, `cpu_census` | Expose counters (queue lengths are known inside `streaming.rs`) |
| Texture and mesh cache sizes | mesh pool `bytes`, audio `bytes`, per-feature caps | Surface them in one structure |
| Worker and queue depths | `jobs.rs`, `streaming.rs` | Expose |
| Frame-time percentiles | `horizon-bench` | Reuse |
| Thermal state, battery, low-power mode | none | New, from Swift via the bridge |

All new telemetry is local and written to the on-device report; no upload. Any upload would be a policy decision (feasibility report section 11).

### 3.3 Scenarios (reusing `--benchmark`)

Cold launch; warm launch; resource load to title screen; new world to first frame; scripted traversal at render distances (for example 4, 6, 8, 10, 12; values chosen after the first run); teleport across 10,000 blocks; rapid look-around; entity-heavy village; particle-heavy fire/explosions; inventory/crafting UI; save then reload; background/foreground cycle; memory-warning response; 20-30 minute sustained session. Each records the metadata listed in the roadmap (device, iOS version, commit, seed, settings, thermal start state, battery, plugged in or not).

### 3.4 Method for comparing runs

- Fixed seed, fixed route (benchmark scenes are scripted flights), fixed settings, fixed device temperature at start (record `thermalState` and wait to nominal), airplane mode, brightness fixed, other apps closed, device restarted before each series.
- Three repeats minimum; report each, plus min/median/max. Do not average away a jetsam.
- A jetsam event is recorded as a failed run, with the footprint trajectory leading to it.

---

## 4. Optimization targets (relative, to be confirmed by M6)

Because absolute limits are unknown, targets are expressed against the first device baseline. Each target names the metric and the instrument that proves it.

| ID | Target | Metric | Proof |
|---|---|---|---|
| T1 | **No jetsam termination** in the 30 min sustained scenario and the memory-pressure scenario at the shipped default settings | Jetsam events = 0 across 3 runs | Device logs, MetricKit |
| T2 | **Stay under a footprint ceiling derived from observed headroom**: record `os_proc_available_memory()` at steady state; define the shipped default so steady-state leaves a margin (the margin size to be chosen after seeing run-to-run variance) | Steady-state and peak footprint | In-app log, Xcode gauge |
| T3 | **Startup peak below steady-state peak plus a small tolerance**, i.e. loading resources must not be the highest point of the session | Peak footprint during load vs session | Phase-marked trace |
| T4 | **Footprint returns toward baseline after a simulated memory warning** and after leaving the world | Footprint delta after trim | In-app log |
| T5 | **p99 frame time does not regress** when any memory optimisation is applied, versus the M6 baseline at equal settings | p50/p95/p99 | `horizon-bench` |
| T6 | **Unexplained footprint** (footprint minus CPU heap minus census GPU bytes) is small and stable | Difference over time | Combined report |
| T7 | **Chunk working set is bounded**: loaded-chunk count tracks the radius formula with no monotonic growth over a long traversal | Chunk counts vs time | Counters |
| T8 | **Thermal**: sustained play does not drive `thermalState` to serious/critical at default settings; if it does, the adaptive controller lowers load | Thermal log | Energy/thermal tracks |

No numeric values are proposed until M6 produces data.

---

## 5. Optimization candidates, ranked by expected value and risk

Ranking is a hypothesis to be re-ordered by M6. Nothing here should be implemented without a baseline.

### Tier 1: policy and configuration (low risk, high likely value)

1. **Mobile settings profile**, selected at runtime by platform: render distance default and cap, simulation distance, worker count, queue multipliers, particle cap, entity distance, mip policy, render scale, shader packs/bluemap/LOD off. All of these already exist as options or constants (`options_file.rs`, `graphics.rs`, `streaming.rs`, `particles.rs`). Mostly data, little code.
2. **Memory-warning handler** (M4): drop mesh pool, audio cache, non-visible meshes; `release_free_memory()`; shrink arena. Uses existing functions.
3. **Lower `IDLE_RELEASE` (generator scratch release), audio `CACHE_BYTES`, mesh pool limits** on mobile.
4. **Arena constants for mobile**: page size, growth step, shrink/compact thresholds (`PAGE_BYTES`, `grown`, `SHRINK_MIN_BYTES`, `COMPACT_MIN_FREE`). Requires the M6 size curve. The mechanism exists.

### Tier 2: measurement-driven structural changes (medium risk)

5. **Adaptive load control** from `os_proc_available_memory()` and `thermalState`: reduce render distance or workers when headroom is low or thermals rise. New code, small, additive.
6. **Integrated-server duplication**: measure `server_columns` vs `client_columns` vs `shared_with_server`. If duplication is large, reduce the server's simulation distance below the client's view, or share more sections. Touches simulation-adjacent code: parity-sensitive, so go slowly.
7. **Depth/target sizing**: render scale option for the 3D view with GUI at native resolution. Affects visuals.
8. **Allocator experiment**: mimalloc (with `purge_delay` 0, and variants) versus the system allocator, on device, with `alloc-census`. Requires first making `system-allocator` a real opt-out of the mimalloc calls in `horizon-threads` (small refactor).

### Tier 3: format and architecture changes (higher risk, only if data demands)

9. **Narrower terrain position** (the vertex is already 24 bytes with quantised UV, light and colour; only `pos: [f32; 3]` is full width) and index width. Touches mesher, WGSL and every vertex consumer, with parity and visual-comparison cost. Only if arena bytes dominate the footprint after Tier 1-2.
10. **Texture compression** (ASTC on Apple GPUs) for block sprites. Would change the resource pipeline and affects visual fidelity of a pixel-art game, where compression artifacts are noticeable. Treat as research.
11. **Streaming section meshes from disk cache** to cut regeneration cost. Uncertain win versus complexity.
12. **Unified-memory-aware upload path** (avoid CPU staging copies). Depends on wgpu's Metal behaviour; needs profiling first.

### Rejected or deferred

- **Replacing the arena with per-chunk buffers**: would raise draw-call and allocation overhead and discard working compaction logic. No evidence it helps.
- **Arbitrary global memory caps**: iOS does not give a fixed budget; capping blindly either wastes headroom or still gets killed.
- **Allocating a large "reserve" up front**: contradicts unified-memory behaviour.
- **Unsafe micro-optimisation**: the crates `forbid(unsafe_code)` by design; keep it.

---

## 6. Per-subsystem checks to run in M2-M7

| Area | Question | Method |
|---|---|---|
| Chunks | Does loaded chunk count equal the radius formula? Do evicted chunks free their columns? | Counters plus long traversal |
| Meshing | Peak simultaneous mesh bytes after a teleport? | `alloc-census` tag by job |
| CPU/GPU duplication | Is mesh vertex data kept on the CPU after upload? | Heap census by tag; read `streaming.rs` upload path |
| Textures | Are decoded RGBA source images retained after atlas upload? | Heap census at title screen vs after load; code audit |
| Assets | Peak during resource load; are jar/zip entries decoded in bulk? | Phase-marked footprint |
| Worldgen | Memory per generation worker; noise caches (`horizon-world/level/data/cache.rs:272` sizes by cores) | Census by thread |
| Persistence | Peak during save; buffer sizes | Footprint trace around autosave |
| Threads | Stack size effect on footprint; count of live threads | Instruments, thread list |
| Allocator | Retention after teleports; footprint after `release_free_memory()` | Trace plus census |
| Audio | Footprint with 64 MiB vs lower cache | A/B |
| Lifecycle | Footprint after background and after memory warning | Scripted run |

---

## 7. Risks specific to memory work

| Risk | Mitigation |
|---|---|
| Optimising the wrong number (RSS) | Footprint first (Gap A) |
| Over-fitting to the iPhone 12 | Test a second device class when available; keep settings as a table keyed by detected memory class, not a hard-coded device |
| Metal allocation failures are not recoverable the way Vulkan's are | `try_create` pattern exists in the arena for pages; extend the idea to other large allocations; the fallback to host memory is meaningless on unified memory |
| Desktop regressions | Platform profile only; run `tools/parity.py --changed`, desktop benchmark before/after |
| Visual quality loss unnoticed | Keep a screenshot set per setting (`horizon-ctl screenshot`) |
| `game.rs` merge conflicts with upstream | Put mobile profile in data/config and `horizon-client-render` constants, not in gameplay code |
| Upstream measurement claims are desktop-only | Treat as hypotheses, re-measure |

## 8. Deliverables of the memory track

1. M2: `phys_footprint` and `os_proc_available_memory` telemetry; extended `gpu_census`.
2. M4: memory-warning trim, with a test that footprint falls.
3. M6: baseline report set in the repository root `benchmarks/ios/`.
4. M7: mobile profile table with before/after evidence per change; updated ADR-4.
5. Ongoing: this document revised with measured values replacing "UNRESOLVED".

## 9. What I did not verify (explicit)

- No iOS footprint formula, no jetsam threshold, no A14 Metal limits, no actual arena sizes at runtime, no thread stack depth, no GPU census completeness, no integrated-server duplication ratio, no allocator behaviour on iOS, no thermal behaviour. Everything labelled UNRESOLVED above stays so until a device run.
