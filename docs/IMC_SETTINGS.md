---
title: iMC Settings and the touch offset fix
summary: What the in-game iMC Settings page holds, where it is stored, how it reaches the touch controls, and the touch offset bug (cause, fix, and what is still unchecked on a phone).
---

# iMC Settings

Written 2026-11-09. **Compiled and run on CI only; not yet run on a phone.** The pure parts
(`imc_settings.rs`, `to_surface`) have unit tests that pass offline. The page itself, and its link
to the touch controls, were written without a full engine build and are checked by the CI run.

## What it is

A page inside the game, under **Options > Horizon Settings > iMC Settings...**, for settings that
belong to the iOS app and not to Minecraft. It follows the same pattern as the PvP & HUD page: a
`Page` in `options_ui.rs`, buttons two to a row, a tooltip on each, and a Done button.

| Setting | Choices | Default | What it changes |
|---|---|---|---|
| On-screen buttons | On, Off | On | Shows or hides the Jump, Sneak, Run, Use, Pause, hotbar, Drop and Inv buttons. Off: the left side still steers and the rest still looks. |
| Double tap to jump | On, Off | Off | A double tap on the world jumps (`Touch::double_tap_jump`). |
| Look speed | Slowest, Slow, Normal, Fast, Fastest | Normal | Degrees of view turn per pixel of drag: 0.05, 0.075, 0.10, 0.14, 0.20. |
| Hold to mine | Very short, Short, Normal, Long | Short | How long a finger must stay still before it mines: 0.15, 0.25, 0.40, 0.60 s. A tap is shorter than this; a long press is 0.15 s longer, so the two never overlap. |
| Stick size | Small, Normal, Large, Largest | Normal | Finger travel for full speed, as a fraction of the screen's shorter side: 0.10, 0.14, 0.18, 0.22. |
| Steering area | Narrow, Normal, Wide, Widest | Normal | How much of the left side steers: 30%, 40%, 50%, 60% of the width. |
| Screen margin | None, Small, Normal, Large | Normal | Multiplies the button layout's safe margins (8% sides, 4% top, 7% bottom) by 0, 0.5, 1 and 1.5. |
| Auto sprint | On, Off | **Off** | Pushing the stick forward to its edge holds Run (starts at 95% of full tilt, stops below 80%). Backward and sideways never sprint. A thumb that is steering cannot also hold the Run button. |
| Touch shift X, Y | -16, -8, 0, +8, +16 px | 0 | Moves every touch by that many screen pixels, after the safe-area correction. For an offset that is left on this phone (see below). |
| Menu touch | Precise, Normal, Careful, Very careful, Firm | Normal | How far a finger may drift on a menu and still be a tap: 0.5, 1, 1.75, 2.5 and 3.5 times the screen's own slop (1% of the shorter side, 11.7 px on an iPhone 12). Higher stops accidental presses and slider moves. |
| Button shift X, Y | -16, -8, 0, +8, +16 px | 0 | Moves where the **on-screen buttons answer**, not how they are drawn and not menus. For the in-game offset (see below). Negative X moves the hit area left, negative Y up. |
| Mobile preset | button | | One tap to settings that suit a phone. Sets the engine's Performance preset (render distance 8, simulation distance 6, no clouds, minimal particles, no entity shadows, no biome blend, no mipmaps) and adds battery mode, max FPS 60 with vsync, no view bobbing, and resolution 100%, no LOD, no upscaling, no HDR, no frame generation. Leaves alone smooth lighting, FOV, sensitivity, GUI scale, the texture budget, the shader pack and every iMC setting. Every value stays adjustable afterwards. Works from the title screen too. |
| Reset to defaults | button | | Puts every setting back, Auto Performance included. (It resets the iMC settings only, not what the Mobile preset changed.) |

**The defaults are the values touch had before this page existed**, so nothing changes until the
player changes something. A test pins this (`the_defaults_are_the_values_touch_had_before_it_had_settings`).

## Auto Performance

Written 2026-11-09. **Compiled on CI only; never run on a phone.** The rules are pure code with 14
offline tests; the glue into the game is not covered by any test.

iOS ends an app that holds too much memory, with no warning. The game used to react only to the
system's own memory warning (`lifecycle.rs`). Auto Performance watches **before** that.

