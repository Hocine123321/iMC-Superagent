# iMC Horizon code map

**Read this first when you add or change something.** It says where each thing lives, which files must change together, and which traps exist. It was written against `main` at the commit named in the "Verified against" line at the end; if you change a path or a name listed here, change it here in the same commit.

Conventions: `E/` = `horizon/crates/` (the Rust engine), `IN/` = `horizon/crates/horizon-client-input/src/`, `RE/` = `horizon/crates/horizon-client-render/src/`, `CL/` = `horizon/crates/horizon-client/src/`, `G/` = `CL/game/`, `APP/` = `platform/ios/App/`, `SW/` = `APP/Swift/`. Line numbers are given as `~N` and drift; search by the function name.

---

## 1. What this repository is

An iPhone app made of **two programs in one process**:

| Part | Language | Where | Job |
|---|---|---|---|
| **Launcher** (the app shell) | SwiftUI + Objective-C | `platform/ios/` | Play, Packs/Marketplace, Controls, Settings, game download, account, diagnostics, crash reporting. Runs before the game. |
| **Engine** (Horizon, a Minecraft Java client written in Rust, drawn with wgpu on Metal) | Rust | `horizon/` | The game itself: world, rendering, input, UI screens. A snapshot of upstream Horizon plus this port's edits. |
| **Bridge** | Rust staticlib | `horizon/platform/ios-bridge/` | The C functions the shell calls to start the engine. |

Everything else: `docs/` (design notes, history, the engine change list), `tools/` (repo checks), `.github/workflows/` (CI).

### The rule that shapes every change
`horizon/` is **upstream Horizon with our edits**. Every edit inside it must be written down in `docs/HORIZON_CHANGES.md`, and the exact diff is kept as `docs/horizon-changes.patch` and `docs/horizon-changes-upstream.patch` (so the edits can be replayed on a newer upstream). After any edit under `horizon/`: (1) add an entry to `docs/HORIZON_CHANGES.md` (the check fails if a changed path is not mentioned there by its path text), (2) **commit the edit**, (3) run `tools/horizon_diff.sh --patch` and commit the two regenerated patches, (4) `tools/horizon_diff.sh --check` must pass. The diff is taken against the committed `HEAD`, so regenerate the patches **after** committing, never before. The baseline commit is in `docs/HORIZON_BASELINE`; in a shallow clone the check is skipped. CI's "Public tree check" runs it.

### Who owns what (working split)
- **In-game work** (touch, cursor, iMC Settings page, Auto Performance, the engine edits): `horizon/crates/...`
- **App shell work**: `platform/ios/...`
- The two meet at **files in the game's home folder** (section 5) and **four C functions** (section 4). Anything that changes one side of those must change the other.

---

## 2. Repository layout

```
.github/workflows/    CI (section 9)
docs/                 design notes + HORIZON_CHANGES.md (engine edit list) + patches
horizon/              the Rust engine (upstream snapshot + our edits)
  crates/             ~40 crates (section 6)
  platform/ios-bridge/  the C entry points
  launcher/ xtask/ tools/ tests/ mods/ ...   upstream's desktop launcher, repo tasks, harnesses (not built for iOS)
platform/ios/         the iOS app
  App/                Objective-C (.m/.h) + main.m
  App/Swift/          SwiftUI launcher
  project.yml         XcodeGen project (the Xcode project is generated, never committed)
  scripts/build-rust.sh   local build of the Rust library
  tests/              Python mirrors of the Objective-C rules (section 8)
  Assets.xcassets/    app icon
tools/                check_public_tree.sh, check_stack_budget.py, horizon_diff.sh, make_app_icon.py
```

Size of the engine: about 1.1 million lines of Rust. **Do not read it broadly.** Use this map, then `grep -n "fn <name>"`.

---

## 3. How the app runs (process flow)

1. **`APP/main.m`** `main()`: builds paths (`Documents/Horizon` = `root`, `root/resources`, `root/home`), reads whether to skip the launcher **before** installing the crash reporter (the reporter rewrites `crash.txt`, which that check reads; do not reorder), installs `HorizonInstallCrashReporter`, starts `HorizonStartSessionLog`, writes `diagnostics.txt`.
2. If the person has not just pressed Play (or the game files are not ready): `HorizonRunLauncher` (`APP/Launcher.m`) starts `UIApplicationMain`, and `SW/LauncherHost.swift` `HZLauncherHost.makeRoot()` returns the SwiftUI `RootView` (`SW/RootView.swift`: tabs Play, Packs, Controls, Settings).
3. **Play** (`SW/LauncherState.swift` `play()`):
   - default: sets a start flag, `HorizonCrashReporterCleanExit()`, `exit(0)`; the next launch goes straight to step 4. (The app restarts to run the game.)
   - **in-process play** (`launcher.txt` line `inProcessPlay:true`, Developer options): the engine is already running behind the launcher, held waiting; Play calls `horizon_ios_play()` and `EngineOverlay.dismiss()` removes the launcher window (`SW/EngineOverlay.swift`, `APP/EngineOverlay.m`).
4. **Start the engine**: `main.m` sets the working directory to `root/home`, rebuilds `argv` with `--resources`, `--home`, `--session-file` (the signed-in account, `APP/GameSession.m`), and calls `horizon_ios_main()` (declared in the bridge, defined in `horizon/platform/ios-bridge/src/lib.rs`). It never returns: winit's `run_app` owns the process from here.
5. **Engine startup (Rust)**: `horizon_ios_main` -> `horizon_client::entry::main` (`CL/entry.rs`) -> `game::run_with` (`CL/game.rs` ~17192) -> `run_loading` (~17128) shows the loading screen -> `Loading::finish` builds the game with `Game::new_boxed` (`game.rs` ~16149; boxed on purpose, see "stack budget" in section 10) -> the winit event loop (`G/loading_screen.rs` `run_event_loop`, then `G/window_handler.rs`).
6. **Every frame** (`G/window_handler.rs` `idle`/`about_to_wait`, ~101): `touch_frame` (time passing for fingers), `auto_performance_frame`, then `tick`/`render` in `game.rs` (`fn tick` ~7346, `fn tick_world` ~7444, `fn render` ~13424). HUD is drawn in `hud_layers` (~7659) and the final overlays in the draw block ending `self.draw_touch_controls(&mut batch)` (~7654).
7. **Lifecycle**: `ApplicationHandler::suspended` and `memory_warning` (`G/window_handler.rs` ~204, ~208) call `G/lifecycle.rs` `app_suspended` (saves the world when the app goes to the background) and `app_memory_warning`.

