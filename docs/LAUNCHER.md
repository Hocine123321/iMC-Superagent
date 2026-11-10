---
title: The iMC Horizon launcher
summary: What the native launcher screens do, how Play works, the look and Settings, the source files, and what is not built yet. Written, compiled on CI, never run on a phone.
---

# The launcher

The app opens to a native launcher, not to the game. Source: `platform/ios/App/Launcher*.{h,m}` and, since v36, `platform/ios/App/Swift/`.

## The SwiftUI shell (M24 stage 2, built 2026-11-10, not yet seen on a phone)

`Launcher.m` now makes `HZLauncherHost.makeRoot()` (`Swift/LauncherHost.swift`) the window's root. It is a system `TabView` with three tabs: **Play** (`PlayTab.swift`: status card, Play, shortcuts to Download and Game files, the round Account button), **Packs** (the UIKit Marketplace, hosted) and **Settings** (`SettingsTab.swift`: Preferences, File manager, Game files, Diagnostics, About). Glass comes only from the system (`glassEffect`, `.glass`, `.glassProminent` on iOS 26 and later; materials and bordered buttons before), see `Swift/Look.swift`. The Objective-C screens are reused unchanged through `Swift/Hosted.swift`; Play still uses the relaunch described below (`LauncherState.play()`). **Where this page describes the old UIKit Home, its "..." menu and its tab bar, that layout is gone; the screens it lists are all still reachable, now from Settings or the Play tab.** The Home, Second pass and Look notes below are kept as history; `HZTheme` still supplies the colours.

## How Play works

winit's `EventLoop::run` asserts that `UIApplicationMain` has not been called, and the game's event
loop owns it. So the launcher and the game cannot be two screens of one running process. They are
two runs of the app:

1. **Open** the app: `main.m` looks for `Documents/Horizon/start-game`. It is not there, so the
   launcher runs (`HorizonRunLauncher`).
2. **Play**: the launcher writes `start-game` and closes the app (iOS cannot relaunch an app).
3. **Open** again: `main.m` finds the flag, deletes it, checks the game files, and starts the engine.
4. Close the game and open the app: no flag, so the launcher is back.

**Open straight into the game** (a switch in Settings under Start-up, off by default) skips steps 1 and 2:
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

- **Home** (redesigned 2026-11-10, never run): name and versions, a status card for the game files,
  a large **Play**, and a 2x2 grid of the things needed most (Download, Marketplace, Game files,
  Account). Everything else is behind the **...** button at the top right: Library (File manager,
  Game files), Tools (Diagnostics), Appearance (System, Dark, Light), Settings and About. The
  "open straight into the game" switch is on the Settings page, not here.
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
- **Marketplace** (M14, written 2026-11-10, never run): browses Horizon's registry (tabs, search, project pages). It installs, updates and removes resource packs (always shown), mods and shaders (shown once turned on in Settings), with an Installed tab, and can search Modrinth for resource packs once that is turned on. See `IOS_MARKETPLACE.md`.
- **About** (M12, written 2026-11-10, never run): what the app is, that it is not a Minecraft product,
  the Horizon MIT licence in full, Horizon's third-party notices (bundled from `horizon/THIRD_PARTY_NOTICES.md`), links, and what the game sends.
- **Settings** (written 2026-11-10, never run): see "Second pass" below for the exact contents.
- **Account** (M9, built, never run): sign in with Microsoft, or the private test mode. See `IOS_SIGN_IN.md`.
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

- Launcher settings for the engine (graphics API, render distance preset). The launcher's own Settings page exists
  (appearance, background colour, Marketplace visibility, start-up); engine settings live inside the game, in
  **Options > Video Settings > iMC** (see `IMC_SETTINGS.md`).
- A working sign-in (M9 needs the owner's Azure app and Mojang's approval) and preparation of the game files on the
  phone (M8b: the download is written but has never run; the Java preparation is not).
- Worlds, Screenshots and Logs pages (M12).
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


## Look: dark and light (written 2026-11-10, never run)

