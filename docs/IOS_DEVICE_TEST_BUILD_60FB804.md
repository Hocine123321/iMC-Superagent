---
title: Phone test checklist for the v17 build (60fb804 and later)
summary: What to try on the iPhone after installing the build with the Return, Attack/Use and Account fixes, and exactly what to send back if something fails.
---

# Phone test checklist (build 60fb804 and later)

**Status 2026-11-10.** This is the checklist for build v17 (`60fb804`). The latest build is v37, which has more in it (a SwiftUI launcher, the earlier UIKit launcher, Marketplace, Settings, Cursor mode, the iMC Settings page inside Video Settings), so install the latest *iOS app* run instead and use this list as a starting point; where it says "Options > Horizon Settings > iMC Settings" read **Options > Video Settings > iMC**. **Nothing here has been run on a phone yet.** The Rust and Objective-C compiled in CI, and the
logic has unit tests, but whether these fixes work on a real iPhone is exactly what this page is for.

Install the unsigned app from the latest successful **iOS app** run (artifact
`Horizon-unsigned-ipa`), sign it with your usual tool, and open it.

## 1. Return sends a chat message

1. Start a world. Open chat (the chat button), so the keyboard appears.
2. Type `test` and press **Return** on the keyboard.

- **Good:** the message is sent and the box clears.
- **Still broken:** nothing happens. Send me Diagnostics (below). The game logs any chat key that
  arrives without a physical key code, which shows what the keyboard really sends.

## 2. Attack and Use

1. In the world, face a block and hold **Attack**. The block should break.
2. Face a door, lever or chest and tap **Use**. It should open or toggle.
3. Try **Jump** too; it worked before and should still.

- **Good:** all three act.
- **Still broken:** say which one (Attack, Use or both), and whether a short tap or a hold fails.

## 3. Account screen

1. On the launcher, tap **Account**.
2. Expected with no Microsoft app set up: the title **Sign-in is not set up yet** and a greyed-out
   **Sign in** button. That is correct for now.

### 3b. Test mode (only if you chose to try it)

This borrows another launcher's app ID, for your own phone only. See `docs/IOS_SIGN_IN.md`,
"Test mode".

1. In the Files app, open **On My iPhone > iMC Horizon > Horizon** and create a text file named
   `test-client-id.txt` with one line, the ID.
2. Force-close and reopen the app. Open **Account**.
3. Expected: **Not signed in (test mode)** and an enabled **Sign in** button.
4. Tap **Sign in**. A code appears and is copied. Open the page, enter the code, sign in with the
   Microsoft account that owns Minecraft: Java Edition.

- **Good:** the screen shows your Minecraft name and "Owns Minecraft: Java Edition".
- **Fails:** copy the exact message on the screen. These are the likely ones and what they mean:
  - "The Minecraft services refused this app: its app is not approved by Mojang yet": Mojang's last
    step said 403. Test mode does not get past it for this ID.
  - "Xbox Live refused the sign-in": Xbox did not accept the token format. Send the message.
  - "The sign-in code expired": you took longer than 15 minutes. Start again.
- To turn test mode off, delete the file and restart the app.

### 3c. The game plays as your profile (needs a successful sign-in from 3b)

1. After signing in, go back. The launcher's button should read **Account: <your Minecraft name>**.
2. Tap Play, close the app, open it again so the game starts.
3. In the game, open chat or the player list and look at your name. Or join a LAN world and see it.

- **Good:** the game uses your Minecraft profile name.
- **Not good:** it shows a generated name (offline). Send Diagnostics. If the engine refused the
  session file, it says so on its error output, which on iOS is **not** known to reach the shared
  game log. What does reach Diagnostics is the last line of `diagnostics.txt` for that launch,
  starting `game account:`. It says whether the app handed your profile over, or why it did not.
- Joining an online-mode server needs a fresh token (about a day old at most). Open the launcher
  screen once first.

## 4. Earlier features nobody has confirmed on a phone yet

Tell me for each: works, doesn't, or didn't try.

- Touch controls: look, move, jump, inventory open and close.
- Long press on an inventory slot (takes half a stack, or places one).
- Auto Performance (lowers render distance when memory is low).
- iMC Settings page opens and saves.

## What to send back if anything fails

1. Open **Diagnostics** from the launcher. Tap the **share icon in the top-right corner**. Send the
   files it shares (it includes the newest game log).
2. A sentence on what you did and what you saw instead.
3. The iOS version and the install method (LiveContainer, SideStore, other).

Do not send screenshots of the Account screen after a successful sign-in if they show your name and
you want it private. The Diagnostics files contain no tokens.
