#!/usr/bin/env python3
"""Checks the decisions of platform/ios/App/Downloader.m and DownloadStore.m. A Python copy of the
logic: it checks the rules, not the Objective-C text, which only CI compiles. Keep this and those two
files in step (the same way download_plan_check.py is for DownloadPlan.m).

  python3 platform/ios/tests/downloader_check.py          offline (temporary folders, no network)
  python3 platform/ios/tests/downloader_check.py --live   also Mojang's real manifest, version file
                                                          and asset index, checksums included
"""
import hashlib, json, os, re, sys, tempfile, urllib.request
from urllib.parse import urlparse

HOSTS = {"libraries.minecraft.net", "piston-data.mojang.com", "piston-meta.mojang.com", "resources.download.minecraft.net"}
MANIFEST = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
fails = 0
def check(name, ok, extra=""):
    global fails
    print(("ok   " if ok else "FAIL ") + name + ((" : " + str(extra)) if (extra and not ok) else ""))
    if not ok: fails += 1

# --- Downloader.m: pure helpers ------------------------------------------------------------------
def backoff(n):                    # +backoffForAttempt:  2, 4, 8, 16, capped at 16
    return min(2.0 * (1 << min(n - 1 if n > 0 else 0, 3)), 16.0)
def should_retry(status):          # +shouldRetryStatus:
    return status in (408, 425, 429) or 500 <= status <= 599
def is_hex(s, n): return isinstance(s, str) and re.fullmatch(r"[0-9a-f]{%d}" % n, s) is not None
def version_entry(manifest_bytes, version):   # +versionEntryIn:version:
    try: root = json.loads(manifest_bytes)
    except Exception: return None
    versions = root.get("versions") if isinstance(root, dict) else None
    if not isinstance(versions, list): return None
    for v in versions:
        if not isinstance(v, dict) or v.get("id") != version: continue
        url, sha1 = v.get("url"), v.get("sha1")
        u = urlparse(url) if isinstance(url, str) else None
        if not u or u.scheme != "https" or (u.hostname or "").lower() not in HOSTS: return None
        if not is_hex(sha1, 40): return None
        return {"url": url, "sha1": sha1}
    return None

# --- DownloadStore.m ------------------------------------------------------------------------------
def abs_path(root, rel):           # -absolutePathFor:
    if not rel or rel.startswith("/") or "\\" in rel: return None
    for part in rel.split("/"):
        if part in ("", ".", ".."): return None
    full = os.path.join(root, rel)
    d = os.path.dirname(full); rest = []
    while len(d) > 1 and not os.path.exists(d):
        rest.insert(0, os.path.basename(d)); d = os.path.dirname(d)
    resolved = os.path.realpath(d)
    for p in rest: resolved = os.path.join(resolved, p)
    if not (resolved + "/").startswith(root + "/"): return None
    return os.path.join(resolved, os.path.basename(full))
def sha1_file(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        while True:
            b = f.read(64 * 1024)
            if not b: break
            h.update(b)
    return h.hexdigest()
def state_of(root, rel, size, sha1):   # -stateOfPath:size:sha1:   returns "complete" or "missing"
    p = abs_path(root, rel)
    if not p: return "missing"
    if not os.path.lexists(p): return "missing"
    if os.path.islink(p) or not os.path.isfile(p):
        (os.remove if os.path.islink(p) or os.path.isfile(p) else __import__("shutil").rmtree)(p); return "missing"
    if size > 0 and os.path.getsize(p) != size: os.remove(p); return "missing"
    if sha1_file(p) == sha1: return "complete"
    os.remove(p); return "missing"
def install(root, temp, rel, size, sha1):   # -installDownloaded:toPath:size:sha1:  None = success
    dest = abs_path(root, rel)
    if not dest: os.remove(temp); return "outside"
    if size > 0 and os.path.getsize(temp) != size: os.remove(temp); return "size"
    if sha1_file(temp) != sha1: os.remove(temp); return "hash"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest): os.remove(dest)
    os.rename(temp, dest); return None
def remove_partial(root):
    n = 0
    for d, _, files in os.walk(root):
        for f in files:
            if f.endswith(".part"): os.remove(os.path.join(d, f)); n += 1
    return n

