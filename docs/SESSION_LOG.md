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
