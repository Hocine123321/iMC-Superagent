#!/usr/bin/env python3
"""Checks the rules of platform/ios/App/MarketIndex.m (the Horizon Marketplace index, M14 step 1). A Python
copy of the logic: it checks the rules, not the Objective-C text, which only CI compiles. Keep both in step.
The rules follow crates/horizon-mods/src/index.rs (schema 1) and are stricter in three places (file host,
image host, no install of a kind the phone cannot use).

  python3 platform/ios/tests/market_index_check.py           offline (small made-up indexes)
  python3 platform/ios/tests/market_index_check.py --live    also the real index at horizon-rust.github.io
"""
import copy, json, re, sys, urllib.request

FILE_HOST = "https://github.com/horizon-rust/horizon-mods/releases/download/"
IMAGE_HOST = "https://horizon-rust.github.io/horizon-mods/"
MAX_FILE = 64 << 20
MAX_INDEX = 16 << 20
SCHEMA = 1
EXT = {"mod": "hmod", "native-mod": "hnmod", "modpack": "hpack", "shader": "hshader",
       "resourcepack": "zip", "shaderpack": "zip", "datapack": "zip"}
fails = 0
def check(name, ok, extra=""):
    global fails
    print(("ok   " if ok else "FAIL ") + name + ((" : " + str(extra)) if (extra and not ok) else ""))
    if not ok: fails += 1

def valid_id(s): return re.fullmatch(r"[a-z0-9_]{1,64}", s or "") is not None
def plain_name(s): return bool(s) and len(s) <= 128 and not s.startswith(".") and re.fullmatch(r"[A-Za-z0-9._+-]+", s) is not None
def hex64(s): return isinstance(s, str) and re.fullmatch(r"[0-9a-f]{64}", s) is not None
def nows(s): return re.search(r"\s", s) is None
def registry_file_url(u):
    if not u.startswith(FILE_HOST) or not nows(u): return False
    parts = u[len(FILE_HOST):].split("/")
    return len(parts) == 2 and all(p and p not in (".", "..") and re.fullmatch(r"[A-Za-z0-9._+%-]+", p) for p in parts)
def registry_image_url(u):
    if not u.startswith(IMAGE_HOST) or not nows(u) or len(u) == len(IMAGE_HOST): return False
    rest = u[len(IMAGE_HOST):]
    if ".." in rest or "\\" in rest or "?" in rest or "#" in rest: return False
    return rest.rsplit(".", 1)[-1].lower() in ("png", "jpg", "jpeg") and "." in rest
def support(kind):
    return "installable" if kind in ("mod", "resourcepack", "shader") else "needs-desktop" if kind == "native-mod" else "not-yet"
def count(d, k):
    v = d.get(k) if isinstance(d, dict) else None
    if isinstance(v, bool) or not isinstance(v, (int, float)): return -1
    return int(v) if v >= 0 and v == int(v) else -1

