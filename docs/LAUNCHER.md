---
title: The iMC Horizon launcher
summary: What the native launcher screens do, how Play works, and what is not built yet.
---

# The launcher

The app opens to a native launcher, not to the game. Source: `platform/ios/App/Launcher*.{h,m}`.

## How Play works

winit's `EventLoop::run` asserts that `UIApplicationMain` has not been called, and the game's event
loop owns it. So the launcher and the game cannot be two screens of one running process. They are
two runs of the app:

1. **Open** the app: `main.m` looks for `Documents/Horizon/start-game`. It is not there, so the
   launcher runs (`HorizonRunLauncher`).
2. **Play**: the launcher writes `start-game` and closes the app (iOS cannot relaunch an app).
3. **Open** again: `main.m` finds the flag, deletes it, checks the game files, and starts the engine.
4. Close the game and open the app: no flag, so the launcher is back.

**Open straight into the game** (a switch on the Home screen, off by default) skips steps 1 and 2:
with it on and the game files ready, opening the app starts the game. The setting is a line,
`openGame:1`, in `Documents/Horizon/launcher.txt`, because `main.m` reads it before the engine and
the engine's own settings live in `home/`. The launcher still opens when:

- the previous run left a crash report or the `.running` marker. **Swiping the game away also leaves
  that marker**, so the launcher shows once after that; it is the safe direction, and one Play tap
  gets back in;
- a file named `open-launcher` is in the `Horizon` folder (create it in the Files app, delete it to
  go back). This is the way out if the game starts and cannot be left;
- the game files are missing or damaged.

It is decided before the crash reporter starts, because the reporter rewrites `crash.txt`.
Written 2026-11-09, **compiled on CI only, never run on a phone.**

The flag is one-shot on purpose: a crashing game does not trap the person in a crash loop, the
next open is the launcher with the crash report on the Diagnostics screen.

If the flag is set but the files fail the check, the launcher opens instead of the engine.

## Screens

- **Home**: name, versions, the state of the game files (ready, missing, damaged), **Play**,
  and the way to the other two screens.
- **Game files**: **Import a folder** (the system folder picker; the copy is made beside the old
  files and swapped in only when complete, with a free-space check first), **Check**, **Delete**.
  The check is the engine's own rule (`missing_resources` and `damaged_prepared` in
  `loading_screen.rs`): `horizon-resources.json` present, not blank, valid JSON, and no other
  top-level `.json` empty.
- **Diagnostics**: the newest crash report (native `crash.txt` or the engine's
  `home/crash-reports/`, whichever is newer) and `home/logs/latest.log`, with a Share button.

## Not built yet

- Launcher settings (graphics API, render distance preset). Needs the engine to read a
  launcher-written file at start. The touch controls' settings already exist, inside the game:
  **Options > Horizon Settings > iMC Settings...** (see `IMC_SETTINGS.md`).
- Account and ownership (M9) and download and preparation on the phone (M8b).
- Going back to the launcher from inside the game (a pause menu entry). Until then, closing the app
  returns to it.
- Play without a relaunch, in one process. winit 0.30's `EventLoop::run` asserts that
  `UIApplicationMain` has not been called and calls it itself with no app class and no delegate
  (read in 0.30.13's `ios/event_loop.rs`), so the launcher cannot also call it. Two ways remain:
  - **Upgrade winit.** Only `0.31.0-beta.4` exists (stable is 0.30.13); it is a restructure into
    `winit-core`, `winit-uikit` and others on Rust edition 2024. 107 files and about 270
    `winit::` uses across four crates change, and `Cargo.lock` with them. Needs the owner's
    approval and a machine that can build the render crate; **not started**.
  - **Start the launcher inside winit's own run**, as a view over its window, with a gate in
    `horizon-client/src/game.rs` that holds the engine's start until Play. A change in `horizon/`,
    untested against a black-screen failure with no way back; **not started**. The skip switch
    above is the safe part of this.

## Checked and not checked

Compiled on the Mac runner by `ios-shell-check.yml` (syntax only, against the iOS SDK). Not yet run
on a phone, so the layout (landscape, two columns) and the folder picker's behaviour with the Files
app are untested.
