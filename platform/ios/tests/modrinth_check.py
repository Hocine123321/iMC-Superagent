#!/usr/bin/env python3
"""Checks the rules of platform/ios/App/ModrinthClient.m and the Modrinth half of MarketInstaller.m (resource packs
from Modrinth, 2026-11-10). A Python copy of the logic: it checks the rules, not the Objective-C text, which only
CI compiles. Keep both in step. Rules follow launcher/src/browser/{modrinth,download}.rs and browser.rs (safe_name).

  python3 platform/ios/tests/modrinth_check.py           offline
  python3 platform/ios/tests/modrinth_check.py --live    also real packs from api.modrinth.com / cdn.modrinth.com
"""
import hashlib, io, json, os, re, struct, sys, tempfile, urllib.parse, urllib.request, zipfile

CDN = "https://cdn.modrinth.com/"
API = "https://api.modrinth.com/v2"
MAX_FILE = 64 << 20
fails = 0
def check(name, ok, extra=""):
    global fails
    print(("ok   " if ok else "FAIL ") + name + ((" : " + str(extra)) if (extra and not ok) else ""))
    if not ok: fails += 1

def is_hex(s, n): return isinstance(s, str) and len(s) == n and re.fullmatch(r"[0-9a-f]+", s) is not None
def is_pid(s): return isinstance(s, str) and re.fullmatch(r"[A-Za-z0-9]{8}", s) is not None
def safe_name(n):
    if not n or len(n.encode()) > 200: return False
    if n.startswith(".") or n.endswith(".") or n.endswith(" "): return False
    if any(c in n for c in '/\\:*?"<>|'): return False
    return not any(ord(c) < 32 or 127 <= ord(c) < 160 for c in n)
def cdn_url(u):
    if not u.startswith(CDN) or re.search(r"\s", u) or "?" in u or "#" in u or ".." in u: return False
    parts = u[len(CDN):].split("/")
    if len(parts) != 5 or parts[0] != "data" or parts[2] != "versions" or any(not p for p in parts): return False
    return is_pid(parts[1]) and len(parts[3]) >= 6
def encode(s): return urllib.parse.quote(s, safe="-_.~")
def search_url(text, game, offset, limit):
    facets = '[["project_type:resourcepack"],["versions:%s"]]' % game
    u = "%s/search?facets=%s&index=%s&offset=%d&limit=%d" % (API, encode(facets), "relevance" if text else "downloads", offset, max(1, min(limit, 50)))
    return u + ("&query=" + encode(text) if text else "")
def refusal(f):
    if not cdn_url(f["url"]): return "host"
    if not safe_name(f["name"]): return "name"
    if not f["name"].lower().endswith(".zip"): return "ext"
    if not is_hex(f.get("sha512"), 128) and not is_hex(f.get("sha1"), 40): return "checksum"
    if f["size"] == 0 or f["size"] > MAX_FILE: return "size"
    return None
def parse_search(obj):
    out = []
    for h in obj.get("hits", []):
        if not isinstance(h, dict) or h.get("project_type") != "resourcepack": continue
        if not is_pid(h.get("project_id")): continue
        out.append(h)
    return out
def pick_version(vers, game):
    vers = sorted([v for v in vers if isinstance(v, dict)], key=lambda v: v.get("date_published", ""), reverse=True)
    problem = None; any_for = False
    for v in vers:
        if v.get("status", "listed") != "listed": continue
        if game not in v.get("game_versions", []): continue
        any_for = True
        files = [f for f in v.get("files", []) if isinstance(f, dict)]
        if not files: continue
        f = next((x for x in files if x.get("primary") is True), files[0])
        ref = {"name": f.get("filename", ""), "url": f.get("url", ""), "size": f.get("size", 0),
               "sha512": (f.get("hashes", {}).get("sha512") or "").lower() or None, "sha1": (f.get("hashes", {}).get("sha1") or "").lower() or None}
        r = refusal(ref)
        if r: problem = problem or r; continue
        return v, ref
    return None, ("no-version" if not any_for else problem or "no-file")

