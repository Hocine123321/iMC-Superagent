# Every change we made inside `horizon/`

Written 2026-11-09, brought up to date 2026-11-10 (after iMC Horizon v37, repo commit `b2fe366`).
**This is the file to open when the upstream Horizon moves and the iOS app has to
be rebuilt on top of the new version.** It lists every difference between the upstream snapshot and
what `horizon/` holds now, why each exists, and how to put it back.

## How this stays true

- **The baseline is commit `fa80441`** ("Move upstream Horizon into horizon/"), the pristine import.
  Everything below is `git diff fa80441 HEAD -- horizon`. At the time of writing that is **63 files,
  +9667 / -92: 19 new files, 44 modified, none deleted.** Only 92 upstream lines are removed or
  rewritten in total; everything else is added.
- **The patches are the exact diff** (generated, not hand-written). When this prose and a patch
  disagree, the patch is right. There are two copies of the same diff:
  - `docs/horizon-changes.patch`: paths start with `horizon/`, for applying inside *this* repo.
  - `docs/horizon-changes-upstream.patch`: the same diff with upstream's own paths (no `horizon/`
    prefix), for applying inside a **clone of upstream Horizon**: `git apply --3way
    /path/to/horizon-changes-upstream.patch`. This is the one to use when upstream moves. (The
    first form does not apply in an upstream clone: every path is wrong there.)

  Both are regenerated together by `tools/horizon_diff.sh --patch`, and `--check` fails if either is
  out of date.
- **`tools/horizon_diff.sh`** regenerates the file list, the stats and the patch, and with `--check`
  fails if this file does not mention a changed path. Run it after any edit under `horizon/`, and
  add the new entry here in the same commit.
- Only the **pristine upstream** is a valid baseline. If `fa80441` is ever lost, take the upstream
  release the import was made from; its version is in `horizon/Cargo.toml`.

## Rule for the future

The standing rule is *never modify `horizon/`*, except minor touch fixes the owner approved on
2026-11-08. Much of what is listed here was made before that rule was written down (the iOS port
could not be built without it) and some of it (the iMC Settings page, Auto Performance, grey-out)
goes beyond a touch fix. They are listed here as the facts they are, not as approved. **Each entry
carries a risk, so you can decide what to keep when you rebase.**

Entries are grouped by what they are for, not by file. Every one of the 63 files appears once, in
the index at the end.

---

## A. Making Horizon build and run on Apple platforms (the port itself)

These are the changes without which the engine does not compile for iOS or opens no window. They are
small, mechanical and mostly `cfg` changes. **Keep all of them.**

### A1. "Apple" instead of "macOS" in platform checks
Upstream treats only `macos` as Metal. iOS is also Metal, so each check became `target_vendor =
"apple"`. (Commits `1b10194`, `5fb3725`, `7bc161f`.)

| File | Change |
|---|---|
| `crates/horizon-hdr/Cargo.toml` | `[target.'cfg(not(target_os = "macos"))'.dependencies]` becomes `cfg(not(target_vendor = "apple"))` (the Vulkan HDR crates do not build for iOS). |
| `crates/horizon-hdr/src/lib.rs` | Three `cfg(... target_os = "macos")` become `target_vendor = "apple"`: `open_vulkan_device`, the body of `set_metadata`, and its `let _ = (...)` fallback. |
| `crates/horizon-client-render/src/gfx.rs` | `open_backend`: the two `cfg`s that pick Vulkan/DX12 vs none. The three `NO_GPU_DRIVER` constants. **`backend_order`: `if os == "macos" \|\| os == "ios" \|\| wgpu_backend`** (`os` is a run-time string, so iOS must be named or no backend is tried). Two test lines for `"ios"`. |
| `crates/horizon-client-render/src/graphics.rs` | `GraphicsApi::choices()` and its test: `cfg!(target_os = "macos")` becomes `cfg!(target_vendor = "apple")`. |
| `crates/horizon-client-render/src/graphics_ui.rs` | `rows()`: the macOS-only removal of two graphics rows becomes `target_vendor = "apple"`. |
| `crates/horizon-client-render/src/logging.rs` | `data_dir()`: the macOS branch also serves iOS (`HOME` is the app container). |
| `crates/horizon-client-render/src/options_ui.rs` | One changed line: the `graphics-api` row is left out when `cfg!(target_vendor = "apple")` (was `target_os = "macos"`). |

**Re-apply:** `grep -rn 'target_os = "macos"' horizon/crates` on the new upstream; each hit that is
about Metal rather than macOS-only APIs gets the same change. New upstream code that mentions macOS
for Metal reasons will also need it.

### A2. Dependencies that cannot build for iOS
- `crates/horizon-client-input/Cargo.toml`: `arboard`'s `wayland-data-control` feature moved to a
  `[target.'cfg(all(unix, not(target_vendor = "apple"), not(target_os = "android")))'.dependencies]`
  table. Without it the Wayland crates are pulled in for iOS and fail. (`9a2f196`)
- **Dependency change.** `horizon/Cargo.lock` gained one `[[package]]` (`horizon-ios-bridge`), see A5.

### A3. Keyboard and memory counters that desktop APIs provide
- `crates/horizon-client-input/src/keybinds.rs` `learn_layout`: `KeyEventExtModifierSupplement` and
  `key_without_modifiers()` do not exist on iOS/Android, so those two lines are `cfg`-gated and the
  logical key stands in. (`476e6ec`)
- `crates/horizon-threads/src/process_memory.rs`: the Apple `resident_bytes` is rewritten on
  `task_info(TASK_VM_INFO)` and adds `footprint_bytes()` (what iOS charges the process) and
  `available_bytes()` (how much more it may use before being ended), with compile-time offset
  asserts for the C struct. **~139 lines.** This is what Auto Performance (section D) reads.
  (`476e6ec`, extended in `179931f`)

### A4. The window must fill the screen
`crates/horizon-client-input/src/window.rs` adds `creation_size(LogicalSize) -> Option<LogicalSize>`
(returns `None` on iOS) and a test. On iOS winit takes `inner_size` as the `UIWindow` frame from the
screen's corner, so a desktop-sized request hangs off the edges. Three call sites use it instead of
`.with_inner_size(...)`:
- `crates/horizon-client/src/game/loading_screen.rs` (`Loading::new`)
- `crates/horizon-client/src/game/window_handler.rs` (`resumed`)
- `crates/horizon-client/src/game/no_resources.rs` (the "no game files" window)

**Re-apply:** wherever upstream calls `Window::default_attributes()....with_inner_size(...)`.
(`05cda51`)

