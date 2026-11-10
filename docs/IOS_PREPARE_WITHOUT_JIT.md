---
title: Preparing the game files on the phone without JIT (research and analysis)
summary: Every realistic route for getting prepared Horizon resources onto an iPhone 12 that cannot run a JIT, what each costs, what is proven and what is not, and a recommended order.
---

# Preparing the game files on the phone without JIT

Written 2026-11-11. Labels: **VERIFIED** (read in a file or run), **SOURCE** (stated in a public document I read, not run by me), **GUESS** (reasoning, not checked), **UNPROVEN** (nobody has shown it).

## 1. The problem, with the evidence

- On the owner's iPhone 12 (A14, no TXM, iOS 27.2) with StikDebug attached (`CS_DEBUGGED=1`), both `MAP_JIT` probes were refused with `errno 1` and `com.apple.developer.cs.allow-jit` was `absent` (`diagnostics.txt` of 2026-11-10 22:59 UTC). Probes B and C killed the app earlier. **VERIFIED.** So the JVM route that Amethyst uses is closed on this setup. This document assumes that stays true.
- Preparation is not a copy. `horizon-prepare` (about 8,000 lines of Rust) compiles and runs **372 Java files, about 51,000 lines**, that call Mojang's own server and client code to dump block behaviour, collision shapes, entity models, mob data, creative tabs and to run the vanilla data generator. **VERIFIED** (`docs/IOS_FEASIBILITY_REPORT.md` 6.1; file count taken from `horizon/`).
- Desktop cost, from upstream's own doc: about 23,200 resource files, 45 to 105 s, about 1.06 GB peak across the JVMs (server worker about 480 MB). **SOURCE.** The phone has 3.6 GB.

What is Java and what is not (reading `lib.rs`): the copying of client assets, sounds (about 380 MB, SHA-1 checked), data-pack files and the manifest are Rust. The **computed tables** (collision, block behaviour, render facts, entity and mob facts, command registries, creative inventory, data-generator reports) come from the JVM. **VERIFIED** in outline; I did not map every stage.

## 2. A fact that kills the obvious shortcut

`java -Xint` ("interpreter only") does **not** avoid executable memory. HotSpot's interpreter is generated at startup: `TemplateInterpreter::initialize_code()` builds "270+ interpreter codelets" into a code `StubQueue` (OpenJDK `templateInterpreter.cpp`, read 2026-11-11). Writing that code and then running it needs the same permission the JIT needs. So `-Xint` on the normal HotSpot VM would be refused the same way. **VERIFIED from source; not run on the phone.** The first thing the owner may try ("just turn the JIT off") will not work.

## 3. The routes

### Route A. A prepared folder from a computer (what exists today)
Prepare on a PC with the official launcher, copy `horizon-resources.json` and the rest into `Documents/Horizon/resources` (`docs/PC_PREPARATION_GUIDE.md`).
- Works now. No legal change. The game runs from it (confirmed).
- Cost: needs a PC, about 500 MB copied by hand. **This is the baseline every other route must beat.**

### Route B. Computed tables built once in CI, assembled on the phone (upstream issue #1750)
CI runs the full preparation once per Minecraft version with Java, packs only the computed tables (`pack-facts`), and the phone runs `horizon-prepare assemble` with the player's own client jar and asset store. No JVM on the phone.
- The issue's author says they ship this for Android and that "Horizon 26.3 plays from an assembled folder on both" PC and Android. **SOURCE** (issue #1750, opened 2026-10-25). Upstream labelled it `roadmap:prepare-without-java`, "Later", and an agent reply says the open question is legal: the tables must hold nothing of Mojang's, and the maintainer decides before anything is published. **SOURCE.**
- `pack-facts` and `assemble` are **not in our checkout** (searched `horizon-prepare/src`: no such module). Someone must write or import them (the issue offers a PR). **VERIFIED absent.**
- Legal/hosting: the tables are computed from Mojang's code. Whether they count as "nothing of Mojang's" is a legal call I cannot make. Hosting them is a distribution act, which is the line the project drew earlier (do not host Mojang material). **Needs the owner's decision.**
- Technically the strongest route: no JVM, no JIT, small download, the phone does only Rust work (hashing, copying, assembling). It also needs no change to the phone's signing.

### Route C. The user's own Mac/PC does the Java step, the phone fetches the result
Same output as A, but the transfer is automated: the PC runs `horizon-prepare` and the phone pulls the folder over the local network or iCloud-free file transfer.
- No hosting, no legal change. Needs a computer, so it does not meet "on the phone alone", but it removes the manual Files-app copy. **GUESS** on effort; a small local server in the PC launcher and a download screen on the phone.

