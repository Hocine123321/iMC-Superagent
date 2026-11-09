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
| Reset to defaults | button | | Puts every setting back. |

**The defaults are the values touch had before this page existed**, so nothing changes until the
player changes something. A test pins this (`the_defaults_are_the_values_touch_had_before_it_had_settings`).

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
```

A stepped setting is stored as the index of its choice. A missing, unknown or out-of-range line
keeps the default for that one setting and never loses the others. The file is not written until
something differs from the defaults (the same rule `horizon-extras.txt` follows).

## Where the code is

| Piece | File |
|---|---|
| Values, parsing, saving, `apply` to the finger logic (pure, 10 tests) | `horizon/crates/horizon-client-input/src/imc_settings.rs` |
| `Settings.imc`: loaded and saved with the other Horizon files | `horizon/crates/horizon-client-render/src/settings.rs` |
| The page, its buttons, `Act::Imc` and `Act::ImcReset` | `horizon/crates/horizon-client-render/src/options_ui.rs` |
| Applies the values to the fingers; hides the buttons; scales the margins | `horizon/crates/horizon-client/src/game/touch.rs` |
| English text (`horizon.imc.*`, `horizon.pages.imc*`) | `horizon/crates/horizon-client/assets/horizon/lang/en_us.json` |

Other languages fall back to English, as the PvP & HUD keys already do in most of them.

These are edits under `horizon/`, which is normally off limits. They were kept to one new file in
the input crate plus small hooks, and no dependency or `Cargo.lock` change was needed
(`horizon-client-render` already depends on `horizon-client-input`).

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

## Still to check on the phone

1. That a finger now lands exactly under itself, in menus and in the world.
2. That the drawn buttons line up with where they react. They are laid out in the surface's own
   pixels, so they should; if they are off while menus are right, this is the place to look.
3. If an offset remains, send `latest.log`. It records the surface size at start
   (`device ready; configuring the surface (WxH ...)`). Compare it with the 2532x1170 of a full
   iPhone 12 screen: if it is smaller, the first surface was the safe area, and if a later size
   change is missing the renderer may still be on it.
