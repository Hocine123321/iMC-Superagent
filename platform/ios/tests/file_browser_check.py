#!/usr/bin/env python3
"""Checks the rules of platform/ios/App/FileBrowser.m (the file manager, M13). A Python copy of the
logic: it checks the rules, not the Objective-C text, which only CI compiles. Keep both in step.

  python3 platform/ios/tests/file_browser_check.py
"""
import os, shutil, sys, tempfile

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("ok   " if ok else "FAIL ") + name + ((" : " + str(extra)) if (extra and not ok) else ""))
    if not ok: fails += 1

def syntax_ok(p):
    if p == "": return True
    if p.startswith("/") or "\\" in p or "\0" in p: return False
    return all(part not in ("", ".", "..") for part in p.split("/"))

class Browser:
    def __init__(self, root): self.root = os.path.realpath(root)
    def resolve(self, rel):
        if not syntax_ok(rel): return None
        if rel == "": return self.root
        full = os.path.join(self.root, rel)
        d = os.path.realpath(os.path.dirname(full))          # the holder is resolved, the last name is not
        resolved = os.path.join(d, os.path.basename(full))
        return resolved if resolved.startswith(self.root + "/") else None
    def list(self, rel):
        p = self.resolve(rel)
        if not p: return None, "outside"
        if os.path.islink(p) or not os.path.isdir(p): return None, "not a folder"
        out = []
        for n in os.listdir(p):
            c = os.path.join(p, n)
            out.append((n, os.path.isdir(c) and not os.path.islink(c)))
        out.sort(key=lambda t: (not t[1], t[0].lower()))
        return out, None
    def size(self, rel):
        p = self.resolve(rel)
        if not p or not os.path.lexists(p): return 0
        if os.path.islink(p) or os.path.isfile(p): return os.lstat(p).st_size if os.path.isfile(p) else 0
        t = 0
        for d, _, files in os.walk(p, followlinks=False):
            for f in files:
                q = os.path.join(d, f)
                if os.path.isfile(q) and not os.path.islink(q): t += os.path.getsize(q)
        return t
    def risk(self, p):
        if p == "": return "forbidden"
        l = p.lower()
        if l == "account.txt": return "account"
        if l == "home/saves" or l.startswith("home/saves/"): return "world"
        if l in ("resources", "minecraft") or l.startswith("resources/") or l.startswith("minecraft/"): return "game"
        if l == "home": return "world"
        return "ordinary"
    def delete(self, rel):
        if self.risk(rel) == "forbidden": return "forbidden"
        p = self.resolve(rel)
        if not p: return "outside"
        if os.path.islink(p) or os.path.isfile(p): os.remove(p)
        else: shutil.rmtree(p)
        return None
    def rename(self, rel, new):
        bad = problem(new)
        if bad: return bad
        if rel == "": return "root"
        a = self.resolve(rel); parent = rel.rsplit("/", 1)[0] if "/" in rel else ""
        b = self.resolve((parent + "/" if parent else "") + new)
        if not a or not b: return "outside"
        if os.path.lexists(b): return "exists"
        os.rename(a, b); return None
    def mkdir(self, name, inside):
        bad = problem(name)
        if bad: return bad
        parent = self.resolve(inside); p = self.resolve((inside + "/" if inside else "") + name)
        if not parent or not p: return "outside"
        if os.path.lexists(p): return "exists"
        try: os.mkdir(p)            # withIntermediateDirectories:NO, so a missing parent is an error
        except OSError: return "error"
        return None

def problem(name):
    if not name: return "empty"
    if name in (".", ".."): return "dots"
    if "/" in name or "\\" in name: return "slash"
    if any(ord(c) < 0x20 or ord(c) == 0x7f for c in name): return "control"
    if len(name.encode()) > 255: return "long"
    return None

