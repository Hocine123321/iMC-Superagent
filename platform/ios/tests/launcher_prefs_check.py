#!/usr/bin/env python3
"""Checks the rules of platform/ios/App/LauncherPrefs.m and the settings-file edit in LauncherTheme.m
(setSetting:for:). A Python copy of the logic: it checks the rules, not the Objective-C text, which only CI compiles.

The owner's rule (2026-11-10): the Marketplace shows resource packs by default. Mods, shaders and every other
category stay hidden until turned on in the launcher's Settings. Modrinth is a separate switch.

  python3 platform/ios/tests/launcher_prefs_check.py
"""
import os, sys, tempfile
fails = 0
def check(name, ok, extra=""):
    global fails
    print(("ok   " if ok else "FAIL ") + name + ((" : " + str(extra)) if (extra and not ok) else ""))
    if not ok: fails += 1

class Settings:
    def __init__(self, path): self.path = path
    def text(self): return open(self.path).read() if os.path.exists(self.path) else ""
    def get(self, key):
        for line in self.text().split("\n"):
            if line.startswith(key + ":"): return line[len(key) + 1:]
        return None
    def set(self, value, key):
        kept = [l for l in self.text().split("\n") if l and not l.startswith(key + ":")]
        kept.append(key + ":" + value)
        open(self.path, "w").write("\n".join(kept) + "\n")
    def boolean(self, key, fallback):
        t = (self.get(key) or "").strip().lower()
        return True if t == "true" else False if t == "false" else fallback
    def visible(self, kind):
        if kind == "resourcepack": return True
        if kind == "mod": return self.boolean("market.mods", False)
        if kind == "shader": return self.boolean("market.shaders", False)
        return self.boolean("market.other", False)
    def tabs(self):
        t = ["Resource packs"]
        if self.boolean("market.modrinth", False): t.append("Modrinth")
        if self.boolean("market.mods", False): t.append("Mods")
        if self.boolean("market.shaders", False): t.append("Shaders")
        if self.boolean("market.other", False): t.append("Everything")
        return t + ["Installed"]

d = tempfile.mkdtemp(); s = Settings(os.path.join(d, "launcher.txt"))
check("fresh install: only resource packs and Installed", s.tabs() == ["Resource packs", "Installed"])
check("fresh install: mods hidden", not s.visible("mod"))
check("fresh install: shaders hidden", not s.visible("shader"))
check("fresh install: native mods, modpacks, data packs hidden", not any(s.visible(k) for k in ["native-mod", "modpack", "datapack", "shaderpack", "weird"]))
check("fresh install: resource packs shown", s.visible("resourcepack"))
check("fresh install: Modrinth off", not s.boolean("market.modrinth", False))
check("fresh install: asks before installing", s.boolean("confirmInstalls", True))
check("fresh install: compact off, motion on", not s.boolean("compact", False) and not s.boolean("reduceMotion", False))
s.set("true", "market.mods")
check("turning on mods adds the Mods tab only", s.tabs() == ["Resource packs", "Mods", "Installed"] and s.visible("mod") and not s.visible("shader"))
s.set("true", "market.modrinth"); s.set("true", "market.shaders"); s.set("true", "market.other")
check("all on: every tab, in a fixed order", s.tabs() == ["Resource packs", "Modrinth", "Mods", "Shaders", "Everything", "Installed"])
check("all on: other kinds visible", s.visible("native-mod") and s.visible("modpack"))
s.set("false", "market.mods")
check("turning mods off hides them again", not s.visible("mod") and "Mods" not in s.tabs())
# the shared file
open(s.path, "w").write("openGame:true\nappearance:dark\n")
s.set("true", "market.modrinth")
check("writing a key keeps the lines other code owns (openGame:)", s.get("openGame") == "true" and s.get("appearance") == "dark" and s.get("market.modrinth") == "true")
s.set("false", "market.modrinth"); s.set("true", "market.modrinth")
check("setting a key twice leaves one line", s.text().count("market.modrinth:") == 1)
check("the file ends with a newline and has no blank lines", s.text().endswith("\n") and "\n\n" not in s.text())
open(s.path, "w").write("market.mods:maybe\ncompact: TRUE \n")
check("an unreadable value falls back to the default", not s.boolean("market.mods", False) and s.boolean("confirmInstalls", True))
check("value text is trimmed and case-insensitive", s.boolean("compact", False) is True)
open(s.path, "w").write("compact:  TRUE \n")
check("true with spaces and capitals is still true", s.boolean("compact", False))
check("a missing file reads as defaults", Settings(os.path.join(d, "nope.txt")).tabs() == ["Resource packs", "Installed"])
check("key prefix must match exactly (market.mod is not market.mods)", (lambda: (open(s.path, "w").write("market.modsX:true\n"), not s.boolean("market.mods", False))[1])())
print("\n%s" % ("all checks passed" if fails == 0 else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
