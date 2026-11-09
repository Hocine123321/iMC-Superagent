# iMC-Superagent: Horizon on iOS

Research and engineering work toward a native iOS client built on the
[Horizon](https://github.com/horizon-rust/horizon) Rust engine for Minecraft
Java Edition. It is **not** an official Minecraft product and is not
approved by or associated with Mojang or Microsoft. It contains no Minecraft
code or assets: players need their own copy of Java Edition.

## Layout

| Path | What it is |
|---|---|
| `horizon/` | Unmodified snapshot of upstream Horizon at `77af961` (MIT). Changes here are kept small and upstreamable. |
| `docs/` | The iOS port documents: feasibility report, implementation roadmap, memory strategy, launcher, touch and iMC Settings, and `ios-evidence/` (logs and the diagnostic patch). |
| `platform/ios/` | The iOS app shell (Objective-C launcher, crash reporter, diagnostics) and the project that builds the IPA. The Rust staticlib bridge is `horizon/platform/ios-bridge/`. |
| `.github/workflows/` | CI for this port. Upstream's own workflows are kept inert in `horizon/.github/`. |

## Status

The engine builds, links and starts on iOS. Each CI run of the `iOS app` workflow publishes an
unsigned IPA as a release named *iMC Horizon vN*, which you sign yourself.

What exists: a native launcher (home, game files, diagnostics), touch controls and app lifecycle
(M4/M5), a crash reporter, and the in-game **iMC Settings** page. What does not: a verified
playable run on a phone, preparing the game files on the phone (M8), and sign-in (M9). You bring
the prepared game files yourself for now.

Where to read next:
- [`docs/IOS_DECISIONS_AND_APP_VISION.md`](docs/IOS_DECISIONS_AND_APP_VISION.md): the decisions and what is proven.
- [`docs/IOS_IMPLEMENTATION_ROADMAP.md`](docs/IOS_IMPLEMENTATION_ROADMAP.md): every milestone.
- [`docs/LAUNCHER.md`](docs/LAUNCHER.md) and [`docs/IMC_SETTINGS.md`](docs/IMC_SETTINGS.md): the launcher, the settings page, the touch offset fix.
- [`docs/IOS_CRASH_STACK.md`](docs/IOS_CRASH_STACK.md): the stack overflow that killed the title screen.

The `iOS app` workflow is the source of truth for whether the app builds.
