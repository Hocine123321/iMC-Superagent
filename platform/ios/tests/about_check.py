#!/usr/bin/env python3
"""The licence text embedded in platform/ios/App/LauncherAbout.m must equal horizon/LICENSE exactly.

  python3 platform/ios/tests/about_check.py
"""
import os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "..", "App", "LauncherAbout.m")).read()
lic = open(os.path.join(here, "..", "..", "..", "horizon", "LICENSE")).read()
m = re.search(r'kHorizonLicense =\n(.*?);\n', src, re.S)
parts = re.findall(r'@"((?:[^"\\]|\\.)*)"', m.group(1)) if m else []
text = "".join(parts).replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')
ok = text.rstrip("\n") == lic.rstrip("\n")
print("ok   embedded licence equals horizon/LICENSE (%d bytes)" % len(lic) if ok else "FAIL embedded licence differs from horizon/LICENSE")
sys.exit(0 if ok else 1)
