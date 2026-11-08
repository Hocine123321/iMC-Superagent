# Horizon iOS Implementation Roadmap

> **Path convention.** This repository keeps the upstream Horizon snapshot in `horizon/`. Source paths cited below (`crates/...`, `tools/...`, `docs/benchmark.md`, `research-lock.json`, `CLAUDE.md`, ...) are relative to `horizon/`. Paths under `docs/ios-evidence/` and the three `docs/IOS_*.md` files are relative to the repository root.

**Status:** proposal. No implementation has started. Companion to `IOS_FEASIBILITY_REPORT.md` (findings, labels VERIFIED / INFERRED / UNRESOLVED) and `IOS_MEMORY_STRATEGY.md`.
**Base:** `horizon-rust/horizon` `77af961`, Minecraft 26.3, protocol 777.

## Ordering principles

1. **Cheapest technical proof first, external approvals last.** Milestones M0-M5 need no one's permission. Anything that depends on Mojang approval, a maintainer's legal decision, or Apple review comes after the engine is proven on a real phone.
2. **Measure before optimizing.** Footprint telemetry (M2) comes before any memory tuning (M7).
3. **Keep the fork thin and upstreamable.** Each platform fix is a small PR (the project asks for under about 500 lines, one claimed issue each). The iOS shell and the bridge crate are additive.
4. **Parity stays on desktop.** The existing harnesses need a JDK and `.local/` vanilla data. They are the spec and must not be weakened. iOS correctness is argued as "same crates pass parity on desktop, plus a small separately tested platform layer".
5. **Physical device gates.** Nothing is called "iOS support" until a signed build runs on an iPhone. Simulator results are recorded but never count as evidence for performance, memory or Metal correctness.

## Prerequisites (not engineering, but they gate the plan)

| Need | Why | Who |
|---|---|---|
| A Mac with Xcode, current stable | Linking, signing, Instruments, device deploy. This sandbox has no Apple SDK | You |
| An iPhone 12 and a way to install an unsigned IPA (AltStore, Sideloadly, a personal certificate, or similar) | Device builds. No App Store, TestFlight or paid developer programme is assumed | You |
| A second device class (a newer or lower-memory iPhone) if available | One device cannot show spread | You |
| A `.local/horizon-client/26.3` prepared on a PC/Mac | Parity runs and the M3 bootstrap path | You |
| Your own Azure app registration | Needed from M8; Horizon's cannot be reused | You |

## Milestone overview

