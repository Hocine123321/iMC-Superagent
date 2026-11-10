# iMC-Superagent: Horizon on iOS

Research and engineering work toward a native iOS client built on the
[Horizon](https://github.com/horizon-rust/horizon) Rust engine for Minecraft
Java Edition. It is **not** an official Minecraft product and is not
approved by or associated with Mojang or Microsoft. It contains no Minecraft
code or assets: players need their own copy of Java Edition.

## Layout

| Path | What it is |
|---|---|
| `horizon/` | Snapshot of upstream Horizon at `77af961` (MIT) plus this port's changes (60 files, listed in `docs/HORIZON_CHANGES.md`, with a patch to replay them on a newer upstream). |
| `docs/` | The iOS port documents: feasibility report, implementation roadmap, decisions, memory strategy, launcher, Marketplace, download plan, sign-in, touch and iMC Settings, the list of changes inside `horizon/` with its patches, and `ios-evidence/` (logs and the diagnostic patch). |
| `platform/ios/` | The iOS app shell (Objective-C launcher, crash reporter, diagnostics) and the project that builds the IPA. The Rust staticlib bridge is `horizon/platform/ios-bridge/`. |
| `.github/workflows/` | CI for this port. Upstream's own workflows are kept inert in `horizon/.github/`. |

## Status

The engine builds, links and starts on iOS. Each CI run of the `iOS app` workflow publishes an
unsigned IPA as a release named *iMC Horizon vN*, which you sign yourself.

What exists: a native launcher (Home, Marketplace, Settings, file manager, game files, Account, diagnostics, About), touch controls and app lifecycle
(M4/M5), a crash reporter, and the in-game **iMC Settings** page. The game itself **runs on a phone without issues**
(confirmed by the owner, 2026-11-10), so the port works; the work now is making it feel made for iOS (milestone M15 in
the roadmap). What does not exist yet: preparing the game files on the phone (M8: the download is written but has never
run on a phone; the Java preparation is not), and a working sign-in (M9: the code and Account screen exist, but they need
your own Azure app and Mojang's approval, see `docs/IOS_SIGN_IN.md`). You bring the prepared game files yourself for now.

Where to read next:
- [`docs/IOS_DECISIONS_AND_APP_VISION.md`](docs/IOS_DECISIONS_AND_APP_VISION.md): the decisions and what is proven.
- [`docs/IOS_IMPLEMENTATION_ROADMAP.md`](docs/IOS_IMPLEMENTATION_ROADMAP.md): every milestone.
- [`docs/LAUNCHER.md`](docs/LAUNCHER.md) and [`docs/IMC_SETTINGS.md`](docs/IMC_SETTINGS.md): the launcher, the settings page, the touch offset fix.
- [`docs/IOS_CRASH_STACK.md`](docs/IOS_CRASH_STACK.md): the stack overflow that killed the title screen.

The `iOS app` workflow is the source of truth for whether the app builds.
