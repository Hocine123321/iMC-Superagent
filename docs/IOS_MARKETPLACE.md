# The Horizon Marketplace on iOS (M14)

Status (2026-11-10): **step 1 (the index client) and a browse screen are written; nothing installs.** Both
compile in CI and have never run on a phone. Steps 3 to 5 of the plan in `IOS_IMPLEMENTATION_ROADMAP.md` (install,
revocation of installed files, honest labels after install) are not built, and no button pretends otherwise.

"Marketplace" here means **Horizon's own registry**, `horizon-rust/horizon-mods`, the source of the desktop
launcher's mod browser. If an app of your own organisation was meant, say so.

## What is built

| File | What it does |
|---|---|
| `MarketIndex.m` | Parses and judges `index.json` (schema 1). No network, no UIKit |
| `MarketClient.m` | Fetches it from the one fixed address, keeps the last good copy in `Documents/Horizon/marketplace/horizon-index.json`, falls back to it offline |
| `LauncherMarketplace.m` | The screen (Home > **Marketplace**): tabs (Works on iPhone, All, Mods, Packs, Shaders), search, a project page |

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

## Not done

- **Install (step 3)**: download, check size and SHA-256, check the minisign signature for the 61 of 208 versions
  that have one (needs a minisign verifier on the phone: a library or a few hundred lines of Ed25519 and BLAKE2b,
  neither written; adding a dependency needs your approval), check what the file says about itself (`index::inspect`),
  write to the right folder, enable it. Without the signature check the SHA-256 still pins the exact reviewed file,
  but a signed project would be less protected than on the desktop. Of the 29 installable versions in the live index
  (2026-11-10) only **2 are signed** (61 of all 208), so the missing verifier affects very little today; the rule
  still stands: install must refuse a signed project's file until the signature is checked, never skip it.
- **`api_level`**: the desktop skips a version that needs a newer mod API than the game serves. The phone's engine
  level has not been read, so this is not applied yet; a code mod could be offered that the game then refuses to start.
- **Images**: icons and screenshots are not fetched or shown yet (the rule is written, the loader is not).
- **Descriptions are plain text**, not rendered Markdown.
- **Installed list, update check, removal, revoked-file removal**, the "restart the game" note, ratings and reporting.
- **A run on a phone.** Nothing here has loaded the index on a device.
- **Registry terms for third-party apps are unverified.** Check them before a public release (roadmap risk).