---

## 4. The C boundary (shell <-> engine)

Rust exports (in `horizon/platform/ios-bridge/src/lib.rs`), declared for Swift in `APP/HorizonApp-Bridging-Header.h` and for Objective-C in `main.m`:

| Function | Meaning | Backed by |
|---|---|---|
| `horizon_ios_main()` | start the game; never returns | `horizon_client::entry::main` |
| `horizon_ios_arm_hold()` | before main: make the engine wait for Play | `IN/ios_hold.rs` `arm` |
| `horizon_ios_play() -> bool` | the person pressed Play | `ios_hold::play` |
| `horizon_ios_cancel_hold()` | the app is leaving for good | `ios_hold::cancel` |
| `horizon_ios_hold_state() -> i32` | 0 not armed, 1 waiting, 2 released, 3 cancelled | `ios_hold::state` |

The shell exports one function **to** Rust: `horizon_ios_breadcrumb(const char*)` in `APP/CrashReporter.m` (the engine calls it through `gfx::BREADCRUMB` at start-up stages so a crash report says how far the game got).

**To add a new C function**: add `#[unsafe(no_mangle)] pub extern "C" fn` in the bridge `lib.rs`, declare it in `HorizonApp-Bridging-Header.h` (Swift) or an `extern` (Objective-C), log it in `docs/HORIZON_CHANGES.md` (the bridge is a changed engine file).

