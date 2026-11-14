---
title: The session log
summary: A local timeline of memory, heat and battery while the app runs, written to a file on the phone for the benchmark and tuning milestones (M6, M7). Nothing is sent anywhere.
---

# The session log (2026-11-09)

**What it is.** While the app runs (the launcher and the game), a timer writes one line every
5 seconds to `Documents/Horizon/session-log.csv`. It is the timeline that frame times and memory
tuning (M6, M7) are compared against, and it is useful now: after a test it shows when the phone
got hot, how close the app came to its memory limit, and what the battery did.

**It stays on the phone.** Nothing in it is sent anywhere. The launcher's **Diagnostics > Share**
button hands the file to you, and you decide what to do with it. (This is separate from Horizon's
own "I'm playing" ping, which is unchanged.)

## The columns

| Column | Meaning |
|---|---|
| `seconds` | Seconds since the app started. |
| `footprint_mb` | The app's memory footprint (`phys_footprint`), the number iOS judges the app by. |
| `available_mb` | How much more memory iOS says the app may use (`os_proc_available_memory`). When it nears 0 the app is killed. Empty on the simulator (no limit reported). |
| `thermal` | `nominal`, `fair`, `serious` or `critical` (`ProcessInfo.thermalState`). From `serious` iOS slows the phone down. |
| `low_power` | 1 if Low Power Mode is on. |
| `battery_pct` | Battery level, 0 to 100. Empty if iOS does not say. |
| `battery_state` | `unplugged`, `charging`, `full` or `unknown`. |
| `foreground` | 1 in the foreground, 0 in the background. A background/foreground test (M4) shows as a run of 0s. |
| `main_ticks_per_s` | How many times per second the main thread answered a display-link tick (a healthy phone shows its screen rate, 60 or 120). Empty in the background. |
| `main_stalls` | Gaps over 50 ms between two ticks in this 5 second window. 0 is what you want. |
| `main_worst_ms` | The longest gap between two ticks in the window, in milliseconds. |

The three `main_` columns (added 2026-11-12) measure the thread that feeds the engine's window events and the
launcher, not the engine's own frames. A low `main_ticks_per_s` with stalls means that thread is being held up;
a normal one with a laggy game points at the engine's render or simulation threads instead.

A value iOS could not give is **empty, never 0**, so a 0 always means a real zero.

The first lines start with `#` and name the device, iOS version and app build. A spreadsheet or
`pandas.read_csv(..., comment="#")` skips them.

## Files and limits

- `session-log.csv` is this run. At the next start it becomes `session-log-previous.csv` (the one
  before that is deleted), so a crash's log survives the relaunch.
- A file reaching 2 MB (about 11 hours) is replaced by a fresh one, so it cannot grow without bound.
- One sample is a few system calls on a background thread at low priority. It does not touch the
  game's frames.

## Where the code is

| Piece | File |
|---|---|
| The timer, the sampling, the file | `platform/ios/App/SessionLog.m`, `SessionLog.h` |
| Started in `main()` after the crash reporter | `platform/ios/App/main.m` |
| Added to the Share list | `platform/ios/App/LauncherModel.m` (`diagnosticFiles`) |

No file under `horizon/` is changed. `project.yml` picks up the new files by itself.

## What it does not do

- **No engine frame times.** The `main_` columns show the main thread only. Those live in the engine; the `--benchmark` scenarios and an in-game frame
  recorder are the rest of M6 and need engine hooks. This is the main gap before tuning (M15 step 2 in
  `IOS_IMPLEMENTATION_ROADMAP.md`).
- **No GPU memory by category**, which M6 also lists.
- **Not tested on a phone.** The line format has a test (a C copy of the logic, 4 cases), but the
  Objective-C itself is only compiled by the CI macOS runner.

## To check on the phone

1. Play ten minutes, then Diagnostics > Share the files. `session-log.csv` should have a line every
   5 seconds and the header with your phone's model.
2. `thermal` should move off `nominal` if you play long enough with the Mobile preset off.
3. Press the home button for a minute, come back: a run of `foreground` 0s, then 1.


