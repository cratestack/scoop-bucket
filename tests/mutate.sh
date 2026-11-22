#!/usr/bin/env bash
# Proves each guard in scripts/render-manifest.sh is tested: neutralises it in a copy of the repo and
# expects tests/render-manifest.test.sh to fail there. Exits 1 if any mutation survives.
# Every `# GUARD:<name>` line in the script must be listed here (checked below).
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
guards="tag tag-anchors downgrade manifest-version asset-zip asset-sha sha-file sha-lines sha-format sha-anchors sha-name digest repin"
survived=0
# shellcheck disable=SC2013
for g in $(grep -o '# GUARD:[a-z-]*' "$repo/scripts/render-manifest.sh" | sed 's/# GUARD://'); do
  case " $guards " in *" $g "*) ;; *) echo "!! guard $g has no mutation listed in tests/mutate.sh"; survived=1 ;; esac
done
for g in $guards; do
  m=$(mktemp -d); cp -R "$repo/." "$m/"
  case $g in
    # the two anchored patterns lose their ^ and $
    tag-anchors) sed -i.bak -E '/# GUARD:tag-anchors$/s/\^v/v/;/# GUARD:tag-anchors$/s/\\\$"/"/' "$m/scripts/render-manifest.sh" ;;
    sha-anchors) sed -i.bak -E "/# GUARD:sha-anchors\$/s/\\^\\[0-9a-f\\]\\{64\\}\\\$/[0-9a-f]{64}/" "$m/scripts/render-manifest.sh" ;;
    *) sed -i.bak -E "/# GUARD:$g\$/{s/\|\| die/|| true/;s/&& skip/\&\& true/;}" "$m/scripts/render-manifest.sh" ;;
  esac
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