# --- the ZIP central-directory reader, a byte-for-byte copy of zipEntryNamesAtPath
def zip_names(data):
    n = len(data)
    if n < 22 or n > MAX_FILE: return None
    start = n - 22 - 65535 if n > 22 + 65535 else 0
    eocd = None
    for i in range(n - 22, start - 1, -1):
        if struct.unpack_from("<I", data, i)[0] == 0x06054b50: eocd = i; break
    if eocd is None: return None
    count = struct.unpack_from("<H", data, eocd + 10)[0]; size, off = struct.unpack_from("<II", data, eocd + 12)
    if off + size > n or count == 0xFFFF: return None
    names = []; p = off; end = off + size
    for _ in range(count):
        if p + 46 > end or struct.unpack_from("<I", data, p)[0] != 0x02014b50: return None
        flags = struct.unpack_from("<H", data, p + 8)[0]
        nl, el, cl = struct.unpack_from("<HHH", data, p + 28)
        if p + 46 + nl > end: return None
        raw = data[p + 46:p + 46 + nl]
        try: name = raw.decode("utf-8")
        except UnicodeDecodeError:
            if flags & 0x800: return None
            name = raw.decode("latin-1")
        names.append(name); p += 46 + nl + el + cl
    return names
def pack_ok(data):
    names = zip_names(data)
    if names is None: return False, "unreadable"
    mc = False
    for nme in names:
        if nme.startswith("/") or "\\" in nme or ".." in nme.split("/"): return False, "path"
        if nme == "pack.mcmeta": mc = True
    return (mc, "ok" if mc else "no-mcmeta")
def mkzip(files):
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w", zipfile.ZIP_DEFLATED) as z:
        for k, v in files.items(): z.writestr(k, v)
    return b.getvalue()

good = {"name": "Pack.zip", "url": CDN + "data/AbCd1234/versions/vEr5ion1/Pack.zip", "size": 100, "sha512": "a" * 128, "sha1": None}
# --- rules
check("a normal file is accepted", refusal(good) is None)
check("sha1 alone is accepted (the desktop falls back to it)", refusal({**good, "sha512": None, "sha1": "b" * 40}) is None)
check("no checksum is refused", refusal({**good, "sha512": None, "sha1": None}) == "checksum")
check("an upper-case hash is refused (parsed lower-case first)", refusal({**good, "sha512": "A" * 128}) == "checksum")
check("a short hash is refused", refusal({**good, "sha512": "a" * 127}) == "checksum")
check("another host is refused", refusal({**good, "url": "https://evil.example/data/AbCd1234/versions/vEr5ion1/Pack.zip"}) == "host")
check("a lookalike host is refused", refusal({**good, "url": "https://cdn.modrinth.com.evil.example/data/AbCd1234/versions/vEr5ion1/Pack.zip"}) == "host")
check("http is refused", refusal({**good, "url": good["url"].replace("https", "http")}) == "host")
check("a query string is refused", refusal({**good, "url": good["url"] + "?x=1"}) == "host")
check("a climbing path is refused", refusal({**good, "url": CDN + "data/AbCd1234/versions/../Pack.zip"}) == "host")
check("a bad project id in the address is refused", refusal({**good, "url": CDN + "data/short/versions/vEr5ion1/Pack.zip"}) == "host")
check("names with spaces, section signs, brackets and + are kept (as the desktop)", all(safe_name(n) for n in ["LowOnFire v26.2§8.zip", "FA+All_Extensions-v1.10.1.zip", "NewGlowingOres-§6[Border]§r.zip", "Fresh Animations.zip"]))
check("a name with a slash is refused", not safe_name("a/b.zip") and not safe_name("..\\x.zip"))
check("a hidden name is refused", not safe_name(".hidden.zip"))
check("a name ending in a dot or space is refused", not safe_name("x.zip.") and not safe_name("x.zip "))
check("a name with : * ? \" < > | is refused", all(not safe_name("a%sb.zip" % c) for c in ':*?"<>|'))
check("a control character in the name is refused", not safe_name("a\x07b.zip"))
check("a name over 200 bytes is refused", not safe_name("a" * 197 + ".zip"))
check("a non-zip is refused", refusal({**good, "name": "Pack.jar"}) == "ext")
check("zero size is refused", refusal({**good, "size": 0}) == "size")
check("over 64 MiB is refused", refusal({**good, "size": MAX_FILE + 1}) == "size")
check("project id: 8 letters or digits", is_pid("50dA9Sha") and not is_pid("short") and not is_pid("has-dash1") and not is_pid("toolong99"))
check("search url asks for resource packs of 26.3 only", "project_type%3Aresourcepack" in search_url("", "26.3", 0, 30) and "versions%3A26.3" in search_url("", "26.3", 0, 30))
check("search url: no text sorts by downloads", "index=downloads" in search_url("", "26.3", 0, 30) and "query=" not in search_url("", "26.3", 0, 30))
check("search url: text sorts by relevance and is encoded", "index=relevance" in search_url("fresh & new", "26.3", 0, 30) and "query=fresh%20%26%20new" in search_url("fresh & new", "26.3", 0, 30))
check("search url: limit is clamped to 50", "limit=50" in search_url("", "26.3", 0, 500) and "limit=1&" in search_url("", "26.3", 0, 0) + "&")
check("search: only resource packs with a valid id", len(parse_search({"hits": [{"project_type": "resourcepack", "project_id": "50dA9Sha"}, {"project_type": "mod", "project_id": "50dA9Sha"}, {"project_type": "resourcepack", "project_id": "bad"}, "x"]})) == 1)

