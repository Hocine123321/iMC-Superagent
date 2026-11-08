#!/usr/bin/env bash
# Runs upstream's guard against committed Mojang files from the folder it was written for.
# (Its allowlist uses paths relative to horizon/, so running it from the repository root
# falsely flags Horizon's own parity-test sources.) Also refuses secrets and archives at the root.
set -euo pipefail
cd "$(dirname "$0")/.."
( cd horizon && python3 tools/check_public_tree.py )
if git ls-files | grep -E '^(platform|docs|tools|\.github)/.*\.(jar|class|ipa|p12|mobileprovision|pem)$'; then
  echo "binary or credential file tracked in the iOS port's own folders" >&2; exit 1
fi
if git grep -InE '(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)' -- platform docs tools .github; then
  echo "secret-looking string tracked" >&2; exit 1
fi
echo "public tree OK"
