#!/usr/bin/env python3
"""Checks the rules of platform/ios/App/MarketInstaller.m and MarketFetcher.m (Marketplace install, M14 step 3).
A Python copy of the logic: it checks the rules, not the Objective-C text, which only CI compiles. Keep both in step.
The rules follow launcher/src/browser/horizon.rs (install_version_guarded) and crates/horizon-client/src/mod_registry.rs.

  python3 platform/ios/tests/market_install_check.py           offline
  python3 platform/ios/tests/market_install_check.py --live    also installs real files from the registry into a temp folder
"""
import hashlib, json, os, re, shutil, sys, tempfile, urllib.request, zipfile

FILE_HOST = "https://github.com/horizon-rust/horizon-mods/releases/download/"
MAX_FILE = 64 << 20
EXT = {"mod": "hmod", "resourcepack": "zip", "shader": "hshader"}
FOLDERS = ["horizon-mods", "resourcepacks", "shaderpacks", "mods"]
fails = 0
def check(name, ok, extra=""):
    global fails
    print(("ok   " if ok else "FAIL ") + name + ((" : " + str(extra)) if (extra and not ok) else ""))
    if not ok: fails += 1

def hex64(s): return isinstance(s, str) and re.fullmatch(r"[0-9a-f]{64}", s) is not None
def plain_name(s): return bool(s) and len(s) <= 128 and not s.startswith(".") and re.fullmatch(r"[A-Za-z0-9._+-]+", s) is not None
def registry_file_url(u):
    if not u.startswith(FILE_HOST) or re.search(r"\s", u): return False
    parts = u[len(FILE_HOST):].split("/")
    return len(parts) == 2 and all(p and p not in (".", "..") and re.fullmatch(r"[A-Za-z0-9._+%-]+", p) for p in parts)
def allowed_redirect(host, scheme):
    if scheme.lower() != "https": return False
    h = host.lower()
    return h == "github.com" or h == "githubusercontent.com" or h.endswith(".githubusercontent.com")
def inside(f):
    parts = f.split("/")
    if len(parts) < 2 or parts[0] not in FOLDERS: return False
    return all(p and p not in (".", "..") and "\\" not in p for p in parts)
def rel_path(kind, pid, name):
    return {"mod": f"horizon-mods/{pid}.hmod", "resourcepack": f"resourcepacks/{name}", "shader": f"shaderpacks/{name}"}.get(kind)
def support(kind): return "installable" if kind in EXT else "needs-desktop" if kind == "native-mod" else "not-yet"

def refusal(p, v, revoked=()):
    sup = support(p["kind"])
    if sup == "needs-desktop": return "native"
    if sup != "installable": return "kind"
    if p.get("key") or v["file"].get("signature"): return "signed"
    if any(r["project"] == p["id"] and (r.get("sha256") in (None, v["file"]["sha256"])) for r in revoked): return "revoked"
    f = v["file"]
    if not registry_file_url(f["url"]): return "host"
    if not plain_name(f["name"]): return "name"
    if not hex64(f["sha256"]): return "hash"
    if f["size"] == 0 or f["size"] > MAX_FILE: return "size"
    if not f["name"].endswith("." + EXT[p["kind"]]): return "ext"
    return None

def zip_magic(b): return len(b) >= 4 and b[:2] == b"PK" and (b[2:4] in (b"\x03\x04", b"\x05\x06"))