**How it works.** Every 5 seconds `game/auto_performance.rs` reads
`os_proc_available_memory()` (how much more memory iOS will let the app use; one kernel counter, no
allocation, so the frames in between pay one `Instant` comparison). The governor
(`horizon-client-input/src/auto_performance.rs`) turns that into **caps**, applied on top of the
player's settings. **The player's saved values are never rewritten**: a bad minute in a crowded
area does not leave the render distance lower for good, and switching it off puts everything back.

| Order | Lever | Step | Why this order |
|---|---|---|---|
| 1 | Far terrain (LOD distance) | half, a quarter, then off | Only the horizon shows it |
| 2 | Render distance | 2 chunks at a time, down to the player's floor | The largest cost: loaded columns, meshes, GPU arenas |
| 3 | Resolution scale | 85, 70, 55 % | Every pixel shows it, so it is **off unless the player allows it** |

**Where the caps are applied** (one helper, `Game::capped_render_distance`, so nothing disagrees):
`apply_settings` (the client's chunk radius), `far_terrain_choice` (LOD), `apply_ui_settings`
(resolution), joining a server and the server's chunk-cache radius packet (`remote.rs`), a dedicated
guest (`dedicated.rs`), and the per-frame `set_distances` call to the single-player server thread
(`game.rs`). The last one matters most: in single player the server keeps its own copy of every
loaded column, so capping only the client would free only part of the memory. Simulation distance is
held to the render distance only while a render cap is in force.

**Not flapping.** Changing the render distance meshes every section again, so:
- a step down needs 10 s to show before the next one (except below the critical line, which pulls
  every allowed lever at once);
- quality comes back one step at a time, after **6 comfortable readings in a row (30 s)**;
- between the "low" and "comfortable" lines nothing moves, and a dip restarts the count.

**Customisation** (iMC Settings > Performance, all saved in `horizon-imc.txt`):

| Setting | Choices | Default |
|---|---|---|
| Auto Performance | On, Off | **Off** |
| Reacts | Relaxed, Balanced, Early | Balanced |
| Lowest distance | 2, 4, 6, 8, 10, 12 chunks | 6 |
| Lower render distance | On, Off | On |
| Cut far terrain | On, Off | On |
| Lower resolution | On, Off | Off |

The settings under the switch are greyed while it is off. A grey line on the page says what is
being held back right now.

**The thresholds are guesses.** Available memory below which it steps down: Relaxed 350 MB,
Balanced 500 MB, Early 700 MB; "comfortable" is 300 MB above that; "critical" is 40 % of the low
line. `IOS_MEMORY_STRATEGY.md` says the real margin must be chosen after seeing run-to-run variance
on the device, and that has not happened. **First job on the phone: read the `Auto Performance`
lines in `latest.log` (they print the available MB at each change) and move the numbers in
`Sensitivity::low_mb`.** Where the system does not say (the simulator, a desktop), nothing is capped.

**Not done:** it does not lower entity distance, mipmaps, biome blend, particles or the audio cache
(the audio cache is large on a 4 GB phone and is the next candidate); it does not react to
`thermalState` (heat), only to memory; and it cannot free the server thread's own generation caches.

### What costs the most (the notices)

The page ends with a grey list of the engine settings that cost the most on a phone: render
distance, LOD distance, resolution scale, simulation distance, mipmap levels, biome blend and TAA,
each with its kind of cost (memory, speed, or both) and one line of why. **No megabyte figures are
quoted**, because none has been measured on an iPhone and an invented number would be believed (a
test enforces it). Replace the wording with measured numbers once `IOS_MEMORY_STRATEGY.md` section 5
has them. The notices sit on the iMC page; they are not yet drawn beside the settings on the Video
page itself.

## Where it is stored

`horizon-imc.txt`, beside `options.txt` (so `options.txt` stays exactly vanilla's, as
`horizon-extras.txt` does). On the phone that is `Files > Horizon > home`. One `key:value` per line:

```
touchControls:true
lookSpeed:2
stickSize:1
moveZone:1
holdTime:1
doubleTapJump:false
safeMargin:2
autoPerformance:false
autoSensitivity:1
autoMinDistance:2
autoFarTerrain:true
autoRenderDistance:true
autoResolution:false
```

A stepped setting is stored as the index of its choice. A missing, unknown or out-of-range line
keeps the default for that one setting and never loses the others. The file is not written until
something differs from the defaults (the same rule `horizon-extras.txt` follows).

## Where the code is

| Piece | File |
|---|---|
| Values, parsing, saving, `apply` to the finger logic, the heavy-setting notices (pure, 17 tests) | `horizon/crates/horizon-client-input/src/imc_settings.rs` |
| The governor: when to cut what (pure, 14 tests) | `horizon/crates/horizon-client-input/src/auto_performance.rs` |
| The 5 s memory check and where the caps are applied | `horizon/crates/horizon-client/src/game/auto_performance.rs` |
| `Settings.imc`: loaded and saved with the other Horizon files | `horizon/crates/horizon-client-render/src/settings.rs` |
| The page, its buttons, `Act::Imc`, `Act::ImcReset` and `Act::MobilePreset` | `horizon/crates/horizon-client-render/src/options_ui.rs` |
| The Mobile preset's values (pure, 6 tests) | `horizon/crates/horizon-client-render/src/mobile_preset.rs` |
| Applies the values to the fingers; hides the buttons; scales the margins | `horizon/crates/horizon-client/src/game/touch.rs` |
| English text (`horizon.imc.*`, `horizon.pages.imc*`) | `horizon/crates/horizon-client/assets/horizon/lang/en_us.json` |

Other languages fall back to English, as the PvP & HUD keys already do in most of them.

These are edits under `horizon/`, which is normally off limits. They were kept to one new file in
the input crate plus small hooks, and no dependency or `Cargo.lock` change was needed
(`horizon-client-render` already depends on `horizon-client-input`).

## Touch behaviour added with Auto Performance

Written 2026-11-09, **compiled on CI only, never run on a phone**; the pure logic has tests.

- **Tap a hotbar slot to select it** (`touch::hotbar_slots`). The nine slots are laid out as the
  engine draws them (182 by 22 GUI units, centred; `hud_layout::hotbar`) and each target is the
  whole 20-unit column, grown 6 units upward for a thumb. It pushes onto the same queue as the
  number keys (`hotbar_presses`), so multiplayer ordering is the engine's. Skipped for spectators.
  The hotbar's left end is inside the steering zone; the slots are checked first, so a finger
  there selects a slot instead of starting the stick.
- **Auto sprint**: see the table. Held on the virtual controller's Run button, so the player's
  rebind applies. The Run pad's own finger keeps its press if both want it.
- **The stick follows an overshoot**: past full travel the origin is dragged after the thumb, so
  turning back is one short move.
- **Tap tolerance scales with the screen** (1% of the shorter side, never under 8 px; 11.7 px on
  an iPhone 12, close to the fixed 12 it replaces).

## Menu touch (2026-11-09, third round)

Written 2026-11-09, **tests only, never run on a phone**. A menu used to press the instant a finger
landed, so a brush or a scroll that began on a button or slider activated it, and a list could be
moved only with two fingers. One finger in a menu now decides by what it does (`touch.rs`, `Gesture`):

- **Lands:** only the pointer moves (hover). Nothing is pressed.
- **Lifts without going past the Menu touch distance:** a tap. The press and release come together
  where it lifted, so a shaky thumb is still one click.
- **Goes past the distance, mostly sideways:** a drag. The button is pressed where the finger
  *landed* and the pointer follows, which moves a slider's knob. Released on lift.
- **Goes past the distance, mostly up or down:** a scroll. The list follows the finger (a line per 40
  px) and **nothing is pressed**, so it cannot hit a button it started on.
- **Held still:** after the hold time plus 0.15 s, a right click, as before. Only while undecided.
- The choice is made once per touch. A second finger is still the two-finger scroll.

The split by direction needs no knowledge of what is under the finger, so the engine is untouched.
Its cost: a vertical drag that starts on a slider scrolls instead of moving it, and a slider is
moved by dragging sideways. A slider track that is itself dragged vertically (none known) would not
work.

## Not done

- The page is reachable from the game's Options only. Opening it from the launcher's Home screen is
  not built.
- The settings do not yet include the graphics API, render distance preset or "keep screen on"
  that `LAUNCHER.md` lists. Those need the engine to read a launcher-written file at start.
- Translations.
- Nothing here has been seen on a phone: the layout of the page at 427x240 GUI units and the feel of
  each choice (the look speeds in particular are guesses) need the owner's hands.

# The touch offset bug

**Reported (build v4):** touch lands a little to the right and a little below the finger.
**Not recreated on a device.** The cause below is from reading winit 0.30.13's iOS backend
(`ios/view.rs`, `ios/window.rs`) and the engine; it explains the direction of the error, but it is
not yet confirmed on the phone.

## Cause

On iOS winit gives two different frames:

- **Touches** are `UITouch.locationInView(nil)`, in the **window's** coordinates, multiplied by the
  view's `contentScaleFactor` (`handle_touches`, `view.rs`).
- **The surface** is first sized from `Window::inner_size()`, which on iOS is the **safe area**: the
  screen minus the notch, the rounded corners and the home bar (`safe_area_screen_space`,
  `window.rs`). Its corner is `Window::inner_position()`, not the window's corner.

The engine treated a touch as if it were relative to the surface. On an iPhone 12 in landscape the
safe area starts about 47 points (141 px at 3x) in from the left, so every touch read that far too
far right, and any top inset too far down. That matches "to the right, and a little down".

## Fix

`horizon_client_input::touch::to_surface(at, safe_origin, safe_size, surface)` moves a touch back
by the safe area's corner, but only when the surface really is the safe-area size. The surface is
one of two sizes: the first one is made from `inner_size()` (the safe area), and `Resized` (sent by
`layoutSubviews`) reports the whole window. If the surface is the whole window the touch is already
right, and subtracting the corner would push it the other way, so it is left alone. A desktop
window has a zero corner, so nothing moves there either. `Game::touch_event` passes in
`Window::inner_position()`, `Window::inner_size()` and the renderer's real size, and the result is
clamped to the surface.

Four tests: the iPhone 12 numbers with a safe-area surface, a whole-window surface (no move), a
desktop window (no move), and a touch on the notch (lands on the nearest edge pixel).

## An offset that is left (2026-11-09, second report)

The owner reported the offset "still there by a small margin" after the fix above. **The cause is
not known.** What the winit 0.30.13 source rules out:

- Menu pointer mapping is right: `CursorMoved` is divided by the GUI scale, the exact inverse of how
  the GUI is drawn (`game.rs`, `HudBatch::new`).
- Touch scale is not the suspect: touches and the surface both use the screen's scale (3.0 on an
  iPhone 12).