| # | Milestone | Needs Mac+device | Needs approval | Est. size |
|---|---|---|---|---|
| M0 | Baseline and decision records | Mac | no | small |
| M1 | Upstream-able compile fixes (B1-B4). **Done** (links on a Mac runner) | Mac (to link) | no | small |
| M2 | Staticlib, Swift shell, Metal surface, test scene, footprint telemetry | Device | no | medium |
| M3 | Resource bootstrap from the user's PC and the engine reaching the title screen | Device | no | medium |
| M4 | Lifecycle correctness (background, foreground, memory warning) | Device | no | small-medium |
| M5 | Touch input, minimal mobile controls, playable singleplayer | Device | no | large |
| M6 | Baseline benchmark suite on device | Device | no | small |
| M7 | Memory and thermal tuning from M6 data | Device | no | medium |
| M8a | **Spike: can an embedded Java 25 iOS runtime run `horizon-prepare`?** (decision 2026-11-08) | Device with JIT | no | small, but gates M8b |
| M8b | On-device download and preparation (owner's account, own copy, embedded JVM) | Device with JIT | Mojang app-ID for sign-in; runtime licence | large |
| M9 | Microsoft sign-in and ownership gate | Device | Mojang app-ID | medium |
| M10 | Multiplayer, audio polish, mobile UI | Device | no | large |
| M11 | Distribution as a downloadable IPA | Device | no | small |

The dependency chain is: M0 -> M1 -> M2 -> (M3, M4) -> M5 -> M6 -> M7. M8a can start now and gates M8b; M8b and M9 ship after M5. M10 and M11 follow.

---

## M0. Baseline and decision records

**Objective.** Fix a reproducible starting point and write down the choices that are expensive to reverse.

**Existing components.** `research-lock.json`, `docs/benchmark.md`, `tools/parity.py`, `.github/workflows/ci.yml`.

**Work.**
- Pin the base commit (`77af961`) and record how to rebase on upstream.
- On a Mac, prepare `.local/horizon-client/26.3` with the stock tools and run `python3 tools/pr_ready.py --quick` plus `cargo build --profile fast -p horizon-client` to prove the Mac desktop build and tests are green before touching anything. Record timings.
- Run `--benchmark standard` on the Mac to get a desktop Metal reference for later comparison.
- Write ADRs: ADR-1 app shell and entry point, ADR-2 renderer integration, ADR-3 resource cache and layout, ADR-4 memory policy, ADR-5 supported version (26.3 only), ADR-6 feature set disabled on iOS.
- Create the porting ledger (crate, dependency, change, status, evidence, test, upstreamable).

**Risks.** The Mac baseline may already fail for unrelated reasons (JDK 25 install, `.local` preparation).

**Success test.** A written baseline report with commit, toolchain versions, desktop Metal benchmark JSON, and all ADRs reviewed.

**Depends on.** Prerequisites only.

---

## M1. Upstream-able compile fixes

**Status: done on the Mac runner (see the feasibility report, section 3.5).** B1-B4, the Apple graphics-choice and data-folder checks, and a deployment target of 16.0 make the whole client build and link for `aarch64-apple-ios`. Still open from this milestone: opening the changes as upstream PRs, and a CI job for the desktop tests on macOS.

**Objective.** Make `cargo build --target aarch64-apple-ios` succeed for the engine crates, with changes small enough to merge upstream.

**Existing components and the fixes (all VERIFIED as needed, see the feasibility report section 3 and `docs/ios-evidence/diagnostic-compile-fixes.patch`).**

| ID | File | Change |
|---|---|---|
| B1 | `horizon-client-input/Cargo.toml` | Restrict `arboard`'s `wayland-data-control` feature to Linux |
| B2 | `horizon-client-input/src/keybinds.rs` | On iOS/Android use `logical_key` instead of `key_without_modifiers` |
| B3 | `horizon-hdr/*`, `horizon-client-render/src/gfx.rs` | Replace `target_os = "macos"` gates with `target_vendor = "apple"` |
| B4 | `horizon-threads/src/process_memory.rs` | Gate the `proc_pidinfo` path to macOS; add an iOS path in M2 |

**Also in this milestone.**
- Replace `cfg!(target_os = "macos")` at `graphics.rs:246/1154` with an Apple check after confirming what those branches select.
- Add an iOS arm to `logging.rs::data_dir()` (or document that the shell must pass `--home`).
- Add a CI job that runs `cargo check --target aarch64-apple-ios -p horizon-client --no-default-features` on a macOS runner so the fixes cannot regress. Upstream already has macOS arm64 release builds (`ROADMAP.md`), so the runner exists.
- Open each as its own PR; reference roadmap issue labels `roadmap:phones-and-browser`.

**Risks.**
- `ring` or `mimalloc` fail to build for iOS with Xcode's clang. **Resolved:** both build; the only link problem was the default 10.0 deployment target (`___chkstk_darwin`), fixed by setting 16.0.
- The patched `third_party/wgpu-hal` may need an iOS check of its own.
- Linking may reveal missing frameworks (Metal, QuartzCore, CoreAudio, AudioToolbox, UIKit). **Not seen** in the command-line link; an app link in M2 may still reveal some.
- Upstream may reject or reshape a change. Mitigation: keep each isolated and behaviour-preserving on desktop.

**Success test.**
1. `cargo build --release --target aarch64-apple-ios -p horizon-client-lib` succeeds on the Mac.
2. Desktop tests unchanged: `python3 tools/pr_ready.py --quick` green on Linux and macOS.
3. `python3 tools/parity.py --changed origin/main` shows no parity impact (these changes touch no simulation code).

**Depends on.** M0.

---

## M2. Staticlib, Swift shell, Metal surface, footprint telemetry

**Design decided from the source (VERIFIED, not yet run).** winit's own iOS guide recommends a static library exporting one C function that the app's `main` calls. `EventLoop::run_app` calls `UIApplicationMain` itself on iOS, so the Xcode project must **not** declare its own app delegate: the "Swift shell" is a thin `main` that builds an argv and calls `horizon_ios_main`, plus `Info.plist`, an icon and a launch screen. The engine's startup is already one plain function, `horizon_client::entry::main()`; it reads `std::env::args()` in two places (`entry.rs:19`, `game.rs:678`), so the shell passes `--home <container>/Library/Application Support/horizon --resources <path>` through the real `argv`. The bridge crate must be a member of the `horizon/` workspace, because the patched `wgpu-hal` (with a Metal HDR fix), `naga` and `libmimalloc-sys` are workspace-level `[patch]` entries that a separate workspace would silently lose.

**Objective.** Prove the shape of the whole port with the smallest thing that can honestly be called a result: a signed app on an iPhone 12, Rust running natively, wgpu presenting through Metal, and a number for memory that matches what iOS enforces.

**Existing components.** `horizon-client/src/entry.rs`, `game.rs` (`run_event_loop` at `:17066`), `horizon-client-render/src/gfx.rs` (`Renderer::new`, `open_backend`), `horizon-client-render/examples/` (candidate test scenes), `horizon-threads/src/process_memory.rs`.

**Work.**
1. **Decide ADR-1.** Two options, to be tested rather than assumed:
   - (a) A Swift/UIKit `main` owns `UIApplicationMain`; Rust is a `staticlib` called through a small C ABI.
   - (b) Rust/winit owns `UIApplicationMain`; Swift is used only for native pickers and sign-in.
   Build the smallest spike of each (a window and a clear colour), compare on lifecycle control, input latency and effort, then choose. My expectation is (a), but this is not established.
2. Add a new additive crate (name to be decided with upstream, for example `horizon-ios`) that builds a `staticlib` and exposes `start`, `suspend`, `resume`, `memory_warning`, `shutdown`, and a way to hand over the native view/layer.
3. A minimal Xcode project under `platform/ios/` with Info.plist, entitlements (none special expected), launch screen, and a build phase that runs `cargo build --target aarch64-apple-ios` and links the staticlib.
4. A test scene that does not need Mojang resources. **Verified: the engine cannot provide it.** `--test-terrain` only swaps the world generator; startup still calls `missing_resources` (`game/loading_screen.rs:466`), which refuses to start without `horizon-resources.json` in the resource folder. So the M2 scene must be a small separate wgpu spike (a spinning textured cube using a procedurally generated texture), living in the new iOS crate or an example. Its purpose is only to prove the Swift shell, the Metal surface, the lifecycle seam and the telemetry. It must not be presented as the Horizon renderer.
5. **Footprint telemetry.** Add an iOS implementation of `process_memory` using `task_info(TASK_VM_INFO)` and report `phys_footprint` alongside the existing resident figure. Expose it in the on-screen debug text and a periodic log line. Add `os_proc_available_memory()` (iOS 13+) as the "headroom" figure. Both need on-device confirmation of what they report.
6. Instrument per-category GPU bytes (arena pages, textures, render targets) from wgpu allocation reports where available, reusing the arena's existing `bytes()` accessors (`arena.rs:~245`).

**Risks.**
- wgpu's `create_surface` from a UIKit view with the patched `wgpu-hal` may need changes (UNRESOLVED).
- Main-thread and event-loop ownership conflicts between Swift and winit.
- `required_limits: adapter.limits()` may request something A14 reports but behaves badly with.
- Rust panics crossing the FFI boundary are undefined behaviour; wrap in `catch_unwind`.
- Xcode, code signing and provisioning friction.

**Success test (all on a physical iPhone 12).**
- App installs and launches; Rust executes (log line with `aarch64`, thread count, `worker_count()`, `default_workers()`).
- The adapter log shows the Metal backend and prints device limits and supported features; save this as evidence for section 4.2 of the feasibility report.
- A textured 3D scene renders for 5 minutes with no validation errors.
- `phys_footprint` and `os_proc_available_memory` appear in the log and track a deliberate 200 MiB allocation test (allocate, observe, free, observe).
- Frame-time percentiles logged.

**Depends on.** M1.

---

## M3. Resource bootstrap and title screen

**What a first launch does today (VERIFIED on the iOS Simulator in CI, run 2; see feasibility report 3.5a).**

1. `missing_resources()` finds no `horizon-resources.json` and the engine prints the "prepared game files are missing" text. I had predicted the app would then exit because `no_resources::show` builds a `HudAtlas` from the empty folder first. **The run did not show that:** the first launch reached the renderer (Metal device, surface, pipelines) before the Flat-draw abort, so that screen does start. Whether it draws text is not yet seen, because the same abort happens first.
2. Its only action opens a download page through `packs::open_uri`, which on non-Windows systems calls `open_folder` (the `open` or `xdg-open` programs). iOS has neither (read from source, `packs.rs:42`; not exercised).
3. The text tells the player to use "its launcher" and to run `horizon-prepare`, which is wrong on a phone.

So on iOS the app is its own launcher and M3 must supply the first-run experience itself: where the files are, how to pick them, progress, and errors. The engine's screen is built for a different situation (the launcher always prepared files first) and should not be patched into this role.

**Objective.** Get real prepared resources onto the phone **by the cheapest route, which is a folder prepared elsewhere**, and reach Horizon's title screen. This is deliberately independent of M8: it lets us test real game rendering, memory and input on a device without waiting for the embedded JVM, which is unproven. It is also the fallback if M8a fails.

**Existing components.** `horizon-prepare` (runs on the PC), the engine flag `--resources PATH`, `docs/native-client.md` preparation steps, `horizon-assets`.

**Work.**
- Use the **user's own PC/Mac** to run stock `horizon-prepare`. Transfer the resulting `horizon-client/26.3` folder to the phone through the Files app, AirDrop, or Xcode "Add Files to Container". The Swift shell imports it with `UIDocumentPicker` into the app's private storage, validating a manifest hash.
- Pass `--resources`, `--game-dir`, `--home` from the shell, pointing into `Library/Application Support`, marked excluded from backup.
- Measure what the engine actually reads at runtime versus what `horizon-prepare` writes. The feasibility report left "which assets the engine consumes" UNRESOLVED; the Android fork claims the client jar is never read after assembly. Produce the evidence by tracing file opens during a desktop run (for example `strace -e trace=openat` on Linux, or Instruments' File Activity on macOS), then trim the transfer set if the engine allows it.
- Get from launch to the title screen, then a flat test world (`--test-terrain` can be used here, since resources are now present).

**Risks.**
- The prepared folder is large (sounds alone about 380 MB; Android reports about 500 MiB total). Transfer is slow and the files are Mojang-derived: this path keeps them strictly on the user's own devices, which matches desktop Horizon's posture, but it is a poor product experience and only suitable for development and early testers.
- Startup memory peak while loading models and atlases may exceed jetsam limits before the title screen. That would be the first real memory finding.
- Pipeline compile time on Metal at first launch.

**Success test.**
- Cold launch to title screen on device; record time and peak `phys_footprint`.
- Enter a `--test-terrain` or flat world, walk with a gamepad (a paired controller works before touch exists), place and break a block, quit, relaunch, confirm the save persists.
- Resource cache hash verifies; corrupt a file and confirm the app refuses with a clear message.

**Depends on.** M2.

---

## M4. Lifecycle correctness

**Findings from reading winit 0.30.13 and the engine (VERIFIED in source, not yet run).**

- winit's iOS backend observes `UIApplicationDidReceiveMemoryWarningNotification` itself and delivers it as `ApplicationHandler::memory_warning`, next to `suspended` and `resumed`. **No Swift observer is needed.**
- Four `ApplicationHandler` implementations sit on the startup path, and **none implements `suspended` or `memory_warning`**, so both are silently dropped today: `game/no_resources.rs:91` (`Missing`, the first screen an iPhone user sees without resources), `game/loading_screen.rs:393` (`App`), `game/split.rs:592` (`Split`, which wraps `Game` and must forward every callback), and `game/window_handler.rs:201` (`Game`).
- `Game::resumed` returns early when `self.window.is_some()` (`window_handler.rs:203`), so a return from the background never reaches `recreate_surface()`, which already exists.

**Objective.** The app survives everything iOS does to it.

**Existing components.** `window_handler.rs` (`resumed` at `:202`), `gfx.rs::recreate_surface` (`:5094`), device-lost callback (`:2338`), `game.rs::shut_down`, `streaming.rs` (workers, `IDLE_RELEASE`).

**Work.**
- Implement `suspended()`: stop submitting GPU work, pause the tick or integrated server, pause audio, flush and **atomically save** the world, lower worker activity.
- Rework `resumed()` so a second call with an existing window **recreates the surface** instead of returning early.
- Handle `WindowEvent::Occluded`/`Focused(false)` consistently with iOS semantics.
- Add `memory_warning()` -> drop mesh pool (`streaming.rs:357`), sound cache (`audio.rs:151`), non-visible chunk meshes, call `release_free_memory()` (`horizon-threads/lib.rs:408`), shrink arena pages (existing `Arena::oversized`/`sparsest` logic).
- Audio session: category, interruption and route-change handling in the Swift shell.
- Ensure a termination-while-saving cannot corrupt a world. Check how `pending_save` (`window_handler.rs:274`) and region writes are made atomic.

**Risks.**
- iOS gives little time between `suspended` and process freeze; a slow world save can lose data. Measure the save time.
- `queue.wait()` in `recreate_surface` can block the main thread.
- A device-lost event after long background needs a full renderer rebuild path; Horizon has "failed renderer replacement" handling (`spare_surface`), which should be reused rather than reinvented.

**Success test.** Scripted on device: 50 cycles of background/foreground during play; incoming phone call; Siri; Control Center pull; screen lock; rotate; low-power mode toggle; simulated memory warning (Xcode "Simulate Memory Warning"). No crash, no black screen, no corrupted save, footprint returns toward baseline after warning.

**Depends on.** M2, M3.

---

## M5. Touch input and playable singleplayer

**Objective.** A human can play survival singleplayer on the phone without a controller.

**Existing components.** `horizon-client-input` (keybinds, mouse, gamepad), `game.rs::handle_window_event_inner`, `ui.rs` registering helpers, `hud.rs`/`hud_layout.rs`, `inventory_input.rs`, `options_ui.rs`.

**Work.**
- Add a touch layer that **synthesises existing input actions** rather than forking gameplay: virtual joystick -> movement keys/axis, drag -> `mouse.on_move`, tap/hold -> use/attack/mine, buttons for jump, sneak, inventory, chat, pause. This follows Horizon's own principle that a gamepad is a "route" into the same handlers (CLAUDE.md, "Controllers reach what registers").
- Menus: make registered widgets touch-targetable; drag for sliders and inventory.
- Optional on-screen keyboard bridge for chat, sign editing and world naming (IME hooks already exist: `ime_allowed`, `ime_area` in `window_handler.rs`).
- Safe-area insets for the HUD; scale GUI to a sensible default on a 6.1-inch screen.
- Settings preset "Mobile" (low render distance, fancy graphics off, shader packs off).
- Gamepad support through `gilrs` if it works on iOS, otherwise bridge Apple's GameController framework (UNRESOLVED).
- Design reference: the Android fork's four schemes and custom layout editor. Check its licence before reading its code for reuse; reimplement if there is any doubt.

**Risks.** Large UI surface; input ergonomics are subjective; `game.rs` conflicts with upstream. Keep touch in `horizon-client-input` plus one hook point.

**Success test.**
- Five testers each complete a scripted run (move, mine a tree, craft a table, place blocks, open and close inventory, eat, sleep) without a controller.
- Input-to-photon latency measured with a 240 fps phone camera or Instruments; record it, set no target in advance.
- Existing desktop input tests (`cargo test -p horizon-client-input`) unchanged and green.

**Depends on.** M3, M4.

---

## M6. On-device benchmark baseline

**Objective.** A repeatable set of numbers that every later change is compared against.

**Existing components.** `--benchmark SCENARIO`, `horizon-bench` report format, `horizon-ctl`, `--smoke-report`.

**Work.**
- Run `--benchmark standard|village|forest|ocean|mountain` through the shell with a writable output path; fetch reports from the container.
- Extend the report with `phys_footprint`, `os_proc_available_memory`, thermal state (`ProcessInfo.thermalState`), battery level, low-power-mode flag, GPU bytes by category.
- Add the scenarios from the plan: cold and warm launch, new world to first playable frame, fixed traversal at several render distances, entity-heavy scene, save/load, background/foreground, memory pressure while turning quickly, and a 20-30 minute sustained session.
- Record device model, iOS version, game version, seed, settings, commit.
- Compare against the Mac desktop Metal result from M0 as a sanity ratio, not as a target.
- Amethyst comparison only if you want it, on the same device and world, clearly labelled as indicative.

**Risks.** Thermal throttling makes runs non-comparable; control by starting each run at a recorded thermal state and room temperature, and by recording rather than hiding it. Performance mode differences with the device plugged in.

**Success test.** Three repeated runs per scenario agree within a spread you define after seeing the first set; reports stored in the repository root `benchmarks/ios/` (not upstream's `horizon/benchmarks/`) with the device metadata.

**Depends on.** M5 (or M3 for the non-interactive scenes, which can start earlier).

---

## M7. Memory and thermal tuning

**Objective.** Use M6 data to set budgets and fix the largest, measured contributors. No change without a before/after.

**Existing components.** `gfx/arena.rs` (`PAGE_BYTES`, `COMPACT_MIN_FREE`, `SHRINK_MIN_BYTES`), `streaming.rs` (queue multipliers, mesh pool), `horizon-threads/jobs.rs`, `audio.rs`, `hud.rs`, `options_file.rs` (`MAX_RENDER_DISTANCE`).

**Candidate work (each only if M6 shows it matters).**
- A platform memory profile: arena page size, initial capacity, translucent arena splitting, texture mip policy, render-distance cap, simulation distance, worker count, queue multipliers, sound-cache size.
- Adaptive control: lower render distance or workers when `os_proc_available_memory()` is low or `thermalState` is `.serious`/`.critical`.
- Allocator experiment: mimalloc with different purge settings versus the system allocator on device, using the existing `alloc-census` feature for heap-by-tag. The `system-allocator` feature does not remove the mimalloc dependency today; make it a real opt-out if the data favours it.
- Disable bluemap/LOD/shader packs on iOS builds at compile time (Cargo features) so their code and caches do not exist.

**Risks.** Over-tuning to one device; regressions in desktop behaviour (profile must be platform-selected, not global). Visual quality is subjective, so keep a screenshot comparison set.

**Success test.** For each change: the same M6 scenarios, before and after, on the same device state. Accept it only if the target metric improves without a worse p99 frame time or a parity regression. Targets are defined in the memory strategy document.

**Depends on.** M6.

---

## M8a. Spike: run Java 25 on iOS (decision 2026-11-08)

**Why this exists.** The owner chose to prepare on the phone with an embedded JVM and JIT, as Amethyst does (feasibility report 6.6). That is plausible but unproven for this workload, so it is tested cheaply before anything is built around it.

**Objective.** Answer four questions with measurements: does a Java 25 iOS runtime load and print its version; can it run one real exporter; how long and how much memory does a full preparation take; and how does `horizon-prepare` start a JVM when iOS forbids `fork`/`exec`.

**Existing components.** Amethyst-iOS (reference only; licences unchecked) which builds `java-25-openjdk` from `jre25-ios-aarch64.zip`; `horizon-prepare` (`java.rs` spawns the JVM with `Command::new`, `lib.rs` runs up to 3 to 4 JVMs in parallel via `pool::jobs`).

**Work, in order. Stop at the first failure and record why.**
1. **Obtain the Java 25 iOS runtime. Result so far (CI run 42493576308): the prebuilt zip cannot be downloaded.** `assets.angelauramc.dev` has no DNS record from GitHub's runners either, and the older `crystall1ne.dev/cdn/amethyst-ios/` returns 404. Two ways forward, in order: (a) ask the Amethyst maintainers (their Discord, or an issue on `AngelAuraMC/Amethyst-iOS`) where `jre25-ios-aarch64.zip` is hosted now; (b) **build it**: `AngelAuraMC/angelauramc-openjdk-build`, branch `duy/buildjre17-21-25-ios`, which clones `openjdk/jdk25u` and applies `patches/jre_25/ios/*.diff` (4,700 lines of build and HotSpot patches). Its own CI uses a self-hosted Mac runner; try GitHub's `macos-15` and record whether it builds, how long it takes, and the artifact's size, `release` file and licence files. If neither works, stop: use the fallback.
2. Put it in the app bundle (a test build, not committed to git). Launch `libjvm` in-process through JNI from the Swift or Obj-C shell with the flags Amethyst found necessary (e.g. `-XX:-UseCompressedClassPointers`). Print `java.version`. Run it on the **simulator first** (no JIT needed to learn whether it loads), then on the owner's device.
3. Run **one** oracle from `horizon/` (not all 335) against a test client jar the owner supplies on the device. Confirm output matches the desktop output byte for byte.
4. Make `horizon-prepare` callable as a library: replace `Command::new("java")` in `java.rs` with an in-process call, set `pool::jobs` to 1 so one JVM runs at a time, and time a full `--prepare`. Record peak `phys_footprint`, wall time, and whether iOS kills it (jetsam).

**Risks.** The runtime does not exist at a fetchable address, or is licensed so that it cannot go in our IPA. JIT is required and the owner's install cannot enable it. A full preparation does not fit in memory with one JVM. The wall time is hours. Any of these sends us to the fallback.

**Success test.** A full `horizon-prepare --prepare --complete` runs to completion on the owner's device, its output passes `horizon-prepare --check`, and the resulting folder is file-for-file hash-identical to one prepared on a desktop from the same inputs. Time and peak memory are written into the feasibility report.

**Fallback if it fails.** M3's path becomes the product: the owner prepares on a machine they control, from their own copy, and copies the folder over. Upstream #1750 (`pack-facts`/`assemble`) is not in this checkout and is not relied on.

**Depends on.** M2 (a shell that can host a JVM). Needs the owner's device model, iOS version and JIT method (not yet stated).

---

## M8b. On-device download and preparation

**Objective.** From a clean install, with the owner's Microsoft account and no computer: sign in, download the owner's own Minecraft 26.3, prepare the Horizon resources, reach the title screen. Nothing of Mojang's is committed, hosted or distributed by this project.

**Existing components.** `docs/api/launch-guide.md` (the contract for a third-party launcher, followed here), `horizon-prepare --prepare/--check/--progress json`, `research-lock.json` pins, M8a's embedded JVM.

**Work.**
- **Downloader** (Swift `URLSession` or Rust): Mojang's version manifest (`piston-meta.mojang.com`), then the pinned version JSON, client jar, libraries (Maven layout), asset index and asset objects, and the **server jar** named by `downloads.server`. Verify size and SHA-1 for each, resumable, with progress. Write to `Documents/Horizon/minecraft/` in the layout `--minecraft-dir` expects. The sign-in gates this step; the endpoints themselves are public.
- **Prepare**: call `horizon-prepare --prepare --server-jar ... --minecraft-dir ... --output Documents/Horizon/resources --complete --progress json` through M8a's in-process path; show the JSON `fraction` and `message` lines as a progress screen. Run `--check` before every start.
- **Disk**: the downloaded copy plus the prepared folder is large (sounds alone about 380 MB; Android reports about 500 MiB prepared). Delete or keep the downloaded copy after success; Android's fork deletes the client jar. Measure what the engine reads before choosing.
- **JIT**: detect that JIT is unavailable and say so plainly instead of hanging. The game itself needs none.
- **Updates**: preparation reruns when the Minecraft version, the Horizon build or `OUTPUT_VERSION` changes; each rerun needs JIT again.

**Risks.** Everything listed under M8a. Mojang's CDN terms for third-party apps are unverified (feasibility report 11.3, item 6). Interrupted preparation: `horizon-prepare` publishes only after verifying, so a half-finished folder must not be mistaken for a prepared one.

**Success test.** Clean device, airplane mode off, owner's account: download, verify, prepare, reach the title screen. Interrupt the download and the preparation at random points and resume. Corrupt a file and confirm the hash check refuses it. Compare the final folder with a desktop-prepared one.

**Depends on.** M8a, M9 for the real ownership gate (the downloader can be built and tested first with a developer override).

---

## M9. Microsoft sign-in and ownership gate

**Objective.** Sign the user in, verify Java Edition entitlement, and hand the engine a session, using your own registrations.

**Existing components.** The documented 7-step flow in `docs/microsoft-account.md`; the engine's `--session-file`/`--session-stdin`; the launcher's implementation (separate workspace, desktop-only, not reusable as is).

**Work.**
- Register your own Azure app (personal accounts, public client, device-code enabled) and **apply for Mojang app-ID review**. Do this early since approval takes "days to weeks" (maintainer's note in the doc), even though the milestone ships late.
- Implement the flow in Swift (simplest) or extract an auth crate shared with the launcher (upstreamable but slower).
- Store tokens in the iOS Keychain with a restrictive accessibility class. Never log tokens, matching Horizon's rule.
- Handle expiry, revocation, offline start (the desktop rule: "being offline never blocks a player who passed before"), XSTS error codes (2148916233, 2148916235, 2148916236/7, 2148916238), the child-account case, and no-profile (404).
- Remember that the gate is a **policy control, not DRM**. The engine does not enforce it.

**Risks.** Mojang rejects or delays the app ID; Apple expects "Sign in with Apple" alongside third-party login in some cases (question D12); device-code UX on a phone is awkward (you read a code on the same device that shows the page), so evaluate `ASWebAuthenticationSession` with a custom redirect if Entra allows it.

**Success test.** Fresh install -> sign in -> entitlement confirmed -> profile (name, UUID, skin) shown. Non-owner account is refused with the documented message. Airplane mode after a pass still starts. Sign-out wipes Keychain items. Network trace review shows no tokens in logs.

**Depends on.** M2 (shell), approvals external. Ships before M11.

---

## M10. Multiplayer, audio and mobile UI polish

**Objective.** Complete the feature set that makes it a product.

**Work.**
- Multiplayer to Java servers on protocol 777 using the existing client (`net.rs`, `remote*.rs`). Verify TLS roots on iOS (the `ureq`/`rustls` root store question, UNRESOLVED), the Local Network permission for LAN, and reconnect after background (sockets die on suspend).
- Online-mode join uses the Minecraft session from M9.
- Audio: spatialisation, ducking, silent-switch policy, headphones route.
- Mobile menus, inventory, crafting and the recipe book at touch size; HUD safe areas; landscape and optional portrait.
- Decide the fate of: friends tunnel, Discord, telemetry upload/heartbeat (remove or privacy-label), narrator (AVSpeechSynthesizer), gamepad via GameController.
- Accessibility: Dynamic Type for the native shell; game text scaling; VoiceOver for the shell screens.

**Risks.** Server anticheat treating a touch client as suspicious; a plain scope-creep risk. Cut scope, do not extend.

**Success test.** A 30-minute session on a public server with background/foreground cycles and a network change (Wi-Fi to cellular). Sessions reconnect or fail cleanly.

**Depends on.** M5, M9.

---

## M11. Distribution as an IPA

**Objective.** Get builds to testers and users as a downloadable IPA, and make staying installed painless. No App Store, no TestFlight, no Apple review.

**Work.**
- CI already produces an unsigned `Horizon-unsigned.ipa` (workflow `iOS app`). Add a release workflow that attaches it to a GitHub release with a checksum, so a tagged commit yields a downloadable file.
- Write the install guide for the route you choose (feasibility report 11.3 D10): which tool, how to re-sign, how often, and what to do when a certificate expires. This is the part users will actually hit.
- Include the third-party notices (`THIRD_PARTY_NOTICES.md` and the iOS dependency licences), the "not an official Minecraft product" disclaimer used in `README.md:170`, and no Mojang assets in the IPA.
- Decide the update story (D15): a release page and the sideload tool's refresh, with no in-app code download.
- Release engineering: reproducible build, dSYM files for crash triage, crash reports that exclude tokens, and an update path that does not re-download unchanged resources.
- Answer the Mojang and Microsoft questions (feasibility report A, B, C) with primary sources before publishing widely. Have a human who can take responsibility for legal positions review them. Not publishing through Apple removes Apple's rules, not Mojang's.

**Risks.** Certificate expiry makes the app stop launching until it is re-signed (a usability problem, not a technical one). A sideload tool may strip or refuse entitlements, so any feature that needs one (increased memory limit) must be tested under the real install route. A public IPA that mentions Minecraft invites a trademark complaint; keep the naming discipline.

**Success test.** A tester who has never seen the project installs the IPA on a clean phone using only the written guide, and completes the M5 scripted run.

**Depends on.** M7, M9, M10 and the install-route decision.

---

## Cross-cutting tracks

| Track | Rule |
|---|---|
| Upstream | One PR per fix, claim the issue first, attribution lines, no hardcoded strings, `tools/pr_ready.py` output in the PR. Re-sync weekly; the repo moves quickly (`game.rs` alone is 17.8k lines) |
| Parity | Never edit or skip harnesses. Run `tools/parity.py --changed` for any touch to shared crates |
| Safety of data | Never commit Mojang files; install `git config core.hooksPath .githooks`; keep `.local/` out of the repo |
| Evidence | Every claim in the ledger links a log, a patch, a benchmark JSON or a trace |
| Risk register | Re-rank risks after each milestone using new evidence |

## Smallest end-to-end proof of concept

M0 -> M1 -> M2 -> M3 (with a gamepad). That is an iPhone 12 app (signed by your install tool), Rust engine, wgpu on Metal, real prepared resources from the user's own machine, the title screen and a walkable test world, with honest footprint numbers. It needs no approvals and no hosting, and it answers the three largest open technical questions (Metal surface, startup memory, lifecycle seam). **I recommend stopping after M3 to review before investing in touch (M5) or the legal-dependent milestones (M8, M9).**

## What would change this plan

- If M2 shows wgpu cannot present through a UIKit layer without a deep `wgpu-hal` change, switch to a direct `CAMetalLayer` integration or contribute the fix to wgpu.
- If M3's startup peak exceeds what iOS tolerates before the title screen, memory work (M7) moves ahead of touch (M5).
- If the maintainer declines #1750, M8 becomes "user-side preparation only", which probably limits the product to technical users.
- If Mojang declines the app ID, sign-in is limited to offline/LAN and the project is a hobby build outside a store.
