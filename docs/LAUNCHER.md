---
title: The iMC Horizon launcher
summary: What the native launcher screens do, how Play works, the look and Settings, the source files, and what is not built yet. Written, compiled on CI, never run on a phone.
---

# The launcher

The app opens to a native launcher, not to the game. Source: `platform/ios/App/Launcher*.{h,m}` and, since v36, `platform/ios/App/Swift/`.

## The launcher UI, remade (2026-11-11 and 12; compiled on CI, not yet seen on a phone)

Every launcher screen is SwiftUI now (`platform/ios/App/Swift/`); the Objective-C side keeps only the logic (account,
download, marketplace, file rules, diagnostics readings). `Launcher.m` makes `HZLauncherHost.makeRoot()` the window's root.

**Look.** Two colours (`Palette.swift`, tuned for dark and light) over a navy-to-wine ground with a faint block grid
(`Backdrop` in `Look.swift`). The defaults are blue with a little red. Settings > Look has nine built-in presets (Blue and red,
Red and blue, Ocean, Sunset, Forest, Violet, Ember, Mint, Slate), two colour pickers for any pair, a swap button, a colour
balance slider and a backdrop strength; the pair is saved as `colour1:` and `colour2:` (RRGGBB) in `launcher.txt`.
**Lightweight visuals** (Settings > Look > Performance, and automatically in Low Power Mode) draws list rows, groups, chips and
pills as flat tinted shapes instead of Liquid Glass; the big hero cards, the primary buttons and the system's bars keep their
glass. The file manager always uses the flat tinted cards. A surface marks itself `repeated: true` to take part in that switch
(`SurfaceModifier` in `Look.swift`).
Glass is only the system's: `glassEffect`, `GlassEffectContainer`, `.glass` and `.glassProminent` on iOS 26 and later, the system's
materials before that; nothing imitates glass. The mark (`BrandMark`) is drawn in code and matches the app icon
(`tools/make_app_icon.py` writes the three icon files). The mark and the icon are a Minecraft dirt block with an iPhone Dynamic Island over it, a blue-to-red glow around the island..

**Tabs** (the system tab bar): **Play**, **Packs**, **Controls**, **Settings**.

| Tab / page | File | What it does |
|---|---|---|
| Play | `PlayTab.swift` | Game state, Play, Download and Game files tiles, storage, a banner for a crash report not yet opened |
| Packs | `MarketplaceTab.swift`, `MarketDetailPage.swift`, `MarkdownText.swift` | The Marketplace: tabs, search, rows with icons, **page arrows** (first, previous, a page menu, next, last: Modrinth's pages come from its server 30 at a time, the other tabs are cut into 25), a page per project with install, update, remove, the mod switch, and an **Overview** plus a **Description** (Modrinth's full text, fetched on opening, shown as clean Markdown; the first part with an Expand button when it is long) |
| Controls | `ControlsTab.swift`, `TouchEditor.swift`, `ControlsModel.swift` | The game's touch and performance settings (the same `horizon-imc.txt` the game reads), and the **touch editor**: full-screen landscape, drag a button, size, opacity, hide; saved to `horizon-touch-layout.txt` (the game's own format; the extra buttons' lines are kept) |
| Settings | `SettingsTab.swift` | Account card, then Look, Game, Marketplace, Download, Game files, File manager, Diagnostics, About |
| Account | `AccountPage.swift`, `SkinHead.swift` | Profile with the player's head (cut from the skin on Mojang's servers, off in Settings > Game), the sign-in code card, ownership, check again, sign out, switch account |
| Download, Game files | `DownloadPage.swift`, `GameFilesPage.swift` | The download (a ring-less progress card, speed, time left) and importing, checking and deleting the prepared files |
| File manager | `FileManagerPage.swift` | A list with swipe actions, rename, new folder, add files, text viewer, share |
| Diagnostics | `DiagnosticsEngine.swift`, `DiagnosticsPage.swift`, `LogsView.swift` | **Check-up**: about thirty checks the person runs (phone, memory left, heat, storage, game files, network reachability and speed to Microsoft, Xbox, Mojang and the registry, account, settings files, last crash and session, signing and JIT), with advice, a report to share, and tools. **Logs**: crash report with a plain reading, game log with filters, session timeline chart, start-up report |
| About | `AboutPage.swift` | Version, what this is, licences (the upstream `LICENSE` and notices are bundled unchanged) |

The old UIKit screens (Home, Settings, Account, Download, Files, File manager, Marketplace, Diagnostics, About) and the
glass UIKit controls were removed. `HZTheme` keeps only the appearance setting, `launcher.txt` and the window colour.

## How Play works

winit's `EventLoop::run` asserts that `UIApplicationMain` has not been called, and the game's event
loop owns it. So the launcher and the game cannot be two screens of one running process. They are
two runs of the app:

1. **Open** the app: `main.m` looks for `Documents/Horizon/start-game`. It is not there, so the
   launcher runs (`HorizonRunLauncher`).
