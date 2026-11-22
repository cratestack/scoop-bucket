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
# What this does and does not protect (trust on first use of a release):
#  - the tag and the hash are validated against strict patterns, and values reach the JSON only
#    through `jq --arg` (never by string splicing);
#  - the zip's hash in its .sha256 file must equal the `digest` GitHub itself computed for the asset,
#    so a .sha256 that disagrees with the archive it names is refused;
#  - once a version is pinned with a real hash, the same version is never re-pinned to a different
#    hash (a swapped asset is refused), and an older release never replaces a newer one.
# It does NOT detect a release that was already compromised when first published: the first release
# seen is trusted. Immutable releases (`isImmutable`) would close the swap window on GitHub's side.
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
tag_re="^v$num\\.$num\\.$num\$" # GUARD:tag-anchors
sha_re='^[0-9a-f]{64}$' # GUARD:sha-anchors
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
[ "$(grep -c '' "$f")" = 1 ] || die "$f must hold exactly one line" # GUARD:sha-lines
line=$(cat "$f")
hash=${line%%  *}
[[ $hash =~ $sha_re ]] || die "$name.sha256: '${hash:0:80}' is not 64 lowercase hex characters" # GUARD:sha-format
[ "$line" = "$hash  $name" ] || die "$name.sha256 does not name $name" # GUARD:sha-name
dg=$(jq -r --arg n "$name" '[.assets[]? | select(.name == $n) | .digest // empty] | first // empty' "$release")
[ "$dg" = "sha256:$hash" ] || die "$name: GitHub's digest '${dg:0:80}' does not match the .sha256 file's $hash" # GUARD:digest
curhash=$(jq -r '.architecture["64bit"].hash // empty' "$manifest")
if [ "$cur" = "$ver" ] && [[ $curhash =~ ^[0-9a-f]{64}$ && ! $curhash =~ ^0+$ ]]; then
  [ "$curhash" = "$hash" ] || die "refusing to re-pin $name at $ver: pinned $curhash, release now says $hash" # GUARD:repin
fi
jq -e '.isImmutable == true' "$release" > /dev/null || echo "note: release $tag is not immutable (trust on first use)" >&2

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
