# The Horizon Marketplace on iOS (M14)

Status (2026-11-10, second pass): **browse and install are written; neither has run on a phone.** Install (step 3)
downloads a mod, resource pack or shader, checks it, puts it in the game's folder and records it; the project page has
Install / Update / Remove, and the list has an Installed tab. 23 of the registry's 25 non-native projects pass the
phone's install rules today; the other 2 are signed and are refused (see "Not done"). Revocation of installed files
(step 4) and honest labels (step 5) are only partly built, see below.

"Marketplace" here means **Horizon's own registry**, `horizon-rust/horizon-mods`, the source of the desktop
launcher's mod browser. If an app of your own organisation was meant, say so.

## What is built

| File | What it does |
|---|---|
| `MarketIndex.m` | Parses and judges `index.json` (schema 1). No network, no UIKit |
| `MarketClient.m` | Fetches it from the one fixed address, keeps the last good copy in `Documents/Horizon/marketplace/horizon-index.json`, falls back to it offline |
| `LauncherPrefs.{h,m}`, `MarketCells.{h,m}`, `ModrinthClient.{h,m}` | The Settings choices (what is hidden until turned on), the card row, and the Modrinth resource pack client |
| `LauncherMarketplace.m` | The screen (Home > **Marketplace**): card rows and a row of chips (Resource packs and Installed always; Modrinth, Mods, Shaders and Everything once turned on in Settings), search, and a project page with Install / Update / Remove and a progress bar |
| `MarketInstaller.m` | The install rules and the disk work, no network or UIKit: what is refused, where each kind goes, SHA-256, atomic replace, the `mod-browser.json` record, `horizon-mods.txt`, remove |
| `MarketFetcher.m` | The download: the registry's release address only, redirects only to github.com or `*.githubusercontent.com` (at most 5), cut off at the listed size, 120 s without data |

**What the screen shows.** Name, kind, a plain label (*Works on iPhone*, *Needs a desktop build*, *Not supported
yet*), the summary, and on the page: authors, licence, categories, the newest version for 26.3 and its size, download
and star counts, whether the author signs their files, the source link, the author's description and changelog
exactly as written (plain text, not rendered), and the registry's reason when a file was taken down.

## Rules, from `crates/horizon-mods/src/index.rs` (read, not remembered)

The parser follows the desktop's: schema higher than 1 is refused with "update the app"; project ids are
`[a-z0-9_]{1,64}` and unique; a name and licence are required; `source` is https; at least one version; versions are
unique; file names are plain (no folder, no leading dot, `[A-Za-z0-9._+-]`, at most 128) and carry the kind's
extension; `sha256` is 64 lowercase hex; size is 1 byte to 64 MiB; a project with a `key` signs every version and a
project without one signs none; unknown fields and unknown kinds are accepted (an unknown kind is "not supported
yet"). **One broken project fails the whole index**, as on the desktop, and the cached copy is used instead.

**Where the phone is stricter, on purpose:**
1. A file of an installable kind must come from `https://github.com/horizon-rust/horizon-mods/releases/download/<tag>/<name>`.
   The desktop also allows the old `ludovic111/horizon-mods` host, Modrinth and CurseForge, and any GitHub release
   asset of a mod's own repository. None of the 208 files in the live index uses anything but the first host.
2. Icons and screenshots load only from `https://horizon-rust.github.io/horizon-mods/`, as PNG or JPEG, with no `..`,
   query or fragment. A foreign image is dropped; the project stays listed.
3. A kind the phone cannot use is listed but never offered: **native mods** (133 of 158 today) change the game's
   source before it is compiled, so they need a desktop build.

**Which copy is trusted** (`MarketClient.m`): a copy under ten minutes old is used without the network; otherwise the
registry is asked; what comes back is parsed and checked **before** it replaces the cache, so a broken or hostile
answer cannot overwrite a good copy; with no network the old copy is shown and the screen says so and when it was fetched.

## Checked

`python3 platform/ios/tests/market_index_check.py` (92 checks offline): every rule above with accepted and refused
cases, revocation by hash and for a whole project, falling back to the older version when the newest is revoked,
the cache decision table. `--live` adds the real index: 158 projects parse, 25 installable and 133 desktop-only,
every installable file is on the registry host, every icon and screenshot passes the image rule, the 3 revoked entries
are all native mods (so none touches an installable project today), and tampering with the real data (an upper-case
hash, a file pointed at another organisation) is refused. It is a Python copy of the logic; the Objective-C was only
compiled by CI.

## Install (step 3), written 2026-11-10, never run on a phone

Follows `launcher/src/browser/horizon.rs` (`install_version_guarded`) and the game's own `mod_registry.rs`:
- **Where:** a mod to `<home>/horizon-mods/<id>.hmod`, a resource pack to `<home>/resourcepacks/<name>`, a shader to
  `<home>/shaderpacks/<name>`; `<home>` is `Documents/Horizon/home`, the folder the game is started with (`--home`).
- **How:** downloaded to `<home>/mod-browser/downloads/`, then size, SHA-256, "taken down" and the ZIP signature are checked
  before a rename into place (a replace for an update). A bad file is deleted and nothing is recorded.
- **Record:** `<home>/mod-browser.json`, the file the desktop launcher and the game both read. Entries from other sources
  are written back untouched. A mod is turned on in `horizon-mods.txt` as `mod.<id>:true` (the other lines are kept), as on
  the desktop; the game reads mods at start, so it says to restart.
- **Never over a player's own file**, a folder mod of the same id, or a file another install owns.
- **Remove** deletes the file, the record and the `mod.<id>` line. A record that names a file outside the install folders
  is refused, and a planted symlink is removed as a link.
- **Checked:** `python3 platform/ios/tests/market_install_check.py --live` (67 checks): every refusal, placing, updating,
  removing, and with `--live` a real mod, resource pack and shader downloaded from the registry and installed into a temp
  folder, a one-bit-flipped real download refused, and the live index judged (23 installable, 2 signed refused).
  It is a Python copy of the logic; the Objective-C was only compiled by CI.

## Modrinth resource packs (2026-11-10, never run on a phone)

Added at the owner's request, **resource packs only**, behind Settings > Marketplace > Modrinth resource packs (off by
default). Modrinth's mods are Java mods that the desktop ports with a JVM tool, and its shaders are not Horizon's format,
so neither is offered. Follows `launcher/src/browser/modrinth.rs`, `download.rs`, `browser.rs` (`safe_name`, `pick`).

