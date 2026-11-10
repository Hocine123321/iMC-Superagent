#!/usr/bin/env python3
"""Checks the decisions of platform/ios/App/GameSession.m against the engine's own parser
(horizon/crates/horizon-client-render/src/auth.rs AuthSession::parse and ::load). A Python copy of
both sides: HZSessionFileData builds the JSON, engine_parse is a copy of what the engine accepts.
It checks the rules, not the Objective-C text, which only CI compiles. Keep this and GameSession.m
in step. Run: python3 platform/ios/tests/game_session_check.py"""
import json, os, stat, tempfile, time, sys

def is_uuid(s):
    h = s.replace("-", "")
    return len(h) == 32 and all(c in "0123456789abcdefABCDEF" for c in h)

def session_file_data(name, uuid, token):
    """GameSession.m HZSessionFileData."""
    if not name or len(name) > 16 or not uuid or not is_uuid(uuid) or not token: return None
    return json.dumps({"name": name, "uuid": uuid, "access_token": token, "user_type": "msa"}).encode()

def engine_parse(text):
    """AuthSession::parse, copied from the engine."""
    try: v = json.loads(text)
    except Exception: return "the session is not valid JSON"
    f = lambda k: v.get(k) if isinstance(v.get(k), str) else None
    name = f("name")
    if name is None: return "the session has no name"
    if not name or len(name) > 16: return "the session's name is not a valid player name"
    u = f("uuid")
    if u is None or not is_uuid(u): return "the session has no valid uuid"
    t = f("access_token")
    if not t: return "the session has no access token"
    if f("user_type") is not None and f("user_type") != "msa": return "the session is not a Microsoft account session"
    return ("ok", name, u.replace("-", "").lower(), t)

def engine_load(path, max_age=120):
    """AuthSession::load: refuses wide permissions and an old file; deletes the file either way."""
    mode = os.stat(path).st_mode
    def refuse(why):
        os.remove(path); return why
    if mode & 0o077: return refuse("other users can read it")
    if time.time() - os.stat(path).st_mtime > max_age: return refuse("it is too old")
    text = open(path).read(); os.remove(path)
    return engine_parse(text)

fails = 0
def check(label, cond):
    global fails
    if not cond: fails += 1
    print(("ok   " if cond else "FAIL ") + label)

UUID = "069a79f444e94726a5befca90e38aaf5"   # Notch's, as Mojang returns it: no dashes
TOK = "eyJhbGciOiJIUzI1NiJ9.e30.sig"

d = session_file_data("Notch", UUID, TOK)
check("a normal account builds a file", d is not None)
r = engine_parse(d.decode())
check("the engine accepts it", r[0] == "ok")
check("the engine reads the same name", r[1] == "Notch")
check("the engine reads the same uuid", r[2] == UUID)
check("the engine reads the same token", r[3] == TOK)
check("user_type is msa", json.loads(d)["user_type"] == "msa")
check("a dashed uuid is accepted too", session_file_data("Notch", "069a79f4-44e9-4726-a5be-fca90e38aaf5", TOK) is not None)
check("16-character name accepted", session_file_data("A" * 16, UUID, TOK) is not None)
check("17-character name refused (the engine would refuse it)", session_file_data("A" * 17, UUID, TOK) is None and engine_parse(json.dumps({"name": "A"*17, "uuid": UUID, "access_token": TOK})) != engine_parse(d.decode()))
check("no name refused", session_file_data(None, UUID, TOK) is None and session_file_data("", UUID, TOK) is None)
check("no uuid refused", session_file_data("Notch", None, TOK) is None)
check("short uuid refused", session_file_data("Notch", "abc123", TOK) is None)
check("non-hex uuid refused", session_file_data("Notch", "z" * 32, TOK) is None)
check("no token refused", session_file_data("Notch", UUID, None) is None and session_file_data("Notch", UUID, "") is None)
check("a token with quotes and a backslash stays valid JSON the engine reads back exactly",
      engine_parse(session_file_data("Notch", UUID, 'a"b\\c').decode())[3] == 'a"b\\c')
# every file the builder can make, the engine accepts
import random
random.seed(7)
alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
ok_all = True
for _ in range(500):
    n = "".join(random.choice(alphabet) for _ in range(random.randint(1, 16)))
    u = "".join(random.choice("0123456789abcdef") for _ in range(32))
    t = "".join(random.choice(alphabet + ".-") for _ in range(random.randint(1, 900)))
    b = session_file_data(n, u, t)
    ok_all &= b is not None and engine_parse(b.decode())[0] == "ok"
check("500 random valid accounts: the builder makes a file and the engine accepts every one", ok_all)

# the file's disk rules
with tempfile.TemporaryDirectory() as tmp:
    p = os.path.join(tmp, "game-session.json")
    def make(mode):
        fd = os.open(p, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, mode); os.write(fd, d); os.close(fd); os.chmod(p, mode)
    make(0o600)
    check("a 0600 fresh file loads", engine_load(p)[0] == "ok")
    check("the engine deleted it after reading", not os.path.exists(p))
    make(0o644)
    check("a 0644 file is refused by the engine (so 0600 is required)", engine_load(p) == "other users can read it")
    check("a refused file is deleted too", not os.path.exists(p))
    make(0o600); old = time.time() - 300; os.utime(p, (old, old))
    check("a file older than 120 s is refused (so it is written just before the engine starts)", engine_load(p) == "it is too old")
    make(0o600); old = time.time() - 100; os.utime(p, (old, old))
    check("a 100 s old file still loads", engine_load(p)[0] == "ok")

print("all checks pass" if not fails else f"{fails} FAILED")
sys.exit(1 if fails else 0)
