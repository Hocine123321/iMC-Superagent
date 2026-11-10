# Sign-in (M9)

Status: **built, not run.** The code is in `platform/ios/App`, but it has never run against Microsoft:
sign-in cannot work until the owner registers an Azure app and Mojang approves it (below). Until then
the Account screen says "Sign-in is not set up yet" and nothing is sent.

## What it is for

Decided 2026-11-09: **sign-in gates the download of the game (M8b) and nothing else.** Playing game
files that are already on the phone never asks for it. The desktop launcher is stricter (no owner, no
Play); this port is not, because its files can also come from a computer through Game files.

The gate is a policy control, not copy protection. The engine does not enforce it.

## What only the owner can do

Nothing here can be done by an agent. The registrations belong to the owner. The flow and the reasons
are in `horizon/docs/microsoft-account.md` ("What Ludovic registers"); for this project:

1. **Azure app registration** at https://portal.azure.com, Microsoft Entra ID, App registrations, New:
   - Name: `iMC Horizon` (shown on Microsoft's consent page).
   - Supported account types: **Personal Microsoft accounts only**.
   - Redirect URI: none (the device-code flow needs none).
   - Authentication, Advanced settings: **Allow public client flows: Yes**.
   - API permissions: none to add. The app asks for `XboxLive.signin offline_access` itself.
   - Copy the **Application (client) ID**.
2. **Mojang's app-ID review**: https://aka.ms/mce-reviewappid, giving that client ID, the app name,
   the project URL and a short description. Approval takes days to weeks. Until then the last step
   (`login_with_xbox`) answers HTTP 403 and the app says "its app is not approved by Mojang yet".
3. **Give the build the ID.** A client ID is public, not a secret. Set a GitHub repository *variable*
   `HZ_MSA_CLIENT_ID` and pass it to `xcodebuild` as `HZ_MSA_CLIENT_ID=$HZ_MSA_CLIENT_ID` in
   `.github/workflows/ios-app.yml` (one line; not done yet, because without an ID the build is correct
   as it is). For a quick test on a device, the environment variable `HORIZON_MSA_CLIENT_ID` overrides
   the built-in value.

A build never carries another application's client ID. The one exception is the private test mode below, which reads one from the phone and is off by default.

## Test mode (a fallback while Mojang has not approved the app)

Decided 2026-11-10: while the app-ID review is pending, the owner can sign in on his own phone with
another launcher's app ID. This is **a private test aid, not a release feature.**

**What was checked (2026-11-10, live against Microsoft).** The official Minecraft Launcher's ID
`00000000402b5328` (the one Amethyst and PojavLauncher send) is a *legacy* Microsoft app:
- The v2 endpoint this project normally uses **refuses it**: `AADSTS700016`, application not found.
  So setting an environment variable on the normal path would not have worked.
- The legacy `login.live.com/oauth20_connect.srf` device-code endpoint **accepts it** and returns a
  code for `microsoft.com/link`. Polling answers `authorization_pending`; a bad refresh token answers
  `invalid_grant`. Same field names as v2, so the same parser reads them.
- **Not checked:** a real sign-in end to end, Xbox Live accepting the token as a bare `RpsTicket`
  (Amethyst sends it bare; v2 tokens need `d=`), and whether Mojang's `login_with_xbox` returns a
  token for a device-code login with that ID. Only a real sign-in on a phone settles these.

**What test mode changes** (only when no registered `HZ_MSA_CLIENT_ID` is in the build, so a
registered ID always wins):
- device code and token requests go to `login.live.com` instead of the v2 endpoint;
- scope `service::user.auth.xboxlive.com::MBI_SSL` instead of `XboxLive.signin offline_access`;
- the Xbox ticket is the bare token, with no `d=` in front.

**How to turn it on.** Put one line, the ID, in `Documents/Horizon/test-client-id.txt` (Files app, On
My iPhone, iMC Horizon, Horizon), then restart the app. (The environment variable
`HORIZON_MSA_LEGACY_CLIENT_ID` also works, but a LiveContainer launch cannot set one.) To turn it
off, delete the file. It is read once per run, never saved by the app and never put in a build. The
Account screen says "test mode" while it is on.

**Why it is only a fallback.**
- It borrows another app's identity. Mojang's rules for third-party launchers say to register your
  own, and an ID that is abused can be blocked, which would break every launcher using it.
- Do not ship a build with it, and do not share the file. Anyone you give the app to would be
  signing in as the official launcher.
- Remove it (delete the file, ignore this section) as soon as the registered app is approved.

## The files

| File | What it does |
|---|---|
| `AccountModel.h/.m` | The rules, with no network and no UIKit: reading each reply, the refusal messages (the desktop launcher's words), whether the account owns Java Edition, and `HZMayDownload`, the one place the gate lives. |
| `AccountClient.h/.m` | The requests, in the order of the doc: device code, poll, Xbox Live, XSTS, `login_with_xbox`, entitlements, profile. An ephemeral `NSURLSession` (no cookies, no cache, nothing on disk). No body is ever logged. |
| `AccountStore.h/.m` | The Keychain (two items) and `<Documents>/Horizon/account.txt` (name, UUID, last answer; no secret). |
| `LauncherAccount.h/.m` | The Account screen, reached from a new *Account* button on the launcher. |

## Decisions

- **Device code**, as on desktop. It needs no redirect URI and no change to the Azure app. On a phone
  the player reads a code on the same device that shows the page, so the code is copied to the clipboard
  and the page opens with one tap. A web-authentication sheet with a custom redirect is an alternative
  to evaluate once the app exists.
- **`login_with_xbox` only.** The desktop launcher tries `launcher/login` (platform `PC_LAUNCHER`) first,
  because a token from `login_with_xbox` alone makes joining an online-mode server fail with "Profile
  not found". This port does not claim to be a PC launcher, so it does not use that route. **Online
  servers (roadmap M10) will need the question reopened.**
- **Keychain class** `AfterFirstUnlockThisDeviceOnly`: no backup, no other device. The Keychain takes
  long items, so the desktop's splitting workaround is not needed.
- **Offline never blocks someone who passed before.** `HZMayDownload`: a fresh answer wins (a fresh "no"
  blocks at once, even after a past "yes"); with no network the last answer stands; no account, or never
  a yes, blocks.
- **The refresh token is renewed** at each check (`recheck`), and a refused one (`invalid_grant`) asks
  the player to sign in again.
- **Sign out** deletes both Keychain items and `account.txt`.

## What is not done

- **The download itself (M8b)** does not exist, so nothing calls `HZMayDownload` yet. The gate is built
  and its rules are tested; the thing it guards is not.
- **Sign in with Apple.** The roadmap (D12) notes that Apple may expect it beside a third-party login
  for the App Store. This app is not distributed through Apple, so it is not added.
- **Skin and cape** of the profile are not read. The profile screen shows the name only.
- **Token expiry timers.** The Minecraft token (24 hours) is renewed when a check runs, not on a timer.
- **Not compiled or run.** There is no Objective-C compiler where this was written. CI's
  *iOS shell check* compiles each `.m` against the iOS SDK; that is the first compile.

## How it is tested

`platform/ios/tests/account_rules_check.py` checks the decisions of `AccountModel.m` against the reply
shapes in the desktop launcher's own tests (`horizon/launcher/src/account/tests.rs`): a Python copy of
the logic, as `SessionLog` has a C copy of its line format. It checks the logic, not the Objective-C
text, so it does not replace the CI compile.

## To check once there is a client ID

1. Account, Sign in: a code appears and is on the clipboard.
2. Open the page, type the code, finish in the browser: the screen shows your Minecraft name.
3. An account that does not own Java Edition: "This account doesn't own Minecraft: Java Edition."
4. Airplane mode after a pass: the account still shows as an owner.
5. Sign out, then check the Keychain item is gone (Settings has none to show; sign in again to see the
   code screen return).
6. A network trace shows no token in any log line (Diagnostics > the game's log, and the session log).