def ver(date, games=("26.3",), status="listed", files=None):
    f = files if files is not None else [{"filename": "P.zip", "url": good["url"], "size": 10, "primary": True, "hashes": {"sha512": "a" * 128, "sha1": "b" * 40}}]
    return {"id": "v" + date, "version_number": date, "date_published": date, "game_versions": list(games), "status": status, "files": f}
def number_of(v): return v.get("version_number") or v.get("id") or ""
check("an empty version number falls back to the id", number_of({"version_number": "", "id": "abc"}) == "abc" and number_of({"version_number": "1.2", "id": "abc"}) == "1.2")
v, r = pick_version([ver("2026-01-01"), ver("2026-03-01"), ver("2026-02-01")], "26.3")
check("the newest version is picked", v and v["date_published"] == "2026-03-01")
v, r = pick_version([ver("2026-03-01", games=("1.21",)), ver("2026-01-01")], "26.3")
check("a newer version for another game is skipped", v and v["date_published"] == "2026-01-01")
v, r = pick_version([ver("2026-03-01", status="archived"), ver("2026-01-01")], "26.3")
check("an unlisted version is skipped", v and v["date_published"] == "2026-01-01")
v, r = pick_version([ver("2026-03-01", games=("1.21",))], "26.3")
check("nothing for 26.3 says so", v is None and r == "no-version")
bad = [{"filename": "P.zip", "url": "https://evil.example/P.zip", "size": 10, "primary": True, "hashes": {"sha512": "a" * 128}}]
v, r = pick_version([ver("2026-03-01", files=bad), ver("2026-01-01")], "26.3")
check("a newer version whose file fails a rule falls back to an older good one", v and v["date_published"] == "2026-01-01")
v, r = pick_version([ver("2026-03-01", files=bad)], "26.3")
check("only a bad file: refused, with the reason", v is None and r == "host")
two = [{"filename": "Other.zip", "url": good["url"], "size": 10, "primary": False, "hashes": {"sha512": "a" * 128}}, {"filename": "Main.zip", "url": good["url"], "size": 10, "primary": True, "hashes": {"sha512": "a" * 128}}]
v, r = pick_version([ver("2026-03-01", files=two)], "26.3")
check("the primary file is chosen, not the first", r and r["name"] == "Main.zip")