class Bad(Exception): pass
def parse(data):
    if not data: raise Bad("nothing")
    if len(data) > MAX_INDEX: raise Bad("too big")
    try: root = json.loads(data)
    except Exception: raise Bad("not json")
    if not isinstance(root, dict): raise Bad("not an index")
    schema = count(root, "schema")
    if schema < 0: raise Bad("not an index")
    if schema > SCHEMA: raise Bad("newer")
    projects = root.get("projects")
    if not isinstance(projects, list): raise Bad("not an index")
    out, ids = [], set()
    for d in projects:
        pid = d.get("id") if isinstance(d, dict) else None
        if not isinstance(pid, str) or not valid_id(pid): raise Bad("id")
        kind, name, lic, src = (d.get(k) for k in ("kind", "name", "license", "source"))
        if not isinstance(kind, str) or not kind: raise Bad(pid + " kind")
        if not (isinstance(name, str) and name.strip() and isinstance(lic, str) and lic.strip()): raise Bad(pid + " name/licence")
        if not (isinstance(src, str) and src.startswith("https://") and len(src) > 8 and nows(src)): raise Bad(pid + " source")
        icon = d.get("icon")
        if isinstance(icon, str):
            if not (icon.startswith("https://") and nows(icon)): raise Bad(pid + " icon")
            icon = icon if registry_image_url(icon) else None
        shots = d.get("screenshots") if isinstance(d.get("screenshots"), list) else []
        if len(shots) > 8: raise Bad(pid + " screenshots")
        ok_shots = []
        for s in shots:
            if not (isinstance(s, str) and s.startswith("https://") and nows(s)): raise Bad(pid + " shot")
            if registry_image_url(s): ok_shots.append(s)
        key = d.get("key") if isinstance(d.get("key"), str) and d.get("key") else None
        versions = d.get("versions")
        if not isinstance(versions, list) or not versions: raise Bad(pid + " no version")
        sup = support(kind); ext = EXT.get(kind); seen = set(); vout = []
        for vd in versions:
            vs = vd.get("version") if isinstance(vd, dict) else None
            if not isinstance(vs, str) or not vs.strip() or vs in seen: raise Bad(pid + " version")
            seen.add(vs)
            f = vd.get("file") if isinstance(vd.get("file"), dict) else {}
            fname, furl, fsha, fsig, fsize = f.get("name"), f.get("url"), f.get("sha256"), f.get("signature"), count(f, "size")
            if not isinstance(fname, str) or not plain_name(fname) or (ext and not fname.endswith("." + ext)): raise Bad(pid + " file name")
            if not (isinstance(furl, str) and furl.startswith("https://") and nows(furl)): raise Bad(pid + " file url")
            if sup == "installable" and not registry_file_url(furl): raise Bad(pid + " file host")
            if not hex64(fsha): raise Bad(pid + " sha")
            if fsize <= 0 or fsize > MAX_FILE: raise Bad(pid + " size")
            if key and not fsig: raise Bad(pid + " unsigned but keyed")
            if not key and fsig: raise Bad(pid + " signed but no key")
            vout.append({"version": vs, "game": vd.get("game", ""), "sha": fsha, "file": f})
        if pid in ids: raise Bad(pid + " twice")
        ids.add(pid)
        out.append({"id": pid, "kind": kind, "support": sup, "versions": vout, "icon": icon, "shots": ok_shots, "key": key})
    rev = []
    for r in (root.get("revoked") if isinstance(root.get("revoked"), list) else []):
        rid = r.get("id") if isinstance(r, dict) else None
        if not isinstance(rid, str) or not rid: continue
        sha = r.get("sha256") if isinstance(r.get("sha256"), str) else None
        if sha is not None and not hex64(sha): raise Bad("revoked sha")
        rev.append({"id": rid, "sha": sha, "reason": r.get("reason", "")})
    return {"projects": out, "revoked": rev}

def revocation(ix, pid, sha):
    for r in ix["revoked"]:
        if r["id"] != pid: continue
        if r["sha"] is None: return r
        if sha and r["sha"].lower() == sha.lower(): return r
    return None
def installable_version(ix, p, game):
    for v in p["versions"]:
        if v["game"] == game and not revocation(ix, p["id"], v["sha"]): return v
    return None

H = "a" * 64
def proj(**kw):
    p = {"id": "coords_hud", "kind": "mod", "name": "Coords", "summary": "s", "license": "MIT",
         "source": "https://github.com/x/y", "versions": [{"version": "0.1.0", "game": "26.3", "api": "0.1",
         "file": {"name": "coords_hud-0.1.0.hmod", "url": FILE_HOST + "coords_hud-0.1.0/coords_hud-0.1.0.hmod", "size": 438, "sha256": H}}]}
    p.update(kw); return p
def idx(*projects, **kw):
    d = {"schema": 1, "generated": "2026-11-10T00:00:00Z", "projects": list(projects), "revoked": []}; d.update(kw)
    return json.dumps(d).encode()
def refused(data):
    try: parse(data); return False
    except Bad: return True

