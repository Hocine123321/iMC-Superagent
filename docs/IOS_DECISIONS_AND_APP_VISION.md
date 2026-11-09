---
title: Decisions and what the app will be
summary: The choices the owner made along the way, and a plain picture of the finished Horizon iOS app, with what is proven, what is built, and what is still unknown.
---

# Horizon for iOS: decisions and the finished app

Written 2026-11-08, status corrected 2026-11-09. This is the owner's reference. It says what was decided, what the app
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
| 8 | **Use JIT to do that preparation, with a Java 25 runtime.** | The data generator is Java and needs JIT to run at a usable speed. | IN TEST, and **at risk**: the one device run so far could not make a JIT page (see 11) |
| 9 | **One JVM only** (`HORIZON_PREPARE_JOBS=1`). | A phone has limited memory; one JVM is also all that can exist in-process. | PLANNED |
| 10 | **Pin the Java build to tag `jdk-25.0.5.0.3-ga`.** | The iOS patches apply cleanly to that tag and fail on newer ones. | DONE |
| 11 | **Test device: iPhone 12 (A14), iOS 27.2, JIT through StikDebug.** | The A14 has no TXM, so JIT only needs a debugger attached. | **Partly shown.** The 2026-11-08 diagnostics report `CS_DEBUGGED` set (a debugger is attached), but the `MAP_JIT` test page was refused: `errno 1 (Operation not permitted)`. So a JIT page could not be made by this app in that run. Earlier text here said "JIT works (owner-confirmed)"; the log does not show that. See `ios-evidence/diagnostics-2026-11-08-run1.txt`. |
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
| M2 | App shell, Metal surface, memory reporting | **Done in CI.** On the owner's phone the app reached the title artwork, then hit a stack overflow that is now fixed (`IOS_CRASH_STACK.md`); the fixed build has not been confirmed on a phone. |
| M8a step 1 | Build a Java 25 runtime for iOS in CI | **DONE** (24 MB compressed, 134 MB unpacked, device-only) |
| M8a step 2 | Show that the phone can run it | **IN TEST.** A diagnostics screen is in the IPA you are installing now. |
| M3 / M3b | Load the game files, reach the title screen, and the native launcher (home, import/check/delete, diagnostics, Play) | **Built and published** (v2 to v4); launcher layout and the folder picker untested on a phone |
| M4 | Pause, resume and memory warnings | **Built**, untested on a phone |
| M5 | Touch controls, playable singleplayer | **Built; first phone test found the touch offset** (right and a little down), fix and **iMC Settings** page written 2026-11-09 and waiting for a CI build (`IMC_SETTINGS.md`). Since then: Mobile preset, touch controls editor, Back button. All untested on a phone. |
| M6 / M7 | Measure on the phone, then tune memory and heat | **M6 started:** a local session log (memory, heat, battery) is built, untested on a phone (`SESSION_LOG.md`). Benchmarks and frame times are PLANNED. M7 PLANNED. |
| M8b | Download and prepare on the phone | PLANNED, depends on M8a |
| M9 | Microsoft sign-in and ownership check | PLANNED, needs Mojang's approval of an app registration |
| M10 / M11 | Multiplayer, polish, final IPA | PLANNED |

**The honest summary:** the engine runs on iOS and the app has a launcher, touch controls and a settings page. What is not yet shown is a game you can play: no run has got past the title screen on the phone, and whether Java can run on the phone at all is open.

---

## 4. What is still unknown

These decide whether the plan above works. None has been tested on your phone yet.

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

## 5. The next three steps

1. **Phone-test the next build** (the one with the touch fix and iMC Settings). Check that a finger
   lands under itself in menus and in the world, that the buttons react where they are drawn, and
   that **Options > Horizon Settings > iMC Settings...** opens and each choice does something. Send
   `latest.log` and `crash.txt` if anything is off.
2. **Settle JIT.** The 2026-11-08 run showed `CS_DEBUGGED` set but the `MAP_JIT` page refused
   (`errno 1`). Repeat the M8a test (`IOS_DEVICE_TEST_M8A.md`) with JIT enabled in StikDebug before
   launch, and keep both `diagnostics.txt` files. If the page is refused again, the Java plan stops
   there and the fallback (prepare on a computer, copy the folder over) becomes the product.
3. **Only if JIT works:** put the Java runtime on the phone, load its library and print
   `java -version`, then run one exporter, then the one-JVM preparation, then the downloader.

See `IOS_DEVICE_TEST_M8A.md` for the exact test, `IOS_IMPLEMENTATION_ROADMAP.md` for every
milestone, `IMC_SETTINGS.md` for the settings page and the touch fix, and
`IOS_FEASIBILITY_REPORT.md` for the evidence behind each claim.