# --- the ZIP reader
z = mkzip({"pack.mcmeta": "{}", "assets/a.png": "x"})
check("zip: names are read from the central directory", zip_names(z) == ["pack.mcmeta", "assets/a.png"])
check("zip: a plain pack with pack.mcmeta is valid", pack_ok(z)[0])
check("zip: no pack.mcmeta is refused", pack_ok(mkzip({"assets/a.png": "x"})) == (False, "no-mcmeta"))
check("zip: pack.mcmeta in a sub folder does not count", pack_ok(mkzip({"folder/pack.mcmeta": "{}"})) == (False, "no-mcmeta"))
check("zip: a .. path is refused", pack_ok(mkzip({"pack.mcmeta": "{}", "../evil": "x"})) == (False, "path"))
check("zip: a .. in the middle is refused", pack_ok(mkzip({"pack.mcmeta": "{}", "a/../b": "x"})) == (False, "path"))
check("zip: a leading slash is refused", pack_ok(mkzip({"pack.mcmeta": "{}", "/etc/x": "x"})) == (False, "path"))
check("zip: a backslash is refused", pack_ok(mkzip({"pack.mcmeta": "{}", "a\\b": "x"})) == (False, "path"))
check("zip: garbage is unreadable", pack_ok(b"PK\x03\x04" + b"x" * 100)[1] == "unreadable")
check("zip: a truncated file is unreadable", pack_ok(z[:len(z) // 2])[1] == "unreadable")
check("zip: an empty file is unreadable", pack_ok(b"")[1] == "unreadable")
cut = bytearray(z); eocd = z.rfind(b"PK\x05\x06"); struct.pack_into("<I", cut, eocd + 16, len(z) + 1000)
check("zip: a directory offset past the end is unreadable", pack_ok(bytes(cut))[1] == "unreadable")
check("zip: a zip with a comment is still read", pack_ok(z[:-2] + struct.pack("<H", 5) + b"hello")[0])

if "--live" in sys.argv:
    H = {"User-Agent": "iMC-Horizon-iOS-check (github.com/Hocine123321/iMC-Horizon)"}
    def get(u): return urllib.request.urlopen(urllib.request.Request(u, headers=H), timeout=90).read()
    r = json.loads(get(search_url("", "26.3", 0, 30)))
    hits = parse_search(r)
    check("live: the search returns resource packs", len(hits) >= 20, len(hits))
    check("live: there are thousands of packs for 26.3", r["total_hits"] > 1000, r["total_hits"])
    good_n = 0; skipped = {}; sizes = []
    for h in hits[:14]:
        vs = json.loads(get("%s/project/%s/version" % (API, h["project_id"])))
        v, ref = pick_version(vs, "26.3")
        if v is None: skipped[ref] = skipped.get(ref, 0) + 1; continue
        data = get(ref["url"])
        okh = (hashlib.sha512(data).hexdigest() == ref["sha512"]) if ref["sha512"] else (hashlib.sha1(data).hexdigest() == ref["sha1"])
        ok, why = pack_ok(data)
        check("live: %s (%d bytes) passes size, hash, zip and pack.mcmeta" % (h["slug"], len(data)), okh and ok and len(data) == ref["size"], (okh, why, len(data), ref["size"]))
        good_n += okh and ok
    print("live: installable %d, skipped %s" % (good_n, skipped))
    check("live: most of the top packs install", good_n >= 8, good_n)
    # a flipped bit must change the hash
    h0 = hits[0]; vs = json.loads(get("%s/project/%s/version" % (API, h0["project_id"]))); v, ref = pick_version(vs, "26.3")
    data = bytearray(get(ref["url"])); data[len(data) // 2] ^= 1
    check("live: a one-bit-flipped real pack fails its SHA-512", hashlib.sha512(bytes(data)).hexdigest() != ref["sha512"])

print("\n%s" % ("all checks passed" if fails == 0 else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
