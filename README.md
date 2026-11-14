<div align="center">

# iMC Horizon

**Minecraft: Java Edition, running natively on iPhone.**

A native iOS port of [Horizon](https://github.com/horizon-rust/horizon), the Rust-based Minecraft: Java Edition client,
rendered with wgpu on Metal, wrapped in a SwiftUI launcher built for touch.

[Download the latest IPA](https://github.com/Hocine123321/iMC-Horizon/releases) ·
[Roadmap](docs/IOS_IMPLEMENTATION_ROADMAP.md) ·
[How it works](docs/IOS_DECISIONS_AND_APP_VISION.md)

</div>

> **Unofficial.** iMC Horizon is not an official Minecraft product and is not made by, approved by or associated with
> Mojang Studios or Microsoft. It contains no Minecraft code or assets: you need your own copy of Minecraft: Java Edition.

## What it is

Minecraft: Java Edition has never run on iPhone. Existing approaches run the Java game inside a JVM, which on iOS needs
JIT and a debugger attached. iMC Horizon takes a different route: it builds Horizon, a from-scratch Java Edition client
written in Rust, as a native iOS app. No JVM in the game loop, just Rust compiled for `aarch64-apple-ios`, drawing through
Metal, speaking the real Java Edition protocol.

**Status:** the engine builds, links and runs on a real iPhone (confirmed on device, 2026-11-10). The current work is making
it feel made for iOS. See [Status](#status) for what is and isn't done.

## What it offers

- **Native performance.** The Horizon engine runs as compiled Rust on the phone's CPU, with wgpu on Metal for graphics.
- **A real iOS launcher.** A SwiftUI app with Play, Packs, Controls and Settings tabs, using iOS 26 Liquid Glass where
  available and working back to iOS 16.
- **Touch controls you can edit.** On-screen controls with a full-screen touch editor (snapping, guides, overlap checks)
  and the in-game **iMC Settings** page for touch, cursor and performance options.
- **Marketplace.** Browse, install, update and remove packs and mods from inside the app.
- **Multiplayer.** Join servers and find LAN worlds hosted on other devices on your network.
- **File manager and Files app support.** Game files live in `Documents/Horizon`, visible in the iOS Files app.
- **Diagnostics and crash reporting.** A built-in check-up (memory, heat, storage, game files, network) and a crash reporter
  that keeps its logs on the phone.
- **Privacy first.** Logs stay on the device unless you share them yourself.
- **Every build is traceable.** Each release IPA carries its version (`vN`), build number and commit, shown in the app's
  About page.

## Install

1. Open [Releases](https://github.com/Hocine123321/iMC-Horizon/releases) and download the newest `iMC-Horizon-vN.ipa`.
2. Sign and install it with a sideloading tool such as AltStore, SideStore or Sideloadly (the IPA is unsigned).
3. Bring your own prepared Java Edition game files for now (see [`docs/PC_PREPARATION_GUIDE.md`](docs/PC_PREPARATION_GUIDE.md)),
   and put them in the app's folder through the Files app.

Requirements: an arm64 iPhone with Metal on iOS 16 or later. Development and testing so far is on an iPhone 12 (A14).

## Status

| Area | State |
|---|---|
| Engine on iOS (Rust + wgpu on Metal) | Works on device |
| SwiftUI launcher, Marketplace, file manager, diagnostics | Built |
| Touch controls, touch editor, app lifecycle | Built |
| Crash reporter | Built |
| Downloading and preparing game files on the phone (M8) | In progress: download written, preparation not yet |
| Microsoft account sign-in (M9) | Code and Account screen exist; needs an approved Azure app (see [`docs/IOS_SIGN_IN.md`](docs/IOS_SIGN_IN.md)) |
| iOS-native polish (M15) | In progress |

## Repository layout

| Path | What it is |
|---|---|
| `platform/ios/` | The iOS app: SwiftUI launcher, Objective-C launcher logic, crash reporter, diagnostics, and the XcodeGen project that builds the IPA. |
| `horizon/` | Snapshot of upstream Horizon at `77af961` (MIT) plus this port's changes (listed in [`docs/HORIZON_CHANGES.md`](docs/HORIZON_CHANGES.md), with a patch to replay them on a newer upstream). The Rust bridge is `horizon/platform/ios-bridge/`. |
| `docs/` | Feasibility report, roadmap, decisions, memory strategy, launcher, Marketplace, sign-in, touch and settings, and on-device evidence. |
| `.github/workflows/` | CI for the port. Upstream's own workflows are kept inert in `horizon/.github/`. |

## Building

Every push to `main` that touches the app runs the **iOS app** workflow on a macOS runner: it builds the Rust static
library, generates the Xcode project with XcodeGen, builds an unsigned `Horizon.app`, checks the startup stack budget, and
publishes the IPA under Releases as *iMC Horizon vN*. The workflow is the source of truth for whether the app builds.

To build locally on a Mac with Xcode 26:

```bash
cd horizon && cargo build --release --target aarch64-apple-ios -p horizon-ios-bridge
mkdir -p ../platform/ios/build/rust/device && cp target/aarch64-apple-ios/release/libhorizon_ios_bridge.a ../platform/ios/build/rust/device/
cd ../platform/ios && xcodegen generate && open Horizon.xcodeproj
```

A local build shows `dev` and `local` in About instead of a release number and commit.

## Read more

- [`docs/IOS_DECISIONS_AND_APP_VISION.md`](docs/IOS_DECISIONS_AND_APP_VISION.md): the decisions and what is proven.
- [`docs/IOS_IMPLEMENTATION_ROADMAP.md`](docs/IOS_IMPLEMENTATION_ROADMAP.md): every milestone.
- [`docs/LAUNCHER.md`](docs/LAUNCHER.md) and [`docs/IMC_SETTINGS.md`](docs/IMC_SETTINGS.md): the launcher and the settings page.
- [`docs/IOS_CRASH_STACK.md`](docs/IOS_CRASH_STACK.md): the stack overflow that killed the title screen.

## Credits and licence

Built on [Horizon](https://github.com/horizon-rust/horizon) by Ludovic Marie and the Horizon contributors (MIT).
This port is released under the [MIT licence](LICENSE); `horizon/` keeps its own [licence](horizon/LICENSE) and
[third-party notices](horizon/THIRD_PARTY_NOTICES.md).

Minecraft is a trademark of Mojang Studios.