- Once `layoutSubviews` has run, `Resized` reports the **whole screen frame**, so the surface is
  the whole window and no shift is wanted; only the first surface (before layout) is the safe area.
  `to_surface` handles both, but it **decides which one it is by comparing sizes to within 1 px**,
  and that comparison is the one part that is a heuristic and not a fact. If the surface size is
  neither, the touch is left alone.

I could not run the phone, so I did not guess a third change. Two things were added instead:

1. **Touch shift X and Y** (iMC Settings > Screen): zero the offset on the spot. Move the shift the
   opposite way to the error: if the finger lands to the right, use a negative X.
2. **A log line on every press**, in `latest.log`:
   `touch: raw (x, y) safe origin (...) safe size WxH surface WxH window ... scale S -> (x, y) shift (...)`.
   Press the centre of a known button and send the log: the raw point, the sizes and the result
   state the error in numbers, and the shift needed is the difference.

The log line is cheap (one line per finger down, none per move) but should be removed once the
cause is fixed.

## The in-game offset (2026-11-09, third report)

The owner reported menus are now right but **the on-screen buttons in the game must be pressed a
little left and up of where they are drawn**. Measured, not guessed:

- The buttons are hit by rectangle in `touch_rects` and drawn by `draw_touch_controls`, from the
  same fractions. Hit uses the surface in pixels; drawn uses the GUI-unit size, which
  `HudBatch::new` rounds **up** (`ceil(window / scale)`). Worked through for three real screen
  sizes the two differ by **0 to 2 px**, nowhere near a visible error, so this is not the cause.