### A7. The game window is landscape only (iOS), 2026-11-10
`crates/horizon-client-input/src/window.rs`, in `with_horizon_icon` (which every window goes through),
adds under `#[cfg(target_os = "ios")]` a call to winit's `WindowAttributesExtIOS::with_valid_orientations`
with `ValidOrientations::Landscape`. Why: the launcher is portrait (M24), so the app's Info.plist now lists
portrait as well as the two landscapes, and winit's default for a window is "landscape and portrait", which
would let the game turn upright. **7 lines, iOS only, no dependency change** (winit's own `platform::ios`).
**Re-apply:** in whatever upstream function builds every window's attributes. **Risk:** low; desktop builds
do not compile it. (Owner approved editing `horizon/` on 2026-11-10.)

### A5. The bridge crate (the C entry point the iOS app calls)
- **New** `platform/ios-bridge/Cargo.toml` (19 lines) and `src/lib.rs` (45 lines): a `staticlib`
  exporting `horizon_ios_main`; it hands the shell's crash-reporter function to
  `gfx::BREADCRUMB` and calls `horizon_client::entry::main_with`.
- `Cargo.toml` (workspace): `"platform/ios-bridge"` added to `members`.
- `Cargo.lock`: the `horizon-ios-bridge` package entry (depends on `horizon-client`, `horizon-mods`,
  `horizon-threads`).
- **Dependency change.** No external crate was added, only a workspace member. (`c72587e`)

**Re-apply:** copy the folder, add the member, let cargo regenerate the lock.

### A6. Flat draws need `INDIRECT_EXECUTION`
`crates/horizon-client-render/src/gfx/flat.rs`: `supported()` now calls a new `flags_allow()` that also
requires `DownlevelFlags::INDIRECT_EXECUTION` (the iOS Simulator's Metal device lacks it and wgpu
ends the game with a validation error). One test added. (`8e57af9`)

---

## B. Not overflowing iOS's 1 MB main-thread stack

Upstream builds a `Game` (hundreds of KB) by value and passes it up through several frames; on an iOS
main thread that overflowed three times. These changes only **move values to the heap and stop
inlining**, with no change in behaviour. Full story: `docs/IOS_CRASH_STACK.md`. **Keep all of them;
without them the app crashes at the title screen.** (`2be345f`, `a7a563d`, `5148c6e`, `ccecac4`,
`fb4270e`)

| File | Change |
|---|---|
| `game.rs` | `Game::new` now calls a new `#[inline(never)] fn new_boxed(...) -> Result<Box<Self>>` and returns `*boxed`; the struct literal became `Box::new(Game { ... })`. `run_with()`'s tail was split into `#[inline(never)] fn run_synchronous(...)`. `run_event_loop(*game)`. |
| `game/loading_window.rs` | `start_game` returns `Result<Option<Box<Game>>>` and calls `Game::new_boxed`. `build_renderer` is `#[inline(never)]`. |
| `game/loading_screen.rs` | `Loading::finish` is `#[inline(never)]`, returns `Option<Box<Split>>`, and is split into `finish` / `finish_game` / `finish_started`, with the new `start_boxed`, `boxed_split` and a `Handoff` struct. `set_ui` is `#[inline(never)]`. `Step::Ready(game)` takes the box directly. |
| `game/startup_menu.rs` | One `#[inline(never)]` on a `Loading` method that reaches `set_ui`. |
| `game/split/players.rs` | `boxed()` takes `Result<Option<Box<Game>>>` and no longer boxes again. |

Also in `loading_screen.rs` and `gfx.rs`: **breadcrumbs.** `gfx::BREADCRUMB` (a `OnceLock<fn(&str)>`)
and `gfx::breadcrumb(step)` are added to `gfx.rs`, and called at `set_ui` / `finish` stages so a
crash report from a phone says where it stopped. They do nothing unless the bridge sets them.

**Re-apply:** this is the hardest section, because it follows upstream's structure. Re-do it by
intent: measure the startup stack (CI fails a build over budget, `tools/` check), and box/split
until it passes. The patch will conflict wherever upstream reshaped `finish` or `start_game`.

---

## C. Touch (the finger as an input device)

### C1. New files (copy as they are)
| File | Lines | What it is |
|---|---|---|
| `crates/horizon-client-input/src/touch.rs` | 1164 | Pure finger state machine: stick, look, tap/hold attack, double-tap jump, hotbar slots, menu gestures (tap on lift, slide, scroll, long press), the surface mapping `to_surface`. 74-test crate with `imc_settings.rs`. |
| `crates/horizon-client/src/game/touch.rs` | 896 | The glue: winit `Touch` event to `touch.rs`, on-screen buttons (`PADS`), hit rectangles, drawing, pointer events fed to the normal mouse path, auto sprint, the per-press log. |
| `crates/horizon-client/src/game/lifecycle.rs` | 47 | `app_suspended` (save on going to the background) and `app_memory_warning`. |

### C2. Hooks into existing files
| File | Change |
|---|---|
| `crates/horizon-client-input/src/lib.rs` | `pub mod auto_performance;`, `pub mod imc_settings;`, `pub mod touch;` |
| `game.rs` | `mod auto_performance; mod touch; mod lifecycle;` and three `Game` fields (`touch`, `last_suspend_save`, `auto_performance`) with their initialisers in `new_boxed`. `self.draw_touch_controls(&mut batch)` in the HUD draw. At the top of `handle_window_event`: `if let WindowEvent::Touch(touch) = &event { self.touch_event(event_loop, touch); return; }` |
| `game/window_handler.rs` | `self.touch_frame(event_loop); self.auto_performance_frame();` per frame, and `ApplicationHandler::suspended` / `memory_warning` forwarding to `lifecycle.rs`. |
| `game/split.rs` | The same two `suspended` / `memory_warning` forwards on `Split`. |
| `game/loading_screen.rs` | `App::suspended` / `memory_warning` forwards. |
| `game/pad.rs` | `set_injected_left(stick)` added (the steering stick writes the virtual controller's left stick), and `pad_cancel_inputs` made `pub(super)`. Changed again in I2: touch now writes `Pads::touched`. |

**Known open problem (2026-11-09):** the on-screen buttons are hit a little left and up of where they
are drawn. The cause is **not found**. Measured: hit and drawn rectangles differ by 0 to 2 px only.
`touch.rs` logs `touch button: ...` for every press so the real offset can be read from
`latest.log`, and iMC Settings has *Button shift X/Y* to compensate. If a rebuild fixes it, delete
the shift and the log line.

---

## D. iMC Settings page (the iOS app's own settings, `horizon-imc.txt`)

> **Partly superseded by section O (2026-11-10).** The two new files and the `settings.rs`, `lib.rs` and `graphics_ui.rs` (`blocked`) hooks below are current. The `options_ui.rs` hooks that created `Page::Imc` and its button on Horizon Settings were removed; the page is now `Page::GraphicsImc` inside Video Settings (section O). Do not re-apply the old `Page::Imc` / `Act::Imc` hunks.

**This section goes beyond "minor touch fixes".** It adds a whole settings page inside the engine's
options screen, following the existing Horizon Settings / PvP page pattern. Risk: **high** (it edits
the large `options_ui.rs`, and every upstream change to that file can conflict).

### D1. New files
| File | Lines | What it is |
|---|---|---|
| `crates/horizon-client-input/src/imc_settings.rs` | 1049 | `Item` (22 settings; `Item::ALL`), `ImcSettings` (parse/serialize `horizon-imc.txt`, `cycle`, `reset`, `apply` into `Touch`), the heavy-setting `Cost` notices. Defaults equal what touch had before settings existed. |
| `crates/horizon-client-render/src/ios_unused.rs` | 267 | The classifier behind "Grey out unused settings": keyboard, mouse, window and desktop-only options, by stable name. |
| `crates/horizon-client-render/src/mobile_preset.rs` | 131 | The **Mobile preset** button's function: the engine's Performance preset plus battery mode, 60 FPS with vsync, no view bobbing, and no upscaling, HDR or frame generation. Only sets values; 6 tests. |

### D2. Hooks into existing files
| File | Change |
|---|---|
| `crates/horizon-client-render/src/lib.rs` | `pub mod ios_unused;`, `pub mod mobile_preset;` |
| `crates/horizon-client-render/src/settings.rs` | `pub imc: ImcSettings` on `Settings`, its default in three constructors, loaded from `horizon-imc.txt` beside `options.txt`, cloned, and saved (only when changed or the file exists). |
| `crates/horizon-client-render/src/graphics_ui.rs` | In `Item::blocked`: when `s.imc.grey_unused`, return the reason from `ios_unused::opt / graphics / extra`. |
| `crates/horizon-client-render/src/options_ui.rs` | **17 hunks: 16 pure insertions (4 of them in `mod tests`) and the one-line A1 change.** `Page::Imc` and its entry button; `Act::Imc(Item)`, `Act::ImcReset`; a perf-status field; the button builder for iMC items (36 lines); tooltips (`horizon_page_tooltip`, `tooltip_text`); the page's rows (95 lines: header, Buttons rows, Auto Performance block, heavy-setting notices); click handling; the grey-out check for `Opt`/`Act` buttons; and tests (every item has a button, a click cycles and saves). |
| `crates/horizon-client/assets/horizon/lang/en_us.json` | **53 added keys, none removed or changed:** 50 `horizon.imc.*` (one caption and one `.tooltip` per setting, plus headers, notices and costs) and 3 `horizon.pages.*` (`imc`, `imc.tooltip`, `open.imc`: the page's title, tooltip and entry button). The tests compare English text in the Rust source to this file, so they must match exactly. |

**Re-apply:** copy the two new files, then re-insert the `options_ui.rs` hunks by finding the same
anchors (`enum Page`, `enum Act`, `fn horizon_page_tooltip`, the page row builder, the click `match`).
`git diff -U3` of that file in the patch shows each anchor.

The settings, in page order: On-screen buttons, Look speed, Stick size, Steering area, Hold to mine,
Double tap to jump, Grey out unused settings, **Menu touch**, **Button shift X, Y**, Auto sprint,
Touch shift X, Y, Screen margin, then the Auto Performance block. `docs/IMC_SETTINGS.md` has the
values.

---

## E. Auto Performance (memory governor)

Polls the process's memory every 5 s and caps render distance, far terrain and resolution when the
system is short, without changing the player's saved settings. Risk: **medium** (it touches the
render-distance paths).

### E1. New files
| File | Lines |
|---|---|
| `crates/horizon-client-input/src/auto_performance.rs` | 510 (the pure policy, 55 tests) |
| `crates/horizon-client/src/game/auto_performance.rs` | 106 (the watcher: `auto_performance_frame`, `capped_render_distance`, `capped_resolution_scale`, `auto_performance_status`) |

### E2. Hooks (each replaces one read of a setting with its capped value)
| File | Change |
|---|---|
| `game.rs` | `server.set_distances(...)` now takes `capped_render_distance()` and a simulation distance held to it while capped. |
| `game/render_settings.rs` | `streaming.radius` uses the capped distance, and the LOD distance uses `auto_performance::capped(...)`. |
| `game/remote.rs` | Three `streaming.radius = self.settings.render_distance` become `self.capped_render_distance()`. |
| `game/dedicated.rs` | One read becomes `capped_render_distance()`. |
| `game/options.rs` | `self.ui.options.perf_status = self.auto_performance_status();` and the resolution scale uses `capped_resolution_scale()`. |

**Re-apply:** `grep -n "settings.render_distance" horizon/crates/horizon-client/src/game/*.rs` and
swap each read that sizes streaming for `capped_render_distance()`.

---

## I. Touch controls editor, Back button, controller hints (2026-11-09)

> **Partly superseded by section O.** `Act::TouchEditor` and its handler were removed from `options_ui.rs`; the editor is opened from the iMC page in Video Settings, and leaving it returns there (`Page::GraphicsImc`). The new files and the other hooks are current.

Three things that were wrong on the phone, fixed together because they share files.

### I1. New files (copy as they are)
| File | Lines | What it is |
|---|---|---|
| `crates/horizon-client-input/src/touch_layout.rs` | 728 | Pure: where each on-screen button sits (`Slot`: move, scale, opacity, shown), saved as the **difference from the built-in layout** in `horizon-touch-layout.txt` (an unedited layout writes nothing and places every button bit-for-bit as before). Also `back` (the Back button's rectangle and what a tap does) and `editor` (the panel's rectangles and the size/opacity steps). 27 tests. |
| `crates/horizon-client/src/game/touch_editor.rs` | 475 | The editor screen: the real buttons drawn on a dimmed stage, drag to move, a panel on the right (size, fade, hide, reset, Cancel, Done). Cancel puts back the arrangement it opened with. |

### I2. Hooks into existing files
| File | Change |
|---|---|
| `horizon-client-input/src/lib.rs` | `pub mod touch_layout;` |
| `horizon-client-render/src/settings.rs` | `touch_layout: ControlLayout` on `Settings`: default in two constructors, cloned in `with_option`, loaded from `horizon-touch-layout.txt` (both `match` arms), saved only when changed or the file exists. |
| `horizon-client-render/src/options_ui.rs` | `Act::TouchEditor` and `Event::TouchEditor`; the *Edit touch controls* button on the iMC page (greyed outside a world: the editor needs the view); its tooltip; the two click handlers. Also `Act::MobilePreset` (the *Mobile preset* button beside it, working anywhere), its tooltip, two click handlers and one arm in the test that names every `Act`. |
| `assets/horizon/lang/en_us.json` | `horizon.imc.editor` and `horizon.imc.editor.tooltip`, `horizon.imc.mobile` and `horizon.imc.mobile.tooltip` (4 keys). |
| `game.rs` | `Screen::TouchEditor` (+ its name), `mod touch_editor;`, the `ime_hidden` and `touch_editor` fields, the draw arm, and the editor's three pointer hooks (drag, press, release) beside the HUD editor's. |
| `game/touch.rs` | **Back button** (`touch_back_*`): drawn over the inventory, creative, chat, command block, block editor, signs and books, which a phone cannot close by key. A finger that goes down on it is kept from the pointer and fires on lift; the first tap puts the phone's keyboard away, the next leaves like Escape. **Layout:** `pad_rect` places every button (hit test and drawing both use it), `faded` for opacity. Helpers exported for the editor. 5 tests. |
| `game/ime.rs` | `sync_ime` honours `ime_hidden`, so Back can put the keyboard away while the text box keeps its text. |
| `game/pad.rs` | **Controller hints.** Touch now writes its buttons and steering into `Pads::touched`, not `injected`. `state` still includes it (touch plays as before) but the "pad in use" check does not, so a finger no longer turns on the controller glyphs, the menus' controller focus, or the engine's own on-screen keyboard (which stacked on the phone's). `virtual_input` counts `touched` so input still reaches the game. |
| `game/agent.rs`, `game/control.rs`, `game/debug_options.rs`, `game/pad_menu.rs`, `game/play_keys.rs`, `game/pointer_capture.rs`, `game/screens.rs`, `game/options.rs`, `game/startup_menu.rs` | One arm each for the new `Screen::TouchEditor` / `Event::TouchEditor`, next to `HudEditor`'s: its name for the agent and control APIs, no blur, controller pointer screen, Escape cancels, pointer released, the options event opens it. |

**Re-apply:** copy the two new files, add `Screen::TouchEditor` and let the compiler list every
`match` that needs an arm (each is one line beside `HudEditor`), then re-do the `pad.rs`, `ime.rs`
and `touch.rs` hunks by their anchors.

---

## J. Touch calibration, Back on the title menus (2026-11-09)

> **Partly superseded by section O.** `Act::TouchCalibrate` and its handler were removed from `options_ui.rs`; the iMC page in Video Settings has the Calibrate touch button. The new files and the other hooks are current.

Two fixes for the phone: a touch that lands off the button, and title pages with no way back.

### J1. New files (copy as they are)
| File | Lines | What it is |
|---|---|---|
| `crates/horizon-client-input/src/touch_calibration.rs` | 260 | Pure: five target positions, a least-squares fit of shift and stretch (per axis) from the player's taps, `apply` to correct a point, and the file text (`horizon-imc-touch-calibration.txt`). An unfitted calibration is the identity and writes nothing. Refuses a run whose taps are too close together to tell shift from stretch. |
| `crates/horizon-client/src/game/touch_calibration.rs` | 155 | The screen: five crosses to tap one after another, the result kept, and a log line per tap (reported point against target) so the real cause of an offset can be read off a log. |

### J2. Hooks into existing files
| File | Change |
|---|---|
| `horizon-client-input/src/lib.rs` | `pub mod touch_calibration;` |
| `horizon-client-render/src/settings.rs` | `touch_calibration` on `Settings`: default in the constructors, cloned in `with_option`, loaded from the file beside `options.txt`, saved only when it is not the identity or the file exists. |
| `horizon-client-render/src/options_ui.rs` | `Act::TouchCalibrate` and `Event::TouchCalibrate`; the *Calibrate touch* button beside *Reset* on the iMC page; its tooltip; the two click handlers. |
| `assets/horizon/lang/en_us.json` | `horizon.imc.calibrate` and `horizon.imc.calibrate.tooltip`. |
| `game.rs` | `mod touch_calibration;` |
| `game/options.rs`, `game/startup_menu.rs` | One arm each for `Event::TouchCalibrate` (options opens the screen; the title menu ignores it, like the editor). |
| `game/touch.rs` | `Touch::calibrating` (+ `Calibrating`); while it is set a finger is a sample and nothing behind it hears of it; the correction is applied to every touch before it is read; `touch_safe_area` is `pub(super)`. **Back button:** `touch_back_visible` now also shows on the title screen for every page but the first, and for Options opened from the title. |

**Re-apply:** copy the two new files, add the `Act`/`Event` variants and let the compiler list each
`match` that needs an arm, then re-do the `settings.rs` and `touch.rs` hunks by their anchors.

---

## K. Extra on-screen buttons (2026-11-09)

> **Status 2026-11-10.** The owner decided to stop developing custom extra buttons, so no more work goes into this. The code stays and works: the *Extra buttons* button on the iMC page (section O) still opens this page, and the buttons are off until switched on. If you rebase and want less to carry, K is the easiest whole section to drop: remove `touch_extras.rs`, `Page::TouchButtons`, `Act::TouchExtra*`, the `PadKind` extras in `touch.rs` and `touch_editor.rs`, the six appended names in `touch_layout.rs` and the 17 language keys.

Chat, F3, F2, View and two keys the player picks, as buttons on the screen. Each presses a key of the
game by the name of the binding, so the player's own choice counts (Chat presses whatever `key.chat` is
bound to). All off until switched on.

### K1. New files (copy as they are)
| File | Lines | What it is |
|---|---|---|
| `crates/horizon-client-input/src/touch_extras.rs` | 378 | Pure: which extras are on, the two picked keys, the list of keys a click steps through (`CHOICES`, each checked against the game's own key table), the file text (`horizon-imc-buttons.txt`). A key name is accepted only if it is `key.keyboard.` plus lower case letters, digits, dots and underscores, because it ends up in a control line. 11 tests. |

### K2. Hooks into existing files
| File | Change |
|---|---|
| `horizon-client-input/src/lib.rs` | `pub mod touch_extras;` |
| `horizon-client-input/src/touch_layout.rs` | `COUNT` 10 to 16, `EXTRA_FIRST`, six names appended to `NAMES` (appended, so an older layout file reads the same). 2 tests. |
| `horizon-client-render/src/settings.rs` | `touch_extras` on `Settings`: default in the constructors, cloned in `with_option`, loaded from the file beside `options.txt`, saved only when changed or the file exists. |
| `horizon-client-render/src/options_ui.rs` | `Page::TouchButtons` (title, tooltip, rows), `Act::TouchExtra(Extra)` and `Act::TouchExtraKey(Extra)` with their two click handlers each, tooltips, the id used by the agent API, and the *Extra buttons* button on the iMC page. |
| `horizon-client-render/src/ios_unused.rs` | `TouchButtons` in the "page is used" arm. |
| `assets/horizon/lang/en_us.json` | 17 keys: `horizon.imc.extra_buttons`, `horizon.pages.touch_buttons(.tooltip)`, `horizon.imc.header.extra_buttons`, and a caption and tooltip for each button and the key setting. |
| `game/touch.rs` | The pad list is now `pad_kinds()`: the nine fixed pads, then the extras that are on (`PadKind`). Hit test, drawing and the nearest-button log use it; the hotbar slots follow the pads' count. An extra presses its key once with `touch_extra_key` (the control line `key <name> tap`, through `replay_line`); `held_button` is `None` for an extra so nothing is left held. Extras stand in a column down the left edge under Pause. 4 tests. |
| `game/touch_editor.rs` | Works on `PadKind` instead of a pad index, so the extras can be moved, resized and hidden like the others. |

**Re-apply:** copy `touch_extras.rs`, grow the layout, add the `Page`/`Act` variants and let the
compiler list each `match` (one in `ios_unused.rs`), then re-do the `touch.rs` and `touch_editor.rs`
hunks: every place that counted `PADS` now asks `pad_kinds()`.

---

## L. Touch editor overhaul (2026-11-09)

The touch controls editor now has sliders for size and fade, snapping with guide lines, a panel that
folds to a tab, named layouts, and red frames on buttons that overlap or leave the safe area.

### L1. New file (copy as it is)
| File | Lines | What it is |
|---|---|---|
| `crates/horizon-client-input/src/touch_editor_tools.rs` | 782 | `snap` (screen edges and middle, a grid, other buttons' edges; guide lines returned; never off screen), `problems` (overlaps and the safe area; hidden buttons ignored), `Presets` (Default, Left-handed, Compact built in, up to 6 saved, a `[name]` file format, `horizon-touch-presets.txt`), `panel2` (the panel's places folded and open, fitting an iPhone 12 in landscape at 422 x 195 units, and the slider maths in 5 % steps). 31 tests. |

### L2. Hooks into existing files
| File | Change |
|---|---|
| `horizon-client-input/src/lib.rs` | `pub mod touch_editor_tools;` |
| `horizon-client-render/src/settings.rs` | `touch_presets` on `Settings`, loaded from and saved to `horizon-touch-presets.txt` beside the layout file (default in the constructors, cloned in `with_option`, written only when something is saved or the file exists). |
| `game/touch.rs` | `SAFE_SIDE`, `SAFE_TOP` and `SAFE_BOTTOM` are `pub(super)` so the editor draws and checks the same safe area. |
| `game/touch_editor.rs` | Rewritten around `panel2`: state gains `panel_open`, `snap_grid`, `slider`, `preset`, `guides`; a slider follows the finger while it is held; a dragged button is snapped (`tools::snap`) against the other shown buttons; every frame the buttons are checked (`tools::problems`) and a flagged one is framed red; the safe area is outlined. The four entry points in `game.rs` keep their names. The old `touch_layout::editor` module is no longer used by a screen and is left in place. |

**Re-apply:** copy `touch_editor_tools.rs`, add the module line and the `touch_presets` field, make the
three safe constants `pub(super)`, then replace `touch_editor.rs`.

---

## M. Touch attack and use, Enter in chat (2026-11-09)

Two bugs found on the phone, both fixed with the smallest change that reaches them.

**M1. A finger on Attack or Use did nothing.** The engine reads the two triggers from their analog
value (`PadState::triggers`) and drops a trigger whose analog value is below the threshold, whatever
its button bit says. Touch only set the bit, so `key.attack` (right trigger) and `key.use` (left
trigger) never fired: tap to hit, hold to break and the Use button all failed, while Jump (a plain
button) worked. A test reproduced it (`Edges::update` returned no edge for a touch-held trigger).

| File | Change |
|---|---|
| `horizon-client-input/src/gamepad.rs` | `PadState::set_pressed(button, down)`: `set`, and a trigger is also pulled to 1.0 or released to 0.0. A `touch_triggers` test module (5 tests: both triggers press, release, an ordinary button unchanged, any threshold from 0.1 to 1.0). |
| `game/pad.rs` | `inject_button` calls `set_pressed` instead of `set` (touch's only way in). |

**M2. Enter did not send a chat message.** A hardware keyboard on iOS can deliver a key with no
physical code, and the chat screen drops such a key before it sees it. Not yet confirmed on a phone:
the log line below says what actually arrives.

| File | Change |
|---|---|
| `game/key_codes.rs` | `follow_named_keymap` also recovers Enter, Backspace, Tab, Delete, the arrows, Home, End, Page Up and Page Down from the logical key, **only** when the physical key is missing (a known key, such as the numpad Enter, is never overridden). **Return from the iOS keyboard** is also recovered: winit's iOS backend sends every typed key as `Key::Character` text with no physical key, so Return arrives as `"\n"` and never as `Named(Enter)`; the first fix handled only `Named(Enter)` and so did nothing on a phone. A `"\n"` or `"\r"` with no physical key now becomes `Enter`. 5 tests. |
| `game.rs` | In the chat arm, a key event with no physical code is logged (`chat key with no physical code: logical ..., text ...`) and its text is typed by `chat_unplaced_key`. |
| `game/chat.rs` | `chat_unplaced_key(text)`: types the text into the chat box. |

**Re-apply:** add `set_pressed` and its tests, change the one line in `inject_button`, add the
named keys and `unidentified` helper to `follow_named_keymap`, add the `else if` arm in the chat
branch and the `chat_unplaced_key` method.

---

## N. Cursor mode (2026-11-10)

A trackpad-style pointer for menus: the finger moves a drawn cursor by its travel instead of being
the pointer. A tap clicks where the cursor is, holding still is a right click, tap then drag holds
the left button, two fingers scroll. A Cursor/Touch button under Back switches it, and iMC
Settings > Cursor has "Cursor in inventory" (off by default) and "Cursor speed". Written and
unit tested for the pure part; the game glue is checked by the CI build only.

| File | Change |
|---|---|
| `crates/horizon-client-input/src/touch_cursor.rs` | **New**, pure state machine, the switch button's place, `source_for` (the switch wins; the setting only helps in an inventory). 28 tests. |
| `crates/horizon-client-input/src/lib.rs` | `pub mod touch_cursor;` |
| `crates/horizon-client-input/src/imc_settings.rs` | Two `Item`s (`CursorInventory`, `CursorSpeed`, keys `cursorInventory`, `cursorSpeed`), their fields, parse, serialize, `value`, `cycle`, `cursor_speed_scale`. 3 tests. `Item::ALL` is 22. |
| `crates/horizon-client-render/src/options_ui.rs` | A "Cursor" header and one row of the two settings on the iMC page. |
| `crates/horizon-client/assets/horizon/lang/en_us.json` | Header, captions and tooltips for the two settings. |
| `crates/horizon-client/src/game/touch_cursor.rs` | **New**, the glue: state, the switch finger, `cursor_event` (feeds the same `touch_apply` as plain touch), per-frame hold, drawing of the button and the crosshair. |
| `crates/horizon-client/src/game.rs` | `mod touch_cursor;`, the `cursor_mode` field and its default. |
| `crates/horizon-client/src/game/touch.rs` | Calls into the cursor from `touch_event` (after Back), `touch_frame`, `touch_release_all`; `draw_touch_controls` split so the cursor draws last (`draw_touch_pads`); `TouchState::pointer` and `touch_apply` are `pub(super)`. |

**Re-apply:** copy the two new files, then re-do the small hooks by their anchors.

## O. iMC Settings moved into Video Settings (2026-11-10)

The standalone iMC Settings list page (Options > Horizon Settings > iMC Settings) is gone. The same
settings are now a page of the Video Settings screen, after HDR, with the pages that hold Shaders and
Performance: searchable, a cost dot and a description for each row, a group header per block. Written
and unit tested in the render and input crates; the game crate edits are checked by the CI build only.

| File | Change |
|---|---|
| `crates/horizon-client-render/src/graphics_ui.rs` | `Page::Imc` (last; `Page::ALL` is 7), `Item::Imc(imc_settings::Item)` and `Item::ImcDo(ImcDo)` with every `match` on `Item` covered, `ImcDo` (Mobile preset, Edit touch controls, Calibrate touch, Extra buttons, Reset), `Action::Imc(ImcDo)`, the page's rows in five groups (Touch controls, Screen, Cursor, Auto Performance, Presets), and `blocked` greying an Auto Performance choice while it is off. Tests that meant "the last page" now name `Page::Imc`. |
| `crates/horizon-client-render/src/options_ui.rs` | Removed: `Page::Imc`, its row builder, its button on Horizon Settings, its title and tooltip, `Act::Imc`, `Act::ImcReset`, `Act::TouchEditor`, `Act::TouchCalibrate`, `Act::MobilePreset`, their tooltips and four click handlers. Added: `Page::GraphicsImc` (the Video screen opened on its iMC page), its arms beside `GraphicsHdr`, and the `Action::Imc` handler in `graphics_events` (the four old actions, plus `Extra buttons` pushing `Page::TouchButtons`). The old page test became "every item is a row of the iMC page, and Horizon Settings has no button for it". |
| `crates/horizon-client-render/src/ios_unused.rs` | `GraphicsImc` in the "page is used" arm (replaces `Imc`). |
| `crates/horizon-client/assets/horizon/lang/en_us.json` | Ten keys: the page name and its about line, the group headers that had no key, one blocked reason, and the tooltips of Extra buttons and Reset. |
| `crates/horizon-client/src/game/touch_editor.rs` | Leaving the editor reopens `Page::GraphicsImc` (was `Page::Imc`). |
| `crates/horizon-client/src/game/control.rs` | The control socket's options page name `graphics-imc`. |

Sections D, I, J and K name `Page::Imc`, `Act::Imc` and the old buttons; they are replaced by this
section. **Re-apply:** the `graphics_ui.rs` additions are self-contained; let the compiler list each
`match` on `Item` and `Page`.

## P. Play without closing the app: the hold (2026-11-11, M24 stage 3, step 1)

The engine can now be started with the app and told to wait for Play before it reads any game file.
**Off unless the iOS shell arms it** (`launcher.txt` `inProcessPlay:true`, default off): every other
build and run, including desktop, behaves exactly as before. This is step 1 of `IN_PROCESS_PLAY_DESIGN.md`
(start, wait, load on Play). **Not in this step:** returning from the game to the launcher (`App::Idle`,
Quit Game). Written and unit tested in the input crate (4 tests); the other edits are type checked on Linux
(`cargo check -p horizon-client --no-default-features`) and compiled for iOS by CI only.

| File | Change |
|---|---|
| `horizon/crates/horizon-client-input/src/ios_hold.rs` | **New, 252 lines with tests.** A process-wide state (`Disarmed`, `Waiting`, `Released`, `Cancelled`) behind a mutex and condvar: `arm`, `armed`, `play`, `cancel`, `state`, `wait_for_play`. No unsafe code, no dependency. |
| `horizon/crates/horizon-client-input/src/lib.rs` | `pub mod ios_hold;` |
| `horizon/crates/horizon-client/src/client_lib.rs` | `pub use horizon_client_input::ios_hold;` so the bridge reaches it as `horizon_client::ios_hold` and `Cargo.toml` and `Cargo.lock` do not change. |
| `horizon/crates/horizon-client/src/game/startup_menu.rs` | `spawn_loader`: the loader thread first calls `ios_hold::wait_for_play()`. Unarmed it returns at once. If the hold is cancelled it sends `Done(Err)` and ends. |
| `horizon/crates/horizon-client/src/game.rs` | `run_with`: the "prepared files are missing" early return is skipped while the hold is armed (the window must exist first; the launcher only lets Play through with usable files, and the loader fails with its own message otherwise). `Options::read`: the `--session-file` read is skipped while armed. New `Options::apply_late_session`, the same read run after Play. |
| `horizon/crates/horizon-client/src/game/loading_screen.rs` | `Loading::finish` calls `options.apply_late_session()` first (a no-op unless the hold was armed). Why: the engine refuses a session file older than two minutes and the launcher writes it at Play, not at app start. |
| `horizon/platform/ios-bridge/src/lib.rs` | Four exported C functions: `horizon_ios_arm_hold`, `horizon_ios_play`, `horizon_ios_cancel_hold`, `horizon_ios_hold_state`. |

**Re-apply:** copy `ios_hold.rs`, add the two one-line exports, and put the three small hooks where the loader
is spawned, where the missing-files check and the session read are in `run_with` / `Options::read`, and at the
top of `Loading::finish`. **Risk:** low with the hold unarmed (each hook is one `armed()` or `wait_for_play()`
call that returns at once). Armed, the unknown is the phone: whether winit's window is presented behind the
launcher and what the orientation change does.

### P.2 Quit Game request (2026-11-11, step 2a, groundwork only)

Nothing calls it yet, so no behaviour changes. `ios_hold.rs` gains `allow_quit_to_launcher`, `request_quit`,
`take_quit_request` and `rearm_after_quit` (2 more unit tests, 6 in all). The two Quit Game sites call
`ios_hold::request_quit()` first: it answers `true` only when the hold is armed **and** the shell called
`allow_quit_to_launcher` (nobody does), so the process still ends exactly as before. What is NOT written:
the `App::Idle` state that drops the game and shows the launcher, and the bridge export that allows it.

| File | Change |
|---|---|
| `horizon/crates/horizon-client-input/src/ios_hold.rs` | The four functions above and two tests. |
| `horizon/crates/horizon-client/src/game/startup_menu.rs` | `menu_action`: `Action::Quit if ios_hold::request_quit() => {}` before the old arm. |
| `horizon/crates/horizon-client/src/game/world_session.rs` | `title_action`: the same guard before `Action::Quit => event_loop.exit()`. |

### P.3 Orientation while the app waits for Play (2026-11-11, fix for the start-up swap)

Phone test of v43: the app still started in landscape and turned to portrait, and the engine's boot screen showed
for a split second. The engine created its window landscape-only (A7), so an app that waits for Play started in
landscape. Now, while the hold is armed and Play has not been pressed, the window is created **portrait**, like the
launcher over it; the first turn after Play switches it to landscape, once (`WindowExtIOS::set_valid_orientations`).
Unarmed (every other build and run) both calls answer "no" and the window is landscape-only as before.

| File | Change |
|---|---|
| `horizon/crates/horizon-client-input/src/ios_hold.rs` | `window_starts_portrait()` and `take_landscape_switch()` (one unit test, 7 in all). |
| `horizon/crates/horizon-client-input/src/window.rs` | `with_horizon_icon`: iOS window orientation is Portrait while `window_starts_portrait()`, else Landscape as before. |
| `horizon/crates/horizon-client/src/game/loading_screen.rs` | `Loading::about_to_wait`: iOS only, `take_landscape_switch()` then `set_valid_orientations(Landscape)`. |

**Risk:** low unarmed. Armed, untested on the phone: whether the system now starts in portrait, and the switch to
landscape on Play. Only `horizon-client-input` was type-checked for aarch64-apple-ios locally; `horizon-client`
needs Apple's C toolchain (`ring`), so only CI compiles that hook.

## F. Index: all 63 files

`A` = new file, `M` = modified. Section in brackets.

```
M horizon/Cargo.lock                                                     [A5]
M horizon/Cargo.toml                                                     [A5]
M horizon/crates/horizon-client-input/Cargo.toml                         [A2]
A horizon/crates/horizon-client-input/src/auto_performance.rs            [E1]
M horizon/crates/horizon-client-input/src/gamepad.rs                     [M]
A horizon/crates/horizon-client-input/src/imc_settings.rs                [D1, N]
A horizon/crates/horizon-client-input/src/ios_hold.rs                    [P]
M horizon/crates/horizon-client-input/src/keybinds.rs                    [A3]
M horizon/crates/horizon-client-input/src/lib.rs                         [C2, I2, J2, K2, L2, N, P]
A horizon/crates/horizon-client-input/src/touch.rs                       [C1]
A horizon/crates/horizon-client-input/src/touch_cursor.rs                [N]
A horizon/crates/horizon-client-input/src/touch_calibration.rs           [J1]
A horizon/crates/horizon-client-input/src/touch_editor_tools.rs          [L1]
A horizon/crates/horizon-client-input/src/touch_extras.rs                [K1]
A horizon/crates/horizon-client-input/src/touch_layout.rs                [I1, K2]
M horizon/crates/horizon-client-input/src/window.rs                      [A4, A7, P]
M horizon/crates/horizon-client-render/src/gfx.rs                        [A1, B]
M horizon/crates/horizon-client-render/src/gfx/flat.rs                   [A6]
M horizon/crates/horizon-client-render/src/graphics.rs                   [A1]
M horizon/crates/horizon-client-render/src/graphics_ui.rs                [A1, D2, O]
A horizon/crates/horizon-client-render/src/ios_unused.rs                 [D1, K2, O]
M horizon/crates/horizon-client-render/src/lib.rs                        [D2]
A horizon/crates/horizon-client-render/src/mobile_preset.rs              [D1]
M horizon/crates/horizon-client-render/src/logging.rs                    [A1]
M horizon/crates/horizon-client-render/src/options_ui.rs                 [A1, D2, I2, J2, K2, N, O]
M horizon/crates/horizon-client-render/src/settings.rs                   [D2, I2, J2, K2, L2]
M horizon/crates/horizon-client/assets/horizon/lang/en_us.json           [D2, I2, J2, K2, N, O]
M horizon/crates/horizon-client/src/client_lib.rs                       [P]
M horizon/crates/horizon-client/src/game.rs                              [B, C2, E2, I2, J2, L2, M, N, P]
M horizon/crates/horizon-client/src/game/agent.rs                        [I2]
A horizon/crates/horizon-client/src/game/auto_performance.rs             [E1]
M horizon/crates/horizon-client/src/game/chat.rs                         [M2]
M horizon/crates/horizon-client/src/game/control.rs                      [I2, O]
M horizon/crates/horizon-client/src/game/debug_options.rs                [I2]
M horizon/crates/horizon-client/src/game/dedicated.rs                    [E2]
M horizon/crates/horizon-client/src/game/ime.rs                          [I2]
M horizon/crates/horizon-client/src/game/key_codes.rs                    [M2]
A horizon/crates/horizon-client/src/game/lifecycle.rs                    [C1]
M horizon/crates/horizon-client/src/game/loading_screen.rs               [A4, B, C2, P]
M horizon/crates/horizon-client/src/game/loading_window.rs               [B]
M horizon/crates/horizon-client/src/game/no_resources.rs                 [A4]
M horizon/crates/horizon-client/src/game/options.rs                      [E2, I2, J2]
M horizon/crates/horizon-client/src/game/pad.rs                          [C2, I2, M]
M horizon/crates/horizon-client/src/game/pad_menu.rs                     [I2]
M horizon/crates/horizon-client/src/game/play_keys.rs                    [I2]
M horizon/crates/horizon-client/src/game/pointer_capture.rs              [I2]
M horizon/crates/horizon-client/src/game/remote.rs                       [E2]
M horizon/crates/horizon-client/src/game/render_settings.rs              [E2]
M horizon/crates/horizon-client/src/game/screens.rs                      [I2]
M horizon/crates/horizon-client/src/game/split.rs                        [C2]
M horizon/crates/horizon-client/src/game/split/players.rs                [B]
M horizon/crates/horizon-client/src/game/startup_menu.rs                 [B, I2, J2, P]
A horizon/crates/horizon-client/src/game/touch.rs                        [C1, C2, I2, J2, K2, L2, N]
A horizon/crates/horizon-client/src/game/touch_calibration.rs            [J1]
A horizon/crates/horizon-client/src/game/touch_cursor.rs                 [N]
A horizon/crates/horizon-client/src/game/touch_editor.rs                 [I1, K2, L2, O]
M horizon/crates/horizon-client/src/game/window_handler.rs               [A4, C2]
M horizon/crates/horizon-client/src/game/world_session.rs                [P]
M horizon/crates/horizon-hdr/Cargo.toml                                  [A1]
M horizon/crates/horizon-hdr/src/lib.rs                                  [A1]
M horizon/crates/horizon-threads/src/process_memory.rs                   [A3]
A horizon/platform/ios-bridge/Cargo.toml                                 [A5]
A horizon/platform/ios-bridge/src/lib.rs                                 [A5, P]
```

## G. Rebase checklist

### What a rebase costs (tested 2026-11-10, not guessed)

The patch was replayed onto the newest upstream of that day, `horizon-rust/horizon` `1405044`
(2026-11-10), which is **4,309 commits** and 1,091 commits touching our files ahead of the snapshot
`77af961`. Nothing in `horizon/` was touched for the test; it ran in a scratch clone.

| Check | Result |
|---|---|
| Is the baseline really upstream `77af961`? | Yes. All 5,615 files are byte-identical (blob ids compared). |
| Does the patch rebuild `horizon/` from the baseline? | Yes. Applied to `77af961`, the resulting tree hash is identical to `horizon/` here. |
| Did upstream delete or rename a file we modified? | No. All 42 modified files still exist. |
| `git apply --3way` onto `1405044` | **40 of 60 files apply cleanly; 20 conflict (37 hunks).** No file is missing. |

The 20 conflicted files and their hunk counts: `graphics_ui.rs` 7, `game.rs` 6, `options_ui.rs` 5,
`horizon-hdr/src/lib.rs` 2, `settings.rs` 2, and one each in `gfx.rs`, `gfx/flat.rs`,
`en_us.json`, `agent.rs`, `control.rs`, `debug_options.rs`, `no_resources.rs`, `options.rs`,
`pad.rs`, `pointer_capture.rs`, `remote.rs`, `screens.rs`, `horizon-client-input/Cargo.toml`,
`Cargo.toml` and `Cargo.lock`. The ones read in detail were all two sides adding lines in the same
place: upstream's new `Screen::Studio` beside our `Screen::TouchEditor`, `mod hud_room;` beside our
`mod touch_*;`, the workspace member `crates/horizon-addresses` beside `platform/ios-bridge`, and
`wayland-data-control` / `horizon-dualsense` lines in `horizon-client-input/Cargo.toml`. Two need
thought rather than keeping both: `horizon-hdr` (upstream's `set_metadata(device, surface, peak, black)` is
now `set_metadata(device, surface, paper_white, peak, black)` on one side, with our `target_vendor`
change on the other) and `remote.rs` (upstream rewrote the render-distance cap; ours uses
`capped_render_distance()`). This will drift: the numbers above are for `1405044` only.

New upstream things to look at that this test did not cover (it applies text, it does not compile):
`crates/horizon-dualsense` already gates itself with `target_os = "ios"`, so upstream knows about iOS;
any new crate or dependency since `77af961` may need the same Apple treatment as section A.

### The procedure

1. Work in a **clone of upstream**, not in this repo: `git clone https://github.com/horizon-rust/horizon.git`,
   then `git checkout <the commit you want>`.
2. Apply the upstream-relative patch: `git apply --3way /path/to/iMC/docs/horizon-changes-upstream.patch`.
   (`docs/horizon-changes.patch` has `horizon/` in every path and does not apply there.) Git writes
   conflict markers into the 20-ish files above and applies the rest; `git diff --name-only --diff-filter=U`
   lists them.
3. Resolve conflicts section by section using this file: A is mechanical (`target_vendor = "apple"`),
   B is by intent (measure the stack with `tools/check_stack_budget.py`), the hooks are C2, D2, E2, I2 to O.
   Sections D, I and J name hooks that O removed: follow O for those.
4. `cargo test -p horizon-client-input` (touch, settings, Auto Performance, cursor logic) needs no engine
   build. The render and client crates build on CI only.
5. Copy the result into this repo's `horizon/` (replacing it), commit it **as one commit with the new
   upstream commit id in the message**, and change the commit id in `README.md` and the roadmap.
6. **The baseline moves.** `docs/HORIZON_BASELINE` must become the *new pristine upstream import* (commit
   the untouched new upstream first, put that commit id in `HORIZON_BASELINE`, then commit our changes on
   top). Otherwise `tools/horizon_diff.sh` would diff against the old snapshot and list thousands of upstream
   files as ours.
7. Run `tools/horizon_diff.sh --patch` then `--check`, and update this file for anything that moved
   (the numbers in "How this stays true" and the index).
8. The `Cargo.lock` change is one workspace package; if upstream's lock changed, regenerate rather than
   merge, and have the owner approve it (standing rule: no `Cargo.lock` or dependency changes without approval).

## H. Changes not in `horizon/` that depend on it

`platform/ios/` (the app shell, launcher, crash reporter) calls `horizon_ios_main`, reads
`horizon-imc.txt`'s folder, and uses the breadcrumb function. If the bridge's C name or signature
changes, `platform/ios/App/main.m` changes with it. The launcher's own `launcher.txt` is not in
`horizon/`.
