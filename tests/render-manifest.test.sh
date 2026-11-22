#!/usr/bin/env bash
# Tests for scripts/render-manifest.sh against fake releases (no network). Run: tests/render-manifest.test.sh
# One test per guard (each `# GUARD:<name>` line in the script); RENDER overrides the script under test.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
RENDER=${RENDER:-$root/scripts/render-manifest.sh}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0 n=0
ZIP=corntchap-cli-windows-x86_64.zip

hex() { printf '%064x' "$1"; }

# mk_release DIR TAG: a complete, valid release (release.json + shas/) in DIR
mk_release() {
  local d=$1 tag=$2
  mkdir -p "$d/shas"
  printf '%s  %s\n' "$(hex 7)" "$ZIP" > "$d/shas/$ZIP.sha256"
  jq -n --arg t "$tag" --arg z "$ZIP" \
    '{tagName:$t,assets:[{name:"corntchap-cli-linux-x86_64.tar.gz"},{name:$z},{name:($z+".sha256")},{name:"install.sh"}]}' > "$d/release.json"
}

# seed_manifest FILE VERSION: the committed manifest brought to VERSION by the script itself
seed_manifest() {
  local d="$work/seed-$2"
  rm -rf "$d"; mk_release "$d" "v$2"
  cp "$root/bucket/corntchap-cli.json" "$1"
  "$RENDER" "$d/release.json" "$d/shas" "$1" > /dev/null 2>&1
}

check() { # check NAME STATUS [detail]
  n=$((n + 1))
  if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1 ${3:-}"; fails=$((fails + 1)); fi
}

# expect_refusal NAME EXPECTED_RC MESSAGE_FRAGMENT DIR [MANIFEST]: the manifest (seeded at 0.1.0 unless given) must not change
expect_refusal() {
  local name=$1 want=$2 frag=$3 d=$4 f=${5:-"$work/manifest-$((n + 1)).json"} before err rc
  [ -n "${5:-}" ] || seed_manifest "$f" 0.1.0
  before=$(cksum < "$f")
  err=$("$RENDER" "$d/release.json" "$d/shas" "$f" 2>&1 > /dev/null); rc=$?
  [ "$rc" = "$want" ] && [[ $err == *"$frag"* ]] && [ "$(cksum < "$f")" = "$before" ]
  check "$name" $? "(rc=$rc, want $want; stderr: $err)"
}

# ---- renders ----
d=$work/ok; mk_release "$d" v0.2.0
f=$work/manifest.json; seed_manifest "$f" 0.1.0
"$RENDER" "$d/release.json" "$d/shas" "$f" > "$work/out" 2>&1
check "renders a newer release (0.1.0 -> 0.2.0)" $? "$(cat "$work/out")"
[ "$(jq -r .version "$f")" = 0.2.0 ] \
  && [ "$(jq -r '.architecture["64bit"].url' "$f")" = "https://github.com/cratestack/corntchap/releases/download/v0.2.0/$ZIP" ] \
  && [ "$(jq -r '.architecture["64bit"].hash' "$f")" = "$(hex 7)" ]