def offline():
    # backoff and retry classification
    check("backoff 1..6 = 2,4,8,16,16,16", [backoff(i) for i in range(1, 7)] == [2, 4, 8, 16, 16, 16])
    check("backoff(0) is the first wait", backoff(0) == 2)
    check("retry on 408/425/429/500/502/503/504", all(should_retry(s) for s in (408, 425, 429, 500, 502, 503, 504)))
    check("no retry on 200/301/400/401/403/404", not any(should_retry(s) for s in (200, 301, 400, 401, 403, 404)))

    # manifest lookup
    good = {"versions": [{"id": "25.1", "url": "https://piston-meta.mojang.com/v1/packages/aa/25.1.json", "sha1": "a" * 40},
                         {"id": "26.3", "url": "https://piston-meta.mojang.com/v1/packages/bb/26.3.json", "sha1": "b" * 40}]}
    check("manifest: finds 26.3", version_entry(json.dumps(good), "26.3") == {"url": good["versions"][1]["url"], "sha1": "b" * 40})
    check("manifest: unknown version is nil", version_entry(json.dumps(good), "9.9") is None)
    check("manifest: not JSON is nil", version_entry(b"<html>", "26.3") is None)
    check("manifest: empty is nil", version_entry(b"", "26.3") is None)
    bad_host = json.loads(json.dumps(good)); bad_host["versions"][1]["url"] = "https://evil.example/26.3.json"
    check("manifest: foreign host refused", version_entry(json.dumps(bad_host), "26.3") is None)
    look = json.loads(json.dumps(good)); look["versions"][1]["url"] = "https://piston-meta.mojang.com.evil.com/26.3.json"
    check("manifest: look-alike host refused", version_entry(json.dumps(look), "26.3") is None)
    http = json.loads(json.dumps(good)); http["versions"][1]["url"] = "http://piston-meta.mojang.com/26.3.json"
    check("manifest: http refused", version_entry(json.dumps(http), "26.3") is None)
    upper = json.loads(json.dumps(good)); upper["versions"][1]["sha1"] = "B" * 40
    check("manifest: upper-case sha1 refused", version_entry(json.dumps(upper), "26.3") is None)
    short = json.loads(json.dumps(good)); short["versions"][1]["sha1"] = "b" * 39
    check("manifest: short sha1 refused", version_entry(json.dumps(short), "26.3") is None)
    check("manifest: versions not a list is nil", version_entry(json.dumps({"versions": {}}), "26.3") is None)

    with tempfile.TemporaryDirectory() as t:
        root = os.path.realpath(t)
        data = b"hello minecraft"; sha = hashlib.sha1(data).hexdigest()
        # path containment
        for bad in ("../x", "a/../../x", "/etc/passwd", "a//b", "a\\b", "", "./x", "a/."):
            check("path refused: %r" % bad, abs_path(root, bad) is None)
        check("path accepted: libraries/a/b.jar", abs_path(root, "libraries/a/b.jar") == os.path.join(root, "libraries/a/b.jar"))
        # a symlink inside the root pointing outside must not let a write out
        outside = tempfile.mkdtemp()
        os.symlink(outside, os.path.join(root, "libraries"))
        check("symlinked folder leading out is refused", abs_path(root, "libraries/evil.jar") is None)
        os.remove(os.path.join(root, "libraries"))
        # resume decision
        p = os.path.join(root, "a", "f.bin"); os.makedirs(os.path.dirname(p))
        check("missing file is missing", state_of(root, "a/f.bin", len(data), sha) == "missing")
        open(p, "wb").write(data)
        check("whole file is complete", state_of(root, "a/f.bin", len(data), sha) == "complete")
        check("whole file kept on disk", os.path.exists(p))
        check("size 0 (unlisted) falls back to hash", state_of(root, "a/f.bin", 0, sha) == "complete")
        open(p, "wb").write(data[:-1])
        check("short file is missing and deleted", state_of(root, "a/f.bin", len(data), sha) == "missing" and not os.path.exists(p))
        open(p, "wb").write(b"X" * len(data))
        check("same size, wrong hash: missing and deleted", state_of(root, "a/f.bin", len(data), sha) == "missing" and not os.path.exists(p))
        os.makedirs(p)
        check("a folder where a file belongs: missing", state_of(root, "a/f.bin", len(data), sha) == "missing")
        # install
        tmp = os.path.join(root, "a", "f.bin.part"); open(tmp, "wb").write(data)
        check("install: good file lands", install(root, tmp, "a/f.bin", len(data), sha) is None and open(p, "rb").read() == data)
        check("install: .part is gone after success", not os.path.exists(tmp))
        open(tmp, "wb").write(b"junk")
        check("install: wrong size refused (4 bytes against %d)" % len(data), install(root, tmp, "a/g.bin", len(data), sha) == "size" and not os.path.exists(tmp))
        open(tmp, "wb").write(b"X" * len(data))
        check("install: same size wrong hash refused, temp deleted", install(root, tmp, "a/g.bin", len(data), sha) == "hash" and not os.path.exists(tmp) and not os.path.exists(os.path.join(root, "a/g.bin")))
        open(tmp, "wb").write(data)
        check("install: wrong listed size refused", install(root, tmp, "a/g.bin", len(data) + 1, sha) == "size" and not os.path.exists(os.path.join(root, "a/g.bin")))
        open(tmp, "wb").write(data)
        check("install: path outside refused, temp deleted", install(root, tmp, "../out.bin", len(data), sha) == "outside" and not os.path.exists(tmp))
        # a failed install must not damage a good existing file
        open(p, "wb").write(data); open(tmp, "wb").write(b"X" * len(data))
        install(root, tmp, "a/f.bin", len(data), sha)
        check("install: a bad download leaves the good file alone", open(p, "rb").read() == data)
        # partial cleanup
        for n in ("x.part", "libraries/y.part", "keep.jar"):
            q = os.path.join(root, n); os.makedirs(os.path.dirname(q), exist_ok=True); open(q, "wb").write(b"1")
        check("removePartialFiles removes 2 .part files", remove_partial(root) == 2 and os.path.exists(os.path.join(root, "keep.jar")))
        # streaming hash equals one-shot hash on a file bigger than the chunk
        big = os.path.join(root, "big.bin"); blob = os.urandom(300 * 1024 + 7); open(big, "wb").write(blob)
        check("chunked sha1 equals one-shot sha1 (300 KB)", sha1_file(big) == hashlib.sha1(blob).hexdigest())
        check("sha1 of empty file", (open(os.path.join(root, "e"), "wb").close() or sha1_file(os.path.join(root, "e"))) == "da39a3ee5e6b4b0d3255bfef95601890afd80709")

