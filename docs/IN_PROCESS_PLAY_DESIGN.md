---
title: Play and Quit Game in one process (design, M24 stage 3)
summary: What the engine change involves, read from our own sources and from the heyskylo fork. Nothing here is built; it is the plan for a small, flagged, iOS-gated edit to horizon/.
---

# Play and Quit Game in one process

Written 2026-11-10 from reading the code. **Nothing here is compiled or run.** Labels: READ (seen in a file), GUESS (not checked).

## Today (READ)

- `crates/horizon-client/src/game/loading_screen.rs:515`: `enum App { Loading(Box<Loading>), Ready(Box<Split<'static>>) }`. It only goes one way: `about_to_wait` swaps `Loading` for `Ready` when the game is loaded.
- The process ends through `event_loop.exit()`: Quit Game in `startup_menu.rs:752`, a failed load, a window close.
- On iOS our launcher is a separate run of the app: Play sets a flag and exits, the next start goes straight to the engine. That relaunch is what stage 3 removes.

## What the fork does (READ, `heyskylo/horizon-ios`, MIT)

One winit loop stays alive for the whole process and the engine is swapped in and out. A 601-line `game/launcher.rs` answers launcher requests (start, state, import, worlds) through a separate crate, `horizon-ios-launcher`, that talks to a native launcher over a queue. It also toggles the window's valid orientations when the launcher covers the game.

We do **not** copy that: it is built around their launcher protocol, their title screen and a game-file download from a third-party server. We keep our own launcher and only need the lifecycle.

## The smallest change that gives the behaviour (proposal)

1. **A third state**, `App::Idle`, meaning "no engine, the launcher is showing". Entering it drops the `Split` (all GPU resources, world, audio). Leaving it builds a new `Loading` exactly as a first start does.
2. **Quit Game asks for Idle** instead of `event_loop.exit()` when running as the iOS app (`cfg(target_os = "ios")` and the flag below). Every other exit (error, window close) still ends the process.
3. **A tiny request channel**, in our own code, between the launcher (Swift) and the engine: `play` and `quit_ack`. A static atomic plus `winit` `EventLoopProxy` wake-up is enough; no socket, no new crate, no `Cargo.lock` change (GUESS: confirm no dependency is needed before writing it).
4. **Orientation**: the window is already landscape only (A5). While Idle the launcher (portrait) must be shown by the app, not the window; how the SwiftUI view and the Metal window share the screen is the open question below.
5. **Behind a flag**, off by default, until the memory numbers are good.

## Open questions (all need the phone or a runner)

- **Does dropping `Split` return the memory?** The fork measured two cycles on a simulator. We need 5 cycles on the iPhone 12: resident memory after each should stay flat (Diagnostics already prints physical footprint counters). If it does not, the fallback is the relaunch we have now.
- **Who owns the UIWindow?** winit creates and owns it. The SwiftUI launcher is currently the app's root view controller. Either the launcher is presented over winit's window (the fork's way) or winit's window is created only on Play. Presenting a SwiftUI controller over winit's root is READ in the fork (`Present.swift`); whether it works with our loop is GUESS.
- **Audio, network and background threads** must stop on Idle. The engine's existing `exiting` path (`game.exiting(event_loop)`) is the list of what a clean stop does; Idle must run the same.
- **Saved state**: the world must be saved before the engine is dropped. `exiting` does that today (READ `autosave.rs`, `saving.rs`; GUESS that it is complete without the process ending).

## Order of work

1. Add `App::Idle`, the flag, and the `quit` path; build; check that Quit Game still leaves the process the old way with the flag off.
2. Wire `play` from the launcher with the flag on; one cycle on the phone.
3. Five cycles, record the footprint after each in `docs/ios-evidence/`.
4. Only then make it the default.

Each step is a separate build you can test. This file is the reference; `HORIZON_CHANGES.md` records the edit when it exists.