with tempfile.TemporaryDirectory() as t:
    root = os.path.join(t, "Horizon"); os.makedirs(root)
    outside = os.path.join(t, "Secret"); os.makedirs(outside); open(os.path.join(outside, "key.txt"), "w").write("secret")
    b = Browser(root)
    for d in ("home/saves/World1", "resources", "minecraft/libraries", "packs"):
        os.makedirs(os.path.join(root, d))
    open(os.path.join(root, "home/saves/World1/level.dat"), "wb").write(b"x" * 1000)
    open(os.path.join(root, "resources/horizon-resources.json"), "w").write("{}")
    open(os.path.join(root, "account.txt"), "w").write("name:x")
    open(os.path.join(root, "notes.txt"), "w").write("hi")

    # syntax and escape
    for bad in ("..", "../Secret", "a/../../Secret", "/etc", "a//b", "a\\b", ".", "a/."):
        check("refused: %r" % bad, b.resolve(bad) is None)
    check("root resolves", b.resolve("") == b.root)
    check("inside path resolves", b.resolve("home/saves") == os.path.join(b.root, "home/saves"))

    # a link planted in the root that points out
    os.symlink(outside, os.path.join(root, "evil"))
    check("link to outside: cannot be listed as a folder", b.list("evil")[0] is None)
    check("path through the link is refused", b.resolve("evil/key.txt") is None)
    check("listing the root shows the link as a file, not a folder", ("evil", False) in b.list("")[0])
    check("size of a link target is not counted", b.size("evil") == 0)
    check("delete of the link removes only the link", b.delete("evil") is None and os.path.exists(os.path.join(outside, "key.txt")) and not os.path.lexists(os.path.join(root, "evil")))
    os.symlink(os.path.join(outside, "key.txt"), os.path.join(root, "packs", "k"))
    open(os.path.join(root, "packs", "plain.txt"), "w").write("p")
    check("rename onto a name taken by a link is refused", b.rename("packs/plain.txt", "k") == "exists" and os.path.exists(os.path.join(root, "packs", "plain.txt")))
    os.symlink(outside, os.path.join(root, "packs", "out"))
    check("a folder reached through a nested link is refused", b.resolve("packs/out/key.txt") is None)
    os.remove(os.path.join(root, "packs", "out")); os.remove(os.path.join(root, "packs", "k"))

    # listing order
    open(os.path.join(root, "Zed.txt"), "w"); open(os.path.join(root, "apple.txt"), "w")
    names = [n for n, _ in b.list("")[0]]
    folders = [n for n, f in b.list("")[0] if f]
    check("folders come first", names[:len(folders)] == folders and set(folders) == {"home", "resources", "minecraft", "packs"})
    files = [n for n, f in b.list("")[0] if not f]
    check("files sorted case-insensitively", files == sorted(files, key=str.lower), files)
    check("listing a file is refused", b.list("notes.txt")[0] is None)
    check("listing a missing folder is refused", b.list("nope")[0] is None)

    # size
    check("size of a folder sums its files", b.size("home/saves") == 1000)
    check("size of a file", b.size("notes.txt") == 2)

    # risk
    check("risk: root forbidden", b.risk("") == "forbidden")
    check("risk: a world", b.risk("home/saves/World1") == "world")
    check("risk: saves folder", b.risk("home/saves") == "world")
    check("risk: home folder (it holds the saves)", b.risk("home") == "world")
    check("risk: SAVES in upper case", b.risk("Home/Saves/x") == "world")
    check("risk: resources", b.risk("resources/horizon-resources.json") == "game" and b.risk("resources") == "game")
    check("risk: downloaded minecraft", b.risk("minecraft/libraries") == "game")
    check("risk: account.txt", b.risk("account.txt") == "account")
    check("risk: ordinary", b.risk("notes.txt") == "ordinary" and b.risk("home/screenshots") == "ordinary")
    check("risk: a name that only starts like 'resources' is ordinary", b.risk("resources2") == "ordinary" and b.risk("homework") == "ordinary")

    # names
    for bad in ("", ".", "..", "a/b", "a\\b", "a\nb", "x" * 256, "a\x7fb"):
        check("name refused: %r" % bad[:12], problem(bad) is not None)
    for good in ("World 2", "résumé.txt", ".hidden", "a.b.c", "日本語", "x" * 255):
        check("name accepted: %r" % good[:12], problem(good) is None)

    # changes
    check("delete: root forbidden", b.delete("") == "forbidden" and os.path.isdir(root))
    check("delete: escape refused", b.delete("../Secret") == "outside" and os.path.exists(outside))
    check("delete a file", b.delete("Zed.txt") is None and not os.path.exists(os.path.join(root, "Zed.txt")))
    check("delete a folder tree", b.delete("home/saves/World1") is None and not os.path.exists(os.path.join(root, "home/saves/World1")))
    check("rename a file", b.rename("apple.txt", "pear.txt") is None and os.path.exists(os.path.join(root, "pear.txt")))
    check("rename onto an existing name refused", b.rename("pear.txt", "notes.txt") == "exists" and os.path.exists(os.path.join(root, "pear.txt")))
    check("rename with a slash refused (cannot move out)", b.rename("pear.txt", "../x") == "slash" and os.path.exists(os.path.join(root, "pear.txt")))
    check("rename the root refused", b.rename("", "x") == "root")
    check("rename inside a subfolder", b.rename("packs", "packs2") is None and os.path.isdir(os.path.join(root, "packs2")))
    check("mkdir", b.mkdir("New", "packs2") is None and os.path.isdir(os.path.join(root, "packs2/New")))
    check("mkdir on an existing name refused", b.mkdir("New", "packs2") == "exists")
    check("mkdir with a bad name refused", b.mkdir("a/b", "") == "slash" and b.mkdir("..", "") == "dots")
    check("mkdir inside a missing folder is an error, nothing created", b.mkdir("x", "nope/deeper") == "error" and not os.path.exists(os.path.join(root, "nope")))
    check("mkdir outside refused", b.mkdir("x", "../Secret") == "outside" and not os.path.exists(os.path.join(outside, "x")))

print("\n%s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
