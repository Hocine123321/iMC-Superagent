#!/usr/bin/env python3
"""Checks the rules of platform/ios/App/DownloadRate.m. A Python copy of the logic: it checks the rules,
not the Objective-C text, which only CI compiles. Keep this and DownloadRate.m in step.

  python3 platform/ios/tests/download_rate_check.py
"""
import math, sys

WARM, ALPHA = 5.0, 0.25

class Rate:
    def __init__(self): self.reset()
    def reset(self): self.started = False; self.smoothed = 0.0; self.have = False
    def note(self, b, now):
        if not self.started:
            self.started = True; self.t0 = self.t = now; self.b = b; return
        if b < self.b: self.b = b; self.t = now; return
        dt = now - self.t
        if dt < 0.5: return
        s = (b - self.b) / dt
        self.smoothed = ALPHA * s + (1 - ALPHA) * self.smoothed if self.have else s
        self.have = True; self.b = b; self.t = now
    def bps(self):
        if not self.started or not self.have: return 0.0
        if self.t - self.t0 < WARM: return 0.0
        return self.smoothed
    def left(self, remaining):
        v = self.bps()
        return None if v <= 0 or remaining == 0 else fmt_s(remaining / v) + " left"

def fmt_speed(v):
    return "%.1f MB/s" % (v / 1e6) if v >= 1e6 else "%.0f KB/s" % max(1.0, v / 1e3)

def fmt_s(s):
    if s < 45: return "about %d s" % int(max(5.0, math.ceil(s / 5.0) * 5.0))
    if s < 90: return "about 1 min"
    if s < 3600: return "about %d min" % int(math.floor(s / 60.0 + 0.5))
    h = int(s // 3600); m = int(math.floor((s % 3600) / 60.0 + 0.5))
    if m == 60: h += 1; m = 0
    return "about %d h" % h if m == 0 else "about %d h %d min" % (h, m)

bad = []
def check(name, got, want):
    if got != want: bad.append("%s: got %r want %r" % (name, got, want))

# formatting
check("speed MB", fmt_speed(4_200_000), "4.2 MB/s")
check("speed KB", fmt_speed(850_000), "850 KB/s")
check("speed floor", fmt_speed(10), "1 KB/s")
check("sec 12", fmt_s(12), "about 15 s")
check("sec 1", fmt_s(1), "about 5 s")
check("sec 44", fmt_s(44), "about 45 s")
check("sec 60", fmt_s(60), "about 1 min")
check("sec 180", fmt_s(180), "about 3 min")
check("sec 3600", fmt_s(3600), "about 1 h")
check("sec 5400", fmt_s(5400), "about 1 h 30 min")
check("sec 7170", fmt_s(7170), "about 2 h")   # 1 h 59.5 min rounds up to 2 h

# steady 4 MB/s for 20 s: silent before 5 s, then 4.0 MB/s
r = Rate()
for t in range(0, 21):
    r.note(t * 4_000_000, float(t))
    if t == 3: check("silent while warming", r.bps(), 0.0)
check("steady speed", fmt_speed(r.bps()), "4.0 MB/s")
check("time left", r.left(400_000_000), "about 2 min left")   # 100 s -> 2 min
check("nothing left", r.left(0), None)

# no progress at all: unknown, not 0 KB/s
r = Rate()
for t in range(0, 12): r.note(1000, float(t))
check("stalled is unknown", r.bps(), 0.0)
check("stalled left", r.left(1_000_000), None)

# a speed change is followed, but smoothed (not a jump)
r = Rate(); b = 0
for t in range(0, 11): r.note(b, float(t)); b += 2_000_000
slow = r.bps()
for t in range(11, 14): r.note(b, float(t)); b += 8_000_000
mid = r.bps()
if not (slow < mid < 8_000_000): bad.append("smoothing: slow %.0f mid %.0f" % (slow, mid))

# a dropped file (bytes go down) does not make a negative speed
r = Rate(); b = 0
for t in range(0, 8): r.note(b, float(t)); b += 1_000_000
r.note(b - 5_000_000, 8.0)
if r.bps() < 0: bad.append("negative speed")

# samples closer than half a second are ignored
r = Rate(); r.note(0, 0.0); r.note(1_000_000, 0.2)
check("too soon", r.have, False)

# reset forgets
r.reset(); check("reset", (r.started, r.have), (False, False))

print("all checks pass" if not bad else "\n".join(bad))
sys.exit(1 if bad else 0)
