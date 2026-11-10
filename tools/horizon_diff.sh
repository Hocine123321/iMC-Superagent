#!/usr/bin/env bash
# What differs between upstream Horizon (the pristine import) and horizon/ now.
#
#   tools/horizon_diff.sh            list the changed files with their stats
#   tools/horizon_diff.sh --patch    rewrite docs/horizon-changes.patch (the exact diff, paths start with horizon/)
#                                    and docs/horizon-changes-upstream.patch (the same diff with upstream's own
#                                    paths, for `git apply -3way` inside a clone of upstream Horizon)
#   tools/horizon_diff.sh --check    fail if docs/HORIZON_CHANGES.md misses a changed file, or if
#                                    docs/horizon-changes.patch is out of date
#
# docs/HORIZON_CHANGES.md is the human-readable account; keep it in step with every edit under
# horizon/. The baseline commit is in docs/HORIZON_BASELINE (the pristine upstream import).
set -euo pipefail
cd "$(dirname "$0")/.."
base=$(tr -d '[:space:]' < docs/HORIZON_BASELINE)
if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  echo "horizon_diff: baseline $base is not in this clone (shallow checkout?); skipped" >&2
  [ "${1:-}" = "--check" ] && exit 0
  exit 1
fi
case "${1:-}" in
  "")      git diff --stat=140 "$base" HEAD -- horizon ;;
  --patch) git diff "$base" HEAD -- horizon > docs/horizon-changes.patch
           git diff --relative=horizon "$base" HEAD -- horizon > docs/horizon-changes-upstream.patch
           echo "wrote docs/horizon-changes.patch and docs/horizon-changes-upstream.patch ($(git diff --numstat "$base" HEAD -- horizon | wc -l) files)" ;;
  --check)
    status=0
    while read -r path; do
      grep -qF "$path" docs/HORIZON_CHANGES.md || { echo "HORIZON_CHANGES.md does not mention $path" >&2; status=1; }
    done < <(git diff --name-only "$base" HEAD -- horizon)
    if ! git diff "$base" HEAD -- horizon | cmp -s - docs/horizon-changes.patch; then
      echo "docs/horizon-changes.patch is out of date: run tools/horizon_diff.sh --patch" >&2; status=1
    fi
    if ! git diff --relative=horizon "$base" HEAD -- horizon | cmp -s - docs/horizon-changes-upstream.patch; then
      echo "docs/horizon-changes-upstream.patch is out of date: run tools/horizon_diff.sh --patch" >&2; status=1
    fi
    [ $status -eq 0 ] && echo "horizon changes documented"
    exit $status ;;
  *) echo "usage: $0 [--patch|--check]" >&2; exit 2 ;;
esac
