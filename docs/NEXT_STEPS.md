# Next steps (written 2026-11-10)

This is the working plan. Read the objective first; if a task does not serve it, it waits.

## Objective

Make iMC the best way to play Minecraft: Java Edition on an iPhone: the game runs well and is smooth, and the app around it (the launcher) feels like a finished native iOS app, not a developer tool.

The game already runs on the phone (confirmed 2026-11-10). What is left is the launcher's quality, Play without relaunching, and iOS-specific polish.

## Rules that stay in force

- Never commit Mojang files. No dependency or `Cargo.lock` change without approval.
- Do not push while a build of 10 minutes or more is running.
- `horizon/` may now be edited, but only in small, iOS-gated, documented changes (`HORIZON_CHANGES.md` and the patch files), approved by the owner on 2026-11-10.
- Glass is the system's or nothing: no hand-drawn imitation. If a piece cannot be done natively, it stays plain and we say so.
- Telemetry stays as it is. The file manager stays inside `Documents/Horizon` and asks before deleting. The Marketplace never installs native mods.
- Removed by the owner and not coming back: world backup and export, signature and update checks, multiplayer polish (old M16, M21, M23), custom extra buttons.

## The order

### 1. Toolchain: Xcode 26 (in progress)
CI now builds on `macos-26` (pushed 2026-11-10, `71341ec`). The first build recompiles the engine (about 21 minutes).
Done when: the build is green and the log shows iOS SDK 26. If the existing code fails to compile under Xcode 26, fix only that, nothing else.

### 2. SwiftUI launcher, still using the relaunch for Play (M24 stage 2)
- Portrait by default for the launcher; the game stays landscape.
- Three tabs in the system `TabView` (floating glass bar on iOS 26): **Play**, **Packs** (our Marketplace and Modrinth), **Settings**. Large title with a small eyebrow line, round account button at the top right, as in the owner's screenshots, with our own look (own colours, own hero card, own wording) and not a copy of the fork.
- Glass only through `glassEffect`, `.glass` and `.glassProminent` on iOS 26 and later; system materials and bordered buttons below that.
- The Objective-C logic stays (downloader, Marketplace client, file rules, accounts, settings, diagnostics) and is called from Swift. Files, Account, Diagnostics and About become pages inside Settings.
- The Play screen is honest about game files: if they are missing it says they must be prepared on a computer and imported, until the Java step is proven (see item 6).
Done when: every current screen is reachable, the tab bar is the system's, and the owner has seen it on the phone.

### 3. Engine: Play and Quit Game in one process (M24 stage 3, `horizon/` edit)
Written against our engine revision, using the fork's design (one winit loop, the engine replaced in place, the launcher presented over the game window). Behind a flag until the numbers are good.
**Status 2026-11-11, step 1 written (not built, not run):** the engine starts with the app and waits for Play; the launcher sits in a window of its own above winit's (phone test 2026-11-11: it worked, but the engine's boot screen flashed in and out when the launcher was presented from winit's controller; changed to a separate cover window; v43 phone test: still a split-second boot screen and a landscape start that turns to portrait, so v44 raises the cover inside didFinishLaunching (before winit's window is visible) and the engine window waits as portrait until Play, untested); flag `inProcessPlay:true` in `launcher.txt` (switch in Settings > Game > Experimental, added 2026-11-11; read at launch, so the app must be restarted), off by default (`HORIZON_CHANGES.md` section P, `LAUNCHER.md`). Left: Quit Game back to the launcher (`App::Idle`), the five-cycle memory test, the phone test of the orientation change and the presentation timing.
Done when: Play starts with no app relaunch, Quit Game returns to the launcher, and memory after 5 repeated cycles on the phone stays flat (the fork only measured two cycles on a simulator).

### 4. Download screen and wording (M24 stage 4)
Speed, time left, retry, a Play button whose label shows its state, clear empty states, error text that says what to do.

### 5. Measure and tune (M15, M17)
Clean exit, a fixed test route, frame times and battery numbers, frame cap and 60/120 Hz, Low Power and heat behaviour (the fork's 120 Hz change is one plist key, `CADisableMinimumFrameDurationOnPhone`).

### 6. Open question: preparing the game on the phone (M8a/M8b)
Retested 2026-11-10 on v33 with a debugger attached: probes B and C killed the app, D was refused (`errno 1`); A was not re-run. Next try: a test build with the `com.apple.developer.cs.allow-jit` entitlement, probes A and D only. Your signing tool may strip it. If that still fails, files come from a computer. The fork does not solve this either.

### 7. Later, each on its own
Touch comfort (M19), controller support (M18, first check whether the iOS build includes the controller feature), reliability and bug-report bundle (M20), test pipeline (M22).

## What the owner needs to do
- Install the build when item 2 is ready and say what looks wrong.
- Install the entitlement test build for item 6 when it is ready (after the Xcode 26 build is done).

## Reference
Roadmap: `IOS_IMPLEMENTATION_ROADMAP.md` (M24 section). Decisions: `IOS_DECISIONS_AND_APP_VISION.md`. Fork findings: the `heyskylo/horizon-ios` repo (MIT; keep its copyright notice if code is copied).
