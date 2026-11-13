#!/usr/bin/env python3
"""Fails when the game's startup call chain needs more stack than an iOS main thread has.

An iOS main thread has 1008 KB (the crash reporter prints it). The game starts from inside the
event loop, on that thread, through run_with -> run_loading -> about_to_wait -> finish ->
finish_game -> start_boxed -> start_game -> Game::new_boxed. Each Rust frame is read from its
prologue in the arm64 binary. Three builds crashed on this (docs/IOS_CRASH_STACK.md); this check
makes the next one fail in CI, before an IPA is published.

usage: check_stack_budget.py <Mach-O binary> [budget_kb, default 760]
The budget counts only these Rust frames; the system frames below them (UIKit, CoreFoundation,
winit) measured about 100 KB in the crash reports, and the engine's own callees need room too.
"""
import re
import sys

import capstone
import lief

# Each frame is found by substrings that must ALL appear in its mangled (Rust v0) name. Use only
# stable pieces: module and item names with their length prefixes. Never paste a whole mangled
# name: it carries crate hashes ("Cs4qHPzLtCqPq_5winit") and back-references ("NtB4_") that change
# whenever the compiler or a dependency changes, which made this check fail on a good build.
CHAIN = [
    ("run_with", ("4game8run_with",)),
    ("run_loading", ("4game11run_loading",)),
    ("App::about_to_wait", ("loading_screen", "3App", "ApplicationHandler13about_to_wait")),
    ("Loading::finish", ("7Loading6finish",)),
    ("Loading::finish_game", ("7Loading11finish_game",)),
    ("start_boxed", ("loading_screen11start_boxed",)),
    ("start_game", ("loading_window10start_game",)),
    ("Game::new_boxed", ("4Game9new_boxed",)),
]


def main():
    path = sys.argv[1]
    budget = float(sys.argv[2]) if len(sys.argv) > 2 else 760.0
    fat = lief.MachO.parse(path)
    m = fat.at(0) if hasattr(fat, "at") else fat
    text = [s for s in m.sections if s.name == "__text"][0]
    code, base = bytes(text.content), text.virtual_address
    starts = sorted({s.value for s in m.symbols if base <= s.value < base + len(code)})
    md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)

    def frame(addr):
        i = starts.index(addr)
        end = starts[i + 1] if i + 1 < len(starts) else base + len(code)
        probe, extra = 0, []
        for ins in md.disasm(code[addr - base:min(end - base, addr - base + 80)], addr):
            if ins.mnemonic != "sub":
                continue
            mm = re.match(r"x9, sp, #(0x[0-9a-f]+)(?:, lsl #(\d+))?", ins.op_str)
            if mm:
                probe = int(mm.group(1), 16) << int(mm.group(2) or 0)
            mm = re.match(r"sp, sp, #(0x[0-9a-f]+)(?:, lsl #(\d+))?", ins.op_str)
            if mm:
                extra.append(int(mm.group(1), 16) << int(mm.group(2) or 0))
        return (probe + (extra[1] if len(extra) > 1 else 0)) if probe else sum(extra)

    total, missing = 0.0, []
    print(f"{'frame':24s} {'KB':>7s}")
    for label, keys in CHAIN:
        found = [s.value for s in m.symbols
                 if "horizon_client" in s.name and all(k in s.name for k in keys) and s.value in starts]
        if not found:
            missing.append(label)
            print(f"{label:24s} {'?':>7s}  (symbol not found)")
            continue
        kb = max(frame(a) for a in found) / 1024
        total += kb
        print(f"{label:24s} {kb:7.0f}")
    print(f"{'chain total':24s} {total:7.0f}   budget {budget:.0f} (main thread 1008, system frames ~100)")
    if missing:
        print(f"::error::symbols not found: {missing}. The call chain changed; update CHAIN in this script "
              f"(match stable name pieces only, no crate hashes).")
        return 2
    if total > budget:
        print(f"::error::startup chain needs {total:.0f} KB of stack, budget {budget:.0f} KB")
        return 1
    return 0


sys.exit(main())
