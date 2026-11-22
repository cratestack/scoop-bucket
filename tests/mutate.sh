#!/usr/bin/env bash
# Proves each guard in scripts/render-manifest.sh is tested: neutralises it in a copy of the repo and
# expects tests/render-manifest.test.sh to fail there. Exits 1 if any mutation survives.
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
survived=0
for g in tag downgrade manifest-version asset-zip asset-sha sha-file sha-format sha-name; do
  m=$(mktemp -d); cp -R "$repo/." "$m/"
  sed -i.bak -E "/# GUARD:$g\$/{s/\|\| die/|| true/;s/&& skip/\&\& true/;}" "$m/scripts/render-manifest.sh"
  if cmp -s "$repo/scripts/render-manifest.sh" "$m/scripts/render-manifest.sh"; then
    echo "!! mutation $g changed nothing"; survived=1; rm -rf "$m"; continue
  fi
  echo "== mutation: guard $g removed"
  out=$(bash "$m/tests/render-manifest.test.sh" 2>&1); rc=$?
  grep -E '^(FAIL|[0-9]+/[0-9]+ passed)' <<< "$out" | cut -c1-110
  if [ "$rc" = 0 ]; then echo "!! guard $g is not covered: tests still pass without it"; survived=1; fi
  rm -rf "$m"
done
exit "$survived"