| Step | Rule |
|---|---|
| Search | `api.modrinth.com/v2/search`, facets `project_type:resourcepack` and `versions:26.3`, 30 per page, most downloaded first (or by relevance when you type). 7,136 packs at the time of writing |
| Version | the newest *listed* version whose `game_versions` contains `26.3`, its primary file; an older one is used if the newest fails a rule |
| File | only `https://cdn.modrinth.com/data/<id>/versions/<id>/<name>`; one plain name (the desktop's rule: spaces, `§`, `[ ]`, `+` are fine; `/ \ : * ? " < > |`, a leading dot, a trailing dot or space are not); ends in `.zip`; at most 64 MB |
| Download | redirects only to `cdn.modrinth.com`, cut off at the listed size |
| Check | size, then **SHA-512** (SHA-1 if that is all it lists), then a ZIP whose every path is plain (no leading `/`, no `..`, no `\`) with `pack.mcmeta` at its root, read from the ZIP's directory without unzipping |
| Place | `resourcepacks/<name>`, never over a player's file; recorded in `mod-browser.json` with `"source":"modrinth"` and `"kind":"resource-pack"` |

Not reviewed by Horizon: the install confirmation says so. A pack only works if the game loads it; nothing here has put a
Modrinth pack in the game's list on a phone.

**A bug fixed on the way.** The first install pass recorded a Horizon resource pack as `"kind":"resourcepack"`. The desktop
reads kinds in kebab-case (`"resource-pack"`), so it would have dropped that entry and not seen the pack. Fixed and tested.

## Not done

- **Signed projects are refused** (2 of 25 today, e.g. `flesh_to_leather`): the minisign check (Ed25519 + BLAKE2b) is not
  written. A dependency needs your approval; the alternative is a few hundred lines of crypto. Install must keep refusing
  until it exists, never skip it.
- **The deep content check.** The desktop runs `index::inspect` after the hash (a mod's manifest against the index, a
  shader pack's own checks, a resource pack's `pack.mcmeta`). The phone checks the ZIP container only. The game checks
  content when it reads it and shows a red reason on a mod it cannot load, so a bad file cannot run silently, but a file
  that passes the hash and is wrong inside would install and then fail in the game.
- **Update checks and automatic updates**, and removing an installed file the registry later takes down (step 4): the page
  shows the registry's reason and refuses a new install, but an old install is not removed by itself.
- **Shaders are untested on Metal**, and no installed pack has been seen in the game's list. The labels say so.
- **`api_level`**: the desktop skips a version that needs a newer mod API than the game serves. The phone's engine
  level has not been read, so this is not applied yet; a code mod could be offered that the game then refuses to start.
- **Images**: icons and screenshots are not fetched or shown yet (the rule is written, the loader is not).
- **Descriptions are plain text**, not rendered Markdown.
- **Installed list, update check, removal, revoked-file removal**, the "restart the game" note, ratings and reporting.
- **A run on a phone.** Nothing here has loaded the index on a device.
- **Registry terms for third-party apps are unverified.** Check them before a public release (roadmap risk).
