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

- Settings (graphics API, render distance preset, controls layout). Needs the engine to read a
  launcher-written file at start.
- Account and ownership (M9) and download and preparation on the phone (M8b).
- Going back to the launcher from inside the game (a pause menu entry). Until then, closing the app
  returns to it.
- Play without a relaunch. That needs the game to run inside a launcher-owned view, which winit 0.30
  cannot do; a winit upgrade changes `Cargo.lock` and needs the owner's approval.

## Checked and not checked

Compiled on the Mac runner by `ios-shell-check.yml` (syntax only, against the iOS SDK). Not yet run
on a phone, so the layout (landscape, two columns) and the folder picker's behaviour with the Files
app are untested.