def offline():
    ix = parse(idx(proj()))
    check("a plain valid index parses", len(ix["projects"]) == 1 and ix["projects"][0]["support"] == "installable")
    check("schema 2 is refused (update the app)", refused(idx(proj(), schema=2)))
    check("schema 0 and 1 are read", not refused(idx(proj(), schema=0)) and not refused(idx(proj(), schema=1)))
    check("a schema that is a string / bool / fraction is refused", all(refused(idx(proj(), schema=s)) for s in ("1", True, 1.5, -1)))
    check("empty data is refused", refused(b""))
    check("not JSON is refused", refused(b"<html>no</html>"))
    check("JSON that is a list is refused", refused(b"[]"))
    check("no projects key is refused", refused(b'{"schema":1}'))
    check("an index over 16 MiB is refused", refused(b'{"schema":1,"projects":[],"pad":"' + b"x" * (MAX_INDEX + 1) + b'"}'))
    check("unknown fields are ignored", not refused(idx(proj(extra_thing=[1, 2], future=True))))
    check("unknown kind is kept and marked not-yet", parse(idx(proj(kind="world")))["projects"][0]["support"] == "not-yet" if not refused(idx(proj(kind="world"))) else False)

    for bad in ("Coords", "a-b", "", "x" * 65, "a b", "ünï"):
        check("project id refused: %r" % bad[:12], refused(idx(proj(id=bad))))
    check("duplicate project id refused", refused(idx(proj(), proj())))
    check("empty name refused", refused(idx(proj(name="  "))))
    check("empty licence refused", refused(idx(proj(license=""))))
    check("source must be https", refused(idx(proj(source="http://github.com/x/y"))) and refused(idx(proj(source="https://"))))
    check("no versions refused", refused(idx(proj(versions=[]))))
    v = proj()["versions"][0]
    check("repeated version refused", refused(idx(proj(versions=[v, v]))))

    def with_file(**kw):
        p = proj(); p["versions"][0]["file"].update(kw); return idx(p)
    for bad in ("../x.hmod", "a/b.hmod", ".hidden.hmod", "x y.hmod", "x\\y.hmod", "", "a" * 129 + ".hmod"):
        check("file name refused: %r" % bad[:14], refused(with_file(name=bad)))
    check("wrong extension for the kind refused", refused(with_file(name="coords.zip")))
    check("file url must be https", refused(with_file(url="http://github.com/horizon-rust/horizon-mods/releases/download/a/b.hmod")))
    check("an installable kind off the registry host is refused", refused(with_file(url="https://evil.example/coords_hud-0.1.0.hmod")))
    check("look-alike host refused", refused(with_file(url="https://github.com/horizon-rust/horizon-mods-evil/releases/download/a/b.hmod")))
    check("old ludovic111 host is refused (phone is stricter)", refused(with_file(url="https://github.com/ludovic111/horizon-mods/releases/download/a/b.hmod")))
    check("url with extra path parts refused", refused(with_file(url=FILE_HOST + "a/b/c.hmod")))
    check("url with .. refused", refused(with_file(url=FILE_HOST + "../b.hmod")))
    check("url with a space refused", refused(with_file(url=FILE_HOST + "a/b c.hmod")))
    check("url with a query string refused", refused(with_file(url=FILE_HOST + "a/b.hmod?x=1")))
    for bad in ("A" * 64, "a" * 63, "a" * 65, "g" * 64, ""):
        check("sha256 refused: %r" % bad[:10], refused(with_file(sha256=bad)))
    for bad in (0, -5, MAX_FILE + 1, "438", True, 1.5):
        check("size refused: %r" % (bad,), refused(with_file(size=bad)))
    check("size at the cap is accepted", not refused(with_file(size=MAX_FILE)))
    check("a key without a signature is refused", refused(idx(proj(key="RWQ"))))
    check("a signature without a key is refused", refused(with_file(signature="untrusted comment: x")))
    p = proj(key="RWQ"); p["versions"][0]["file"]["signature"] = "sig"
    check("a key with a signature is accepted", not refused(idx(p)) and parse(idx(p))["projects"][0]["key"] == "RWQ")

    # native mods are listed but never installable; their host is not checked (not installed)
    nm = proj(id="big_native", kind="native-mod"); nm["versions"][0]["file"].update(name="big.hnmod", url="https://example.org/big.hnmod")
    check("a native mod is listed as needs-desktop", parse(idx(nm))["projects"][0]["support"] == "needs-desktop")
    check("a native mod still needs a .hnmod name", refused(idx(dict(nm, versions=[dict(nm["versions"][0], file=dict(nm["versions"][0]["file"], name="big.hmod"))]))))
    check("modpack, shaderpack, datapack are not-yet", all(support(k) == "not-yet" for k in ("modpack", "shaderpack", "datapack", "world")))
    check("mod, resourcepack, shader are installable", all(support(k) == "installable" for k in ("mod", "resourcepack", "shader")))

    # images: a foreign icon drops the image, not the project; a non-https one fails
    check("a foreign https icon is dropped, project kept", parse(idx(proj(icon="https://cdn.evil.example/i.png")))["projects"][0]["icon"] is None)
    check("a registry icon is kept", parse(idx(proj(icon=IMAGE_HOST + "icons/coords_hud.png")))["projects"][0]["icon"] == IMAGE_HOST + "icons/coords_hud.png")
    check("a non-https icon fails the index", refused(idx(proj(icon="http://x/i.png"))))
    check("icon with .. or a query is dropped", parse(idx(proj(icon=IMAGE_HOST + "../i.png")))["projects"][0]["icon"] is None and parse(idx(proj(icon=IMAGE_HOST + "i.png?x=1")))["projects"][0]["icon"] is None)
    check("an icon that is not png/jpg is dropped", parse(idx(proj(icon=IMAGE_HOST + "icons/x.svg")))["projects"][0]["icon"] is None)
    shots = [IMAGE_HOST + "screenshots/a/%d.png" % i for i in range(8)]
    check("8 screenshots fine, 9 refused", not refused(idx(proj(screenshots=shots))) and refused(idx(proj(screenshots=shots + [shots[0]]))))
    check("foreign screenshots dropped, registry ones kept", parse(idx(proj(screenshots=[shots[0], "https://evil.example/s.png"])))["projects"][0]["shots"] == [shots[0]])

    # revocation
    other = "b" * 64
    rv = [{"id": "coords_hud", "sha256": H, "reason": "bad", "date": "2026-11-01"}]
    ix = parse(idx(proj(), revoked=rv))
    check("a revoked hash is found", revocation(ix, "coords_hud", H) is not None)
    check("another hash of the same project is not revoked", revocation(ix, "coords_hud", other) is None)
    check("revoked hash matches case-insensitively", revocation(ix, "coords_hud", H.upper()) is not None)
    check("a revoked version is not installable", installable_version(ix, ix["projects"][0], "26.3") is None)
    ix = parse(idx(proj(), revoked=[{"id": "coords_hud", "reason": "gone"}]))
    check("a revocation without a hash revokes every version", revocation(ix, "coords_hud", other) is not None and installable_version(ix, ix["projects"][0], "26.3") is None)
    check("a revocation of another project does not touch this one", installable_version(parse(idx(proj(), revoked=[{"id": "zzz", "reason": "x"}])), parse(idx(proj()))["projects"][0], "26.3") is not None)
    check("a revoked entry with a bad hash fails the index", refused(idx(proj(), revoked=[{"id": "a", "sha256": "xyz", "reason": ""}])))
    # newest non-revoked version wins, and the game must match
    p = proj(); v2 = copy.deepcopy(p["versions"][0]); v2["version"] = "0.2.0"; v2["file"]["sha256"] = other
    p["versions"] = [v2, p["versions"][0]]
    ix = parse(idx(p, revoked=[{"id": "coords_hud", "sha256": other, "reason": "bad"}]))
    check("newest version revoked: falls back to the older one", installable_version(ix, ix["projects"][0], "26.3")["version"] == "0.1.0")
    check("no version for another game", installable_version(ix, ix["projects"][0], "27.1") is None)
    ix = parse(idx(p))
    check("newest version first is chosen", installable_version(ix, ix["projects"][0], "26.3")["version"] == "0.2.0")

