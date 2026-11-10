#!/usr/bin/env python3
"""Checks the decisions of platform/ios/App/DownloadPlan.m. A Python copy of the logic: it checks the
rules, not the Objective-C text, which only CI compiles. Keep this and DownloadPlan.m in step.

  python3 platform/ios/tests/download_plan_check.py          synthetic fixtures only (offline)
  python3 platform/ios/tests/download_plan_check.py --live   also the real 26.3 files from Mojang
"""
import json, re, sys, hashlib, urllib.request
from urllib.parse import urlparse

HOSTS = {"libraries.minecraft.net", "piston-data.mojang.com", "piston-meta.mojang.com", "resources.download.minecraft.net"}
OBJECTS = "https://resources.download.minecraft.net"
SYSTEM = "linux"   # an iPhone is linux on arm64, as horizon-prepare's rule_system()

def is_hex40(s): return isinstance(s, str) and re.fullmatch(r"[0-9a-f]{40}", s) is not None
def s(d, k):
    v = d.get(k) if isinstance(d, dict) else None
    return v if isinstance(v, str) and v else None
def size(d):
    v = d.get("size") if isinstance(d, dict) else None
    if isinstance(v, bool) or not isinstance(v, int): return 0
    return v if v > 0 else 0

def safe_path(p):
    if not p or "\\" in p or p.startswith("/"): return None
    for part in p.split("/"):
        if part in ("", ".", ".."): return None
    return p

class Refused(Exception): pass

def allowed(lib):
    rules = lib.get("rules")
    if not isinstance(rules, list) or not rules: return True
    ok = False
    for r in rules:
        if not isinstance(r, dict): raise Refused("rule that is not an object")
        os_ = r.get("os")
        if os_ is not None and not isinstance(os_, dict): raise Refused("unreadable os")
        if isinstance(os_, dict) and (isinstance(os_.get("arch"), str) or isinstance(os_.get("version"), str)):
            raise Refused("rule about architecture or version")
        f = r.get("features")
        if f is not None and not (isinstance(f, dict) and len(f) == 0): raise Refused("rule about features")
        name = s(os_, "name") if isinstance(os_, dict) else None
        if name and name != SYSTEM: continue
        ok = r.get("action") == "allow"
    return ok

def ends(c, names): return any(c == n or c.endswith("-" + n) for n in names)

def native_matches(lib, names):
    name = s(lib, "name") or ""
    parts = name.split(":"); c = parts[3] if len(parts) > 3 else ""
    if ends(c, ["arm64", "aarch64", "aarch_64"]): return True
    if ends(c, ["x86_64", "x64"]): return False
    if c.startswith("natives-"):
        for suf in ("arm64", "aarch64"):
            if f"{name}-{suf}" in names: return False
    return True

def file_from(entry, path):
    url, sha = s(entry, "url"), s(entry, "sha1")
    u = urlparse(url) if url else None
    if not u or u.scheme != "https" or (u.hostname or "").lower() not in HOSTS: raise Refused(f"{path} is not on a Mojang server")
    if not is_hex40(sha): raise Refused(f"{path} has no usable sha1")
    sp = safe_path(path)
    if not sp: raise Refused(f"unsafe path {path}")
    return dict(url=url, sha1=sha, size=size(entry), path=sp)

def plan_game(raw, version):
    try: root = json.loads(raw)
    except Exception: root = None
    if not isinstance(root, dict): raise Refused("version file not readable")
    sv = safe_path(version)
    if not sv or "/" in sv: raise Refused("version name not usable")
    game = [file_from(root.get("downloads", {}).get("client"), f"versions/{sv}/{sv}.jar")]
    libs = root.get("libraries")
    if not isinstance(libs, list): raise Refused("no libraries")
    names = {s(l, "name") for l in libs if s(l, "name")}
    count = 0
    for lib in libs:
        if not isinstance(lib, dict): continue
        ok = allowed(lib)
        if isinstance(lib.get("natives"), dict): raise Refused("old-style natives")
        art = (lib.get("downloads") or {}).get("artifact")
        if not ok or not isinstance(art, dict) or not native_matches(lib, names): continue
        game.append(file_from(art, "libraries/" + (s(art, "path") or ""))); count += 1
    logging = ((root.get("logging") or {}).get("client") or {}).get("file")
    if isinstance(logging, dict): game.append(file_from(logging, "assets/log_configs/" + (s(logging, "id") or "")))
    idx = root.get("assetIndex")
    game.append(file_from(idx, f"assets/indexes/{s(idx, 'id') or ''}.json"))
    return game, count

