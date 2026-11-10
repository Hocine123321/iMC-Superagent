---
title: Decisions and what the app will be
summary: The choices the owner made along the way, and a plain picture of the finished Horizon iOS app, with what is proven, what is built, and what is still unknown.
---

# Horizon for iOS: decisions and the finished app

Written 2026-11-08, status corrected 2026-11-10 (after iMC Horizon v33). This is the owner's reference. It says what was decided, what the app
will be when it is done, and how much of that is real today.

**How to read the labels**

- **DONE**: built and checked in CI (or on the owner's phone, where stated).
- **IN TEST**: built, waiting for a result from the owner's iPhone.
- **PLANNED**: designed in the roadmap, not started.
- **UNKNOWN**: depends on something nobody has verified yet.

---

## 1. Decisions made

| # | Decision | Why it matters | Status |
|---|---|---|---|
| 1 | **Port the existing Rust engine**, do not rewrite the game. | Horizon already renders with wgpu/Metal and has a touch-free desktop client. The work is a thin iOS shell around it. | DONE (engine builds, links, starts on the simulator) |
| 2 | **Do not modify, delete or rewrite anything in `horizon/`.** | The upstream snapshot stays clean and updatable. All iOS work lives beside it (`platform/`, `docs/`, `.github/`). | Followed throughout |
| 3 | **Minimal native iOS app first**, features later. | Get something running on a real phone before polishing. | Followed |
| 4 | **Build and verify on a GitHub Actions macOS runner.** | There is no Mac in the loop. The repo was made **public** so those runners are free. | DONE |
| 5 | **Distribute as an IPA you sign yourself.** No App Store, no TestFlight, no verification by Apple. | Removes App Store review and its rules from the plan. | DONE (decision); IPA builds |
| 6 | **User-owned assets, processed locally.** Nothing from Mojang is committed, hosted or shared by this project. | The player's own copy is downloaded to their own phone from Mojang's servers. | PLANNED (M8b) |
| 7 | **Prepare the game files on the phone**, not on a computer. | No Mac or PC is needed after install. | PLANNED, **UNKNOWN** (see section 4) |
| 8 | **Use JIT to do that preparation, with a Java 25 runtime.** | The data generator is Java and needs JIT to run at a usable speed. | IN TEST, and **at risk**: two device runs (2026-11-08, 2026-11-10) could not make a JIT page (see 11) |
| 9 | **One JVM only** (`HORIZON_PREPARE_JOBS=1`). | A phone has limited memory; one JVM is also all that can exist in-process. | PLANNED |
| 10 | **Pin the Java build to tag `jdk-25.0.5.0.3-ga`.** | The iOS patches apply cleanly to that tag and fail on newer ones. | DONE |
| 11 | **Test device: iPhone 12 (A14), iOS 27.2, JIT through StikDebug.** | The A14 has no TXM, so JIT only needs a debugger attached. | **Partly shown.** The 2026-11-08 diagnostics report `CS_DEBUGGED` set (a debugger is attached), but the `MAP_JIT` test page was refused: `errno 1 (Operation not permitted)`. So a JIT page could not be made by this app in that run. Earlier text here said "JIT works (owner-confirmed)"; the log does not show that. **Second run, 2026-11-10 (v33, probes B, C, D with a debugger attached): B and C killed the app, D was refused with `errno 1`; A was not re-run.** No executable page was possible. The app has no `com.apple.developer.cs.allow-jit` entitlement, which is the next thing to try (`ios-evidence/diagnostics-2026-11-10-run2-probes.txt`). See `ios-evidence/diagnostics-2026-11-08-run1.txt`. |
| 12 | **Repository: `Hocine123321/iMC-Superagent`**, upstream in `horizon/`, port in the root. | Keeps the port and the clone separate. | DONE |

---

## 2. What the finished app will be

**In one line:** Horizon, the Rust-built Minecraft: Java Edition 26.3 client, running natively
on the iPhone, installed from an IPA you sign yourself, with the game files downloaded and prepared
on the phone from your own Minecraft account.

### What you will see, in order

1. **First launch.** A short setup screen, not the game. It checks that JIT is on and tells you
   plainly if it is not, instead of hanging.
2. **Sign in.** You sign in with your own Microsoft account. The app checks you own Minecraft:
   Java Edition. Without it, the game does not start.
3. **Download.** The app downloads your copy of Minecraft 26.3 from Mojang's servers to the phone,
   with a progress bar and checksums, and resumes if interrupted.
4. **Prepare.** The app runs a one-time preparation (a Java program that builds the data Horizon
   needs). Done once per game version. Progress is shown.
5. **Title screen, then play.** Singleplayer first.

### Once running

- **Graphics:** Horizon's own renderer on Metal, full screen, landscape.
- **Controls:** on-screen joystick, drag to look, tap to mine or place, buttons for jump, sneak,
  inventory and chat. A controller is a later goal.
- **Memory:** the app reports its real iOS memory footprint and reacts to memory warnings, so it
  is not killed silently.
- **Files:** saves, settings and logs sit in `Files > Horizon`, so you can see and copy them.
- **Later:** multiplayer, better audio, a nicer mobile interface.

### What it will not be

- Not on the App Store, and not built for it.
- Not a launcher for pirated copies. It checks ownership, as a policy check, not as copy protection.
- Not a way around Mojang's rules: no Mojang files are ever stored in this repository.
- Not guaranteed to be fast. No frame rate or memory number is promised until measured on your phone.

---

## 3. How far along it is

| Milestone | What it is | State |
|---|---|---|
| M1 | Fix the code so the engine compiles for iOS | **DONE** |
| M2 | App shell, Metal surface, memory reporting | **DONE.** The early stack overflow was fixed (`IOS_CRASH_STACK.md`) and the game now runs on the owner's phone (confirmed 2026-11-10). |
| M8a step 1 | Build a Java 25 runtime for iOS in CI | **DONE** (24 MB compressed, 134 MB unpacked, device-only) |
| M8a step 2 | Show that the phone can run it | **OPEN.** The 2026-11-08 run set `CS_DEBUGGED` but refused the `MAP_JIT` page; the test is to be repeated with JIT enabled before launch (`IOS_DEVICE_TEST_M8A.md`). Only matters for preparing files on the phone, since the game already runs from files prepared on a computer. |
| M3 / M3b | Load the game files, reach the title screen, and the native launcher (home, import/check/delete, diagnostics, Play) | **Built and published** (v2 onward; the latest release is v33). The launcher has since been rebuilt (Home, Marketplace, Settings, Files, Game files, Account, Diagnostics, About, see `LAUNCHER.md`); none of it is confirmed on a phone |
| M4 | Pause, resume and memory warnings | **Built**; the game runs, but suspend and memory-warning behaviour has not been tested on purpose |
| M5 | Touch controls, playable singleplayer | **DONE: the game runs and is playable on the phone (owner, 2026-11-10).** The first test found the touch offset (right and a little down), fix and the **iMC Settings** page built and published (`IMC_SETTINGS.md`). Fixes and additions since: Mobile preset, touch controls editor, Back button, touch calibration, Cursor mode (a trackpad-style pointer for menus), and the iMC Settings moved into a page of Video Settings. The custom extra buttons were abandoned (the code stays). The newer additions have had less testing than the core. |
| M6 / M7 | Measure on the phone, then tune memory and heat | **M6 started:** a local session log (memory, heat, battery) is built, untested on a phone (`SESSION_LOG.md`). Benchmarks and frame times are PLANNED. M7 PLANNED. |
| M8b | Download and prepare on the phone | **Download built, not run** (plan, downloader and screen, `IOS_DOWNLOAD_PLAN.md`; CI-compiled only). Preparation PLANNED, depends on M8a |
| M9 | Microsoft sign-in and ownership check | BUILT, NOT RUN: code and screen are in `platform/ios/App`; needs the owner's Azure app and Mojang's approval before it can sign in. Gates the download only. See `docs/IOS_SIGN_IN.md` |
| M10 / M11 | Multiplayer, polish, final IPA | PLANNED |
| **M15** | **iOS optimisation: make it feel made for iOS** (added 2026-11-10): leave the game for the launcher, measure, tune speed and battery, touch polish, launcher extras | **NEXT.** First step below |
| **M24** | **Launcher v2**: SwiftUI, real system Liquid Glass, portrait, Play and Quit Game in one process (owner decisions, 2026-11-10; `horizon/` editing approved) | **IN PROGRESS.** Stage 1 (CI on Xcode 26) pushed; plan in `NEXT_STEPS.md` |
| M17 | Frame pacing, 60/120 Hz, battery and thermal modes | PLANNED, needs M15 numbers |
| M18 | Controller support through iOS's GameController | PLANNED, **to check** what the engine sees first |
| M19 | Haptics, one-handed layout, screenshot and chat buttons, text size | PLANNED |
| M20 | Clean exit, crash recovery, out-of-memory explanation, bug report bundle, log viewer | PLANNED |
| M22 | Objective-C tests in CI, simulator smoke test, signing guide, version in About | PLANNED |
| M12 | Real launcher pages: Settings, Library, Worlds, Screenshots, Logs, About (added 2026-11-10) | **Written, not run:** Home, Settings (Look, Marketplace, Start-up), Game files, Account, Diagnostics and About. Worlds, Screenshots and Logs pages PLANNED |
| M13 | In-app file manager, limited to the app's own folder (added 2026-11-10) | **Written, not run** (browse, preview, share, rename, delete with warnings, new folder, add files). Zip export and folder import PLANNED |
| M14 | Horizon Marketplace: browse and install from Horizon's registry (added 2026-11-10). Only about 25 of the 158 registry projects can work on a phone (133 are native mods that need a desktop build) | **Browse, install, update and remove written, not run** (`IOS_MARKETPLACE.md`); SHA-256 checked, projects whose author signs their files are refused until a minisign check exists. Modrinth resource packs are an opt-in extra in Settings |

**The honest summary (2026-11-10):** the game runs on the owner's iPhone without issues, so the first goal, making Horizon work on iOS, is **done**. What was built around it (launcher, Marketplace, file manager, download, sign-in code) is written and compiled in CI but mostly not yet tried on the phone. The work now is making it feel made for iOS: features, speed, battery and touch comfort. The plan for that is `IOS_IMPLEMENTATION_ROADMAP.md`, milestone M15.

---

## 4. What is still unknown

These decide whether the preparation-on-the-phone part of the plan works. The game itself already runs from a folder prepared on a computer, so none of them blocks playing; they decide whether the phone can do everything without a computer.

1. **Can the phone load the Java runtime?** JIT working is necessary, but not enough. The app must
   also load the runtime's libraries, which iOS restricts. Amethyst solves this with its own
   method; this project will not copy their GPL code.
2. **Can Horizon's preparation run in-process?** Horizon's preparer starts Java as a separate
   process, and iOS forbids that. It needs a changed copy of two files, kept outside `horizon/`
   (your rule), that drive one JVM from inside the app.
3. **Mojang approval.** Signing in needs Mojang to approve this app's registration. It takes days
   to weeks. Applying early costs nothing.
4. **Licensing questions**, to verify before anything is shared publicly: the Java runtime's
   licence (GPL with Classpath exception, to be confirmed), Mojang's terms for downloads by a
   third-party app, and Horizon's own licence for a downstream fork.
5. **Disk space.** The downloaded copy plus the prepared folder is large (sounds alone about
   380 MB; Android reports about 500 MiB prepared).

**Fallback, only if (1) or (2) fails:** prepare once on a computer you control and copy the
finished folder to the phone. You chose not to rely on this, so it stays a backup.

---

## 5. The next step (2026-11-10)

The game runs, so the question is no longer "does it work" but "is it good on an iPhone". The plan is milestone **M15** in `IOS_IMPLEMENTATION_ROADMAP.md`. In order:

1. **Leave the game for the launcher without force-closing it.** A "Back to launcher" entry in the pause menu First I check what the game's own Save and Quit does on iOS; if it does not end the app cleanly, the fix is a small iOS-only edit under `horizon/` (listed in `HORIZON_CHANGES.md`), which needs your approval because `horizon/` is normally off limits. Swiping the app away makes the launcher show a crash notice next time. This is the smallest change that fixes something you hit every session.
2. **Measure before tuning.** Play a fixed route (a new world, walking and flying at three render distances, five minutes each) and send the `session-log.csv` and `latest.log`. This gives the real memory, heat and battery numbers that M7 needs. Nothing gets tuned without a before and after.
3. **Tune from the numbers** (M7): defaults for render distance, resolution scale and Auto Performance's thresholds.
4. **Touch polish**: drag to spread a held stack, haptics, a better inventory.
5. **Launcher extras**: Worlds (list with size and date), Screenshots and Logs. World backup, signature checks, update checks and multiplayer polish were removed from the plan by the owner on 2026-11-10 as not important enough; the two signed Marketplace projects stay refused for now.

Still open and not blocking: **Play without relaunching** (needs a winit upgrade or a launcher window inside winit's run, see `LAUNCHER.md`), the JIT/Java test (M8a, only matters for preparing the files on the phone), and Mojang's approval for sign-in.

See `IOS_IMPLEMENTATION_ROADMAP.md` for every milestone, `IMC_SETTINGS.md` for the settings page, and `IOS_FEASIBILITY_REPORT.md` for the evidence behind earlier claims.