def live():
    raw = urllib.request.urlopen("https://horizon-rust.github.io/horizon-mods/index.json", timeout=40).read()
    ix = parse(raw)
    n = len(ix["projects"])
    check("live: the real index parses (%d projects, %.0f KB)" % (n, len(raw) / 1000), n > 100)
    by = {}
    for p in ix["projects"]: by[p["support"]] = by.get(p["support"], 0) + 1
    check("live: native mods are listed as needs-desktop and installable kinds as installable", by.get("needs-desktop", 0) > 0 and by.get("installable", 0) > 0, by)
    print("     support: %s; revoked entries: %d" % (by, len(ix["revoked"])))
    inst = [p for p in ix["projects"] if p["support"] == "installable"]
    check("live: every installable file is on the registry host with a plain name", all(registry_file_url(v["file"]["url"]) and plain_name(v["file"]["name"]) for p in inst for v in p["versions"]))
    ok_v = [p for p in inst if installable_version(ix, p, "26.3")]
    print("     installable on 26.3 after revocations: %d of %d" % (len(ok_v), len(inst)))
    check("live: at least one installable project has a usable 26.3 version", len(ok_v) > 0)
    rawd = json.loads(raw)
    named = [p for p in rawd["projects"] if p.get("icon")]
    kept = {p["id"] for p in ix["projects"] if p["icon"]}
    check("live: every icon the index names is on the registry site and kept (%d icons)" % len(named), all(p["id"] in kept for p in named))
    rejected_imgs = sum(1 for p in rawd["projects"] for s in p.get("screenshots", []) if not registry_image_url(s))
    check("live: no screenshot is refused by the image-host rule", rejected_imgs == 0, rejected_imgs)
    # tamper: flipping one hash digit to upper case must be refused
    t = json.loads(raw); t["projects"][0]["versions"][0]["file"]["sha256"] = t["projects"][0]["versions"][0]["file"]["sha256"].upper()
    check("live: an upper-cased hash in the real data is refused", refused(json.dumps(t).encode()))
    t = json.loads(raw); inst0 = next(p for p in t["projects"] if p["kind"] in ("mod", "shader", "resourcepack"))
    inst0["versions"][0]["file"]["url"] = inst0["versions"][0]["file"]["url"].replace("horizon-rust", "evil-org")
    check("live: pointing an installable file at another organisation is refused", refused(json.dumps(t).encode()))