`LauncherTheme.{h,m}` is the one place for colours, buttons and the Background colour strength (`glass:` in `launcher.txt`, the name of the first version). Every colour is dynamic, so all
screens follow dark or light. The choice is the line `appearance:system|dark|light` in
`Documents/Horizon/launcher.txt` (the same file as `openGame:`; both setters keep the other's line)
and is applied to the window with `overrideUserInterfaceStyle`.

**Liquid Glass was tried and removed.** The first pass drew surfaces, buttons and controls on `UIGlassEffect`, found at run
time because CI builds with the iOS 18.5 SDK. On the test phone (iOS 27.2) it did not read as glass and came out as flat
black on the dark background, so everything is solid now (see the second pass). If the runner ever gets an iOS 26 SDK, the
system's own controls turn into glass without any code, and the custom ones could be dropped.

## Second pass (2026-11-10)

- **Glass did not work, so it is gone from the controls.** The first pass drew the slider, switch, tabs and progress bar
  on `UIGlassEffect` and called `glassButtonConfiguration` for buttons. On a phone (iOS 27.2) none of it looked like
  glass: over the launcher's near-black background there is nothing to refract, and the tabs came out as a black slab with
  no visible selection. The controls (`GlassControls.{h,m}`, names kept) are now plain: a clear track, an accent fill or
  pill, a white knob. The Home card is a system blur material with a hairline edge. Buttons still ask the system for
  `glassButtonConfiguration` / `prominentGlassButtonConfiguration` where it exists (iOS 26+); the owner said they did
  not look like glass either, so (polish pass) buttons are solid too: a primary button is the accent fill with the
  on-accent text, a secondary one is the surface colour. Contrast is the same on every iOS and in both themes.
- **Marketplace redesign.** Cards (a coloured icon tile per kind, name, kind and source, one-line summary, a pill that
  says Get / v1.2 / Desktop only) in a plain list, with one row of scrolling chips for the tabs. Both project pages share
  one layout (`HZMarketPageController`): header, a big Install button with a progress bar, one line saying what happens,
  the facts on the right.
- **Settings page** (Home > ... > Settings), grouped: **Look** (Appearance, Background colour, Compact lists, Reduce motion),
  **Marketplace** (Modrinth resource packs, Show mods, Show shaders, Show everything else, Ask before installing),
  **Start-up** (Open straight into the game). All saved in `launcher.txt` (`LauncherPrefs.{h,m}`), defaults the safe way.
- **What the Marketplace shows** (owner's rule): resource packs and Installed by default. Mods, Shaders and Everything are
  tabs that exist only once their switch is on; Modrinth likewise. Checked by `launcher_prefs_check.py`.
- **The ... menu** is grouped: Library (File manager, Game files), Tools (Diagnostics), Appearance, Settings, About.

## The source files (`platform/ios/App`)

| Files | What they do |
|---|---|
| `main.m`, `GameSession` | Entry point and the Play / flag logic; the signed-in profile handed to the engine |
| `Launcher`, `LauncherModel` | The navigation shell, and the shared model (game folder, checks, diagnostics list) |
| `LauncherHome`, `LauncherSettings`, `LauncherPrefs`, `LauncherTheme`, `GlassControls` | Home, the Settings page, the saved choices, colours and buttons, and the plain controls (the file name is from the glass version) |
| `LauncherFiles`, `LauncherDownload`, `DownloadPlan`, `Downloader`, `DownloadStore` | Game files, and downloading Minecraft (`IOS_DOWNLOAD_PLAN.md`) |
| `LauncherAccount`, `AccountClient`, `AccountModel`, `AccountStore` | Sign-in (`IOS_SIGN_IN.md`) |
| `LauncherFileManager`, `FileBrowser` | The file manager and its rules |
| `LauncherMarketplace`, `MarketIndex`, `MarketClient`, `MarketFetcher`, `MarketInstaller`, `MarketCells`, `ModrinthClient` | The Marketplace (`IOS_MARKETPLACE.md`) |
| `LauncherDiagnostics`, `Diagnostics`, `CrashReporter`, `SessionLog` | Diagnostics, crash reports, the session log (`SESSION_LOG.md`) |
| `LauncherAbout` | About and the third-party notices |
