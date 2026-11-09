# Every change we made inside `horizon/`

Written 2026-11-09. **This is the file to open when the upstream Horizon moves and the iOS app has to
be rebuilt on top of the new version.** It lists every difference between the upstream snapshot and
what `horizon/` holds now, why each exists, and how to put it back.

## How this stays true

- **The baseline is commit `fa80441`** ("Move upstream Horizon into horizon/"), the pristine import.
  Everything below is `git diff fa80441 HEAD -- horizon`. At the time of writing that is **51 files,
  +5848 / -77: 12 new files, 39 modified, none deleted.** Only 77 upstream lines are removed or
  rewritten in total; everything else is added.
- **`docs/horizon-changes.patch` is the exact diff** (generated, not hand-written). When this prose
  and the patch disagree, the patch is right. Replay it onto a new upstream with
  `git apply --3way docs/horizon-changes.patch` from the repo root, and fix the rejects by hand
  using the notes below.
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

Entries are grouped by what they are for, not by file. Every one of the 51 files appears once, in
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
| `crates/horizon-client/src/game/touch.rs` | 729 | The glue: winit `Touch` event to `touch.rs`, on-screen buttons (`PADS`), hit rectangles, drawing, pointer events fed to the normal mouse path, auto sprint, the per-press log. |
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

**This section goes beyond "minor touch fixes".** It adds a whole settings page inside the engine's
options screen, following the existing Horizon Settings / PvP page pattern. Risk: **high** (it edits
the large `options_ui.rs`, and every upstream change to that file can conflict).

### D1. New files
| File | Lines | What it is |
|---|---|---|
| `crates/horizon-client-input/src/imc_settings.rs` | 970 | `Item` (20 settings), `ImcSettings` (parse/serialize `horizon-imc.txt`, `cycle`, `reset`, `apply` into `Touch`), the heavy-setting `Cost` notices. Defaults equal what touch had before settings existed. |
| `crates/horizon-client-render/src/ios_unused.rs` | 266 | The classifier behind "Grey out unused settings": keyboard, mouse, window and desktop-only options, by stable name. |
| `crates/horizon-client-render/src/mobile_preset.rs` | 135 | The **Mobile preset** button's function: the engine's Performance preset plus battery mode, 60 FPS with vsync, no view bobbing, and no upscaling, HDR or frame generation. Only sets values; 6 tests. |

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

Three things that were wrong on the phone, fixed together because they share files.

### I1. New files (copy as they are)
| File | Lines | What it is |
|---|---|---|
| `crates/horizon-client-input/src/touch_layout.rs` | 678 | Pure: where each on-screen button sits (`Slot`: move, scale, opacity, shown), saved as the **difference from the built-in layout** in `horizon-touch-layout.txt` (an unedited layout writes nothing and places every button bit-for-bit as before). Also `back` (the Back button's rectangle and what a tap does) and `editor` (the panel's rectangles and the size/opacity steps). 27 tests. |
| `crates/horizon-client/src/game/touch_editor.rs` | 246 | The editor screen: the real buttons drawn on a dimmed stage, drag to move, a panel on the right (size, fade, hide, reset, Cancel, Done). Cancel puts back the arrangement it opened with. |

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

## F. Index: all 51 files

`A` = new file, `M` = modified. Section in brackets.