- Menus and the world take the same finger position (`touch_event`), so the position is not it.

So the cause is **still unknown**. Two things were added, as for the menu offset:

1. **Button shift X and Y** (iMC Settings > Screen) move the hit rectangles only. Press where the
   button is *drawn*; if it does not answer, shift the hit area toward where you had to press.
2. **A log line on every press while playing**: `touch button: finger (x, y) nearest <button>
   centre offset (dx, dy) rect WxH at (x, y) hit true|false`. Press the middle of a few buttons and
   send `latest.log`: the average `dx, dy` is the shift to set, and it says whether the cause is
   constant.

## Edit touch controls, Back, and controller hints

**Edit touch controls** (iMC Settings, next to *Reset to defaults*; needs a world open, the buttons are
shown over it). The buttons are drawn exactly as in play. Drag one to move it; the panel on the right
sets its size (50% to 200%) and fade (20% to 100%), hides or shows it, and resets it. *Reset all* puts
every button back. **Done** keeps the arrangement, **Cancel** (or Back) restores the one the editor
opened with. A hidden button is drawn faintly in the editor so it can be found again.

The arrangement is saved in `horizon-touch-layout.txt`, beside `horizon-imc.txt`, as the difference
from the built-in layout. Nothing edited means no file, and every button exactly where it was.
Screen margin and Button shift still apply on top. A damaged file is ignored line by line and cannot
push a button off the screen.

