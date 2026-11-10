---
title: Touch controls (M5) and lifecycle (M4): design from source
summary: What the engine already provides, the smallest set of edits under horizon/ for touch and lifecycle, and what is still a guess. This is the original design (2026-11-08); touch and lifecycle have since been built, see the update below.
---

# Touch (M5) and lifecycle (M4): design

Written 2026-11-08 from reading the code. **At the time of writing nothing here had been compiled or run.** Every claim
about the engine says where it was read. Guesses are marked GUESS.

**Update 2026-11-10.** The design was built and has shipped in the iOS builds (never confirmed on a phone beyond the first test, which found the touch offset). Where to look now: the touch state machine is `touch.rs` in `horizon-client-input`, the glue is `game/touch.rs`, the lifecycle hooks are `game/lifecycle.rs` and the `suspended` / `memory_warning` handlers, and the settings are in `IMC_SETTINGS.md`. Every edit under `horizon/` is listed with its reason in `HORIZON_CHANGES.md` (sections C and M), and the findings below are left as they were written. Later additions not in this design: calibration, a touch controls editor, Cursor mode, Auto Performance.

Owner approval (2026-11-08): edits under `horizon/` are allowed for this work. Keep them to one hook
point plus new files. Never touch `Cargo.lock`.

## 1. What the engine already gives us (read from source)

1. **Touches are dropped today.** winit 0.30.13 on iOS delivers `WindowEvent::Touch` (id, physical
   location, phase; multitouch is on: `ios/view.rs:374`, `handle_touches` at `:477`). No code in
   `horizon-client` matches `WindowEvent::Touch` (grep over `game.rs` and `game/*.rs`).
2. **One choke point for window events.** `Game::handle_window_event_inner`
   (`game.rs:14556`) is where every key and mouse event is interpreted. Its own doc comment says
   so. `agent.rs` (`synth_drag`, `:927`) already builds `CursorMoved` and `MouseInput` events and
   feeds them to `handle_window_event`, so synthesising pointer events is an established pattern.
3. **A virtual controller already exists.** `Pads.injected: PadState` (`game/pad.rs:63`) is merged
   with the hardware state on every poll (`pad.rs:324`, `hardware.merge(&self.pad.injected)`).
   `PadState` holds a button bit set, two sticks and two triggers (`gamepad.rs:146`). Buttons are
   routed through the player's own bindings (`actions_of(button)` then `pad_action`,
   `pad.rs:459-545`), so jump, sneak, use, attack, inventory, drop, hotbar step and pause (Start ->
   `pad_back`) all work with no new gameplay code.
4. **Stick to movement and look is done.** Left stick -> `pad_move` (`pad.rs:638`) and the
   `eight_direction_keys` helper. Right stick -> `pad_look` (`pad.rs:667`), per frame, with
   `look_deadzone` and sensitivity settings.
5. **`controllers` is a cargo feature** (default on in `horizon-client`). Without it, only the
   virtual pad exists (`pad.rs:132-190`). Whether the iOS build has it on, and whether `gilrs`
   even compiles for iOS, is NOT checked yet (`platform/ios-bridge/Cargo.toml` depends on
   `horizon-client` with default features, so it is probably on; GUESS).

## 2. Proposed touch design

**Principle: touch is a new route into existing handlers, never a fork of gameplay.**

Two layers, both inside one new file `horizon-client/src/game/touch.rs`, reached from one hook:

### Hook (the only edit to an existing file besides module registration)

At the top of `handle_window_event_inner` (before the `Focused(false)` block):

```rust
if let WindowEvent::Touch(touch) = &event {
    self.touch_event(event_loop, touch);
    return;
}
```

Exact hook sites (read 2026-11-08, line numbers will drift):

1. `game.rs:14556` `handle_window_event_inner`: the `WindowEvent::Touch` early return above.
2. `game/window_handler.rs:160`, next to `self.poll_pads(event_loop)`: `self.touch_frame(event_loop)`.
   It reads the clock, runs `Touch::tick`, writes the stick into `pad.injected.left` and applies the
   returned actions. Must run **before** `poll_pads` so the same frame sees the stick.
3. `game.rs:~7609`, in the frame builder right after `self.draw_pad_cursor(&mut batch)`:
   `self.draw_touch_controls(&mut batch)`. The HUD is in **GUI pixels** (`HudBatch.scale`,
   `hud.rs:1567`), touch is in **physical pixels**, so the glue divides by `batch.scale`.
4. `mod touch;` and a `touch: touch::Touch` field in `Game`.

Pure logic is already written and tested: `horizon-client-input/src/touch.rs` (20 tests, clippy
clean, mutation-checked). What remains is the glue file `game/touch.rs`, which cannot be tested
without the 25 minute engine build.

### Layer A: menus and the title screen (pointer emulation)

When not playing (title, inventory, any `Screen` other than `Playing`, dialogs): one finger is the
mouse. A touch start becomes `CursorMoved` + `MouseInput(Left, Pressed)`; moves become
`CursorMoved`; end becomes `MouseInput(Left, Released)`. Every widget, slider, inventory slot drag
and scroll list then works by construction, because they already handle the mouse. Long-press
(about 400 ms, no movement) becomes a right click, which is how the inventory splits stacks.
Two-finger vertical drag becomes `MouseWheel` for lists.