## Lag investigation (2026-11-12)

Reported: "the app is so laggy". No measurement from the phone existed, so the first pass removed the main-thread
work that could be found by reading the app side, and added the `main_` columns so the next test has numbers.

| Change | Why |
|---|---|
| The launcher is released after Play (`EngineOverlay.dismiss` drops the root controller) | A hidden window still kept the whole SwiftUI tree, its glass layers and observers alive under the game |
| `LauncherState.refresh()` reads on a utility queue | It parsed the manifest, listed the folder, read up to 64 KB of each crash report and walked the game folder on the main thread at every tab change, page push and return to the app |
| The backdrop's block grid is drawn once into a bitmap | A `Canvas` of hundreds of rounded rectangles was redrawn for every tab and pushed page |
| The crash marker is written every 5 s on a utility queue | It was a 1 s `NSTimer` on the main run loop writing a file each time |

**What this does not fix.** If the game itself runs slowly (low frames with a quiet main thread), the cause is in the
engine's render settings or the GPU, and needs the numbers first. The Mobile preset (iMC Settings) lowers render
distance, cuts effects and caps the frame rate; try it and compare the `main_` columns and the heat.


## Launcher lag, second pass (2026-11-12)

The owner clarified that the lag is in the launcher, not the game. Found by reading the app, not yet measured on the
phone (the `main_` columns above are how to check):

| Change | Why |
|---|---|
| `launcher.txt` is read through an in-memory copy (`LauncherTheme.m`), checked against the file's date and size | Every setting question (compact lists, haptics, the backdrop mix, each Marketplace row) re-read and re-parsed the file |
| Writes to `launcher.txt` are coalesced and made on a utility queue (about 0.4 s later; flushed on leaving the app and before Play) | A drag of "Backdrop colour" or "Colour balance" rewrote the file (read, edit, atomic write) sixty times a second on the main thread |
| The backdrop is one bitmap (gradients, glows and grid), redrawn only when size, scheme, colours or mix change, at most about ten times a second during a drag | Four layers sat behind every glass card on every screen; glass samples what is behind it each frame it moves |
| The tab bar observes only the accent (`AccentLook`), not all of `Prefs` | A slider drag rebuilt every tab sixty times a second |
| `LongText` splits the log once per text | It split and joined up to 256 KB on every body pass, a keystroke in the log search included |
| Haptic generators are kept and prepared | A new generator for every tap meant a late first tap |

`LauncherModel.m` still writes `launcher.txt` itself for `openGame:` and `inProcessPlay:`; it flushes pending settings
first and tells the cache to reload afterwards.

## Launcher overhaul (2026-11-11 and 12)

The owner asked for the whole launcher to be remade: a red and blue palette on system Liquid Glass, a new app icon, a touch
editor inside the launcher, a bigger Account page, a Diagnostics page that is a real tool, and more settings.

| Done | Where |
|---|---|
| Blue and red palette, system-glass design system, backdrop with a blue and a red glow and a block grid; accent blue or red, colour balance, backdrop strength | `Palette.swift`, `Look.swift`, `Prefs.swift` |
| Every screen rewritten in SwiftUI: Play, Packs (Marketplace and project pages), Controls, Settings (Look, Game, Marketplace), Account, Download, Game files, File manager, Diagnostics, About; the UIKit screens and glass controls are gone | `platform/ios/App/Swift/` |
| New app icon (a glass block, blue and red, over navy and wine; light, dark and tinted) | `tools/make_app_icon.py`, `Assets.xcassets` |
| Touch editor in the launcher: full-screen landscape, drag, size, opacity, hide; reads and writes the game's own `horizon-touch-layout.txt` | `TouchEditor.swift`, `ControlsModel.swift` |
| Game settings in the launcher (touch, menus, calibration, Auto Performance) through the game's own `horizon-imc.txt` | `ControlsTab.swift` |
| Account page: the player's head (from Mojang's servers, optional), sign-in code card with timer, ownership, last checked, check again, sign out, switch account | `AccountPage.swift`, `SkinHead.swift` |
| Diagnostics check-up (about thirty checks the person runs, advice, a shareable report, tools) and Logs (crash reading, filters, memory chart) | `DiagnosticsEngine.swift`, `DiagnosticsPage.swift`, `LogsView.swift` |

