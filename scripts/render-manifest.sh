#!/usr/bin/env bash
# Update bucket/corntchap-cli.json from a release of cratestack/corntchap.
#
#   render-manifest.sh RELEASE_JSON SHA_DIR MANIFEST
#
#   RELEASE_JSON  `gh release view --json tagName,assets` output
#   SHA_DIR       the release's corntchap-cli-windows-x86_64.zip.sha256
#   MANIFEST      the Scoop manifest to rewrite (version, url and hash; the rest is kept, autoupdate included)
#
# Exit 0: MANIFEST is up to date (rewritten, or already identical). Exit 10: skipped, the release is
# older than the manifest (never downgrade). Anything else: refused, MANIFEST is untouched.
#
# The tag and the hash come from a release, so they are untrusted: each is validated against a strict
# pattern, and values reach the JSON only through `jq --arg` (never by string splicing).
# Each `# GUARD:<name>` line is covered by a test in tests/render-manifest.test.sh.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
skip() { echo "skip: $*" >&2; exit 10; }

[ $# -eq 3 ] || die "usage: render-manifest.sh RELEASE_JSON SHA_DIR MANIFEST"
release=$1 shas=$2 manifest=$3
[ -f "$release" ] || die "no such file: $release"
[ -d "$shas" ] || die "no such directory: $shas"
[ -f "$manifest" ] || die "no such file: $manifest"
command -v jq > /dev/null || die "jq is required"

num='(0|[1-9][0-9]{0,8})'
tag_re="^v$num\\.$num\\.$num\$"
sha_re='^[0-9a-f]{64}$'
name=corntchap-cli-windows-x86_64.zip

tag=$(jq -er '.tagName | strings' "$release") || die "release JSON has no tagName"
[[ $tag =~ $tag_re ]] || die "refusing tag '${tag:0:80}': not vMAJOR.MINOR.PATCH" # GUARD:tag
ver=${tag#v}

# ver_lt A B: A < B, component by component (no overflow, no `sort -V` portability trouble)
ver_lt() {
  local IFS=. i
  local -a a b
  read -r -a a <<< "$1"
  read -r -a b <<< "$2"
  for i in 0 1 2; do
    if ((a[i] < b[i])); then return 0; fi
    if ((a[i] > b[i])); then return 1; fi
  done
  return 1
}

cur=$(jq -r '.version // empty' "$manifest")
[[ $cur =~ ^$num\.$num\.$num$ ]] || die "manifest version '${cur:0:40}' is not MAJOR.MINOR.PATCH" # GUARD:manifest-version
ver_lt "$ver" "$cur" && skip "release $ver is older than the manifest's $cur" # GUARD:downgrade

jq -e --arg n "$name" 'any(.assets[]?; .name == $n)' "$release" > /dev/null \
  || die "release $tag has no asset $name" # GUARD:asset-zip
jq -e --arg n "$name.sha256" 'any(.assets[]?; .name == $n)' "$release" > /dev/null \
  || die "release $tag has no asset $name.sha256" # GUARD:asset-sha
f=$shas/$name.sha256
[ -f "$f" ] || die "missing $f" # GUARD:sha-file
line=$(cat "$f")
hash=${line%%  *}
[[ $hash =~ $sha_re ]] || die "$name.sha256: '${hash:0:80}' is not 64 lowercase hex characters" # GUARD:sha-format
[ "$line" = "$hash  $name" ] || die "$name.sha256 does not name $name" # GUARD:sha-name

tmp=$(mktemp "$manifest.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq --indent 4 --arg v "$ver" --arg h "$hash" --arg n "$name" '
  .version = $v
  | .architecture["64bit"].url = "https://github.com/cratestack/corntchap/releases/download/v\($v)/\($n)"
  | .architecture["64bit"].hash = $h' "$manifest" > "$tmp"
if cmp -s "$tmp" "$manifest"; then
  echo "manifest already at $ver"
else
  mv "$tmp" "$manifest"
  echo "manifest now at $ver"
fi