Why this and not "make widgets touch-targetable" (the roadmap's wording): the engine's UI is
immediate-mode and mouse-driven; emulating the pointer needs no per-screen work. Risk: hover-only
effects, and tooltips need a finger held still. Acceptable for a first build.

### Layer B: playing (virtual pad)

On-screen controls are drawn by the engine's HUD and drive `pad.injected`:

| Control | Region | Drives (defaults read from `gamepad.rs:303 ACTIONS`) |
|---|---|---|
| Move joystick | left third, floating origin at first touch | `injected.left` |
| Look | right two thirds, any drag not on a button | `look_turn(dx, dy)` (see below) |
| Attack / mine | tap or hold on the world | `Button::RightTrigger` (`key.attack`) |
| Use / place | dedicated button, or long-press | `Button::LeftTrigger` (`key.use`) |
| Jump | button, right edge | `Button::South` |
| Sneak | button | `Button::RightStick` (`key.sneak`; has a toggle mode) |
| Sprint | double-tap forward, or button | `Button::LeftStick` |
| Inventory | button | `Button::North` |
| Drop | button | `Button::DPadDown` |
| Swap offhand | button | `Button::West` |
| Chat | button | `Button::DPadUp` |
| Pause | button | `Button::Start`, hardwired to `pad_back` (`pad.rs:~486`), not rebindable |
| Hotbar | tap a slot, or swipe | `LeftBumper` / `RightBumper` step previous/next |

The touch layer should press the **Button**, not call the action, so a player's rebinds in the
controller settings apply to touch too. It must also use the same `late_releases` path (a tap
shorter than one game tick would otherwise be lost, `pad.rs:382-397`); that path is only entered
through `edges.update` in `poll_pads`, which injected state already goes through.

Look through the right stick is simplest but gives velocity control (a stick), not drag control. A
finger drag should be 1:1 like a mouse. So look should call `self.mouse.on_move(...)` /
`look_turn` with the drag delta instead (the same entry the mouse uses at `window_handler.rs:~290`),
leaving the right stick alone. GUESS: this needs a sensitivity multiplier tuned on the phone.

### Drawing the controls

Needs a HUD draw call. Not yet read: how `hud.rs`/`HudBatch` draws rectangles and circles and how
`render` is ordered. First build can draw nothing (invisible zones plus a debug overlay), since
the owner can tell where the zones are. UNKNOWN effort; read `hud.rs` first.

### Tests (offline, before any 25 minute build)

The pure parts go in `horizon-client-input` as a new file `touch.rs` with no winit types beyond
`f32`: zone classification, floating joystick maths (offset to `[x,y]` with deadzone and clamp),
tap versus hold versus drag classification with a clock argument, and two-finger scroll. These
run as `cargo test -p horizon-client-input` on this Linux machine in seconds. Only the thin glue in
`horizon-client/src/game/touch.rs` needs the 25 minute build to check.

## 3. Lifecycle (M4)

Read from source:

- iOS winit maps `UIApplicationDidBecomeActive` -> `Resumed` and `WillResignActive` -> `Suspended`
  (`ios/event_loop.rs:186-203`). These fire on **every** Control Center pull, call banner or Siri,
  not only on backgrounding. Entering background also sends `Occluded(true)`
  (`send_occluded_event_for_all_windows`, `:216-231`). Memory warnings arrive as
  `ApplicationHandler::memory_warning`.
- `Game::resumed` returns early when a window exists (`window_handler.rs:203`), which is harmless
  for repeated activation. It also means a surface lost during a long background is never
  recreated through that path. **Whether it actually is lost is not known**: wgpu on iOS keeps the
  CAMetalLayer, so it may survive (GUESS). Test on device before adding recreate logic.
- `suspended` and `memory_warning` are not implemented on any of the four startup handlers
  (`no_resources.rs`, `loading_screen.rs`, `split.rs`, `window_handler.rs`), so both are silently
  dropped (the roadmap already notes this).

Minimum useful M4, in priority order:

1. `Game::suspended`: if playing, save the world (reuse the `save_for_exit` or autosave path;
   must read which is safe to call from a non-exit context) and release held keys and pad state
   (`release_source`, `pad_cancel_inputs`). This protects the player's world if iOS kills the app
   in the background, which is the real risk.
2. `Game::memory_warning`: call `horizon_threads::release_free_memory()` and drop caches the
   roadmap lists. Needs a read of `streaming.rs:357` and `audio.rs:151` for safe entry points.
3. Forward both in `Split` (it wraps `Game`; `split.rs:592`).
4. Surface recreation only if a device test shows a black screen after backgrounding.

## 4. Order of work

1. DONE: `horizon-client-input/src/touch.rs`, the pure logic, 20 unit tests.
2. DONE: HUD read. Draw with `HudBatch::fill(&self.gui.atlas, x, y, w, h, argb)` and `text`.
3. One batched engine build containing: touch glue, `suspended`, `memory_warning`.
4. Device test with the real resources folder.

## 5. Open questions for the owner

- Joystick on the left and look on the right, or the reverse? Left-handed layout later.
- Should a tap on the world attack, or place? Most mobile ports: tap = attack/mine (hold),
  separate button or long-press = place.
- Is a visible on-screen layout needed in the first build, or are invisible zones enough to test
  the glue?
