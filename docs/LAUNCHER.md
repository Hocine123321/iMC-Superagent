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
- **Download Minecraft** (written 2026-11-10, never run): downloads the game from Mojang with a progress
  bar, behind the sign-in check. See `IOS_DOWNLOAD_PLAN.md`.
- **File manager** (M13, written 2026-11-10, never run): browses `Documents/Horizon` and nothing else.
  Folders first, sizes (folder sizes fill in as they are measured), dates and free space; tap a folder to
  open it, a small text file to read it, any other file to share it; swipe a row for Delete, Rename and
  Share; the **+** menu makes a folder or copies files in from the Files app (refusing a name already
  taken and a copy that would leave less than 100 MB free). Rules in `FileBrowser.m`: see below.
- **Marketplace** (M14, written 2026-11-10, never run): browses Horizon's registry (tabs, search, project pages). It does not install anything yet. See `IOS_MARKETPLACE.md`.
- **About** (M12, written 2026-11-10, never run): what the app is, that it is not a Minecraft product,
  the Horizon MIT licence in full, Horizon's third-party notices (bundled from `horizon/THIRD_PARTY_NOTICES.md`), links, and what the game sends.
- **Diagnostics**: the newest crash report (native `crash.txt` or the engine's
  `home/crash-reports/`, whichever is newer) and `home/logs/latest.log`, with a Share button.

## The file manager's rules (`FileBrowser.m`, checked by `tests/file_browser_check.py`, 61 checks)

- **Confinement.** A path is refused if it is absolute, has `..`, a backslash or an empty part. Otherwise
  the folder holding it is resolved through links and must still be inside the Horizon folder. A link
  planted inside pointing out is shown as a file, never opened as a folder, never counted for size, and
  deleting it removes the link only.
- **What a delete says first.** An ordinary file or folder: its size and "cannot be undone". Worlds
  (`home`, `home/saves`, anything under it): a strong warning that they cannot come back. Game files
  (`resources`, `minecraft`): the game will not start until downloaded or imported again. The sign-in
  record (`account.txt`): refused, with a pointer to the Account screen. The Horizon folder itself:
  refused. Names that only start like these (`homework`, `resources2`) are ordinary.
- **Names.** Not empty, not `.` or `..`, no slash, backslash or control character, at most 255 bytes, so
  a rename cannot move a file out of its folder.
- **Not there yet.** Exporting a folder as a zip (the Share swipe says so for folders), importing a
  folder, a backup copy offered before deleting a world, and Quick links to saves and packs.

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
  - **Start the launcher inside winit's own run**, as a window over winit's, with a hold in the
    engine's `Loading::resumed` / `about_to_wait` (`horizon-client/src/game/loading_screen.rs`)
    until Play. Read through on 2026-11-09 and **deliberately not built**: it needs a second
    `UIWindow` raised above winit's and handed back (window level, scene and key-window rules
    differ for a winit-made window), a flag shared between Objective-C and the engine, and the
    launcher's navigation stack torn down without a leak. Each failure is a **black screen with
    no log**, because the engine's logging has not started and the crash reporter sees a healthy
    process, and each try costs a 25 minute build. It would also add a `horizon/` change to the
    rebase list in `docs/HORIZON_CHANGES.md`. The skip switch above already removes the relaunch
    from the normal path, which is most of the gain. If it is wanted anyway, do it behind an
    off-by-default switch so a bad build cannot lock the owner out.

## Checked and not checked

Compiled on the Mac runner by `ios-shell-check.yml` (syntax only, against the iOS SDK). Not yet run
on a phone, so the layout (landscape, two columns) and the folder picker's behaviour with the Files
app are untested.