The hold itself (the engine's "wait for Play" mode): state in `IN/ios_hold.rs`; used in `CL/game.rs` (`ios_hold::armed()` near ~721 and ~17253), `G/loading_screen.rs` (the wait, the portrait-to-landscape switch), `G/startup_menu.rs` (`wait_for_play`, `request_quit`), `G/world_session.rs` (Quit game), `IN/window.rs` (`window_starts_portrait`).

---

## 5. Files the two sides share (the game's home folder)

The game's home is `Documents/Horizon/home` (the Files app shows it). Launcher-only files sit one level up in `Documents/Horizon`.

| File | Written by | Read by | Format / owner of the format |
|---|---|---|---|
| `home/horizon-imc.txt` | **both**: the game (`RE/settings.rs` save) and the launcher Controls tab (`SW/ControlsModel.swift` `ImcStore`) | both | `key:value` lines. Format: `IN/imc_settings.rs` (`Item::key`, `parse`, `serialize`). Mirror: `SW/ControlsModel.swift` `ImcSchema.entries` |
| `home/horizon-touch-layout.txt` | both (game editor, launcher editor) | both | `name:dx,dy,scale,opacity,shown`, only non-default buttons. `IN/touch_layout.rs` (`NAMES`, 18 slots). Mirror: `SW/ControlsModel.swift` `TouchLayoutFile.names` |
| `home/horizon-imc-buttons.txt` | game | game | the extra on-screen buttons and their keys: `IN/touch_extras.rs` |
| `home/horizon-touch-presets.txt` | game | game | saved layouts: `IN/touch_editor_tools.rs` (`Presets`, max 6) |
| `home/horizon-imc-touch-calibration.txt` | game | game | the fitted touch correction: `IN/touch_calibration.rs` |
| `home/options.txt` | game | game | vanilla options (kept exactly vanilla); `RE/options_file.rs`, `RE/settings.rs` |
| `home/horizon-extras.txt` | game | game | Horizon's own extras (`RE/extras.rs`) |
| `home/latest.log`, `home/crash-reports/` | game | launcher Logs | engine logs |
| `launcher.txt` | launcher | launcher + `main.m` | `key:value`; see sections 7.4 and 7.5 |
| `game-session.json` | launcher (`GameSession.m`) before launch | engine, then **deleted by the engine** | the account handed to the game (`--session-file`) |
| `account.txt` | launcher | launcher | name, UUID, ownership; the secrets are in the Keychain |
| `crash.txt`, `crash-previous.txt` | `CrashReporter.m` | launcher Logs | why the last run ended |
| `diagnostics.txt` | `Diagnostics.m` | launcher | device report each launch |
| `session-log.csv` | `SessionLog.m` | launcher Logs | one line / 5 s: memory, heat, stalls |
| `horizon-resources.json` | the preparer | `LauncherModel.m` | the game-files manifest (`filesOK` cache keyed in launcher.txt) |

### TRAPS in this table (read before touching the settings files)
1. **Both sides rewrite `horizon-imc.txt` whole.** The launcher's `ImcStore.save()` writes only the keys in `ImcSchema.entries`; any key the schema lacks is **lost on the next launcher save** (reset to default). `ImcSchema.entries` must list **every** key `Item::key` can return, in the game's write order. It was missing five keys until this was fixed (`cursorHold`, `cursorDragGrab`, `worldControls`, `airHold`, `airHoldDelay`). **When you add an `imc_settings::Item`, also add its `Entry` in `ImcSchema`** (step count and default must equal the Rust side).
2. **Layout slots**: `touch_layout::NAMES` has 18 entries (the nine pads, back, six extras, then `cursor`, `shift`). The Swift `TouchLayoutFile.names` must list the same 18 so lines for `cursor`/`shift` are kept when the launcher saves (it keeps lines for index >= 10 verbatim). The launcher **edits** only the first ten (`TouchPad.all`).
3. The launcher says "the game must not be running while the launcher changes the file". That holds because the launcher and game are separate runs, **except in in-process play**, where both exist at once.

---

## 6a. iMC in-game systems (the part we write most)

All pure logic is in `IN/` (crate `horizon-client-input`) and is **unit tested offline**: `cd horizon && cargo test -p horizon-client-input`. The glue in `G/` needs the whole engine (audio and system libraries) and is verified only by CI. **Rule: put every decision in `IN/`, keep `G/` a thin translator.**

### 6a.1 Files

| File | Lines (approx) | Owns |
|---|---|---|
| `IN/touch.rs` | 1250 | The finger state machine, no game types. `Touch` (`down`, `moved`, `tick`, `up`, `cancel_all`), `Action` (what the game should do), `Mode` (Playing/Menu), `WorldStyle` (Classic/Bedrock), `Layout`, `Feel` (slop, tap and long-press times, look speed), `Rect`, `to_surface` (window to safe-area mapping), `stick_vector`, `hotbar_slots`. Tests inline. |
| `IN/touch_cursor.rs` | 840 | Cursor mode (finger = trackpad, a drawn pointer): `Cursor` (`down/moved/tick/up`), `Source`/`source_for` (when it is active), `SPEEDS`, `switch` (the Cursor button rect), `shift` (the Shift button rect). |
| `IN/touch_layout.rs` | 740 | The player's button arrangement as nudges: `NAMES` (18), `Slot`, `ControlLayout` (`parse`, `serialize`), `back` (Back button), `editor` (the editor panel's controls). |
| `IN/touch_editor_tools.rs` | 890 | Editor rules: `snap`, `overlap`, `problems`, built-in layouts (`BUILT_IN`: Default, Left-handed, Compact, Bedrock, Big thumbs; `built_in`, `wants_bedrock_controls`), saved presets (`Presets`, file `horizon-touch-presets.txt`). |
| `IN/touch_extras.rs` | 380 | The six optional buttons (Chat, F3, F2, View, two picked keys): `Extra`, `Extras`, `CHOICES`, file `horizon-imc-buttons.txt`. |
| `IN/touch_calibration.rs` | 260 | Least-squares touch correction: `Calibration` (`fit`, `apply`), `TARGETS`, file `horizon-imc-touch-calibration.txt`. |
| `IN/imc_settings.rs` | 1150 | **The iMC settings.** `Item` (every row), `ImcSettings` (`parse`, `serialize`, `value`, `cycle`, `is_active`, `reset`, `apply`), the step tables, `Cost` notices. File `horizon-imc.txt`. |
| `IN/auto_performance.rs` | 510 | Memory governor: `Governor::tick` -> `Caps`; `Sensitivity`, `Config`. Never changes saved settings, only caps. |
| `IN/ios_hold.rs` | 290 | The wait-for-Play state machine and the quit/landscape flags. |
| `G/touch.rs` | 1010 | **The glue.** `TouchState`, `PADS` (the nine buttons), `PadKind`, `touch_event` (every finger), `touch_frame` (every frame), `touch_apply` (turns `Action` into game input), `draw_touch_controls`. |
| `G/touch_cursor.rs` | 330 | Cursor glue: `CursorState`, `cursor_event`, `cursor_frame`, `cursor_switch_event`, `shift_button_event`, `draw_touch_cursor`. |
| `G/touch_editor.rs` | 520 | The in-game button editor screen (`Screen::TouchEditor`): `open_touch_editor`, `draw_touch_editor`, `touch_editor_press/drag/release`. |
| `G/touch_calibration.rs` | 155 | The Calibrate overlay (`TouchState::calibrating`). |
| `G/auto_performance.rs` | 110 | `auto_performance_frame`, `capped_render_distance`, `capped_resolution_scale`, `auto_performance_status`. |
| `G/lifecycle.rs` | 47 | `app_suspended` (30 s save throttle), `app_memory_warning`. |
| `RE/mobile_preset.rs` | 250 | "Phone preset" button: `Kind` (Mobile, Battery saver, Smooth), `apply_kind`, `current`. |
| `RE/ios_unused.rs` | 270 | "Grey out unused settings": reasons for keyboard/mouse/desktop-only options (`opt`, `graphics`, `extra`, `page`, `pvp`). |
| `RE/graphics_ui.rs` | 3680 | Video Settings rows, including the **iMC page** (`Page::Imc`, `Item::Imc`, `ImcDo`, `imc_description_key`, the rows near ~726-790, `blocked` ~1263). |
| `RE/options_ui.rs` | 8530 | The options screens: `Page::GraphicsImc` (the iMC page lives inside Video Settings), `Page::TouchButtons`, the click handler (~2335 `ImcDo::...`), tooltips. |
| `RE/settings.rs` | 1280 | `Settings` struct with the touch fields (`imc`, `touch_layout`, `touch_calibration`, `touch_extras`, `touch_presets`) and their load (~377-445) and save (~760-780). |
| `horizon/crates/horizon-client/assets/horizon/lang/en_us.json` | | One caption + one `.tooltip` per setting under `horizon.imc.*`. Tests compare these to the Rust English strings. |

### 6a.2 How a finger becomes a game action (trace it before changing touch)

```
winit WindowEvent::Touch
  -> game.rs handle_window_event_inner (~14601): `if let WindowEvent::Touch ... { self.touch_event(..); return; }`
  -> G/touch.rs touch_event  (calibration -> to_surface -> Back / Cursor-switch / Shift / cursor_event -> button rects)
  -> IN/touch.rs Touch::down / moved / up      returns Vec<Action>
  -> G/touch.rs touch_apply(actions)
        Look            -> look_turn (G/pointer_capture.rs ~35)
        Attack / Use    -> pad.inject_button(RightTrigger / LeftTrigger)   [virtual controller]
        Jump            -> pad.inject_button(South)
        Tap (Bedrock)   -> aims at entity ? RightTrigger : LeftTrigger, released a frame later (touch_pulse_frame)
        Hold(true)      -> entity or block ? hold RightTrigger : (air_hold setting ? start air_wait : nothing)
        PointerTo/Left/Right/Scroll -> synthetic CursorMoved / MouseInput / MouseWheel through handle_window_event
```
Buttons on the screen press **controller buttons** (`PADS[i].button`), so the player's rebinds apply. The pad merges `injected` (horizon-ctl) and `touched` (fingers): `G/pad.rs` (`inject_button` ~213, `set_injected_left` ~217, merge ~330, `late_releases` keeps a one-frame press alive). `Button::RightTrigger` is `key.attack`, `LeftTrigger` is `key.use` (`IN/gamepad.rs` ~322); `G/pad.rs` `pad_action` (~510) routes them to `mouse_mapping` (`G/play_input.rs` ~289), which reaches `tick_mining` (`game.rs` ~7132), `attack_mob` (~10294) and `use_hand` (~6504).