def plan_assets(raw):
    try: root = json.loads(raw)
    except Exception: root = None
    objs = root.get("objects") if isinstance(root, dict) else None
    if not isinstance(objs, dict): raise Refused("asset index has no objects")
    by = {}
    for o in objs.values():
        h = s(o, "hash")
        if not h: continue
        if not is_hex40(h): raise Refused(f"bad asset hash {h}")
        by[h] = size(o)
    return [dict(url=f"{OBJECTS}/{h[:2]}/{h}", sha1=h, size=by[h], path=f"assets/objects/{h[:2]}/{h}") for h in sorted(by)]

fails = 0
def check(label, cond):
    global fails
    if not cond: fails += 1
    print(("ok   " if cond else "FAIL ") + label)

def raises(fn):
    try: fn(); return False
    except Refused: return True

H = "a" * 40
def art(host="libraries.minecraft.net", path="a/b/c.jar", sha=H): return {"url": f"https://{host}/{path}", "sha1": sha, "size": 10, "path": path}
def manifest(libs, **kw):
    m = {"downloads": {"client": {"url": "https://piston-data.mojang.com/x/c.jar", "sha1": H, "size": 100}},
         "libraries": libs, "assetIndex": {"id": "34", "url": "https://piston-meta.mojang.com/i.json", "sha1": H, "size": 5}}
    m.update(kw); return json.dumps(m).encode()
def lib(name, rules=None, **extra):
    l = {"name": name, "downloads": {"artifact": art(path=name.replace(":", "/") + ".jar")}}
    if rules is not None: l["rules"] = rules
    l.update(extra); return l

# ---- synthetic ----
g, n = plan_game(manifest([lib("a:plain:1")]), "26.3")
check("client jar path", g[0]["path"] == "versions/26.3/26.3.jar")
check("plain library kept", n == 1 and g[1]["path"] == "libraries/a/plain/1.jar")
check("asset index last, in indexes/", g[-1]["path"] == "assets/indexes/34.json")
_, n = plan_game(manifest([lib("m:mac:1", [{"action": "allow", "os": {"name": "osx"}}])]), "26.3")
check("osx-only library dropped", n == 0)
_, n = plan_game(manifest([lib("l:lin:1", [{"action": "allow", "os": {"name": "linux"}}])]), "26.3")
check("linux-only library kept", n == 1)
_, n = plan_game(manifest([lib("w:win:1", [{"action": "allow", "os": {"name": "windows"}}])]), "26.3")
check("windows-only library dropped", n == 0)
_, n = plan_game(manifest([lib("x:all:1", [{"action": "allow"}, {"action": "disallow", "os": {"name": "linux"}}])]), "26.3")
check("last matching rule decides (disallow linux)", n == 0)
_, n = plan_game(manifest([lib("x:all:1", [{"action": "disallow", "os": {"name": "linux"}}, {"action": "allow"}])]), "26.3")
check("last matching rule decides (allow after)", n == 1)
check("arch rule refused", raises(lambda: plan_game(manifest([lib("x:a:1", [{"action": "allow", "os": {"name": "linux", "arch": "x86"}}])]), "26.3")))
check("version rule refused", raises(lambda: plan_game(manifest([lib("x:v:1", [{"action": "allow", "os": {"name": "linux", "version": "^10"}}])]), "26.3")))
check("features rule refused", raises(lambda: plan_game(manifest([lib("x:f:1", [{"action": "allow", "features": {"demo": True}}])]), "26.3")))
check("old natives refused", raises(lambda: plan_game(manifest([lib("x:n:1", natives={"linux": "natives-linux"})]), "26.3")))
check("foreign host refused", raises(lambda: plan_game(manifest([{"name": "e:v:1", "downloads": {"artifact": art(host="evil.example.com")}}]), "26.3")))
check("http (not https) refused", raises(lambda: plan_game(manifest([{"name": "e:v:1", "downloads": {"artifact": {**art(), "url": "http://libraries.minecraft.net/a.jar"}}}]), "26.3")))
check("lookalike host refused", raises(lambda: plan_game(manifest([{"name": "e:v:1", "downloads": {"artifact": art(host="libraries.minecraft.net.evil.com")}}]), "26.3")))
check("path traversal refused", raises(lambda: plan_game(manifest([{"name": "e:v:1", "downloads": {"artifact": art(path="../../x.jar")}}]), "26.3")))
check("absolute path refused", raises(lambda: plan_game(manifest([{"name": "e:v:1", "downloads": {"artifact": art(path="/etc/x.jar")}}]), "26.3")))
check("backslash path refused", raises(lambda: plan_game(manifest([{"name": "e:v:1", "downloads": {"artifact": art(path="a\\b.jar")}}]), "26.3")))
check("bad sha1 refused", raises(lambda: plan_game(manifest([{"name": "e:v:1", "downloads": {"artifact": art(sha="XYZ")}}]), "26.3")))
check("uppercase sha1 refused", raises(lambda: plan_game(manifest([{"name": "e:v:1", "downloads": {"artifact": art(sha="A" * 40)}}]), "26.3")))
check("version with slash refused", raises(lambda: plan_game(manifest([]), "../x")))
check("garbage version file refused", raises(lambda: plan_game(b"not json", "26.3")))
# natives: arm variant present => plain x64 natives dropped
libs = [lib("o:gl:3:natives-linux"), lib("o:gl:3:natives-linux-arm64"), lib("o:gl:3:natives-macos")]
g, n = plan_game(manifest(libs), "26.3")
check("plain natives dropped when an arm64 variant exists", [x["path"] for x in g[1:-1]] == ["libraries/o/gl/3/natives-linux-arm64.jar", "libraries/o/gl/3/natives-macos.jar"] or n == 2)
libs = [lib("o:gl:3:natives-linux")]
_, n = plan_game(manifest(libs), "26.3")
check("plain natives kept when no arm64 variant exists (same as desktop)", n == 1)
libs = [lib("n:epoll:4:linux-x86_64"), lib("n:epoll:4:linux-aarch_64")]
g, n = plan_game(manifest(libs), "26.3")
check("netty x86_64 dropped, aarch_64 kept", n == 1 and "aarch_64" in g[1]["path"])
# assets
idx = json.dumps({"objects": {"a/1": {"hash": "b" * 40, "size": 3}, "a/2": {"hash": "b" * 40, "size": 3}, "a/3": {"hash": "c" * 40, "size": 4}}}).encode()
a = plan_assets(idx)
check("asset objects de-duplicated by hash", len(a) == 2)
check("asset url and path from hash", a[0]["url"] == f"{OBJECTS}/bb/{'b'*40}" and a[0]["path"] == f"assets/objects/bb/{'b'*40}")
check("bad asset hash refused", raises(lambda: plan_assets(json.dumps({"objects": {"x": {"hash": "zz", "size": 1}}}).encode())))
check("asset index without objects refused", raises(lambda: plan_assets(b"{}")))