check "version, url and hash are updated" $?
# shellcheck disable=SC2016
[ "$(jq -r '.autoupdate.architecture["64bit"].url' "$f")" = "https://github.com/cratestack/corntchap/releases/download/v\$version/$ZIP" ] \
  && [ "$(jq -r '.autoupdate.architecture["64bit"].hash.url' "$f")" = '$url.sha256' ] \
  && [ "$(jq -r '.bin' "$f")" = corntchap-cli.exe ] && [ "$(jq -r '.checkver.github' "$f")" = https://github.com/cratestack/corntchap ]
check "autoupdate, checkver and bin are kept" $?
before=$(cksum < "$f")
"$RENDER" "$d/release.json" "$d/shas" "$f" 2>&1 | grep -q 'already at 0.2.0' && [ "$(cksum < "$f")" = "$before" ]
check "second run is a no-op (byte-identical)" $?

# the committed placeholder manifest (0.1.0) is replaced by a 0.1.0 release (same version is not a downgrade)
d=$work/first; mk_release "$d" v0.1.0
f=$work/placeholder.json; cp "$root/bucket/corntchap-cli.json" "$f"
grep -qE '"hash": "0{64}"' "$f" && "$RENDER" "$d/release.json" "$d/shas" "$f" > /dev/null 2>&1 && ! grep -qE '"hash": "0{64}"' "$f" && [ "$(jq -r '.architecture["64bit"].hash' "$f")" = "$(hex 7)" ]
check "first release replaces the committed placeholder hash" $?

# ---- guards ----
# GUARD:tag
d=$work/evil; mk_release "$d" 'v1.0.0"; system("id")#'
expect_refusal "tag: shell/json injection is refused" 1 "refusing tag" "$d"
d=$work/evil2; mk_release "$d" 'v1.0.0-rc1'
expect_refusal "tag: pre-release suffix is refused" 1 "refusing tag" "$d"
d=$work/evil3; mk_release "$d" $'v1.0.0\nv9.9.9'
expect_refusal "tag: embedded newline is refused" 1 "refusing tag" "$d"
# GUARD:sha-format
d=$work/short; mk_release "$d" v0.2.0
printf '%s  %s\n' "$(hex 7 | cut -c2-)" "$ZIP" > "$d/shas/$ZIP.sha256"
expect_refusal "sha-format: 63 hex chars is refused" 1 "not 64 lowercase hex" "$d"
d=$work/upper; mk_release "$d" v0.2.0
printf '%s  %s\n' "$(hex 7 | sed 's/^0/G/')" "$ZIP" > "$d/shas/$ZIP.sha256"
expect_refusal "sha-format: non-hex characters are refused" 1 "not 64 lowercase hex" "$d"
d=$work/jsonhash; mk_release "$d" v0.2.0
printf '%s  %s\n' '","bin":"evil.exe","x":"' "$ZIP" > "$d/shas/$ZIP.sha256"
expect_refusal "sha-format: a hash carrying json is refused" 1 "not 64 lowercase hex" "$d"
# GUARD:sha-name
d=$work/wrongname; mk_release "$d" v0.2.0
printf '%s  corntchap-cli-linux-x86_64.tar.gz\n' "$(hex 9)" > "$d/shas/$ZIP.sha256"
expect_refusal "sha-name: a hash for another file is refused" 1 "does not name" "$d"
# GUARD:asset-zip
d=$work/nozip; mk_release "$d" v0.2.0
jq --arg z "$ZIP" '.assets |= map(select(.name != $z))' "$d/release.json" > "$d/r" && mv "$d/r" "$d/release.json"
expect_refusal "asset-zip: release without the windows zip is refused" 1 "has no asset $ZIP" "$d"
# GUARD:asset-sha
d=$work/nosha; mk_release "$d" v0.2.0
jq --arg z "$ZIP.sha256" '.assets |= map(select(.name != $z))' "$d/release.json" > "$d/r" && mv "$d/r" "$d/release.json"
expect_refusal "asset-sha: release without the .sha256 asset is refused" 1 "has no asset $ZIP.sha256" "$d"
# GUARD:sha-file
d=$work/nofile; mk_release "$d" v0.2.0
rm "$d/shas/$ZIP.sha256"
expect_refusal "sha-file: a listed asset that was not downloaded is refused" 1 "missing" "$d"
# GUARD:downgrade
d=$work/older; mk_release "$d" v0.0.9
expect_refusal "downgrade: an older release is skipped (rc 10)" 10 "older than the manifest" "$d"
d=$work/older2; mk_release "$d" v0.1.0
f=$work/manifest-newer.json; seed_manifest "$f" 0.10.0
expect_refusal "downgrade: 0.1.0 is older than 0.10.0 (numeric, not lexical)" 10 "older than the manifest" "$d" "$f"
# GUARD:manifest-version
d=$work/ok2; mk_release "$d" v0.2.0
f=$work/manifest-bad.json; jq '.version = "nightly"' "$root/bucket/corntchap-cli.json" > "$f"
expect_refusal "manifest-version: an unreadable current version is refused" 1 "not MAJOR.MINOR.PATCH" "$d" "$f"

echo "$((n - fails))/$n passed"
[ "$fails" = 0 ]