Per frame: `G/window_handler.rs` `idle` -> `touch_frame` (applies settings, `cursor_frame`, `Touch::tick`, `touch_apply`, `touch_pulse_frame`, `touch_air_frame`, writes the stick to the pad, `touch_sprint`).

**Hooks of touch into engine files (all must survive an upstream rebase):** `game.rs` (`mod touch;`, fields `touch`/`last_suspend_save`/`auto_performance`, `touch_event` at the top of `handle_window_event_inner`, `draw_touch_controls` ~7654, `Screen::TouchEditor` draw ~8039 and mouse handling ~15067/~15470, `capped_render_distance` ~15993), `G/window_handler.rs` (~160, ~161, ~205, ~209), `G/options.rs` (~357, ~476, ~477, ~549), `G/play_keys.rs` (~89), `G/remote.rs` (~1033, ~1281, ~5463), `G/render_settings.rs` (~34), `G/dedicated.rs` (~1483), `G/pad.rs`, `G/split.rs` and `G/loading_screen.rs` (suspended/memory_warning forwards). Full list: `docs/HORIZON_CHANGES.md` sections C to Q.

### 6a.3 The nine fixed buttons
`G/touch.rs` `PADS` (~201): Jump, Sneak, Run, Use, Pause, `<`, `>`, Drop, Inv, each an anchor (corner + offsets as fractions of the screen) and a controller `Button`. Button slot numbers (index in the layout file) = `PadKind::slot` (~85); extras start at slot 10 (`touch_layout::EXTRA_FIRST`), Cursor = 16, Shift = 17. The Back button is separate (`IN/touch_layout.rs` `back`, glue `touch_back_event`).

---

## 6b. Checklists: "I want to ... what do I touch?"

### Add an iMC setting (a new row on the iMC page) — every step, all verified on the AirHold change
1. `IN/imc_settings.rs`: add a variant to `enum Item` and to `Item::ALL` (and bump the array length); add the arms in `key()` (the file key), `caption()`, `description()` (the tooltip English text), and `cost()` if heavy; add the field to `struct ImcSettings`, its default in `Default`, the `parse` arm (clamp it), the `serialize` format string **and its argument list**, `value()`, `cycle()`, `is_active()` (greying), and `apply()` if it feeds `Touch`. Add step tables (`const NAMES`, values) at the top. Add tests next to the others.
2. `RE/graphics_ui.rs`: add the arm in `imc_description_key` (~229) **and** a row `m(I::YourItem, Cost)` in the iMC page rows (~726-790), in the order you want. `blocked()`/grey rules are in `ImcSettings::is_active`.
3. `horizon/crates/horizon-client/assets/horizon/lang/en_us.json`: add `horizon.imc.<key>` and `horizon.imc.<key>.tooltip` (must equal the Rust English text exactly; tests compare).
4. If the game uses it: read `self.settings.imc.<field>` in `G/touch.rs` (or the right glue file).
5. **`platform/ios/App/Swift/ControlsModel.swift` `ImcSchema.entries`: add the `Entry`** (same key, `.flag` or `.steps(n)`, same default), in the game's write order. Otherwise the launcher's Controls tab silently resets your setting.
6. Optional launcher row: `SW/ControlsTab.swift` (`ChoiceRow(... selection: store.stepBinding("key"))`).
7. `docs/HORIZON_CHANGES.md`: add a line under the section for the iMC settings (Q or a new one); `tools/horizon_diff.sh --patch`.
8. Tests: `cd horizon && cargo test -p horizon-client-input` (and `-p horizon-client-render` if you changed rows; it checks that every row has a key and a tooltip).

### Change how a finger behaves in the world
Decision logic -> `IN/touch.rs` (`down/moved/tick/up`, `Feel`, `Layout`, `Action`); then translate any **new `Action`** in `G/touch.rs touch_apply` (the match is exhaustive, the compiler will point at every place). Timings come from `ImcSettings::apply` (`IN/imc_settings.rs` `ImcSettings::apply` ~708) writing `Touch.feel`/`layout`. Test in `IN/touch.rs` tests (use the `bedrock()` and `touch()` helpers).

### Change how a finger behaves in a menu / the inventory cursor
`IN/touch.rs` for plain menu touch; `IN/touch_cursor.rs` for cursor mode; glue `G/touch_cursor.rs`. The cursor is on when `touch_cursor::source_for` says so (the Cursor button, or "Cursor in inventory").

### Add or change an on-screen button
- A **fixed** button: add a `Pad` to `PADS` (`G/touch.rs`), a slot name to `touch_layout::NAMES` **at the end** (and bump `COUNT`), the `PAD_SLOT` mapping, and mirror it in `SW/ControlsModel.swift` (`TouchLayoutFile.names`, `TouchPad.all` if the launcher should edit it).
- An **extra** (optional, key-pressing) button: `IN/touch_extras.rs` (`Extra::ALL`, `name`, `label`, `binding`) plus its slot in `touch_layout`.
- A **menu** button (Cursor/Shift style): `MenuButton` in `G/touch.rs`, rect in `IN/touch_cursor.rs`, event in `G/touch_cursor.rs`, drawn in `draw_touch_pads`.
- Default positions: `Pad.at` anchors (fractions) and `PadKind::base`. Player nudges: `touch_layout::Slot` (`place`, `moved_to`).

### Add a built-in layout / change the editor
`IN/touch_editor_tools.rs` (`BUILT_IN`, `built_in`, `wants_bedrock_controls`, snapping constants `GRID`, `SNAP_RANGE`); editor screen `G/touch_editor.rs` (panel actions are `touch_layout::editor::Action`, laid out by `editor::panel`).

### Add a new **screen** that fingers and the pad can use
Add a variant to `enum Screen` (`game.rs` ~966), draw it in the screen draw `match` (~8039 shows `Screen::TouchEditor`), handle its mouse in `handle_window_event_inner` (~15470 shows how), close it in `G/play_keys.rs` (~89), and name it in the screen-name `match` (~1039).