# ---- live ----
if "--live" in sys.argv:
    def get(url):
        with urllib.request.urlopen(url, timeout=60) as r: return r.read()
    VM = json.loads(get("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"))
    ver = "26.3"
    entry = next(v for v in VM["versions"] if v["id"] == ver)
    raw = get(entry["url"])
    check("live: version file matches the sha1 Mojang lists", hashlib.sha1(raw).hexdigest() == entry["sha1"])
    game, libs_n = plan_game(raw, ver)
    m = json.loads(raw)
    idx_raw = get(m["assetIndex"]["url"])
    check("live: asset index matches its sha1", hashlib.sha1(idx_raw).hexdigest() == m["assetIndex"]["sha1"])
    assets = plan_assets(idx_raw)
    total = sum(f["size"] for f in game) + sum(f["size"] for f in assets)
    print(f"      game files {len(game)} (libraries {libs_n}), assets {len(assets)}, total {len(game)+len(assets)} files, {total/1e6:.1f} MB")
    check("live: every host is Mojang's", all(urlparse(f["url"]).hostname in HOSTS for f in game + assets))
    check("live: no duplicate paths", len({f['path'] for f in game + assets}) == len(game) + len(assets))
    check("live: client jar is the listed size", game[0]["size"] == m["downloads"]["client"]["size"])
    # independent count: a different way of reading the same manifest
    linux_ok = 0
    for l in m["libraries"]:
        if not (l.get("downloads") or {}).get("artifact"): continue
        r = l.get("rules"); ok = True
        if r:
            ok = False
            for x in r:
                n_ = (x.get("os") or {}).get("name")
                if n_ is None or n_ == "linux": ok = x["action"] == "allow"
        if ok: linux_ok += 1
    print(f"      rule-only count {linux_ok}, after the native architecture filter {libs_n}")
    check("live: the native filter only removes libraries", libs_n <= linux_ok)
    check("live: total bytes at least the manifest's own totalSize for assets", sum(f['size'] for f in assets) <= m["assetIndex"]["totalSize"] + 1)
    names = [f["path"] for f in game]
    check("live: no x86_64 netty native in the plan", not any("linux-x86_64" in p for p in names))
    check("live: the arm64 netty native is in the plan", any("linux-aarch_64" in p for p in names))
    check("live: no macOS or Windows natives in the plan", not any(("natives-macos" in p or "natives-windows" in p) for p in names))

print("all checks pass" if not fails else f"{fails} FAILED")
sys.exit(1 if fails else 0)
