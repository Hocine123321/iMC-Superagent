# Horizon iOS Feasibility Report

> **Path convention.** This repository keeps the upstream Horizon snapshot in `horizon/`. Source paths cited below (`crates/...`, `tools/...`, `docs/benchmark.md`, `research-lock.json`, `CLAUDE.md`, ...) are relative to `horizon/`. Paths under `docs/ios-evidence/` and the three `docs/IOS_*.md` files are relative to the repository root.

**Status:** Phase 1 and 2 findings. No source files were modified. Evidence artifacts are in `docs/ios-evidence/`.
**Base:** `horizon-rust/horizon` `main` at `77af961663c48ef035b841cad68d84fc682918fd` (2026-11-07). Local branch `ios-port`; original remote renamed `upstream`.
**Game version pinned by the repo:** Minecraft Java 26.3, network protocol 777 (`research-lock.json`, `horizon-core/src/version.rs`).
**Toolchain used:** rustc/cargo 1.99.1 on Linux x86_64, targets `aarch64-apple-ios` and `aarch64-apple-ios-sim`. Workspace `rust-version` is 1.95.

## How to read this report

Every claim carries one of three labels.

- **VERIFIED**: observed by running a command or reading the cited source in this checkout.
- **INFERRED**: follows from verified facts but was not itself tested.
- **UNRESOLVED**: needs a Mac, a physical iPhone, or a human/legal decision. Not guessed.

**Limits of the method.** Two evidence sources. (1) `cargo check` on Linux: Rust type-checking and cfg resolution only. (2) A macOS 15 / Xcode 16.4 / iPhoneOS 18.5 SDK GitHub Actions runner (`.github/workflows/ios-build.yml`, runs linked in section 3.5): real C compilation, linking and a few runtime tests on an Apple kernel. Neither proves app behaviour on a device: nothing here has run on an iPhone, and no Metal frame has been drawn. Where a statement rests on source (2) it says so.

---

## 1. Executive summary

**Recommendation: proceed, with major changes to the resource pipeline and a new platform layer.** Full reasoning is in section 12.

The engine is a much better starting point than the plan assumed, in some ways, and worse in others.

Better than assumed:
- The renderer is wgpu 30.0.1 with the `metal` feature already enabled, and Horizon already ships a macOS Metal build. (VERIFIED, `crates/horizon-client-render/Cargo.toml`.)
- The game windowing layer is winit 0.30.13, which supports iOS. (VERIFIED, `Cargo.lock`.)
- After six small source edits (about 60 changed lines, see `diagnostic-compile-fixes.patch`) the entire `horizon-client` crate, including audio (cpal/CoreAudio), controllers (gilrs), the renderer, streaming and the gameplay layer, type-checks for `aarch64-apple-ios`. (VERIFIED, scratch copy.)
- A downstream Android fork already runs this exact engine on phones, which shows the engine does not need desktop-only assumptions at runtime. (VERIFIED by reading its public docs; not independently run.)

Worse than assumed:
- **Resource preparation runs Mojang's own server code and a vanilla data generator inside a JDK 25.** A normally signed iOS app cannot run that. This is the single largest structural blocker. (VERIFIED, `crates/horizon-prepare/src/java.rs`, `exporters.rs`.) **Decision (2026-11-08): run the preparation on the phone in an embedded iOS JVM with JIT enabled, as Amethyst does. A Java 25 iOS runtime exists (section 6.6), but running this workload on it is UNPROVEN and is the next experiment.**
- **There is no touch input at all.** No `WindowEvent::Touch` handling exists in the game. (VERIFIED by grep.)
- **There is no app-lifecycle handling.** No `suspended()` and `resumed()` returns early if a window exists. (VERIFIED, `window_handler.rs:201-253`.)
- **Horizon's "native mods" are compiled from source with cargo.** That cannot exist on iOS. (VERIFIED, `docs/native-mods.md`.)
- **Memory telemetry measures the wrong number for iOS.** (VERIFIED, `process_memory.rs`; see section 8.)

---

## 2. Repository map

### 2.1 Workspace shape (VERIFIED)

40 crates under `crates/`, 39 in the game workspace; `launcher/` and `crates/horizon-telemetry-server` are separate workspaces. Plus `third_party/{wgpu-hal,naga,libmimalloc-sys}` patched forks.

| Layer | Crates | Role |
|---|---|---|
| Simulation base | `horizon-core` (`libm =0.2.16` only), `horizon-world`, `horizon-protocol`, `horizon-items`, `horizon-command`, `horizon-client-core`, `horizon-assets` | Pure Rust. Java RNG, noise, NBT, Anvil, worldgen, packets, models. |
| Client | `horizon-client-render` (rendering, streaming, meshing, UI), `horizon-client-input`, `horizon-client-lib`, `horizon-client` (gameplay + binary) | The game. |
| Platform glue | `horizon-threads` (allocator, QoS, process memory), `horizon-hdr`, `horizon-narrator`, `horizon-dualsense` | Small OS-specific crates. |
| Not needed for iOS v1 | `horizon-server*`, `horizon-anticheat`, `horizon-chat-filter`, `horizon-bots`, `horizon-relay`, `horizon-friends`, `horizon-telemetry`, `horizon-mod*`, `cargo-horizon-mod`, `horizon-port-pack`, `xtask`, `launcher/` | Server, tooling, desktop launcher. |

Size indicators (VERIFIED): `gfx.rs` 14,596 lines; `game.rs` 17,802 lines; `streaming.rs` 4,510 lines; `horizon-prepare` about 8,000 lines.

### 2.2 Project process constraints (VERIFIED, `CLAUDE.md`, `AGENTS.md`)

These affect how any iOS work must be delivered.
- Small PRs (under about 500 lines). Contributors must `/claim` an issue first.
- Parity harnesses are the spec and must never be weakened or deleted.
- Never commit Mojang files; `tools/check_public_tree.py` enforces it.
- Agent-authored PRs must carry attribution lines.
- No hardcoded user-facing strings; use `Text::tr` / `lang::get`.
- Horizon-only features are off by default where they would change the vanilla look.

### 2.3 Upstream position on mobile (VERIFIED, `ROADMAP.md:727-735`)

"Android, iOS and the browser" is a **long-term** roadmap item with "nothing official yet". Android was first closed as not planned. Upstream issues: #9134, #8069, #4153, #1750 (prepare without Java), #1813 (`horizon-dualsense` on iOS, already merged: its Cargo.toml gates `hidapi`/`cpal` with `cfg(not(target_os = "ios"))`).