### Add an item to the **Auto Performance** governor
`IN/auto_performance.rs` (`Step`, `Governor::steps`, `Caps`), apply the cap where the engine reads the setting (see `capped_render_distance` call sites above), expose toggles as iMC `Item`s.

### Change what Play does / the hold
Shell: `SW/LauncherState.swift` `play()`, `playInProcess()`. Engine: `IN/ios_hold.rs`. Bridge: `horizon/platform/ios-bridge/src/lib.rs`. The design is `docs/IN_PROCESS_PLAY_DESIGN.md`.

---

## 6c. The rest of the engine

### Crate layers (bottom to top; from each `Cargo.toml`)
- **No internal deps**: `horizon-core` (Java `Random`s, `jmath`, noise, version), `horizon-theme`, `horizon-mcp`, `horizon-polytone`, `horizon-anticheat`, `horizon-chat-filter`, `horizon-prepare`, `horizon-threads` (allocator, memory counters, `process_memory.rs` with the iOS footprint code), `horizon-hdr`, `horizon-telemetry`, `horizon-narrator`, `horizon-dualsense` (stubbed on iOS: `haptics_stub.rs`), `horizon-cosmetics`, `horizon-friends`.
- Over `horizon-core`: `horizon-assets` (models, atlases), `horizon-shaders`, `horizon-optifine`, `horizon-world`.
- Over `horizon-world`: `horizon-protocol` (network protocol 777), `horizon-server-files`, `horizon-items`.
- `horizon-command` (Brigadier), `horizon-client-core` (text, lang, nbt paths, scoreboard, registries).
- **The three client crates** that carry our work: `horizon-client-input` (keys, mouse, gamepad, window, **all touch**), `horizon-client-render` (world data, renderer `gfx`, HUD, **all options screens**, settings), `horizon-client` (gameplay: `game.rs` + `game/*.rs`, mobs, LAN, save, title).
- `horizon-client-lib`: a manifest only; its `[lib] path` points at `CL/client_lib.rs` (tools and probes link it without gameplay).
- Top: `horizon-server`, `horizon-bots`, `horizon-relay`, `horizon-mod-registry`, `horizon-port-pack`.
- **iOS links**: `horizon-ios-bridge` -> `horizon-client` (and everything under it), `horizon-threads`, `horizon-mods`.
- Separate workspaces (not in the iOS build): `horizon/launcher`, `crates/horizon-telemetry-server`, `crates/horizon-mod-registry`, `third_party/*`.

Sizes (Rust lines): `horizon-client` 633k (919 files), `horizon-client-render` 219k, `horizon-world` 190k, `horizon-protocol` 36k, `horizon-shaders` 24k, `horizon-core` 23k, `horizon-server` 20k, `horizon-client-input` 14k.

### Where things are in the engine (verified file names)

