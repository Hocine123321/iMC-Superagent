---
title: Download plan (M8b, step 1)
summary: What the app will fetch from Mojang for Minecraft 26.3, how that list is decided, what was verified live, and what is not built yet.
---

# Download plan (M8b, step 1)

Status (2026-11-10): **the plan is written and tested, and the downloader and its screen are written
(M8b step 2), but none of it has run on a phone.** `platform/ios/App/DownloadPlan.m` decides *which* files
to fetch and *where* to put them (no network, no UIKit, no disk). `Downloader.m` fetches them,
`DownloadStore.m` keeps the disk rules and `LauncherDownload.m` is the screen, reached from Home >
**Download Minecraft**. CI compiles them; a phone has never run them. Preparing the files for the game
(the Java part) is not built.

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

## The downloader (M8b, step 2): written 2026-11-10, not run

| File | What it does |
|---|---|
| `Downloader.m` | Asks Mojang's manifest for the 26.3 version file, checks it against the manifest's sha1, reads the asset index it names (checked against its sha1), asks `DownloadPlan` for the files, adds the 62.3 MB server jar from the same version file, then fetches what is missing |
| `DownloadStore.m` | The disk rules: is a file already here and whole, SHA-1 in chunks, write to `<name>.part` and rename only after size and SHA-1 match, delete leftover `.part` files |
| `LauncherDownload.m` | The screen: the sign-in gate, a progress bar, bytes and file counts, Stop, and the developer override |

**How it resumes.** A real file name only ever holds a whole, verified file. On the next run a file that is
there with the listed size and SHA-1 is kept; a wrong one is deleted and fetched again; a `.part` is never
trusted and is deleted. So stopping, a crash, or the phone running out of battery loses at most the files in
flight (six at a time), and starting again carries on.

**Other rules.**
- Six files at once (5,147 small sounds one at a time would take hours); a failed file is retried up to four
  times with 2, 4, 8 second waits for network trouble and 408, 425, 429 and 5xx answers. A 404 or a wrong
  hash after four tries stops the whole run with the file's name.
- A free-space check before fetching: the bytes still to fetch plus 100 MB. It says the numbers if short.
- Every address must be https on a Mojang host, including the manifest's address for the version file; the
  folder every path lands in is resolved, so a link planted inside the game folder cannot lead a write out.
- Nothing is logged but file names; no account token is used (the endpoints are public).
- Where it writes: `Documents/Horizon/minecraft/`, in the official launcher's layout
  (`versions/26.3/26.3.jar`, `versions/26.3/26.3.json`, `versions/26.3/26.3-server.jar`, `libraries/...`,
  `assets/indexes/34.json`, `assets/objects/<2 hex>/<sha1>`, `assets/log_configs/...`).

**The gate.** The screen calls `HZMayDownload` with a fresh ownership check. No account blocks it with a
message; a fresh "no" blocks it; offline, a past "yes" stands (but the download itself needs the network, so
it then fails with a plain message). **Developer override:** create a file named `developer-download` in the
Horizon folder (Files app) to skip the check, so this can be tried before Mojang approves the app's sign-in.
The screen says when the override is on. It is meant for the owner's own phone.

**Verified.** `python3 platform/ios/tests/downloader_check.py` (48 offline checks: retry and backoff rules,
the manifest lookup and its refusals, path containment including a planted symlink, the resume decision for
a missing, short, wrong-hash, whole and folder-in-the-way file, install refusing bad size and hash and leaving
a good file alone, partial-file cleanup, chunked SHA-1). `--live` adds Mojang's real manifest, version file
and asset index checksums (all match) and the server jar. It is a Python copy of the logic and checks the
rules, not the Objective-C text. **No Objective-C was compiled here;** CI is the only compile check.

## Not done

- **A run on a phone**: nothing here has downloaded a byte on a real device. Things only a phone shows:
  whether six connections is right on cellular, how long 5,215 files take, whether the screen stays awake
  and the download survives a lock-screen, and what iOS does when the app is sent to the background (a
  foreground `URLSession` is paused by iOS shortly after; the next run resumes it, but a background
  session is not used yet).
- **Background downloading** (`NSURLSessionConfiguration.backgroundSessionConfiguration`): not built. The app
  must stay open.
- **The Java runtime** (`java-runtime-epsilon`, Java 25) as a separate download, and **preparation**:
  whether the phone can run Java at all is M8a and is not settled.
- **A check of the whole folder at the end** against the plan (the per-file checks cover each file; a
  final "everything the plan lists is present" sweep is not written).
- **Deleting the downloaded copy** after preparation to save space (decision for M8b step 3).