**Calibrate touch.** If a touch lands a little off, more toward the edges of the screen, *Calibrate
touch* (beside *Reset*) shows five crosses. Tap the centre of each with the tip of a finger; the game
fits a shift and a stretch for each axis from the five taps and keeps them
(`horizon-imc-touch-calibration.txt`). It applies to every touch, menus and world alike, on top of
Touch shift. If the taps are too close together to tell, it says so and starts over. Each tap is also
written to the log (where the window said it was against where the cross is), so a stubborn offset
can be diagnosed.

**Extra buttons.** *Extra buttons* (iMC Settings) lists six more buttons for the screen while you
play, all off until switched on: **Chat**, **F3**, **F2** and **View** press the keys you set in
Controls for chat, the debug screen, screenshots and the camera, so a rebind carries over. **Key 1**
and **Key 2** press a key picked on the right of each: a click steps through none, F1, F4 to F11 and
some letters. They stand in a column down the left edge under Pause, and *Edit touch controls* moves,
resizes, fades or hides them like the others. They are saved in `horizon-imc-buttons.txt`.

**Back on the title menus.** Every title page but the first (Add Server, Direct Connection, Create
World, a world's Edit, Realms) and Options opened from the title now have the Back button.

**Back button.** On the inventory (and chests, furnaces, crafting), creative, chat, command block,
block editor, signs and books there is a Back button in the top left, since a phone has no Escape. It
fires when the finger lifts on it, so brushing past does nothing. While the phone's keyboard is up it
reads **Done**: the first tap puts the keyboard away (the text stays), the next leaves the screen.

**Controller hints.** The corner hints and the button symbols on menus are for a controller. Touch
no longer turns them on; they appear for a real controller, or a script's. This also stops the
engine's own on-screen keyboard from opening over the phone's.

## Still to check on the phone

00. New this round: open the inventory in a world. Is there a Back button top left, and does it close
    it? Open chat: with the keyboard up it should say Done; Done hides the keyboard, then Back leaves.
    No controller symbols or hints should appear anywhere while you only use your fingers.
01. iMC Settings > Edit touch controls: drag a button, change its size and fade, Done. Leave the
    world and come back: the arrangement is kept. Cancel restores. Reset all returns the original.
02. iMC Settings > Mobile preset: tap it, then look at Options > Video Settings. Render distance should
    read 8, max FPS 60, vsync on. Play for ten minutes and compare how warm the phone gets with a build
    that has not used the preset. Tell me if 8 chunks feels too short: it is a guess until M6 measures.
03. After any session: Diagnostics > Share now offers session-log.csv. It should have a line every
    5 seconds with your phone's model in the header (see SESSION_LOG.md).
0. Menus: tap, slide a slider sideways, scroll a list with one finger, and try to press by accident.
   Raise Menu touch if it still happens.
1. That a finger now lands exactly under itself, in menus and in the world.
2. That the drawn buttons line up with where they react. They are laid out in the surface's own
   pixels, so they should; if they are off while menus are right, this is the place to look.
3. If an offset remains, send `latest.log`. It records the surface size at start
   (`device ready; configuring the surface (WxH ...)`). Compare it with the 2532x1170 of a full
   iPhone 12 screen: if it is smaller, the first surface was the safe area, and if a later size
   change is missing the renderer may still be on it.