```
M horizon/Cargo.lock                                              [A5]
M horizon/Cargo.toml                                              [A5]
M horizon/crates/horizon-client-input/Cargo.toml                  [A2]
A horizon/crates/horizon-client-input/src/auto_performance.rs     [E1]
A horizon/crates/horizon-client-input/src/imc_settings.rs         [D1]
M horizon/crates/horizon-client-input/src/keybinds.rs             [A3]
M horizon/crates/horizon-client-input/src/lib.rs                  [C2, I2]
A horizon/crates/horizon-client-input/src/touch.rs                [C1]
A horizon/crates/horizon-client-input/src/touch_calibration.rs    [J1]
A horizon/crates/horizon-client-input/src/touch_extras.rs         [K1]
A horizon/crates/horizon-client-input/src/touch_layout.rs         [I1]
M horizon/crates/horizon-client-input/src/window.rs               [A4]
M horizon/crates/horizon-client-render/src/gfx.rs                 [A1, B]
M horizon/crates/horizon-client-render/src/gfx/flat.rs            [A6]
M horizon/crates/horizon-client-render/src/graphics.rs            [A1]
M horizon/crates/horizon-client-render/src/graphics_ui.rs         [A1, D2]
A horizon/crates/horizon-client-render/src/ios_unused.rs          [D1]
M horizon/crates/horizon-client-render/src/lib.rs                 [D2]
A horizon/crates/horizon-client-render/src/mobile_preset.rs       [D1]
M horizon/crates/horizon-client-render/src/logging.rs             [A1]
M horizon/crates/horizon-client-render/src/options_ui.rs          [A1, D2, I2]
M horizon/crates/horizon-client-render/src/settings.rs            [D2, I2]
M horizon/crates/horizon-client/assets/horizon/lang/en_us.json    [D2, I2]
M horizon/crates/horizon-client/src/game.rs                       [B, C2, E2, I2]
M horizon/crates/horizon-client/src/game/agent.rs                [I2]
A horizon/crates/horizon-client/src/game/auto_performance.rs      [E1]
M horizon/crates/horizon-client/src/game/control.rs               [I2]
M horizon/crates/horizon-client/src/game/debug_options.rs         [I2]
M horizon/crates/horizon-client/src/game/dedicated.rs             [E2]
M horizon/crates/horizon-client/src/game/ime.rs                   [I2]
A horizon/crates/horizon-client/src/game/lifecycle.rs             [C1]
M horizon/crates/horizon-client/src/game/loading_screen.rs        [A4, B, C2]
M horizon/crates/horizon-client/src/game/loading_window.rs        [B]
M horizon/crates/horizon-client/src/game/no_resources.rs          [A4]
M horizon/crates/horizon-client/src/game/options.rs               [E2, I2]
M horizon/crates/horizon-client/src/game/pad.rs                   [C2, I2]
M horizon/crates/horizon-client/src/game/pad_menu.rs              [I2]
M horizon/crates/horizon-client/src/game/play_keys.rs             [I2]
M horizon/crates/horizon-client/src/game/pointer_capture.rs       [I2]
M horizon/crates/horizon-client/src/game/remote.rs                [E2]
M horizon/crates/horizon-client/src/game/render_settings.rs       [E2]
M horizon/crates/horizon-client/src/game/screens.rs               [I2]
M horizon/crates/horizon-client/src/game/split.rs                 [C2]
M horizon/crates/horizon-client/src/game/split/players.rs         [B]
M horizon/crates/horizon-client/src/game/startup_menu.rs          [B, I2]
A horizon/crates/horizon-client/src/game/touch.rs                 [C1, I2]
A horizon/crates/horizon-client/src/game/touch_calibration.rs     [J1]
A horizon/crates/horizon-client/src/game/touch_editor.rs          [I1]
M horizon/crates/horizon-client/src/game/window_handler.rs        [A4, C2]
M horizon/crates/horizon-hdr/Cargo.toml                           [A1]
M horizon/crates/horizon-hdr/src/lib.rs                           [A1]
M horizon/crates/horizon-threads/src/process_memory.rs            [A3]
A horizon/platform/ios-bridge/Cargo.toml                          [A5]
A horizon/platform/ios-bridge/src/lib.rs                          [A5]
```

## G. Rebase checklist

1. Import the new upstream beside the old one; do **not** overwrite `horizon/` first.
2. Copy the twelve new files (C1, D1, E1, A5, I1): they are self-contained.
3. Do section A (mechanical), then B (by intent, measure the stack), then the hooks in C2, D2, E2.
4. `cargo test -p horizon-client-input` (touch, settings and Auto Performance logic) needs no
   engine build. The render and client crates build on CI only.
5. Run `tools/horizon_diff.sh --check` and update this file for anything that moved.
6. The Cargo.lock change is one workspace package; if upstream's lock changed, regenerate rather
   than merge, and have the owner approve it.

## H. Changes not in `horizon/` that depend on it

`platform/ios/` (the app shell, launcher, crash reporter) calls `horizon_ios_main`, reads
`horizon-imc.txt`'s folder, and uses the breadcrumb function. If the bridge's C name or signature
changes, `platform/ios/App/main.m` changes with it. The launcher's own `launcher.txt` is not in
`horizon/`.