**Implication:** a fork can proceed, but it should keep changes small and upstreamable, because upstream is receptive to the groundwork (#1813, #1750 are labelled roadmap items) and hostile to large unreviewed rewrites.

---

## 3. iOS build compatibility matrix

### 3.1 Method

`cargo check --locked --target aarch64-apple-ios -p <crate>`, each crate in isolation, against the **unmodified** checkout (logs: `check-round1-unmodified.log`, `check-round2-unmodified.log`). Then a **scratch copy outside the repo** with diagnostic edits to find what hides behind each blocker.

### 3.2 Unmodified checkout results (VERIFIED)

| Crate | Result | Notes |
|---|---|---|
| horizon-core | PASS | |
| horizon-world | PASS | worldgen, NBT, Anvil, datafix |
| horizon-protocol | PASS | |
| horizon-items, -command, -client-core, -assets, -theme, -optifine, -polytone, -shader-api, -shaders, -bench | PASS | |
| horizon-dualsense, horizon-narrator | PASS | narrator has no iOS impl; compiles to no-op |
| horizon-mods, -anticheat, -chat-filter, -mcp, -friends, -relay | PASS | |
| horizon-threads | FAIL (environment) | `libmimalloc-sys` build script needs clang |
| horizon-telemetry, -cosmetics, -server-files | FAIL (environment) | `ring 0.17.14` build script needs clang |
| horizon-client-render, -client-lib, -client | FAIL | `-render` fails on B1/B3-class errors; `-lib` and `-client` fail first on `ring` |
| **horizon-hdr** | **FAIL (code)** | imports `wgpu::hal::api::Vulkan`, absent on iOS |
| **horizon-client-input** | **FAIL (code)** | `arboard` built with `wayland-data-control` pulls Wayland crates |

### 3.3 Classification of failures

**Environment failures (not code defects): RESOLVED on a Mac runner.** `libmimalloc-sys` and `ring` are the only crates in the iOS graph that compile C. Both compile with Xcode 16.4's clang for `aarch64-apple-ios`; `ring` was seen compiling on the first runner log and mimalloc linked in the final build. The one real problem was a link error (section 3.5).

**Confirmed code blockers (four), each found by peeling the previous one:**

| # | Location | Problem | Minimal fix | Size |
|---|---|---|---|---|
| B1 | `crates/horizon-client-input/Cargo.toml:15` | `arboard` feature `wayland-data-control` is unconditional. Pulls `wayland-backend 0.3.17`, which cannot compile for iOS. | Make the feature `cfg(target_os="linux")`-only | 2 lines |
| B2 | `crates/horizon-client-input/src/keybinds.rs:303-311` | Uses `winit::platform::modifier_supplement::KeyEventExtModifierSupplement::key_without_modifiers`, desktop-only in winit 0.30.13. | `cfg` fallback to `event.logical_key` on iOS/Android | 6 lines |
| B3 | `crates/horizon-hdr/src/lib.rs`, `Cargo.toml`; `gfx.rs:2327-2332, 2367-2373` | Gated on `not(target_os="macos")`, so iOS is treated as a Vulkan platform. | Gate on `target_vendor="apple"` | ~10 lines |
| B4 | `crates/horizon-threads/src/process_memory.rs:65-82` | `libc::proc_pidinfo`/`proc_taskinfo` do not exist for iOS in the `libc` crate. | Gate to macOS; add an iOS implementation (section 8) | ~10 lines + new code |

After B1-B4 (scratch copy only, with `ring` and `mimalloc` build scripts stubbed to no-ops purely so rustc can type-check): **PASS** for `horizon-client-input`, `horizon-hdr`, `horizon-client-render`, `horizon-client-lib`, and `horizon-client` including `--bins`, **with default features** (`audio`, `controllers`, `discord`, `friends`, `heartbeat`).

I confirmed the pass is real and not an artifact: `cargo tree --target aarch64-apple-ios` shows `cpal 0.16.0`, `coreaudio-rs 0.13.0`, `objc2-core-audio`, `gilrs 0.11.2`, `objc2-metal 0.3.2`, `winit 0.30.13`, `rustls 0.23.46`, `ureq 2.12.1`, `mimalloc 0.1.52` and the patched `wgpu-hal 30.0.1` in the iOS graph.

**Caveat on that pass.** Type-checking passing does not mean the features work on iOS. For example `gilrs` on iOS may compile to a stub, and `arboard`'s iOS clipboard support is unverified.

### 3.4 What is still NOT known

Answered by the macOS runner (section 3.5): whether it links, whether `ring` and mimalloc build, and the host-side `horizon_mod_api_gen` build script (it ran as part of the cross-build on the runner). Still open:

- Binary size after `-dead_strip` and with the final feature set. The 71 MiB figure is a plain release link of a command-line executable; no stripping or size work was done.
- Whether the **tests** build and run for iOS. Only libraries and the binary were built.
- How the engine is entered as an app: winit on iOS, `UIApplicationMain`, and where Horizon's own `main` fits.
- Whether the Metal backend initialises on an A14 and which of the renderer's optional features it enables. Nothing has run on a device or the simulator.
- Which of the other 10 crates not checked matter for the app (`horizon-prepare` in particular).

---

### 3.5 Verified on a macOS runner (the unmodified snapshot, then B1-B4)

All results are from GitHub Actions runs on `macos-15` (Xcode 16.4, iPhoneOS 18.5 SDK, rustc 1.99.1) in this repository.

| Step | Result |
|---|---|
| Unmodified snapshot, `horizon-world`, `horizon-protocol` for `aarch64-apple-ios` | Build and link: pass |
| Unmodified snapshot, `horizon-client-lib` and `horizon-client` | Fail first at `wayland-backend` (B1): 5 errors, identical to the Linux finding. `ring` had already compiled |
| After B1 and B3 | `horizon-client-lib` builds for `aarch64-apple-ios` and `aarch64-apple-ios-sim` |
| After B2 and B4 | Same. `process_memory` tests pass on an Apple kernel: 256 MiB touched moves `phys_footprint`, and the value is plausible |
| Full `horizon-client` binary, default deployment target | **Link failure**: `___chkstk_darwin`, referenced from mimalloc's C code, unresolved. Rust's default iOS deployment target is 10.0; the symbol is not in that libSystem |
| Same, with `IPHONEOS_DEPLOYMENT_TARGET=16.0` | **Pass.** `target/aarch64-apple-ios/release/horizon-client`, a Mach-O of 74,439,272 bytes (about 71 MiB), release profile, build time 10 min 38 s on a cold cache |

What this does and does not show. It shows the whole client, with its default features (audio via CoreAudio, controllers, windowing via winit, TLS via rustls and ring, the patched wgpu-hal with Metal), compiles and links for iOS once B1-B4 and a deployment target are set. It does **not** show that the binary starts: it is a command-line executable, not an app bundle, has no `UIApplicationMain`, is unsigned, and has never run. `winit` on iOS expects to own `UIApplicationMain`, so how `main` is entered is the first design question of milestone M1.

**Deployment target.** 16.0 is a working value, chosen because it links and exceeds the 13.0 minimum of `os_proc_available_memory`. It is not a support decision. UNRESOLVED: the lowest iOS the project should support.

### 3.5a First runs on the iOS Simulator (VERIFIED; iPhone 16 Pro simulator, iOS 18.5, Apple-silicon runner)

The Horizon engine runs inside an iOS app. Each row is a CI run in this repository; each fix was found from the previous run's log, not predicted.

| Run | What happened | Cause and fix |
|---|---|---|
| 1 | Process alive, engine printed its version and the "prepared game files are missing" message, then `Failed to create surface for any enabled backend: {}`. Screen black apart from the status bar | `gfx.rs backend_order` compared the run-time string `"macos"` only, so iOS was asked for Vulkan and OpenGL (neither built). Added `"ios"` |
| 1 | The resource path printed as `/.local/horizon-client/26.3` | The default is `<executable folder>/resources` or a path relative to the working directory, which is `/` on iOS. `main.m` now passes `--resources` under Documents (std reads `_NSGetArgv` on demand on Apple platforms, checked against the Rust source) |
| 2 | Metal chosen (`Apple iOS simulator GPU (Metal)`), device and surface created, HDR output scRGB selected, then a validation error at pipeline creation: `Downlevel flags INDIRECT_EXECUTION are required but not supported` for the buffer `Flat section draw calls, phase 2` | `gfx/flat.rs supported()` did not require `INDIRECT_EXECUTION` although its buffers use `BufferUsages::INDIRECT`. Added it, with a test. **Whether an A14 reports the flag is not known**: the simulator's Metal device is not representative of the phone |
| 2 | `servers.dat` and `options.txt` could not be saved: read-only file system | The game folder is the process's working directory (`options.rs game_dir`); an iOS app starts in `/`. `main.m` now changes to `Documents/Horizon/home` |
| 2 | Narrator: "Unsupported platform ios" logged as an error | Expected; the narrator has no iOS implementation (section 9.3). Harmless |
| 2 | `fatal runtime error: failed to initiate panic, error 3` after the wgpu panic | A Rust panic that unwinds through a UIKit (Objective-C) frame cannot unwind and aborts. The engine already treats wgpu errors as fatal, so the outcome is the same. Not a defect to fix |

| 3 | Metal, first frame presented, loading screen reached, process alive after 40 s, no crash report, saves and logs written under `Documents/Horizon/home` | The indirect-draw gate and the working-directory change worked. Pipelines report "multi-draw off, occlusion culling off, GPU culling unavailable": the fallback paths |
| 4 | Surface `2250x1143` (was `3120x2040` and `3840x2100`), black share of the screenshot fell from 30.6% to 1.2%, built `Info.plist` has `UIRequiresFullScreen`, landscape-only orientations, `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` (1,162 bytes, was 743) | winit on iOS uses `inner_size` as the UIWindow frame (`winit-0.30.13/src/platform_impl/ios/window.rs:511-516`), so the desktop sizes overflowed the phone; `window::creation_size` skips the request on iOS. XcodeGen had rewritten the plist from a bare `path:`; the keys now live in `project.yml` |

Still **not established** about orientation: `simctl io screenshot` returns the device framebuffer in portrait (1206x2622), and the simulator was not rotated, so these runs cannot say whether the app is displayed landscape. The surface is landscape-shaped and the plist is landscape-only, which is consistent but not proof.

What these runs do **not** show: any frame of the game drawn, behaviour on a real GPU, memory, or input. The stub resource manifest (`{}`, no game data) was used only to get past the first screen and see what the loader needs; it is not a prepared folder. The simulator is not evidence for performance or for Metal correctness on the phone (roadmap principle 5).

### 3.6 SDK facts read from the iPhoneOS 18.5 headers (VERIFIED)

- `task_vm_info`: `TASK_VM_INFO` = 22; the revision-1 prefix is 38 words (152 bytes); `phys_footprint` is at byte offset 144, `internal` at 48, `compressed` at 120, `resident_size` at 16; `limit_bytes_remaining` at 336 (a later revision). The full struct is 372 bytes.
- `os_proc_available_memory()` is declared in `<os/proc.h>`, `API_AVAILABLE(ios(13.0))` and `API_UNAVAILABLE(macos)`.
- `malloc_zone_pressure_relief()` is a public declaration in `<malloc/malloc.h>` (`__IPHONE_4_3`), so the allocator release path in `horizon-threads` has a documented API on iOS.
- `libc` 0.2.190 exposes `task_info` for iOS, but `mach_task_self` and `mach_task_self_` only for macOS (deprecated). The fix declares `mach_task_self_` locally.

## 4. Rendering pipeline and Metal compatibility

### 4.1 What exists (VERIFIED)

- `Renderer::new` (`gfx.rs:1722` area) creates a `wgpu::Instance`, a surface from an `Arc<winit::Window>`, requests an adapter with `PowerPreference::HighPerformance`, and a device.
- Backends: Metal on macOS, Vulkan/DX12/GL elsewhere (`graphics.rs:246`). The renderer already special-cases Metal: `mesher::group_parts(backend == Metal)` and a two-pass solid terrain draw (`split_solid`) at `gfx.rs:4492-4494`. On iOS wgpu would select Metal automatically. Whether `graphics.rs:246`'s `cfg!(target_os = "macos")` branch needs an iOS arm is INFERRED, not tested.
- Shaders: WGSL via naga. `naga` is patched in `third_party/naga`. The tests already translate every shader to HLSL; the dev-dependency enables `msl-out`, so **Metal shader translation is already exercised in tests** (`crates/horizon-client/Cargo.toml` dev-deps). That is good evidence the shaders are MSL-translatable. It is not proof they run correctly on Apple GPUs.
- `third_party/wgpu-hal` is patched, including a fix to the Metal backend's HDR colour-space lookup.
- Device requests use `required_limits: adapter.limits()` and an optional-feature mask intersected with the adapter's features (`gfx.rs:2271-2304`). That means the renderer **adapts to what the GPU offers** rather than demanding features.

### 4.2 Feature dependence relevant to Apple GPUs (VERIFIED by grep, INFERRED for behaviour)

Optional, guarded by capability checks with fallbacks: `MULTI_DRAW_INDIRECT_COUNT` (GPU culling, `gpu_culling.rs:517`), `INDIRECT_FIRST_INSTANCE`, `SUBGROUP`, `TEXTURE_ATOMIC`, `MAPPABLE_PRIMARY_BUFFERS`, `TIMESTAMP_QUERY`, `FLOAT32_BLENDABLE` (OIT).

I did **not** verify which of these Metal on an A14 exposes through wgpu 30. The renderer's design means a missing feature should select a fallback path, but **each fallback path must be tested on device**, because fallbacks are the least-exercised code. UNRESOLVED.

### 4.3 Surface and lifecycle (VERIFIED)

- `Renderer::recreate_surface()` exists (`gfx.rs:5094`) and handles surface loss. It is used for Wayland/Windows cases today.
- Device-lost callback exists (`gfx.rs:2338-2349`).
- Present modes: Fifo/Mailbox/Immediate selection (`gfx.rs:5156`). On iOS only Fifo is expected. INFERRED.
- Swapchain format preference: `Bgra8Unorm`, then `Rgba8Unorm`, non-sRGB by design (`gfx.rs:2008`).

### 4.4 Gaps for iOS

| Gap | Evidence |
|---|---|
| No `suspended()` handler | `window_handler.rs` implements only `resumed`, `window_event`, `device_event`, `about_to_wait`, `exiting` |
| `resumed()` returns early when a window exists | `window_handler.rs:202-204`. winit on iOS calls `resumed` after each foreground; the surface must be recreated, not ignored |
| GPU work submitted while backgrounded is fatal on iOS | General iOS behaviour; the app must stop presenting before `suspended` returns. UNRESOLVED how winit 0.30 orders this |
| Fullscreen/cursor-grab/window-size assumptions | `resumed()` calls `with_inner_size`, `with_fullscreen(Borderless)`, `settle_created_fullscreen`; cursor capture via `CursorGrabMode` (`game.rs:572, 2433`) has no iOS meaning |
| Window icon, Wayland name | Guarded or harmless |
| ProMotion / refresh-rate cap | iPhone 12 is 60 Hz; not an issue for the first device |
| Safe areas, notch, home indicator | Nothing in the HUD code addresses them. Not searched exhaustively. UNRESOLVED |

### 4.5 Metal-specific risks to test on device (UNRESOLVED)

1. Maximum buffer and storage-buffer binding sizes on A14 versus the arena's assumptions (section 8).
2. `texture_array` layer counts. The renderer's `check_layers`/`layer_split` logic (`gfx.rs:1987`) already adapts to `max_texture_array_layers`, which is reassuring.
3. `Depth32Float` is used 54 times; confirm it is renderable, and its memory cost, on A14.
4. `Rgba16Float`, `Rg11b10Ufloat`, `Rgba32Uint` usage in shader-pack paths. Shader packs are optional and can be disabled on mobile.
5. Metal shader compile time at startup. Horizon already caches DX12 shaders to disk because FXC took about 2.6 s; **a Metal pipeline cache has not been looked at**. Cold-start cost on A14 is UNRESOLVED.

---

## 5. Windowing, input, audio, networking, persistence

### 5.1 Entry point and event loop (VERIFIED)

`entry::main` (316 lines) ends in `EventLoop::new()?.run_app(&mut app)` (`game.rs:17066`). On iOS, winit requires the event loop to be created on the main thread from `UIApplicationMain`'s context, normally via a C-callable `main` in a Swift/ObjC host, or winit's own `UIApplicationMain` when run as the process entry. The binary today is `fn main()` in `crates/horizon-client/src/main.rs`.

**Decision needed (ADR-1):** (a) ship the Rust as a staticlib and let a thin Swift/ObjC `main` call into it, which gives clean control of the launcher UI and lifecycle; or (b) let winit own `UIApplicationMain` and build the launcher UI in Rust. The plan document leans toward (a). I agree for the launcher, because account sign-in, file handling and document pickers are much easier in UIKit/SwiftUI. See roadmap M1.

`horizon-client` has no `[lib] crate-type = ["staticlib"]` today (`grep` found `[lib]` only in `horizon-client-lib`). A `staticlib` wrapper crate would be a new additive crate, which fits the plan's "narrow bridge" and upstream conventions.

`build.rs` embeds the Windows icon and sets an 8 MB main-thread stack for Windows only. On iOS the main thread has the system default; secondary threads default to 512 KB. The code comment says splitscreen builds a roughly 67 KB `Game` "deep in the event loop". Stack depth on iOS worker threads was **not** audited. UNRESOLVED.

### 5.2 Input (VERIFIED)

- Keyboard and mouse via winit. Gamepads via `gilrs` and `horizon-client-input/gamepad.rs`.
- **Zero** handling of `WindowEvent::Touch`. The only `TouchPhase` use is a synthetic scroll in `agent.rs:1555`.
- The game assumes a captured pointer with relative motion (`DeviceEvent::MouseMotion`, `window_handler.rs:271-292`). Touch has no such device event, so look control needs a touch-to-look mapper.
- UI is mouse-first: click targets, hover, and a "Mouse toggle" inventory. CLAUDE.md notes "Controllers reach what registers" through registering UI helpers; **that existing controller path is the cheapest on-ramp for a touch UI** because widgets already register hit regions. INFERRED.
- The Android fork implements four touch schemes (joystick/D-pad x crosshair/tap), custom buttons and layout editing. That is a useful design reference. It is Android code and its licence/reuse must be checked before reading it as a template. UNRESOLVED.

### 5.3 Audio (VERIFIED + INFERRED)

`cpal 0.16` behind the `audio` feature; CoreAudio backend appears in the iOS graph. Decoding uses `symphonia` (ogg/vorbis). A 64 MiB LRU decoded-sound cache exists (`audio.rs:151`). Not verified on device: `AVAudioSession` category, interruption handling (phone call, Siri), route changes, silent-switch behaviour. cpal does not manage `AVAudioSession`; the Swift shell likely must. UNRESOLVED.

### 5.4 Networking (VERIFIED + INFERRED)

`ureq 2.12.1` with `rustls 0.23.46` and `ring 0.17.14` (not the system TLS). Works without ATS issues because it bypasses Foundation. Consequences: (a) certificates come from whatever root store ureq/rustls is configured with; whether it uses `webpki-roots` or platform verifier was not checked, and **iOS has no `/etc/ssl`**. UNRESOLVED and important. (b) iOS "Local Network" permission is needed for LAN play; `NSLocalNetworkUsageDescription` and Bonjour entries belong in Info.plist. (c) The game also hosts LAN worlds (`lan/`), which would trigger that prompt.

Multiplayer protocol is 777 and handled in `horizon-protocol`. It does not depend on platform code.

### 5.5 Persistence and filesystem (VERIFIED)

- `data_dir()` (`logging.rs:31-52`) handles Windows, macOS, then falls through to `XDG_DATA_HOME` or `$HOME/.local/share`. **On iOS this returns a Linux-style path under the sandbox home** (`$HOME` is the app container, so it would work by accident but is not the platform-correct `Library/Application Support`, and would not be excluded from backup correctly). Fix: add an iOS arm or let the Swift shell pass `--home`/`--game-dir`, which both already exist.
- The game already takes `--game-dir`, `--home`, `--resources`, `HORIZON_HOME`. That means **the shell can fully control paths without engine changes**. This is a significant plus.
- Worlds are vanilla Anvil. Saves, `options.txt`, caches live in the game dir.
- `fs4` (disk space), `rustix` (CPU time via `CLOCK_THREAD_CPUTIME_ID`) are pulled on unix; both type-check on iOS.
- Process spawning (`Command::new`) appears in `crash.rs`, `telemetry.rs` (`ps`), `dedicated.rs`, `world_management.rs`, `pad_menu.rs`, `packs/folder.rs`, `split_ui.rs`. `fork/exec` of arbitrary binaries is not permitted for iOS apps. These sites compile but will fail at runtime. Each needs an audit. UNRESOLVED which are on hot paths. `telemetry.rs:334` runs `ps`, which does not exist on iOS.
- Dedicated server mode re-executes `current_exe()` (`dedicated.rs:2589`). Not applicable on iOS; the integrated singleplayer server runs in-process (`integrated.rs`). INFERRED from CLAUDE.md that singleplayer uses an in-process server thread.

---

## 6. Resource preparation (the largest blocker)

### 6.1 What happens today (VERIFIED)

`horizon-prepare` (crate, about 8k lines) builds `.local/horizon-client/26.3` from the player's own Minecraft install:

1. Verifies the client jar and server jar against pinned checksums (`research-lock.json`, `artifacts.rs`).
2. Finds a JDK 25 (`java.rs`: `Jdk { javac, java }`), **compiles Horizon's own Java exporter classes** (`exporters.rs`: lists `VanillaHeightmapOracle`, `VanillaCollisionOracle`, `VanillaBlockBehaviourExporter`, `VanillaEntityModelExporter`, and others) against Mojang's jars, and **runs Mojang's code in a JVM** to dump block behaviour, collision shapes, entity models, mob data, creative tabs, and runs vanilla's data generator.
3. Extracts assets and data from the jar into the resource folder; copies roughly 380 MB of sounds from the launcher asset store, each checked against the asset index SHA-1 (`docs/native-client.md:70-73`).

`BATCH_OPTIONS` shows a fresh preparation took 63-66 s on desktop with JVMs together using 1.25 GB.

### 6.2 Why this cannot run on iOS (VERIFIED + well-established platform fact)

- iOS apps cannot `fork`/`exec` a JDK, and a JVM needs a JIT (writable+executable memory). A normally signed app does not get that capability. Some sideloading routes can enable JIT. **The game itself does not need it (it is ahead-of-time Rust). Under the decision in section 6.6, the one-time preparation does**, so preparation is only available to installs that can enable JIT.
- The memory is also prohibitive: 1.25 GB of JVMs on a 4 GB device.

### 6.3 The known way around it (VERIFIED as a proposal; implemented downstream)

Upstream issue **#1750** (open, labelled `roadmap:prepare-without-java`, "Later") proposes exactly this:
1. In CI, run the full preparation once per version with Java.
2. `horizon-prepare pack-facts` packages only the **computed tables** ("computed numbers only, no assets or code").
3. On the device, `horizon-prepare assemble` combines the published tables with the **player's own client jar and asset store** into the usual resource folder. No JVM.

The author states they use it for Android and that "Horizon 26.3 plays from an assembled folder on both" PC and Android. The upstream agent's reply: it fits the roadmap, but **"the open question is legal rather than technical: the published tables have to hold nothing of Mojang's... and the maintainer decides that before any of it is published."**

### 6.4 Assessment

This is the **critical path and the main legal/maintainer risk**.

- Technically: feasible and demonstrated downstream. The tables are produced by running Mojang's code, so whether they count as "nothing of Mojang's" is a legal characterisation, not a technical one. I make no legal conclusion.
- Practically: until upstream accepts #1750 (or you carry your own variant), **an iOS build cannot prepare resources**. A fork would have to host the tables, which is a distribution act. That is exactly the point the user's statement of intent distinguishes ("we do not host Mojang/Microsoft assets from our servers"). Hosting derived tables is a different category from hosting assets, and needs review. See section 11.
- Alternative rejected: reimplementing the Java exporters in Rust. Ruled out as unsound. The exporters call vanilla code (for example `VanillaBlockBehaviourExporter`, `VanillaCollisionOracle`) precisely because Horizon treats vanilla as the specification. Reimplementing them would duplicate logic Horizon is built to mirror, and reproduce it without the oracle that proves correctness.
- Alternative rejected: shipping the tables inside the app binary. That is redistribution of derived data to every user with no ownership check, and is a worse legal posture than a gated download.
- Alternative worth evaluating: have the **user's own Mac/PC** run `horizon-prepare` and transfer the folder to the phone (Files app/AirDrop). This needs no hosting and no new legal surface, at a large usability cost. It is a sensible **bootstrap path for milestone M3** before the tables question is settled.

### 6.5 Size and storage (VERIFIED from docs, Android precedent)

Sounds about 380 MB. The Android fork documents about 500 MiB total first install. The iOS app should keep the prepared cache excluded from iCloud backup (`isExcludedFromBackup`). Whether iOS may purge it is relevant: `Application Support` is not purged, `Caches` can be. Choose accordingly. UNRESOLVED.

### 6.6 Decision: prepare on the phone with an embedded JVM and JIT (2026-11-08)

**The owner's model**, which matches Horizon's own launch guide (`docs/api/launch-guide.md`, section 0: "Horizon never downloads Mojang's files; when your launcher downloads them, it does so only for that owner, as it would for vanilla"):

1. The app signs the player in with their Microsoft account and checks they own Java Edition.
2. The app downloads the player's own copy (version JSON, client jar, libraries, assets, and the server jar named by the version JSON's `downloads.server`) from Mojang's endpoints, to the device.
3. The app prepares the Horizon resources from that copy, on the device.
4. Nothing of Mojang's is committed to git, hosted, or distributed by this project.