Not yet seen on a phone. The first builds failed on missing bridging-header imports and optional strings; CI now repeats the
compiler's first errors as annotations (`ios-app.yml`, "Report compiler errors as annotations"), which is how they were read.
Another session worked in the same repository at the same time (lag passes, Developer options, in-process Play); the two
sets of commits were rebased onto each other without conflict except one duplicate fix.

## Launcher follow-ups (2026-11-13)

| Change | Why |
|---|---|
| The engine draws nothing and wakes every 50 ms while it waits for Play behind the launcher (`Loading::about_to_wait`, `Loading::draw`; `HORIZON_CHANGES.md`) | With Play without closing the app, the covered engine window rendered its title panorama every frame under `ControlFlow::Poll`: GPU and main-thread work for nothing, heat, and a launcher that competed with it |
| New app icon and mark: a dirt block with a Dynamic Island over it | The owner's idea; `tools/make_app_icon.py`, `BrandMark`. The island was removed the next day (the dirt block alone), and one icon per colour theme was added (see below) |
| Two free colours, nine presets, default blue with a little red; Lightweight visuals | `Palette.swift`, `Prefs.swift`, `Look.swift`, Settings > Look |
| The Account head loads: Mojang names its skins with an `http://textures.minecraft.net` address, which the first version refused (it required https); it now asks the same server over https, and the page says why when there is no head | `SkinHead.swift` |
| Marketplace pages; Modrinth Description with Expand | `MarketplaceTab.swift`, `MarketDetailPage.swift`, `MarkdownText.swift`, `ModrinthClient.m` (`bodyOfProject`) |
| File manager rows are flat tinted cards | Glass on a long list is the expensive case |
| "Checking the game files" no longer waits for the whole manifest to be parsed and the folder to be walked: the verdict is remembered per manifest size and date (`filesOK:`), the size of the files likewise (`resourcesKey:`), the Play tab paints the remembered answer at once, and the slow reads arrive after the first | `LauncherModel.m` `checkFiles:`, `LauncherState.refresh()` |

## One app icon per colour theme (2026-11-14)

The Dynamic Island came off the icon: the dirt block alone. Each of the nine colour themes has its own icon (the block lit in the
theme's two colours, light, dark and tinted), shipped as iOS alternate icons: `AppIcon` for Blue and red and `AppIcon-red-blue`,
`-ocean`, `-sunset`, `-forest`, `-violet`, `-ember`, `-mint`, `-slate`, listed in `project.yml`
(`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`). `AppIconTheme.swift` changes the home screen icon when the theme changes,
after the colours have been still for 1.2 s, only if it would be a different icon, and only while the app is active.
Because iOS shows a system notice on every icon change, Settings > Look > Match the app icon can turn it off (it then goes back
to the default icon). The theme list exists in two places (`ThemePreset.all` in `Palette.swift`, `PRESETS` in the icon script):
`tools/make_app_icon.py --check` compares them and the shell-check workflow runs it. The app build now also fails if the built
app lacks an alternate icon in its Info.plist. Not tried on a phone: whether a re-signed install keeps working alternate icons is
the thing to check first.

### Icon follow-up (2026-11-14)

The app icon now uses the in-app mark's block (six cells to a face, same browns by the same formula in `make_app_icon.py` and
`BrandMark`) instead of the larger, finer 16-cell block. The background went back to the original icon's style, a sky with a soft
glow behind the block, stepped ground and a horizon line (the faint grid of squares, which was added on the first overhaul and
never asked for, is gone), in each theme's two colours. Settings > Look has an App icon section: the match-the-theme switch and a grid of
the nine icons to pick by hand (`AppIconTheme.choose`, `IconPreview`), saved as `iconChoice:` in `launcher.txt`.
