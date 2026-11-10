---
title: Download plan (M8b, step 1)
summary: What the app will fetch from Mojang for Minecraft 26.3, how that list is decided, what was verified live, and what is not built yet.
---

# Download plan (M8b, step 1)

Status: **the plan is written and tested; nothing downloads yet.** `platform/ios/App/DownloadPlan.m`
decides *which* files to fetch and *where* to put them. It has no network, no UIKit and no disk
access. The code that fetches, the progress screen and preparation are not built.

It mirrors `horizon/launcher/src/mojang.rs` (the desktop download): the client jar, the libraries,
the logging file, the asset index, then the asset objects, each with the size and sha1 Mojang lists,
in the official launcher's layout.

## Owner decisions

- **Mobile data (2026-11-10): no special handling.** The app does not ask before downloading and has
  no Wi-Fi-only mode.
- **Sign-in gates the download only** (docs/IOS_SIGN_IN.md). Nothing calls that gate yet.

## What the plan contains for 26.3 (measured live, 2026-11-10)

| Part | Files | Notes |
|---|---|---|
| Client jar | 1 | `versions/26.3/26.3.jar`, 41.5 MB |
| Libraries | 65 | of 114 in the version file |
| Logging file | 1 | `assets/log_configs/client-1.21.2.xml` |
| Asset index | 1 | `assets/indexes/34.json` |
| Asset objects | 5,147 | de-duplicated by hash; the sounds and other assets |
| **Total** | **5,215** | **610.5 MB** |

The server jar (62.3 MB, listed in the same version file) is **not** in the plan. The desktop
launcher fetches it separately, so the full first-time download is 672.8 MB (610.5 + 62.3).

## How libraries are chosen

Two filters, in the same order as `horizon-prepare` (`artifacts.rs`):

1. **Rules.** The last rule that matches decides; no rules means allowed. An iPhone counts as
   **`linux`**: `rule_system()` returns `osx` only on macOS, `windows` on Windows and `linux` for
   everything else, which includes iOS. A phone matches none of the Windows, macOS or Linux entries
   by itself, so without this decision the plan would fetch the wrong set. This takes 114 libraries
   to 66.
2. **Architecture of natives.** A classifier ending in `arm64`, `aarch64` or `aarch_64` is kept; one
   ending in `x86_64` or `x64` is dropped; a plain `natives-<os>` jar is dropped when the file also
   lists an arm64 variant of it. This takes 66 to 65 (it removes the x86_64 Netty epoll native and
   keeps `linux-aarch_64`).

One thing to know: in 26.3 the LWJGL `natives-linux` jars have **no** arm64 variant, so the plan keeps
the plain ones, exactly as the desktop does on Linux/arm64. Whether those jars work on an iPhone is
the Java runtime question (M8a), not something this plan can answer.

## What it refuses

The plan stops with a message, and fetches nothing, for:

- a download host that is not Mojang's (`libraries.minecraft.net`, `piston-data.mojang.com`,
  `piston-meta.mojang.com`, `resources.download.minecraft.net`), a non-https URL, or a look-alike
  host such as `libraries.minecraft.net.evil.com`;
- a path that is absolute, has `..`, a backslash or an empty part;
- a malformed or upper-case sha1;
- a library rule that asks about architecture, version or features, and a library with old-style
  natives. **No 26.3 library has any of these.** If Mojang adds one, the plan names the library
  rather than guess, which is safer than silently skipping or including it.

## Verified

`platform/ios/tests/download_plan_check.py` is a Python copy of the logic, kept in step with
`DownloadPlan.m` (the same way `account_rules_check.py` is for sign-in). It checks the rules, not the
Objective-C text.

- `python3 platform/ios/tests/download_plan_check.py` : 29 offline checks (rules, refusals, native
  filter, asset de-duplication).
- `... --live` : 39 checks in all. It fetches the real 26.3 files and confirms the version file and
  asset index match the sha1 Mojang lists, every host is Mojang's, there are no duplicate paths, no
  macOS, Windows or x86_64 files, and the arm64 Netty native is present. The rule-only count (66) was
  worked out a second, independent way and matches the first filter.

CI compiles `DownloadPlan.m` against the iOS SDK (the iOS shell check). **It has never run on a
phone.**

## Not done

- **The fetch itself**: a URLSession downloader that checks size and sha1 and writes whole files.
  The desktop keeps files already there and whole, so an interrupted download resumes; this needs
  the same.
- **The progress screen** and the call to the sign-in gate (`HZMayDownload`).
- **The server jar** and the **Java runtime** (`java-runtime-epsilon`, Java 25): separate downloads.
  Whether the phone can run Java at all is M8a and is not settled.
- **Preparation** (`horizon-prepare`) after the download.
- **Disk space check** before starting. 610 MB (673 MB with the server) should be compared with free
  space first.