**What the launch guide requires of a launcher (VERIFIED).** Preparing reads: version JSON, client jar, libraries (Maven layout), assets (`indexes/`, `objects/`), the server jar (first time only), and **a Java of `java_major` (25)**, passed with `--java-home`. Every file is checked against `research-lock.json`. The command is `horizon-prepare --prepare --server-jar ... --minecraft-dir ... --output ... --complete --progress json`; `--check` verifies a folder with no Java.

**Evidence that a Java 25 iOS runtime exists (VERIFIED from Amethyst's public repository, not run by me).**
- Amethyst-iOS's `Makefile` defines `AME_JRE25_DIR` and fetches `jre25-ios-aarch64.zip` from `assets.angelauramc.dev/openjdk/ios-arm64/` (also jre8, 17, 21), and bundles it as `java-25-openjdk`.
- Its CI history shows "[Makefile] Switch URLs, update JREs, and add Java 25" (Jul 12, 2026) and "Java 25 in staging, fix download links" (Oct 17, 2026, commit `c1f3aea`), both green.
- A commit "fix(JVM): append `-XX:-UseCompressedClassPointers` for all cases" (Aug 10, 2026) shows that modern Java on iOS needs JVM flag workarounds.
- **Correction after a CI probe (run 42493576308).** `assets.angelauramc.dev` does not resolve from GitHub's own runners either, so it is not a sandbox block: no DNS record for that name exists today. The parent `angelauramc.dev` and `cdn.angelauramc.dev` do resolve, but `cdn.` only redirects to the homepage and the earlier host `crystall1ne.dev/cdn/amethyst-ios/` now returns 404. Amethyst-iOS publishes no GitHub releases. **So the prebuilt `jre25-ios-aarch64.zip` is not obtainable from any address I can reach.** The Makefile's URL is not evidence that the file can be downloaded.
- **The source recipe is public (VERIFIED by cloning).** `github.com/AngelAuraMC/angelauramc-openjdk-build`, branch `duy/buildjre17-21-25-ios` (commit `3f41bca`, "add: java 25", 2026-07-10, by khanhduytran0). Its workflow builds `version: [17, 21, 25]` for iOS aarch64 on a **self-hosted Mac runner** (`J316sAP`, a procursus toolchain), cloning upstream `openjdk/jdk25u`. `patches/jre_25/ios/` holds two diffs: `1_jdk25u_ios.diff` (3,260 lines, the JDK build system: autoconf flags, `java.base`, `java.desktop`, `java.instrument`) and `2_mirror_mapping.diff` (1,474 lines, HotSpot: aarch64 assembler, `codeBuffer`, `codeBlob`, `codeCache`, `os_bsd`, signal handling). Mirror mapping is the dual-mapped code region that lets a JIT run under iOS's rules. On `master` the iOS job builds **Java 8 only** (a patched Corretto 8), so the 25 work lives on that branch.
- **What this means:** a Java 25 for iOS can be **built from source in CI**, but I have not built it, nobody has shown the result running `horizon-prepare`, and a build needs a Mac runner with that toolchain (GitHub's `macos-15` is a candidate, untested). The runtime also contains code from the OpenJDK project under its own licences, which matters for redistribution (section 11.3, 16a).

**What is NOT established. These are the risks of this decision.**

| Question | Why it matters | State |
|---|---|---|
| Does Java 25 for iOS run `horizon-prepare`'s exporters and data generator at all? | They call Mojang's server and client code (335 oracle sources, about 44,000 lines) | UNPROVEN |
| How slow is it without a fast JIT, and how long does a full preparation take on a phone? | Amethyst's README says JIT needs a debugger or a special install | UNMEASURED |
| Peak memory. | Today up to three JVMs run at once (`lib.rs:767`), plus a fourth at 6 or more cores (about 400 MB). iOS limits an app's memory | UNMEASURED. Preparation would have to run one JVM at a time (`pool::jobs` = 1) |
| What installs can enable JIT, on which iOS versions? | Amethyst lists AltStore, SideStore, StikDebug, TrollStore, Jitterbug and jailbreak, and its JIT26 work targets iOS 26 | Depends on the owner's device and iOS version, not yet stated |
| Entitlements and signing. | Amethyst ships `entitlements.sideload.xml`, `.trollstore.xml`, `.codesign.xml`; it also uses a "DyldDeNeuralyzer" to bypass library validation | Our unsigned IPA has none of these |
| Licence of the runtime. | Amethyst's list names Azul Zulu JDK (GPLv2 with the Classpath exception, to be confirmed) and Caciocavallo (GPLv2). A runtime built from `openjdk/jdk25u` would be GPLv2 with the Classpath exception (to be confirmed against the tree's `LICENSE`) | UNRESOLVED, see section 11 |
| Can the runtime be obtained at all? | The prebuilt zip's host has no DNS record; the source recipe exists but is unbuilt by us | **Open.** Option: build `jdk25u` with the branch's patches in CI (hours, unproven toolchain), or ask the Amethyst maintainers where the file lives now |
| Does `horizon-prepare` (a Rust CLI) run in-process on iOS? | iOS has no `fork`/`exec` for a child process | It would be built as a library and call into a JVM embedded in-process (JNI), not spawn `java`. `java.rs` spawns child processes with `Command::new`, so **this needs code changes** in `horizon-prepare` (UNRESOLVED how large) |

**Consequence for the "once only" expectation.** Preparation is incremental ("later preparations skip what is already current"), but it runs again when the Minecraft version, the Horizon build, or the preparer's `OUTPUT_VERSION` changes. So it is once per version, not once ever, and every re-run needs JIT again.

**Fallback if the experiment fails.** Prepare once on a machine the owner controls (a PC, Mac, or the owner's own CI) from the owner's own copy, and copy the finished folder to the phone through the Files app. This hosts nothing and distributes nothing. Upstream's `pack-facts`/`assemble` (issue #1750) is **not in this checkout**: I checked `crates/horizon-prepare/src/main.rs` and it has no such command. It is an open proposal labelled "Later", and its maintainers say whether the published tables count as "nothing of Mojang's" is undecided. This project does not depend on it.

**Mojang's app approval still applies to sign-in.** `docs/microsoft-account.md`: a new Azure app is refused by `login_with_xbox` until Mojang approves it (days to weeks), and Horizon's own client ID must not be reused. The downloads themselves use Mojang's public endpoints, so the downloader can be built and tested before sign-in is approved; sign-in only proves ownership.

---

## 7. Authentication and ownership

### 7.1 What Horizon does (VERIFIED, `docs/microsoft-account.md`)

OAuth **device-code flow** against `login.microsoftonline.com/consumers`, scope `XboxLive.signin offline_access`, public client (no secret). Then Xbox Live, XSTS (`rp://api.minecraftservices.com/`), `login_with_xbox`, `entitlements/mcstore` (must own `game_minecraft` or `product_minecraft`), and `minecraft/profile`. Tokens go in the OS keychain (service `dev.playhorizon.launcher`). An **owner gate** (decided 2026-10-27) refuses to launch without an owning account; the game binary itself, harnesses and CI are not gated.

Two Horizon-specific facts that matter for you:

1. **The Azure app registration belongs to the maintainer, and "nothing below can be done by an agent."** A build without a client ID cannot sign in.
2. **Mojang gates new apps.** `login_with_xbox` returns 403 "Invalid app registration" until Mojang approves the app via `aka.ms/mce-reviewappid`; "approval takes days to weeks". The doc says "Never use another application's client ID."

The Android fork states its own registration is "a temporary development configuration, not a project-owned Microsoft/Mojang approval. Production registration remains pending."

### 7.2 Implications for iOS (INFERRED + UNRESOLVED)

- **You need your own Azure app registration and your own Mojang app-ID approval** for an iOS app. You cannot reuse Horizon's. Timeline is Mojang-controlled.
- Device-code flow works on iOS with no redirect URI and is the least-effort path. A native flow with `ASWebAuthenticationSession` and a custom-scheme redirect would be a better UX but needs a public-client redirect URI registered in Azure. Which is allowed for this app type should be confirmed against current Microsoft docs. UNRESOLVED.
- The launcher's keychain code is in the **separate `launcher/` workspace** (GPUI, desktop). **It is not reusable on iOS.** The auth logic (about the 7 steps) must be reimplemented or extracted into a shared crate. Extracting into a crate that both launcher and iOS use is the upstreamable route. The Swift shell could alternatively own auth entirely and hand the engine a session via the existing `--session-file` / `--session-stdin` interface (`game.rs` help text), which is a **clean seam already in the engine**. VERIFIED that these flags exist.
- Store tokens in iOS Keychain with appropriate accessibility class, never in files or logs. Matches Horizon's own rule that tokens never appear in logs.
- Ownership gating is **a product/ethics control, not a technical protection.** The game binary does not check it. I note this so nobody over-claims what the gate guarantees.

### 7.3 What this document does NOT conclude

Whether Microsoft's/Mojang's API terms permit this app, whether the resource download endpoints (`launcher/src/mojang.rs`) may be called from a third-party iOS app, and whether Apple would accept the app: all UNRESOLVED and listed in section 11.

---

## 8. Memory findings (summary; full strategy in `IOS_MEMORY_STRATEGY.md`)

All figures below are from source, not measurement. No on-device number exists yet and none should be assumed.

1. **The telemetry measures the wrong thing for iOS.**
   - `process_memory.rs` on Apple reports `pti_resident_size` via `proc_pidinfo`. That API is unavailable to iOS apps (B4), and resident size is not the figure iOS enforces.
   - The relevant figure is the task's **physical footprint** (`phys_footprint` from `task_info(TASK_VM_INFO)`), which is what the Xcode memory gauge and jetsam reporting are based on. I did not verify an exact formula; **INFERRED from Apple documentation, to be confirmed on device.**
   - `docs/benchmark.md:13` states that on Apple Silicon "the GPU shares RAM and no per-process figure is available". On iOS this would double-count or omit GPU buffers unless footprint is used.
2. **GPU terrain arena pages have a 256 MiB ceiling** (`arena.rs:14`, `PAGE_BYTES`), with `LARGE_PAGE_BYTES` of about 2 GiB for translucent data, clamped to device `max_buffer_size`. The section arena **starts small** (`1 << 20` vertices, `gfx.rs:4495-4500`, about 24 MiB at a 24-byte stride) and grows by doubling or by `PAGE_BYTES`, then shrinks via `oversized`/`sparsest`. The shrink and compact thresholds (64 MiB, 128 MiB) are desktop-scaled and may never fire on a phone. On unified memory arena bytes are ordinary RAM. Sizes and thresholds must be tuned from measurement. UNRESOLVED.
3. **Allocator.** `horizon-threads` hard-depends on `mimalloc`. `system-allocator` removes `#[global_allocator]` but still links `libmimalloc-sys` and calls `mi_option_set`, `mi_process_info`, `mi_collect` (`lib.rs:362-412`), so the feature is not a clean mimalloc opt-out. The code records a measured tradeoff: with mimalloc's default purge delay "the game held a quarter more memory than with the system heap"; `purge_delay=0` was chosen. That was measured on desktop, not iOS.
4. **Existing bounded structures** (good): mesh pool 16 MiB / 128 entries (`streaming.rs:357`), sound cache 64 MiB LRU, section copy limit 64 MiB, compaction budget 32 MiB, particles 16,384, custom-sky texel budget 64 MiB, cit_glint 64 MiB.
5. **Existing unbounded or large structures to audit:** `bluemap.rs` tile cache up to 192 MiB and 2048 tiles (a far-terrain feature fed from a web map; should be off on iOS); `MAX_FETCHED_PIXELS` 4096x4096 in `hud.rs:187`; GUI atlas pixels held LZ4-compressed after upload (`hud.rs pack_pixels`, already a memory optimisation).
6. **Worker pool.** `horizon-threads::worker_count()` honours `HORIZON_WORKER_THREADS`. `default_workers()` is every core but one, counting only performance cores on Apple (`sysctl hw.perflevel0.physicalcpu`). Queue depths scale as `workers*3` generation, `workers*4` lighting, `workers*32` meshing (`streaming.rs:1816-2117`). The iPhone 12's A14 is publicly specified as a 6-core CPU with 2 performance and 4 efficiency cores (Apple's published spec; not measured or re-verified here). If that holds and the sysctl is readable, `workers_for(6, 2)` gives `min(6,2) - 1 = 1` worker; if the sysctl is unreadable it falls back to `6 - 1 = 5`. Both outcomes are plausible and both are untested, so the worker count must be set explicitly for iOS. Whether `hw.perflevel0.physicalcpu` is readable by an iOS app is UNRESOLVED.
7. **Render distance** defaults to 12 and goes to 128 (`options_file.rs:92,165`). iOS defaults must be much lower and capped; the right number is a measurement outcome.
8. **Chunk storage is already compact**: palette-compressed containers and `Arc<Section>` copy-on-write (`chunk.rs`). Overworld column is 384 high (24 sections).
9. **No jetsam/memory-warning integration exists** (no `didReceiveMemoryWarning` equivalent, grep found none). Adding a pressure hook that drops caches is high value and low risk.

---

## 9. Compatibility limits

### 9.1 Java mods: not supported, by design (VERIFIED)

`docs/mods.md`: "Fabric and NeoForge jars do **not** run as they are: their code calls and patches Minecraft's Java classes, and Horizon has none." This is true on desktop Horizon already. **No iOS-specific loss.**

### 9.2 Horizon's two mod kinds on iOS

| Kind | iOS viability |
|---|---|
| Content mods `.hmod` (data and assets, no code) | VIABLE. Read at startup. The Android fork supports `.hmod` on 64-bit. |
| Native mods `.hnmod` (mixins applied to Rust source, compiled with cargo by the launcher) | **NOT POSSIBLE on iOS.** No compiler on device; apps cannot load new native code. A fork could only ship mods **compiled into the app binary** at build time. |

I found no embedded WebAssembly engine in `Cargo.lock` (no wasmtime/wasmer/wasmi). Doc text calls mods "sandboxed WebAssembly components" in a Cargo comment, but the `horizon-mods` crate depends only on `wasmparser` (validation). So the doc and the code disagree about whether a runtime exists; treat "WASM mods" as not available. This is a discrepancy worth raising upstream.

### 9.3 Other features to disable or replace on iOS

- Shader packs (OptiFine-style GLSL via naga) and Horizon's `.hshader` packs: heavy and memory-hungry; disable by default.
- Bluemap far terrain, LOD distant horizons: disable until measured.
- Discord Rich Presence (`discord` feature), `friends` tunnel, `heartbeat`/telemetry upload: disable by default. Not an App Store matter any more, but they are network features with privacy implications for users, and they are not needed for the first builds.
- **Clipboard (a real gap, found on the Mac runner's link log).** `arboard 3.7.0` has real backends only for Linux/BSD (X11, Wayland), macOS and Windows. Its Linux branch is gated `all(unix, not(any(macos, android, emscripten)))`, which is **true on iOS**, so the iOS archive contains `arboard`'s X11 backend (`x11rb`, `x11rb_protocol`, `rustix`). It compiles and links, but there is no X server on an iPhone, so `Clipboard::new()` will fail at run time and copy and paste will quietly do nothing (`ClipboardManager` keeps `Option<arboard::Clipboard>` and treats failure as no clipboard, so it will not crash). Fix: an iOS `UIPasteboard` backend behind `ClipboardManager` in `horizon-client-input/src/clipboard.rs`, and keep `arboard` out of the iOS graph. Not done yet. UNRESOLVED whether upstream would take it.
- Narrator: compiles to no-op on iOS; could be mapped to `AVSpeechSynthesizer` later.
- DualSense output: already excluded on iOS by upstream.
- Controllers: `gilrs` on iOS needs checking; Apple's GameController framework is the native way. UNRESOLVED.
- Dedicated server and `horizon-ctl`: out of scope.

### 9.4 Version compatibility

Single pinned version 26.3 (`research-lock.json`), protocol 777. Horizon targets one version at a time; the plan's "version selection" step should be dropped for v1. Older-server bridging exists as opt-in experiments upstream (#8871 for 1.21). Do not promise multi-version.

---

## 10. Testing and benchmarking inventory

### 10.1 Existing assets (VERIFIED)

- Parity harnesses: `tools/test_<name>_parity.py` + Java oracle + Rust probe, run via `tools/parity.py`. They need `.local/` vanilla data and a JDK, so **they run on a Mac/Linux dev machine, not on the phone**.
- `horizon-bench`: report format; `--benchmark SCENARIO` with scenes standard/village/forest/ocean/mountain; metrics include FPS percentiles, resident and GPU memory, chunk load times (`docs/benchmark.md`, `benchmark-report.md`).
- `horizon-ctl`: control socket for driving the game (`launch --offscreen --wait`, `screenshot`, `state`).
- `--smoke-report`, `--frames N` flags for CI.
- Rust integration tests under `crates/horizon-client/tests/` (`streaming_meshes.rs`, `generation_saves.rs`, `lan_bot.rs`).

### 10.2 What this means for iOS

- **Parity must stay on desktop.** The iOS port's correctness argument is: the same Rust crates pass the same parity harnesses on desktop; the iOS-specific delta (platform layer) is small and separately tested. This honours "do not weaken parity tests".
- iOS-specific tests needed: lifecycle (background/foreground), surface recreation, memory pressure, touch mapping, path resolution, auth, resource assembly (hash-verified), thermal behaviour.
- `--benchmark` and `--frames N` are launchable from the Swift shell via arguments or environment, so the **existing benchmark harness can be reused on device** if the shell can pass `--benchmark standard`. The output is written to `benchmarks/` relative to the working directory, so it needs a writable path. Retrieval from device: Xcode "Download container" or Files app sharing.
- Simulator success is not valid evidence (also stated in the plan). The iOS Simulator on Apple Silicon uses a different Metal driver and has no jetsam.

---

## 11. Licensing, policy and review questions requiring human verification

**I make no legal conclusions.** The items below are questions I could not settle from the repository and that someone with authority should check against current primary sources.

### 11.1 What the repository itself states (VERIFIED)

- Code is MIT licensed (`LICENSE`): "Copyright (c) 2026 Ludovic Marie and the Horizon contributors".
- `README.md:76`: "Horizon contains no Minecraft code or assets: an existing install... is reused, and without one the launcher downloads 26.3 from Mojang for your account."
- `README.md:170`: "NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT. Minecraft is a trademark of Mojang Synergies AB; its code and assets belong to Mojang and Microsoft under the Minecraft EULA."
- `CLAUDE.md`: "Never commit Mojang's files: game jars, assets, decompiled source, prepared resources." A CI check rejects them.
- Download behaviour (`docs/microsoft-account.md`): the launcher downloads from Mojang endpoints only after the owner gate, on the player's machine; "CI, agents, harnesses and the repo never download or keep Mojang's files".
- Horizon **decompiles Mojang's code** for reference (`.local/minecraft/26.3/sources`, `tools/lab.py decompile`) and mirrors vanilla's Java signatures "one to one so they can be checked against the decompiled sources" (`Cargo.toml` comment). It also compiles and runs Mojang's code locally for exporters. These are the project's own practices, not yours; whether they affect a derivative is for counsel.

### 11.2 Comparison with your intended approach

| Your stated approach | Horizon's actual approach | Gap |
|---|---|---|
| User must own Java Edition | Owner gate in the launcher; engine binary itself not gated | Same intent; you would reimplement the gate. The gate is a policy control, not DRM |
| Verify ownership before resource acquisition | Entitlement check precedes "Download and prepare" | Same |
| Assets from the user's own download, not our servers | Downloaded from Mojang by the user's device | Same, **provided you do not host tables** (see next row) |
| Do not bundle or host Mojang/Microsoft assets | Horizon hosts nothing of Mojang's today | **Different if you adopt #1750:** published computed tables would be hosted by someone. Upstream maintainer has explicitly flagged this as undecided |
| Independently developed Rust code | Rust rewrite whose method includes studying decompiled sources and running Mojang code as oracles | Your framing ("not redistributed source") matches the repo. Whether derived-behaviour porting from decompiled code affects the independence characterisation is not for me to judge |
| Process resources locally | `horizon-prepare` locally, using Java | Same intent; JVM step is the iOS problem |

### 11.3 Open questions (each needs verification against current primary sources)

**A. Minecraft EULA and Usage Guidelines**
1. Does the current EULA / Commercial Usage Guidelines permit a third-party client that reimplements gameplay and reads user-owned assets? Does it differ for a free app distributed as a downloadable IPA versus a paid or store-distributed one?
2. Naming and branding: can the app's name, icon, store listing and screenshots reference Minecraft? (Trademark.) Horizon avoids the word in its name; you would need the same discipline for the app name, icon and the page the IPA is downloaded from.
3. Is "Java Edition" content licensed to be used on a platform where Mojang sells a different edition (Bedrock) for mobile? (Business question, not legal advice.)

**B. Microsoft / Mojang API terms**
4. Mojang app-ID review (`aka.ms/mce-reviewappid`): criteria, whether a mobile client is accepted, whether approval is per-platform, and expected timeline.
5. Terms for calling `api.minecraftservices.com` entitlements/profile endpoints from a third-party iOS app.
6. Terms for downloading client jars, libraries and assets from Mojang's CDN endpoints in a third-party app, including rate limits and attribution.
7. Whether Microsoft Entra app registration for **personal accounts only**, public client, device-code flow, is acceptable for a sideloaded app, and what redirect URI types are allowed.

**C. Derived data (issue #1750)**
8. Whether "computed tables" derived by executing Mojang's code count as Mojang content for distribution purposes. Upstream says the maintainer decides this. If you host them: who hosts, under whose name, with what takedown plan.
9. If a user's own PC/Mac produces the tables locally and transfers them, does that avoid the question? (Probably the same posture as desktop Horizon today, but confirm.)

**D. Distribution as an IPA (replaces the App Store questions; Apple review does not apply)**
10. **Install method and its limits.** Which route will users take: a personal developer certificate, AltStore or SideStore, Sideloadly, TrollStore, or an enterprise or ad-hoc profile? Each decides how often the app must be re-signed (a free Apple account's certificates last 7 days and limit active app IDs; a paid account's last a year), whether a device must be registered, and whether anything beyond plain signing is available. Needs a decision from you; I will not guess it.
11. **Entitlements.** **Changed by the decision in 6.6:** preparation needs JIT, which on iOS means the debugger-attached route or an install method that grants `get-task-allow` (Amethyst ships sideload and TrollStore entitlement files). The game itself needs none of this. No extended virtual addressing or increased memory limit is assumed. Whether the `com.apple.developer.kernel.increased-memory-limit` entitlement is obtainable and honoured under the chosen install method is UNRESOLVED and matters for a 4 GB phone. Some sideload tools rewrite entitlements; some cannot add ones that need a provisioning profile.
12. **Third-party notices.** The IPA is a binary distribution, so the notices Horizon already maintains (`THIRD_PARTY_NOTICES.md`) and the licences of the iOS-specific dependencies must travel with it (see E).
13. **Where the IPA is hosted** and under what name, given the trademark question in A2. The Android fork's precedent is GitHub releases.
14. **Privacy.** Horizon has opt-in telemetry and a "heartbeat" ping. Not a store-disclosure matter now, but a build that phones home should say so; the simplest answer is to leave them out.
15. **Auto-update.** Without a store there is no update channel. Decide whether the app checks a release page, relies on the sideload tool's refresh, or neither. A self-updater that downloads code would be a design problem; one that only points at a new IPA is not.

**E. Licensing of dependencies**
16a. **The embedded Java runtime.** Amethyst lists Azul Zulu JDK as GNU GPLv2 and Caciocavallo as GNU GPLv2; OpenJDK is normally GPLv2 with the Classpath exception, which would need confirming for the exact build. Open: who built `jre25-ios-aarch64.zip`, from what source, under what terms, and may a different project redistribute it inside its own IPA. I could not retrieve the file or its licence (the host does not resolve from my sandbox).
16b. **Reuse of Amethyst's iOS JVM glue** (launching a JVM in-process, the dyld validation bypass, JIT detection). It is a fork of PojavLauncher; check each component's licence before copying anything, and prefer reading it as a reference.
17. `THIRD_PARTY_NOTICES.md` (18 KB) lists notices; a distributed binary must reproduce them. A license audit of the iOS-specific dependency set (`objc2-*`, `coreaudio-rs`, `cpal`, `ring` OpenSSL/ISC-style terms) was not done.
18. Reuse of code from the Android forks: check their licences before copying anything.

---

## 12. Biggest risks, ranked

| Rank | Risk | Type | Severity | Mitigation |
|---|---|---|---|---|
| 1 | Resource preparation needs a JVM. **Chosen route (6.6): an embedded Java 25 iOS runtime with JIT, on the phone.** Unproven: no one has shown `horizon-prepare`'s exporters running on it, and preparation spawns child JVMs, which iOS forbids | Structural + technical | Blocks everything user-facing | Spike first (roadmap M8a): `java -version`, then one oracle, on the simulator and on the owner's device with timing and peak memory. Fallback: prepare on a machine the owner controls and copy the folder over. #1750 is not relied on |
| 1b | JIT is needed for preparation, so it only works on installs that can enable it (StikDebug, TrollStore, AltStore/SideStore, jailbreak) | Distribution | High | Say so in the app; the game itself needs no JIT. Owner's device and iOS version are not yet stated |
| 2 | Mojang app-ID approval for a new client is outside your control | External | Blocks sign-in | Apply early; use a clearly labelled dev path with `--session-file` for internal testing |
| 3 | 4 GB device memory ceiling with a desktop-tuned engine (256 MiB arena pages, desktop render distances, mimalloc) | Technical | High; unmeasured | Telemetry first (footprint), then tune with data (see memory strategy) |
| 4 | Touch input and mobile UI do not exist | Scope | High effort, low technical risk | Reuse the controller-registration path; Android design as a reference |
| 5 | Lifecycle: surface loss on background, early-return `resumed()` | Correctness | High if missed (crash or black screen) | Implement `suspended`/`resumed` with `recreate_surface`; test on device |
| 6 | Install method and certificate lifetime for an IPA | Distribution | Medium; decides how users keep the app installed | Choose the route (section 11.3 D10); document re-signing for users |
| 7 | Upstream churn: `game.rs` is a 17.8k-line monolith with fast-moving commits; a long-lived fork will conflict | Maintenance | Medium | Keep a minimal delta; upstream the platform fixes as small PRs |
| 8 | C dependencies and link step | Technical | Closed for the library and binary | Verified on a Mac runner (section 3.5); an app bundle and signing remain untested |
| 9 | Process-spawn sites fail at runtime | Technical | Low-medium | Audit and feature-gate |
| 10 | Thermal and battery behaviour under sustained load | Technical | Unknown | Measure; adapt worker count and render distance to `ProcessInfo.thermalState` |

## 13. Required architecture changes (summary)

1. **New:** an iOS shell (Swift) plus a thin `staticlib` crate exposing a C ABI: `start(config)`, `suspend()`, `resume()`, `memory_warning()`, `shutdown()`, and a way to pass the `UIView`/`CAMetalLayer`. (ADR-1 to be written.)
2. **Fix:** B1-B4 above.
3. **Add:** `suspended()` plus a real `resumed()`; surface recreation; cache trimming on memory warning.
4. **Add:** touch input and a mobile HUD/menu layer.
5. **Add:** iOS path resolution (or shell-provided `--home`/`--game-dir`).
6. **Add:** `phys_footprint` telemetry.
7. **Replace for iOS:** resource preparation (no JVM), account sign-in storage (Keychain), launcher UI.
8. **Gate off:** native mods, shader packs, bluemap, Discord, friends tunnel, telemetry upload, dedicated server, `Command::new` sites.
9. **Keep unchanged:** `horizon-core`, `-world`, `-protocol`, `-assets`, `-items`, `-command`, streaming, meshing, the arena renderer (tuned, not replaced), parity harnesses.

## 14. Open questions from the plan (section 11 of the brief), answered

| Question | Answer |
|---|---|
| Which commit and version? | `77af961`, Minecraft 26.3, protocol 777 |
| What share of the workspace builds for iOS? | Unmodified: 30 crates checked in isolation, 21 type-check and 9 fail (of 40 crate folders; 10 were not checked: `cargo-horizon-mod`, `horizon-bots`, `horizon-mod-api-gen`, `horizon-mod-deps`, `horizon-mod-registry`, `horizon-port-pack`, `horizon-prepare`, `horizon-release-sign`, `horizon-server`, `horizon-telemetry-server`; none is needed in the iOS app, though `horizon-prepare` matters for the resource pipeline and `horizon-mod-api-gen` runs as a build script of `horizon-client`). The 9 failures reduce to 2 environment causes (C toolchain: `libmimalloc-sys`, `ring`) and 2 code causes (B1 `arboard`/Wayland, B3 `horizon-hdr`), with B2 and B4 revealed behind them. With B1-B4 plus stubbed C scripts the whole client type-checks |
| Does wgpu expose a suitable iOS surface? | wgpu 30.0.1 with `metal` is enabled and `objc2-metal` is in the iOS graph. The actual `create_surface` path with a UIKit view was **not exercised**. UNRESOLVED, M2 |
| Desktop-only crates? | `arboard` wayland feature, `horizon-hdr` (Vulkan), `horizon-narrator` (no iOS impl), `horizon-dualsense` (already gated), `libloading` use in narrator is Linux-only |
| Can the importer be reused unchanged? | No. It requires a JDK 25 |
| Which downloaded assets does the engine consume? | Not fully traced. The Android fork notes the client jar can be deleted after assembly because "Horizon never reads it". UNRESOLVED for this checkout |
| Which caches are bounded? | See section 8 items 4-5 |
| Minimum iOS version? | Not determined. Depends on wgpu-hal Metal requirements and `objc2` crates. UNRESOLVED |
| Smallest realistic first demo? | Roadmap M2-M4 |
| Auth approvals? | Own Azure registration plus Mojang app-ID review; section 7 |
| iPhone 12 success measurements? | Memory strategy document |

## 15. Conclusion

The port is **technically plausible** and the engine-side delta found so far is small. The difficulty is concentrated in three places that are not engine code: **the Java dependency in resource preparation**, **the missing touch and lifecycle layer**, and **external approvals** (Mojang app-ID, Apple review, and an undecided legal question about derived tables). Proceed, but sequence the work so the technical proofs (milestones M0-M2) come before any investment that depends on those approvals.

Companion documents: `docs/IOS_IMPLEMENTATION_ROADMAP.md`, `docs/IOS_MEMORY_STRATEGY.md`. Evidence: `docs/ios-evidence/`.