| Area | Files |
|---|---|
| **Game object and loop** | `CL/game.rs` (17.9k lines: `struct Game`, `tick` ~7346, `tick_world` ~7444, `render` ~13424, `handle_window_event_inner` ~14601, `Screen` enum ~966, `new_boxed` ~16149, `run_with` ~17192); `G/window_handler.rs` (winit callbacks); `G/loading_screen.rs`, `G/loading_window.rs`, `G/startup_menu.rs` (start-up, title); `G/split.rs` (splitscreen) |
| **Input mapping** | `G/play_keys.rs` (`key_pressed`), `G/play_input.rs` (`mapped_key`, `mouse_mapping`, `hotbar_step`), `G/pointer_capture.rs` (`look_turn`), `G/pad.rs` (controller; touch rides on it), `G/pad_menu.rs` (controller in menus, `gui_scale`), `IN/keybinds.rs`, `IN/gamepad.rs` (default button -> action table `ACTIONS` ~322), `IN/mouse.rs`, `IN/actions.rs` (`Action` enum) |
| **Player actions** | `G/hand.rs` (clicks, held attack), `game.rs` `tick_mining` ~7132, `attack_mob` ~10294, `use_hand` ~6504, `G/pick_entity.rs` (entity under crosshair), `G/combat.rs`, `G/block_edits.rs` |
| **Inventory / containers** | `game.rs` `click_inventory` ~9119 and `menu_ops` ~8521, `G/inventory_input.rs`, `G/inventory_slots.rs`, `CL/menu.rs`, `CL/container_screen.rs`, `CL/creative.rs` |
| **Menus** | `G/screens.rs` (pause, death), `G/startup_menu.rs`, `CL/title.rs` + `CL/title/`, `RE/options_ui.rs`, `RE/screen_draw.rs`, `RE/ui.rs` (widgets), `RE/settings_shell.rs` (searchable settings frame), `RE/widgets.rs` |
| **HUD / drawing 2D** | `RE/hud.rs` (atlas, `HudBatch`), `RE/hud_layout.rs`, `RE/hud_overlays.rs`, `RE/font.rs`, `RE/chat.rs`, `RE/tab_list.rs`; the per-frame composition is in `game.rs` (`hud_layers` ~7659, overlays ~7640) |
| **Renderer** | `RE/gfx.rs` (14.6k lines: `Renderer::new`, `render`, backend choice `open_backend`/`backend_order`), `RE/gfx/*` (cull, occlusion, upload, translucency, flat draws `flat.rs`, timing, lod), shaders `RE/*.wgsl` and `RE/gfx/*.wgsl`, `RE/mesher.rs` (chunk meshing), `RE/streaming.rs` (chunk workers), `RE/light.rs`, `RE/camera.rs` (FOV), `RE/spans.rs` (frame timings), `RE/particles.rs`, `RE/clouds.rs`, `RE/fog.rs` |
| **Settings** | `RE/settings.rs` (`Settings`, load/save), `RE/options_file.rs` (`options.txt`), `RE/graphics.rs` + `RE/graphics_ui.rs` (Video Settings), `G/options.rs` (apply), `G/render_settings.rs` (build/apply the renderer), `RE/extras.rs` (`horizon-extras.txt`) |
| **World / server** | `G/integrated.rs` (single player runs on a server thread), `G/levels.rs` (one level per dimension), `G/remote.rs` (client side of any server), `CL/lan/` (LAN host), `G/dedicated.rs`, `G/saving.rs` + `G/persist.rs` + `CL/save.rs` (saves), `G/world_entry.rs` + `G/world_loading.rs` (opening a world), `horizon-world/src/` (`worldgen/`, `level/` block behaviour, `region.rs`, `nbt.rs`, `chunk`, entity physics) |
| **Mobs** | `CL/mobs.rs` + `CL/mobs/` (species, AI `ai.rs`/`goals.rs`/`brain.rs`, spawning, models `render.rs`/`anim.rs`) |
| **Network** | `horizon-protocol/src/` (`packets/{handshake,status,login,configuration,play}.rs`, `entity_data.rs`, `connection.rs`), `CL/net.rs` |
| **Commands** | `G/commands.rs` + `G/commands/`, parsing in `horizon-command` |
| **Audio** | `RE/audio.rs`, `RE/sound_engine.rs`, `RE/sound_events.rs`, `CL/music.rs` |
| **Language** | `horizon-client-core/src/lang.rs`, `text.rs`; strings in `horizon/crates/horizon-client/assets/horizon/lang/*.json` (Horizon's own keys; vanilla's come from the player's game files) |
| **Mods / packs** | `horizon-mods`, `CL/mod_content.rs`, `CL/mod_registry/`, `RE/packs.rs` + `RE/pack_screen.rs`, `horizon-optifine`, `horizon-shaders` |
| **Agent control** | `CL/control.rs`, `CL/bin/horizon-ctl/`, `G/control.rs` (the `pad` command can inject buttons; used for tests) |

### Engine edits made for iOS (outside touch) — all listed with reasons in `docs/HORIZON_CHANGES.md`
- `target_vendor = "apple"` instead of macOS for Metal: `horizon-hdr`, `RE/gfx.rs` (`open_backend`, `backend_order`), `RE/graphics.rs`, `RE/graphics_ui.rs`, `RE/logging.rs`, `RE/options_ui.rs` (A1).
- `horizon-client-input/Cargo.toml` (arboard wayland), `IN/keybinds.rs` `learn_layout` (A2, A3), `horizon-threads/src/process_memory.rs` (iOS memory footprint; feeds Auto Performance).
- Window: `IN/window.rs` `creation_size` and landscape-only `with_horizon_icon` (A4, A7); call sites `G/loading_screen.rs`, `G/window_handler.rs` (`resumed`), `G/no_resources.rs`.
- `RE/gfx/flat.rs`: flat draws need `INDIRECT_EXECUTION` (A6).
- **Stack budget** (B): `Game::new_boxed`, `run_synchronous`, `Loading::finish*`, `start_game` are `#[inline(never)]` and box the `Game`. See section 10.

---

## 7. The app shell

### 7.1 Objective-C (`APP/`) — logic with no UI, mirrored by Python tests where marked (T)

| File | Owns |
|---|---|
| `main.m` | process start order, argv rebuild, hand-off to Rust |
| `Launcher.m/.h` | `HorizonRunLauncher`; the app delegate that hosts SwiftUI, applies theme, silent account recheck |
| `LauncherModel.m/.h` | game-files state (`checkFiles:` -> `HZFilesReady`), `launcher.txt` reads for `openGame:` and `inProcessPlay:`, the start-game flag, `root`/`resources`/`home` paths |
| `LauncherPrefs.m/.h` (T) | Marketplace visibility flags (`market.mods`, `market.shaders`, `market.other`, `market.modrinth`), `confirmInstalls`, `compact`, `reduceMotion` |
| `LauncherTheme.m/.h` | `HZTheme`: appearance, glass strength, **the in-memory copy of `launcher.txt`** (`setting(for:)`, `setSetting:forKey:`, `flushSettings`) |
| `GameSession.m/.h` (T) | writes `game-session.json` for the engine (`--session-file`): exact rules the engine enforces |
| `AccountClient.m`, `AccountModel.m`, `AccountStore.m` (T for the model) | Microsoft device-code sign-in -> Xbox -> XSTS -> Minecraft -> ownership; secrets in Keychain, `account.txt` for the rest; never logs tokens |
| `DownloadPlan.m` (T), `DownloadStore.m`, `Downloader.m` (T), `DownloadRate.m` (T) | game download from Mojang: plan (which files), disk rules (`.part` then verify SHA-1), network, speed estimate |
| `MarketIndex.m` (T), `MarketClient.m`, `MarketFetcher.m`, `MarketInstaller.m` (T), `ModrinthClient.m` (T) | Marketplace: the registry index, fetching, hash-checked install into `home/horizon-mods`, `resourcepacks`, `shaderpacks`; Modrinth resource packs |
| `FileBrowser.m` (T) | the file manager's rules; **never touches a path outside `Documents/Horizon`** |
| `CrashReporter.m` | fatal signals, ObjC exceptions, "running" marker (a kill by the system is detected at next launch), `horizon_ios_breadcrumb` |
| `SessionLog.m` | `session-log.csv`, one line / 5 s, written off the main thread |
| `Diagnostics.m` | `diagnostics.txt` and the readings the check-up page uses (`HZDiagAvailableMemory`, `HZDiagFootprint`, `HZDiagEntitlement`) |
| `EngineOverlay.m` | in-process play flag (`HZSetInProcessPlay`, `HZIsInProcessPlay`) |
| `HorizonApp-Bridging-Header.h` | what Swift sees of Objective-C **and** the Rust C functions |
| `Horizon.entitlements`, `project.yml` (`info:` block) | permissions, Info.plist keys (orientations, file sharing, local network text, version stamps) |

### 7.2 SwiftUI (`SW/`)

| File | Screen / job |
|---|---|
| `RootView.swift` | the four tabs; flushes settings on resign/background |
| `PlayTab.swift`, `LauncherState.swift` | Play tab; `play()`/`playInProcess()` |
| `DownloadPage.swift` (`DownloadCenter`), `GameFilesPage.swift` | game download, prepared-files page |
| `MarketplaceTab.swift`, `MarketDetailPage.swift`, `MarkdownText.swift` | Marketplace list, project page, Markdown reader |
| `ControlsTab.swift`, `ControlsModel.swift`, `TouchEditor.swift` | Controls tab (settings editor = `ImcStore`), the engine-file mirrors, the launcher's button editor (`TouchEditorModel`, `TouchPad.all`, `LauncherOrientation` allows landscape only while it is open) |
| `SettingsTab.swift`, `Prefs.swift` | Settings pages (Look, Game, Marketplace), `LauncherFile` (read/write `launcher.txt`), `Prefs`, `AccentLook`, `Haptics` |
| `AccountPage.swift`, `SkinHead.swift` | sign-in UI, player head from Mojang |
| `DiagnosticsPage.swift`, `DiagnosticsEngine.swift`, `LogsView.swift`, `DeveloperPage.swift` | check-up, logs, hidden Developer options (tap the app mark in About 3 times) |
| `FileManagerPage.swift`, `AboutPage.swift` | file manager UI, version + licences |
| `Palette.swift`, `Look.swift` | colours/themes; backdrop, glass components (`GlassStack`, `GlassGroup`, `SectionLabel`) |
| `EngineOverlay.swift`, `LauncherHost.swift` | in-process play overlay; the SwiftUI root host |

### 7.3 Where do I look to (shell)

| Task | Files |
|---|---|
| Add a launcher tab | `SW/RootView.swift` (`enum Tab`, `TabView`), new `*Tab.swift` |
| Add a Settings toggle saved in `launcher.txt` | `SW/Prefs.swift` (`@Published` + `LauncherFile.set`), UI in `SW/SettingsTab.swift`; if `main.m`/ObjC must read it, `LauncherModel.m` or `LauncherPrefs.m` |
| Change brand colours / presets | `SW/Palette.swift` (`ThemePreset`, `Palette`), `SW/Prefs.swift` (`AccentLook`) |
| Change the app icon | `python3 tools/make_app_icon.py`, copy PNGs to `platform/ios/Assets.xcassets/AppIcon.appiconset/`; the in-app mark is `BrandMark` in `SW/Look.swift` |
| Change where game files are expected / what "ready" means | `APP/LauncherModel.m` `checkFiles:` and the manifest `horizon-resources.json`; the engine's own check is in `horizon-client` (`G/no_resources.rs`) |
| Change the download | rules `APP/DownloadPlan.m`; disk `DownloadStore.m`; network `Downloader.m`; UI `SW/DownloadPage.swift`; docs `docs/IOS_DOWNLOAD_PLAN.md` |
| Add a Marketplace source | `APP/MarketClient.m` (index fetch), `MarketIndex.m` (rules: allowed hosts!), `MarketFetcher.m` (redirect rules), `MarketInstaller.m` (install path), UI `SW/MarketplaceTab.swift` + `MarketDetailPage.swift`; Modrinth is `ModrinthClient.m` |
| Change what the crash reporter records | `APP/CrashReporter.m`; reading side `SW/DiagnosticsEngine.swift` `CrashFiles`/`CrashInfo`, `SW/LogsView.swift` |
| Add a diagnostics check | `SW/DiagnosticsEngine.swift` (`CheckDef`, `CheckResult`), readings in `APP/Diagnostics.m` |
| Sign-in behaviour | rules `APP/AccountModel.m`; requests `AccountClient.m`; storage `AccountStore.m`; UI `SW/AccountPage.swift`; `docs/IOS_SIGN_IN.md` (needs an approved Azure app: `HZ_MSA_CLIENT_ID`) |
| Permissions / Info.plist / orientations | `platform/ios/project.yml` (`info:`), `APP/Horizon.entitlements` |
| Change what the game receives on launch | `APP/main.m` (argv), `APP/GameSession.m` (account file) |
| Edit controls from the launcher | `SW/ControlsTab.swift`, `SW/ControlsModel.swift` (keep in step with the engine, section 5 traps) |
| Add a file manager rule | `APP/FileBrowser.m` + its test `tests/file_browser_check.py` |

### 7.4 Persistence summary
Launcher: `launcher.txt` (the list is open-ended: search `LauncherFile.set(`/`HZTheme setSetting`; today it holds `openGame`, `inProcessPlay`, `appearance`, `glass`, `colour1`, `colour2`, `balance`, `accent`, `haptics`, `showHead`, `lightweight`, `lightweightAuto`, `compact`, `reduceMotion`, `keepAwake`, `confirmPlay`, `confirmInstalls`, `devMode`, `market.mods/.shaders/.other/.modrinth`, and caches `filesOK`, `resourcesKey`, `resourcesBytes`, `accountChecked`, `crashSeen`), `account.txt`, the Keychain items. `home/mod-browser.json` is the **install record** `MarketInstaller.m` writes in the desktop launcher's format (not a cache). `LauncherFile`/`HZTheme` keep **unknown lines** when writing; the engine files do not (section 5).

### 7.5 Adding a launcher key
`LauncherFile.set("key", value)` in Swift; reading from Objective-C goes through `HZTheme setting(for:)`. Never write `launcher.txt` by hand elsewhere: `HZTheme` holds an in-memory copy and writes within half a second.

---

## 8. Tests

| What | Command | Notes |
|---|---|---|
| Touch / settings / layout logic | `cd horizon && cargo test -p horizon-client-input` | offline, fast. Run it after any change under `IN/` |
| Settings screens and page rows | `cd horizon && cargo test -p horizon-client-render` | checks every iMC row has a key and a tooltip, English text equals `en_us.json` |
| Gameplay glue (`G/touch*.rs`) | CI only | the sandbox cannot build the whole client (system audio libraries) |
| Shell rules | `for t in platform/ios/tests/*.py; do python3 $t; done` | Python mirrors of the Objective-C rules: `account_rules`, `download_plan`, `download_rate`, `downloader`, `file_browser`, `game_session`, `launcher_prefs`, `market_index`, `market_install`, `modrinth` (each is a Python copy of the Objective-C rules and prints `ok`/`FAIL` per check; when you change a rule in the `.m`, change the copy too, because CI never runs these) |
| Repo guards | `tools/check_public_tree.sh` (no Mojang files, no secrets; ends by calling `tools/horizon_diff.sh --check`: every `horizon/` edit documented, patches current) | runs in CI "Public tree check" |
| Stack budget | `tools/check_stack_budget.py <Mach-O> 760` | needs the built binary; CI step "Check the startup stack budget" |
| Engine parity harnesses (`horizon/tools/test_*_parity.py`) | need the player's own Minecraft data in `.local/` | not runnable in the sandbox; upstream's, not ours |

---

## 9. CI (`.github/workflows/`)

| Workflow | Trigger | What it does |
|---|---|---|
| **`ios-app.yml`** ("iOS app") | push to `main` touching `horizon/crates/**`, `horizon/platform/**`, `horizon/Cargo.*`, `platform/**`, `tools/check_stack_budget.py`, the workflow; tags `v*`; manual (`simulator` option) | macOS 26 runner. Hashes `horizon/` (not docs/tools/*.md) as the Rust cache key -> restores or builds `libhorizon_ios_bridge.a` for `aarch64-apple-ios` (`cargo build --locked --release -p horizon-ios-bridge`) -> `xcodegen generate` -> **works out the version** (next `vN` = highest published `vN` + 1; `vN-dev` when not publishing) -> `xcodebuild` unsigned, passing `CURRENT_PROJECT_VERSION`, `HZ_BUILD_TAG`, `HZ_COMMIT` -> zips `Horizon-unsigned.ipa` -> **stack budget check** (760 KB) -> uploads the IPA as an artifact (named `...STACK-CHECK-FAILED-may-crash` if over budget) -> on `main` and a passing check, **publishes a prerelease `iMC Horizon vN`** and keeps the newest 15 |
| `ios-build.yml` ("iOS build") | push or PR touching `horizon/crates/**`, `horizon/platform/**`, `horizon/Cargo.*`; manual | two jobs on `macos-15`: runs `cargo test -p horizon-threads process_memory` (real Apple `task_info`), and builds `libhorizon_ios_bridge` for device and simulator targets and checks the exported entry point and size |
| `ios-shell-check.yml` | push to `main` touching `platform/ios/App/**`; manual | `clang -fsyntax-only` on each `APP/*.m` against the iOS SDK (about a minute, no engine). Files that import `Horizon-Swift.h` are skipped (only the full build compiles them) |
| `public-tree.yml` | every push and PR (ubuntu) | `tools/check_public_tree.sh`, which runs upstream's public-tree guard, rejects tracked `.jar/.class/.ipa/.p12/.mobileprovision/.pem` under `platform docs tools .github` and token-looking strings, then runs `tools/horizon_diff.sh --check` |
| `ios-probe.yml`, `java-runtime-probe.yml`, `java25-ios-build.yml` | manual only | feasibility probes (JVM on iOS); not part of the app |
`concurrency` cancels an older run of the same ref. The workflow is the source of truth for whether the app builds. **Pushing to `main` under those paths publishes a release**, so every merge to `main` that touches the app produces an IPA.

Version in the app: About page shows `HZBuildTag`, `CFBundleVersion`, `HZCommit` from Info.plist (`project.yml` `info:`).

---

## 10. Traps and rules that bite

1. **Stack budget.** An iOS main thread has ~1 MB. The engine builds `Game` (hundreds of KB) during start-up on that thread. Never construct `Game` by value, never remove `#[inline(never)]` or the `Box` in `new_boxed`, `start_game`, `Loading::finish*`, `run_synchronous`; CI fails over 760 KB (`docs/IOS_CRASH_STACK.md`).
2. **Settings files are rewritten whole by both programs** (section 5).
3. **Public tree**: never commit Mojang files, jars, IPAs, keys or tokens (`tools/check_public_tree.sh`).
4. **Document every `horizon/` edit** in `docs/HORIZON_CHANGES.md` and refresh the patches, or CI fails.
5. **Pure logic in `IN/`, tested; glue in `G/`, untested here.** A mistake in `G/touch*.rs` only shows up in CI or on the phone.
6. **Controllers reach only what registers** (upstream rule): draw buttons with a registering helper (`ui::button`, `settings_shell::foot_button`), not `graphics_style::button`/`screen_draw::button` (paint only).
7. **No hard-coded UI text in the engine**: use language keys (`Text::tr`, `lang::get`); the iMC page uses `horizon.imc.*` keys with an English fallback and tests that tie the two.
8. **iOS cannot grab the pointer** (winit): mouse-look never runs; all looking is `look_turn` from `Action::Look`.
9. **The launcher is portrait, the game is landscape**; the game window requests landscape only (`IN/window.rs`). In in-process play the engine window starts portrait while it waits (`ios_hold::window_starts_portrait`).
10. **App shell exclusivity**: the Swift code reads `launcher.txt` through `HZTheme`'s in-memory copy; do not read the file directly for a value that was just set.
11. **The Xcode project is generated** (`xcodegen generate` from `project.yml`); add Swift/ObjC files to `App/` and they are picked up, do not hand-edit a `.xcodeproj`.
12. **Upstream rebase**: `docs/HORIZON_CHANGES.md` section G is the procedure; `docs/horizon-changes-upstream.patch` applies with `git apply --3way` in an upstream clone.

---

## 11. Docs worth opening
`docs/HORIZON_CHANGES.md` (every engine edit, by topic A to Q, with risk and how to re-apply), `docs/IMC_SETTINGS.md` (what each iMC setting does), `docs/LAUNCHER.md`, `docs/IOS_TOUCH_AND_LIFECYCLE_DESIGN.md`, `docs/IN_PROCESS_PLAY_DESIGN.md`, `docs/IOS_CRASH_STACK.md`, `docs/IOS_MEMORY_STRATEGY.md`, `docs/IOS_MARKETPLACE.md`, `docs/IOS_SIGN_IN.md`, `docs/IOS_DOWNLOAD_PLAN.md`, `docs/SESSION_LOG.md` (history), `docs/NEXT_STEPS.md`; upstream's `horizon/AGENTS.md` and `horizon/docs/architecture.md` (a feature-to-files table for the whole engine).

---

*Verified against `main` at the commit that added this file (see `git log -1 -- docs/CODE_MAP.md`); every file path and function name in it was checked to exist at that time. Line numbers marked `~` drift: search by name. Keep this document current: when you add a file, setting, button or shared file, update the matching table in the same commit.*
