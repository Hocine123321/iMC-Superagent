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
| `docs/` | The iOS port documents: feasibility report, implementation roadmap, memory strategy, and `ios-evidence/` (logs and the diagnostic patch). |
| `platform/ios/` | The iOS app shell (Swift) and the Rust staticlib bridge. Not started. |
| `.github/workflows/` | CI for this port. Upstream's own workflows are kept inert in `horizon/.github/`. |

## Status

Research phase complete; implementation starts at roadmap milestone M1.
See [`docs/IOS_IMPLEMENTATION_ROADMAP.md`](docs/IOS_IMPLEMENTATION_ROADMAP.md).
The `iOS build` workflow is the source of truth for whether the engine links
for `aarch64-apple-ios`.
