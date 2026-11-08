---
title: First device test (M8a)
summary: What to install on the iPhone 12 and what to send back, so the Java runtime question gets a real answer.
---

# First device test (M8a)

Everything here is a **test**. Nothing in this file has been run on a phone yet. The goal is to
answer, in order, with evidence:

1. Does the Horizon app install and stay open with your signing method?
2. Does StikDebug list it, and does it report `CS_DEBUGGED` once JIT is on?
3. Does a JIT page (written, then executed) work inside the app on iOS 27.2?
4. Is the Java 25 runtime where the app expects it?

Steps 1 to 4 need no Java and no game files. They are what the diagnostics report checks.

## What to install

- The unsigned app from the latest successful **iOS app** run on GitHub Actions:
  artifact **Horizon-unsigned-ipa** (`Horizon-unsigned.ipa`).
- Sign and install it with your usual tool (SideStore or iloader). That tool signs it with your own
  certificate, which is what adds `get-task-allow`. Nothing in the repo signs the app.

## What to do

1. Install the IPA and open Horizon once. It will show the loading screen or close. Either is fine.
2. Open **Files > On My iPhone > Horizon > Horizon**. Open **diagnostics.txt** and keep the text.
3. In StikDebug, with the VPN on, enable JIT for Horizon. Then open Horizon again (force-close it first).
4. Open `diagnostics.txt` again. It is overwritten on each launch.
5. Send both versions of the text back.

## What each line means

| Line | Good result | If not |
|---|---|---|
| `get-task-allow` | `1` or `true` | StikDebug will not list the app. The signing tool removed it; use another install method. |
| `CS_DEBUGGED` | `SET` after step 3 | StikDebug did not attach to this app. Report what StikDebug says. |
| `MAP_JIT page ... returned 42` | `JIT WORKS` | JIT is not usable by this app on iOS 27.2, and the Java plan stops here. |
| `jre25 ... libjvm.dylib` | `file present` | Only after the runtime is copied in (a later step). `not found` is expected today. |

## Why the JIT test runs last

If the kernel refuses a JIT write it kills the app and cannot be caught. The report is flushed
after every line, so a crash at that test still leaves everything before it in the file.
That would itself be an answer, so send the file even if the app closed.

## What this does not test

Loading `libjvm`, running `java -version`, or running any exporter. Those come after this passes.