class Home:
    def __init__(self, path): self.h = path; os.makedirs(path, exist_ok=True)
    def raw(self):
        try: return [e for e in json.load(open(os.path.join(self.h, "mod-browser.json")))["entries"] if isinstance(e, dict)]
        except Exception: return []
    def save(self, es): json.dump({"entries": es}, open(os.path.join(self.h, "mod-browser.json"), "w"), indent=2, sort_keys=True)
    def mods_text(self):
        p = os.path.join(self.h, "horizon-mods.txt")
        return open(p).read() if os.path.exists(p) else ""
    def enabled(self, pid):
        for line in self.mods_text().split("\n"):
            if ":" in line:
                k, v = line.split(":", 1)
                if k.strip() == "mod." + pid and v.strip() == "true": return True
        return False
    def set_mod(self, pid, on):
        key = "mod." + pid; lines = []
        for line in self.mods_text().split("\n"):
            if not line: continue
            if ":" in line and line.split(":", 1)[0].strip() == key: continue
            lines.append(line)
        if on: lines.append(key + ":true")
        open(os.path.join(self.h, "horizon-mods.txt"), "w").write(("\n".join(lines) + "\n") if lines else "")
    def place(self, tmp, p, v, revoked=()):
        def fail(why):
            if os.path.exists(tmp): os.remove(tmp)
            return why
        r = refusal(p, v, revoked)
        if r: return fail(r)
        if os.path.getsize(tmp) != v["file"]["size"]: return fail("size-mismatch")
        data = open(tmp, "rb").read()
        if hashlib.sha256(data).hexdigest() != v["file"]["sha256"]: return fail("hash-mismatch")
        if not zip_magic(data): return fail("not-zip")
        rel = rel_path(p["kind"], p["id"], v["file"]["name"]); target = os.path.join(self.h, rel)
        es = self.raw(); ours = next((e for e in es if e.get("source") == "horizon" and e.get("project") == p["id"]), None)
        for e in es:
            if e is ours: continue
            if e.get("file") == rel: return fail("belongs-to-other")
        exists = os.path.lexists(target)
        if exists and not (ours and ours.get("file") == rel): return fail("not-ours")
        if p["kind"] == "mod" and os.path.isdir(os.path.join(self.h, "horizon-mods", p["id"])): return fail("folder-mod")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        os.replace(tmp, target)
        old = ours.get("file") if ours else None
        if old and old != rel and inside(old) and os.path.exists(os.path.join(self.h, old)): os.remove(os.path.join(self.h, old))
        entry = {"source": "horizon", "project": p["id"], "slug": p["id"], "title": p["name"], "kind": p["kind"], "version": v["version"],
                 "number": v["version"], "file": rel, "checksum": "SHA-256:" + v["file"]["sha256"], "dependency": False, "verdict": "Unsigned"}
        self.save([e for e in es if e is not ours] + [entry])
        if p["kind"] == "mod": self.set_mod(p["id"], True)
        return None
    def remove(self, pid):
        es = self.raw(); mine = next((e for e in es if e.get("source") == "horizon" and e.get("project") == pid), None)
        if not mine: return "not-installed"
        if not inside(mine.get("file", "")): return "outside"
        path = os.path.join(self.h, mine["file"])
        if os.path.lexists(path): os.remove(path)
        self.save([e for e in es if e is not mine])
        if mine.get("kind") == "mod": self.set_mod(pid, False)
        return None

def make_zip(path, extra=b""):
    with zipfile.ZipFile(path, "w") as z: z.writestr("a.txt", "hi" + extra.decode())
    return path