### Route D. A JVM on the phone that needs no JIT: the OpenJDK Zero variant
Zero is a plain C++ bytecode interpreter with no generated code. It is a supported build option (`--with-jvm-variants=zero`, needs libffi; OpenJDK `doc/building.md`). **VERIFIED that it exists.**
- Our iOS runtime recipe (AngelAuraMC `6_buildjdk.sh`) takes `JVM_VARIANTS` from the environment and passes `--with-jvm-features=-zero`, so Zero is deliberately **off** today. **VERIFIED.** Using Zero means changing the recipe, cross-building libffi for iOS, and getting the patched tree to compile with that variant. Nobody has shown Zero running on iOS. **UNPROVEN.**
- It would still have to load `libjvm` in the app. Loading unsigned dynamic libraries on iOS is blocked by library validation, which Amethyst gets around by patching dyld in memory, and that patching itself needs the same memory permission that is refused. **VERIFIED in the feasibility report (Amethyst's dyld bypass); that the bypass fails here is my inference (GUESS).** A Zero JVM could instead be linked **statically into the app** (no dynamic load), but then the JDK's class libraries (`libjava`, `libzip`, `libnio`, and the module image) must also be static. No known iOS recipe does that. **UNPROVEN, probably the largest unknown.**
- Speed: Zero is much slower than the template interpreter (which is itself slower than JIT). I found no measured number for Zero, so I give none. The workload is Minecraft's registry bootstrap and iterating over every block state, which is long-running even on desktop. Whether it fits in minutes or hours on an A14 is **unknown**.
- Memory: 480 MB for the server worker on desktop with a JIT; an interpreter-only VM uses less code cache but I have no number.
- Verdict: a research project with several independent unknowns, each of which could end it. Not recommended as the first move.

### Route E. Ahead-of-time compile the exporters (GraalVM Native Image, or similar)
Turn the 372 Java files plus the Minecraft jars they call into native code once, so the phone runs ordinary machine code with no JVM.
- Native Image can build shared libraries, but I found no evidence of it targeting iOS arm64 for a large reflective codebase. **UNPROVEN.** Mojang's code uses reflection, registries and class loading that Native Image needs configured by hand, and the output would contain Mojang's compiled code, which cannot be distributed. It would have to be built on the player's machine, which has no toolchain.
- Verdict: not viable for distribution. Dropped.

### Route F. Rewrite the exporters in Rust
Ruled out in the feasibility report: the Java oracles are the specification Horizon is checked against, and 51,000 lines of Mojang-calling code cannot be reproduced without the oracle. **VERIFIED reasoning.** Dropped.

### Route G. Use Apple's own JIT permission
iOS grants JIT to web browsers and, in the EU, to some browser engines under special entitlements. A normal sideloaded app cannot hold them, and the owner's signing tool strips even `allow-jit` (diagnostics). **SOURCE for the policy; VERIFIED for the stripping.** Dropped.

### Route H. Run the Java step on another device the user already owns, over their account
A Mac/PC (Route C) or a server the user controls. The phone sends nothing but its own files. Same legal profile as C.

## 4. Comparison

| Route | Needs a computer | Needs hosting | JIT | New code | Proven by someone | Main risk |
|---|---|---|---|---|---|---|
| A. Copy a prepared folder | yes | no | no | none | yes (works) | usability |
| B. Published tables + assemble | no | **yes** | no | `assemble` in Rust | yes, on Android (SOURCE) | legal call on the tables |
| C. PC prepares, phone pulls | yes | no | no | small server and screen | n/a | still needs a PC |
| D. Zero JVM on the phone | no | no | no | very large | no | static JVM, speed, memory |
| E. AOT exporters | no | no | no | very large | no | cannot distribute |
| F. Rust rewrite | no | no | no | huge | no | unsound |

## 5. Recommendation

1. **Do not spend time on `-Xint`.** It needs the same permission as the JIT (section 2).
2. **Decide the Route B question, because it is the only route that removes the computer without a JVM.** The owner decides whether publishing the computed tables is acceptable; I cannot judge it. If the answer is yes, the work is small and checkable: bring `pack-facts` and `assemble` into `horizon-prepare` (or call them as the issue's author's library), run `pack-facts` in CI per version, host the zip with its SHA-256, and have the app download it and assemble beside the player's own jar. Everything else on the phone is Rust. The result is checked against a desktop folder file by file (`horizon-prepare --check`).
3. **Until then, make Route A and C good.** A clear Play screen that says files must come from a computer, plus a guided import (pick the folder in Files; the app validates `horizon-resources.json`). Route C (a local transfer from the PC launcher) is an optional improvement.
4. **Treat Zero (Route D) as a research spike only if Route B is refused.** The cheap first test: build Zero for macOS arm64 from the same patched tree and run one exporter, to learn the speed and memory with no iOS risk. Only if that is acceptable does the static-linking question matter.

## 6. What I could not establish

- Whether upstream will accept #1750, and whether the tables are legally "nothing of Mojang's" (not mine to decide).
- Whether Zero builds in the AngelAuraMC patched tree for iOS, and how slow it is.
- Which stages of `lib.rs` need the JVM, stage by stage. I counted the Java files and read the stage list but did not map each output to its source.
- Whether a statically linked JVM could pass iOS library validation. No source says it has been done.