2. **Play**: the launcher writes `start-game` and closes the app (iOS cannot relaunch an app).
3. **Open** again: `main.m` finds the flag, deletes it, checks the game files, and starts the engine.
4. Close the game and open the app: no flag, so the launcher is back.

**Play without closing the app (experimental, off by default, written 2026-11-11, never built or run).**
Turn on **Settings > Developer options > Play without closing the app** (unlock Developer options first, see "Developer options" below), then close the app fully and open it again (the flag is read once, at launch, so it does nothing until then). The switch writes the line `inProcessPlay:true` in `Documents/Horizon/launcher.txt`; typing the line by hand works too (true, 1, yes or on, any capitals, stray spaces tolerated).
Then `main.m` always starts the engine, arms its hold (`horizon_ios_arm_hold`), and the engine opens its window
and waits. `EngineOverlay.swift` puts the SwiftUI launcher in a window of its own above that one (since 2026-11-11; the first version presented it from winit's controller, and the engine's black boot screen flashed in and out behind it). The cover is raised from a `didFinishLaunching` observer registered before winit's, and while the hold waits the engine's window is portrait (`ios_hold::window_starts_portrait`), switched to landscape on Play. Play writes the signed-in
account's session file, calls `horizon_ios_play()` (the engine's loader goes on), and dismisses the launcher.
Quit Game still ends the process (returning to the launcher is the next step). Delete the line to go back to the
relaunch. If the engine's window never appears the launcher is not shown (20 s limit, noted in the breadcrumb);
the app then switches the flag off itself, so the next open is the normal launcher (or remove the line in the Files app). `openGame:1` and `start-game` are ignored in this mode.

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

## Screens (the earlier UIKit launcher, kept as history; replaced by the table above)

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

## Developer options (2026-11-12, never run on a phone)

Features that are off by default because they are unfinished, untested or only useful to testers live on one page, **Developer options** (`Swift/DeveloperPage.swift`), hidden until unlocked, as on Android:

- **Unlock:** About > tap the app mark three times, each within two seconds of the last. The second tap shows "One more tap to open developer options"; the third turns developer mode on (`devMode:true` in `launcher.txt`, so it survives restarts), gives a success haptic and opens the page. Tapping three times again when it is already on just opens the page.
- **Where it is afterwards:** a **Developer options** row under About in Settings, shown only while developer mode is on. **Turn off developer mode** (bottom of the page) removes the row again. It does not switch the features back off: each keeps the value it has. **Reset launcher settings** also turns developer mode off.
- **What is on it:** the experimental feature switches (today: *Play without closing the app*, moved here from Settings > Game, same `inProcessPlay` line, same restart rule); the sign-in state (the build's own app ID, test mode, or not set up) and the private test mode: a field to paste another launcher's app ID (Paste, Save, Remove). It is written only to `Documents/Horizon/test-client-id.txt` on the phone (so the Files route still works), checked as letters, digits and dashes (8 to 64), shown masked, and applies to the next sign-in; and a read-only list of this build (launcher version, whether Play-without-closing and open-straight-into-the-game are on).
- **Adding a feature to it:** a new off-by-default switch goes in `DeveloperPage.swift` under "Experimental features", with a `Prefs` property and a `launcher.txt` line like the others.

Not a security boundary: anyone can find it. It only keeps unfinished things out of the normal settings.

**Glass and the 2026-11-12 screenshots.** `GlassStack` no longer wraps its content in a `GlassEffectContainer`: a container merges glass shapes that are within its spacing into one, which pinched the Logs buttons (Share, Copy, trash) and the Marketplace tabs into waisted shapes. Each card and chip now stays its own shape. The Marketplace tab row is a fixed 50 pt band with space below it, so the first card no longer slides under the chips, and the Logs trash button is an explicit circle.

## The source files (`platform/ios/App`)

| Files | What they do |
|---|---|
| `main.m`, `GameSession` | Entry point and the Play / flag logic; the signed-in profile handed to the engine |
| `Launcher`, `LauncherModel`, `Swift/*` | The window and the SwiftUI launcher (see the table above), and the shared model (game folder, checks, diagnostics list) |
| `LauncherPrefs`, `LauncherTheme` | The saved Marketplace choices; the appearance setting, `launcher.txt` and the window colour |
| `DownloadPlan`, `Downloader`, `DownloadStore`, `DownloadRate` | Downloading Minecraft (`IOS_DOWNLOAD_PLAN.md`) |
| `AccountClient`, `AccountModel`, `AccountStore` | Sign-in (`IOS_SIGN_IN.md`) |
| `FileBrowser` | The file manager's rules |
| `MarketIndex`, `MarketClient`, `MarketFetcher`, `MarketInstaller`, `ModrinthClient` | The Marketplace (`IOS_MARKETPLACE.md`) |
| `Diagnostics`, `CrashReporter`, `SessionLog` | The start-up report and the small readings the check-up uses, crash reports, the session log (`SESSION_LOG.md`) |