def project(kind="mod", pid="demo", name="demo.hmod", key=None, data=None, url=None):
    data = data if data is not None else b"x"
    p = {"id": pid, "kind": kind, "name": pid.title()}
    if key: p["key"] = key
    v = {"version": "1.0.0", "file": {"name": name, "url": url or (FILE_HOST + f"{pid}-1.0.0/" + name), "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}}
    return p, v

def tmpdir():
    d = tempfile.mkdtemp(); return d

# ---------- the rules
p, v = project()
check("an unsigned mod is accepted", refusal(p, v) is None)
check("a native mod is refused", refusal(project("native-mod", "n", "n.hnmod")[0], v) == "native")
check("a modpack is refused (no folder yet)", refusal({"id": "m", "kind": "modpack", "name": "M"}, v) == "kind")
check("a signed project is refused, never installed unchecked", refusal(project(key="RWQ...")[0], v) == "signed")
check("a signed version is refused", refusal(p, {**v, "file": {**v["file"], "signature": "sig"}}) == "signed")
check("a revoked hash is refused", refusal(p, v, [{"project": "demo", "sha256": v["file"]["sha256"]}]) == "revoked")
check("a whole-project revocation is refused", refusal(p, v, [{"project": "demo", "sha256": None}]) == "revoked")
check("another project's revocation does not matter", refusal(p, v, [{"project": "other", "sha256": None}]) is None)
check("a foreign host is refused", refusal(p, {**v, "file": {**v["file"], "url": "https://evil.example/x.hmod"}}) == "host")
check("the old ludovic111 host is refused (stricter than the desktop)", refusal(p, {**v, "file": {**v["file"], "url": "https://github.com/ludovic111/horizon-mods/releases/download/t/x.hmod"}}) == "host")
check("a path in the file name is refused", refusal(p, {**v, "file": {**v["file"], "name": "../x.hmod"}}) == "name")
check("a path in the address is refused", refusal(p, {**v, "file": {**v["file"], "url": FILE_HOST + "t/../x.hmod"}}) == "host")
check("a zero size is refused", refusal(p, {**v, "file": {**v["file"], "size": 0}}) == "size")
check("over 64 MiB is refused", refusal(p, {**v, "file": {**v["file"], "size": MAX_FILE + 1}}) == "size")
check("a wrong extension is refused", refusal(*project("mod", "demo", "demo.zip")) == "ext")
check("an upper-case hash is refused", refusal(p, {**v, "file": {**v["file"], "sha256": v["file"]["sha256"].upper()}}) == "hash")
check("paths: a mod goes to horizon-mods/<id>.hmod", rel_path("mod", "demo", "ignored") == "horizon-mods/demo.hmod")
check("paths: a resource pack keeps its name", rel_path("resourcepack", "p", "p-1.0.0.zip") == "resourcepacks/p-1.0.0.zip")
check("paths: a shader goes to shaderpacks", rel_path("shader", "s", "s.hshader") == "shaderpacks/s.hshader")
check("paths: a datapack has no folder", rel_path("datapack", "d", "d.zip") is None)
check("redirect: github release assets are allowed", allowed_redirect("release-assets.githubusercontent.com", "https"))
check("redirect: github.com itself is allowed", allowed_redirect("github.com", "https"))
check("redirect: plain http is refused", not allowed_redirect("github.com", "http"))
check("redirect: lookalike suffix is refused", not allowed_redirect("evilgithubusercontent.com", "https"))
check("redirect: lookalike prefix is refused", not allowed_redirect("github.com.evil.example", "https"))
check("redirect: another host is refused", not allowed_redirect("example.com", "https"))
check("record: a file in horizon-mods is inside", inside("horizon-mods/a.hmod"))
check("record: a file with .. is outside", not inside("horizon-mods/../options.txt"))
check("record: a file in the game root is outside", not inside("options.txt"))
check("record: an absolute path is outside", not inside("/etc/passwd"))
check("record: a folder only is outside", not inside("resourcepacks"))

# ---------- placing on disk
d = tmpdir(); h = Home(d)
zp = make_zip(os.path.join(d, "dl.part")); data = open(zp, "rb").read()
p, v = project("mod", "demo", "demo.hmod", data=data)
check("place: a good mod installs", h.place(zp, p, v) is None)
check("place: file is at horizon-mods/demo.hmod", os.path.isfile(os.path.join(d, "horizon-mods/demo.hmod")))
check("place: temp file is gone", not os.path.exists(zp))
check("place: record written", [e["project"] for e in h.raw()] == ["demo"])
check("place: mod is turned on", h.enabled("demo"))
check("place: horizon-mods.txt line is exact", h.mods_text() == "mod.demo:true\n")
# reinstall same project replaces, one record
zp2 = make_zip(os.path.join(d, "dl2.part"), b"v2"); data2 = open(zp2, "rb").read()
p2, v2 = project("mod", "demo", "demo.hmod", data=data2); v2["version"] = "2.0.0"
check("place: an update replaces our own file", h.place(zp2, p2, v2) is None)
check("place: still one record, new version", [(e["project"], e["version"]) for e in h.raw()] == [("demo", "2.0.0")])
# other lines of horizon-mods.txt kept
h.set_mod("other", True); h.set_mod("demo", True)
check("mods list keeps other mods", h.enabled("other") and h.enabled("demo"))
h.set_mod("demo", False)
check("mods list: turning off removes only that line", (not h.enabled("demo")) and h.enabled("other"))
# bad downloads
z3 = make_zip(os.path.join(d, "dl3.part")); p3, v3 = project("mod", "bad", "bad.hmod", data=b"different")
check("place: size mismatch refused", h.place(z3, p3, v3) == "size-mismatch" and not os.path.exists(z3))
z4 = make_zip(os.path.join(d, "dl4.part")); dd = open(z4, "rb").read(); p4, v4 = project("mod", "bad", "bad.hmod", data=dd)
v4["file"]["sha256"] = "0" * 64
check("place: hash mismatch refused and temp deleted", h.place(z4, p4, v4) == "hash-mismatch" and not os.path.exists(z4))
z5 = os.path.join(d, "dl5.part"); open(z5, "wb").write(b"NOTZIP-but-right-hash"); dd5 = open(z5, "rb").read(); p5, v5 = project("mod", "bad5", "bad5.hmod", data=dd5)
check("place: right hash but not a ZIP is refused", h.place(z5, p5, v5) == "not-zip")
check("place: nothing recorded for the refused ones", [e["project"] for e in h.raw()] == ["demo"])
# something the player put there
os.makedirs(os.path.join(d, "horizon-mods"), exist_ok=True); open(os.path.join(d, "horizon-mods/mine.hmod"), "w").write("mine")
z6 = make_zip(os.path.join(d, "dl6.part")); d6 = open(z6, "rb").read(); p6, v6 = project("mod", "mine", "mine.hmod", data=d6)
check("place: never over a file the player put there", h.place(z6, p6, v6) == "not-ours" and open(os.path.join(d, "horizon-mods/mine.hmod")).read() == "mine")
os.makedirs(os.path.join(d, "horizon-mods/folder_mod"))
z7 = make_zip(os.path.join(d, "dl7.part")); d7 = open(z7, "rb").read(); p7, v7 = project("mod", "folder_mod", "folder_mod.hmod", data=d7)
check("place: a folder mod with the same id blocks it", h.place(z7, p7, v7) == "folder-mod")
# resource pack
z8 = make_zip(os.path.join(d, "dl8.part")); d8 = open(z8, "rb").read(); p8, v8 = project("resourcepack", "pack", "pack-1.0.0.zip", data=d8)
check("place: a resource pack installs to resourcepacks", h.place(z8, p8, v8) is None and os.path.isfile(os.path.join(d, "resourcepacks/pack-1.0.0.zip")))
check("place: a resource pack is not added to horizon-mods.txt", "pack" not in h.mods_text())
# update of a pack whose file name changes removes the old file
z9 = make_zip(os.path.join(d, "dl9.part"), b"new"); d9 = open(z9, "rb").read(); p9, v9 = project("resourcepack", "pack", "pack-2.0.0.zip", data=d9); v9["version"] = "2.0.0"
check("place: pack update installs", h.place(z9, p9, v9) is None)
check("place: old pack file removed, new one present", (not os.path.exists(os.path.join(d, "resourcepacks/pack-1.0.0.zip"))) and os.path.isfile(os.path.join(d, "resourcepacks/pack-2.0.0.zip")))
# an entry the desktop wrote (another source) is untouched when ours is saved
es = h.raw(); es.append({"source": "modrinth", "project": "x", "file": "resourcepacks/theirs.zip", "title": "Theirs"}); h.save(es)
z10 = make_zip(os.path.join(d, "dl10.part"), b"z"); d10 = open(z10, "rb").read(); p10, v10 = project("shader", "sh", "sh.hshader", data=d10)
check("place: a shader installs", h.place(z10, p10, v10) is None and os.path.isfile(os.path.join(d, "shaderpacks/sh.hshader")))
check("place: another source's record survives", any(e.get("source") == "modrinth" for e in h.raw()))
z11 = make_zip(os.path.join(d, "dl11.part"), b"clash"); d11 = open(z11, "rb").read(); p11, v11 = project("resourcepack", "clash", "theirs.zip", data=d11)
check("place: a file another install owns is not replaced", h.place(z11, p11, v11) == "belongs-to-other")
# remove
check("remove: a mod", h.remove("demo") is None and not os.path.exists(os.path.join(d, "horizon-mods/demo.hmod")) and not h.enabled("demo"))
check("remove: its record is gone, others stay", "demo" not in [e["project"] for e in h.raw()] and "sh" in [e["project"] for e in h.raw()])
check("remove: a project that was not installed", h.remove("never") == "not-installed")
es = h.raw(); es.append({"source": "horizon", "project": "evil", "file": "horizon-mods/../options.txt", "kind": "mod", "title": "Evil"}); h.save(es)
open(os.path.join(d, "options.txt"), "w").write("keep")
check("remove: a record pointing outside the folders is refused", h.remove("evil") == "outside" and os.path.exists(os.path.join(d, "options.txt")))
# a symlink planted at the file's place is removed as a link
os.makedirs(os.path.join(d, "outside")); open(os.path.join(d, "outside/precious"), "w").write("keep")
os.symlink(os.path.join(d, "outside/precious"), os.path.join(d, "shaderpacks/link.hshader"))
es = h.raw(); es.append({"source": "horizon", "project": "lnk", "file": "shaderpacks/link.hshader", "kind": "shader", "title": "L"}); h.save(es)
check("remove: a planted symlink is removed as a link, target kept", h.remove("lnk") is None and open(os.path.join(d, "outside/precious")).read() == "keep")
shutil.rmtree(d)

# ---------- live
if "--live" in sys.argv:
    idx = json.load(urllib.request.urlopen("https://horizon-rust.github.io/horizon-mods/index.json", timeout=60))
    revoked = [{"project": r["id"], "sha256": r.get("sha256")} for r in idx.get("revoked", [])]
    ok = []; refused = {}
    for pr in idx["projects"]:
        ver = next((x for x in pr["versions"] if x.get("game") == "26.3"), None)
        if not ver: continue
        r = refusal(pr, ver, revoked)
        if r is None: ok.append((pr, ver))
        else: refused[r] = refused.get(r, 0) + 1
    print("live: installable by the phone's rules:", len(ok), " refused:", refused)
    check("live: 23 or 24 projects pass the install rules", 22 <= len(ok) <= 26, len(ok))
    check("live: the signed project is among the refused", refused.get("signed", 0) >= 1)
    d = tmpdir(); h = Home(d); installed = 0
    # one of each kind, downloaded for real
    want = {}
    for pr, ver in sorted(ok, key=lambda t: t[1]["file"]["size"]):
        want.setdefault(pr["kind"], (pr, ver))
    for kind, (pr, ver) in want.items():
        req = urllib.request.Request(ver["file"]["url"], headers={"User-Agent": "iMC-Horizon-iOS-check"})
        tmp = os.path.join(d, kind + ".part")
        with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f: f.write(r.read())
        res = h.place(tmp, pr, ver, revoked)
        check(f"live: real {kind} '{pr['id']}' ({ver['file']['size']} bytes) installs", res is None, res)
        if res is None: installed += 1
    check("live: one of each installable kind", installed == len(want) == 3, (installed, list(want)))
    # a corrupted real download is refused
    pr, ver = want["mod"]
    req = urllib.request.Request(ver["file"]["url"], headers={"User-Agent": "iMC-Horizon-iOS-check"})
    raw = bytearray(urllib.request.urlopen(req, timeout=120).read()); raw[len(raw)//2] ^= 1
    bad = os.path.join(d, "bad.part"); open(bad, "wb").write(raw)
    h.remove(pr["id"])
    check("live: a one-bit-flipped real download is refused", h.place(bad, pr, ver, revoked) == "hash-mismatch")
    check("live: and nothing was left installed", not os.path.exists(os.path.join(d, "horizon-mods", pr["id"] + ".hmod")))
    shutil.rmtree(d)

print("\n%s" % ("all checks passed" if fails == 0 else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