def get(url):
    with urllib.request.urlopen(url, timeout=40) as r: return r.read()

def live():
    m = get(MANIFEST)
    e = version_entry(m, "26.3")
    check("live: manifest has 26.3 on a Mojang host with a sha1", e is not None)
    if not e: return
    v = get(e["url"])
    check("live: version file matches the manifest's sha1", hashlib.sha1(v).hexdigest() == e["sha1"])
    vj = json.loads(v)
    ai = vj["assetIndex"]
    check("live: asset index id is a plain name", re.fullmatch(r"[A-Za-z0-9._-]+", ai["id"]) is not None, ai["id"])
    check("live: asset index host is Mojang's", urlparse(ai["url"]).hostname in HOSTS)
    idx = get(ai["url"])
    check("live: asset index matches its sha1", hashlib.sha1(idx).hexdigest() == ai["sha1"])
    srv = vj["downloads"]["server"]
    check("live: server jar on a Mojang host with sha1 and size", urlparse(srv["url"]).hostname in HOSTS and is_hex(srv["sha1"], 40) and srv["size"] > 0, srv)
    print("     server jar: %.1f MB, asset index %s with %d objects" % (srv["size"] / 1e6, ai["id"], len(json.loads(idx)["objects"])))
    # a corrupted copy of the version file must NOT match
    check("live: a one-byte change breaks the checksum", hashlib.sha1(v[:-1] + b"X").hexdigest() != e["sha1"])

offline()
if "--live" in sys.argv: live()
print("\n%s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