# --- MarketClient.m: which copy is trusted --------------------------------------------------------
FRESH = 600
def decide(cached_age, force, net):
    """cached_age: seconds since the cache was written, or None for no (valid) cache.
    net: ('ok', valid_index_bool) | ('error',). Returns (source, replaced_cache)."""
    if cached_age is not None and not force and 0 <= cached_age < FRESH: return ("cached", False)
    if net[0] == "ok" and net[1]: return ("fresh", True)
    if cached_age is not None: return ("offline", False)
    return ("error", False)

def client():
    check("cache younger than 10 minutes is used without the network", decide(30, False, ("ok", True)) == ("cached", False))
    check("cache exactly 10 minutes old is refreshed", decide(600, False, ("ok", True)) == ("fresh", True))
    check("force refresh skips a young cache", decide(30, True, ("ok", True)) == ("fresh", True))
    check("a cache dated in the future is not trusted as fresh", decide(-5, False, ("ok", True)) == ("fresh", True))
    check("no cache and a good answer: fresh, cache written", decide(None, False, ("ok", True)) == ("fresh", True))
    check("no network with a cache: the old copy, flagged offline, cache untouched", decide(9999, False, ("error",)) == ("offline", False))
    check("a hostile or broken answer never replaces a good cache", decide(9999, False, ("ok", False)) == ("offline", False))
    check("no network and no cache is an error", decide(None, False, ("error",)) == ("error", False))
    check("a broken answer and no cache is an error, nothing written", decide(None, False, ("ok", False)) == ("error", False))

offline()
client()
if "--live" in sys.argv: live()
print("\n%s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
