# scoop-bucket

[Scoop](https://scoop.sh) bucket for [cratestack](https://github.com/cratestack) tools.

```powershell
scoop bucket add cratestack https://github.com/cratestack/scoop-bucket
scoop install corntchap-cli
```

Installs the prebuilt `corntchap-cli.exe` (64-bit Windows) from the [corntchap releases](https://github.com/cratestack/corntchap/releases). Check it with `corntchap-cli --version`; update with `scoop update corntchap-cli`.

On Windows `corntchap-cli fire install` (a login service) is not available: run `corntchap-cli fire` in a terminal or as a scheduled task.

macOS and Linux users: see the [Homebrew tap](https://github.com/cratestack/homebrew-tap).

## How updates work

Nobody edits `bucket/corntchap-cli.json` by hand. The `update` workflow runs every 12 hours (and on demand: Actions, update, Run workflow, optionally with a tag — `gh workflow run update.yml --repo cratestack/scoop-bucket -f tag=vX.Y.Z` right after a corntchap release) on the default branch only, in three jobs:

1. **render**: checks that `cratestack/corntchap` exists and is public, asks GitHub for its latest release (no release yet means it exits quietly; an explicit tag that does not exist is an error), downloads the release's `corntchap-cli-windows-x86_64.zip.sha256` and runs `scripts/render-manifest.sh`;
2. **test**: installs the rendered manifest on real runners (the `test` workflow, Windows), before anything is pushed;
3. **publish**: only if the test passed, commits `corntchap-cli <version>` as `github-actions[bot]`, and only if the manifest changed.

### What is and is not verified

This is **trust on first use** of a release. `scripts/render-manifest.sh` checks:

| Check | Effect |
| --- | --- |
| the tag is exactly `vMAJOR.MINOR.PATCH` | anything else (quotes, `;`, pre-release suffixes, newlines) fails before it reaches the manifest |
| every needed archive and `.sha256` is an asset of the release | missing asset: fail, nothing is committed |
| each `.sha256` is one line, `<64 lowercase hex>  <archive name>` | fail |
| that hash equals the `digest` GitHub computed for the archive asset | a `.sha256` that disagrees with the archive it names, or an asset without a digest: fail |
| a version already pinned with a real hash is never re-pinned to a different hash | a swapped asset under the same tag: fail, the file is untouched |
| the release is not older than the manifest | exit 10, left alone (never a downgrade) |
| the manifest's own current version can be read | fail (the two checks above cannot run) |

Only validated values are substituted into the manifest. **What this does not catch:** a release that was already malicious when the workflow first saw it (the first release seen for a version is trusted), or a compromised `cratestack/corntchap` release pipeline. The renderer prints a note when a release is not immutable. GitHub's *immutable releases* would stop assets being swapped after publishing; as of this writing they are not enabled on `cratestack/corntchap` (repository Settings, General, Releases, "Enable release immutability", or an organisation policy; it applies to releases published afterwards, and the release job must then publish a draft that already holds its assets).

Runs are serialised (`concurrency`), jobs have least-privilege tokens (only `publish` can write contents, and only the job token is used), and every action is pinned to a full commit SHA.

`checkver` and `autoupdate` stay in the manifest, so Scoop's own `checkver.ps1 -Update` or Excavator also work; the workflow does not depend on them. The `test` workflow also validates the manifest against [Scoop's schema](https://github.com/ScoopInstaller/Scoop/blob/master/schema.json) (pinned to a commit); its install test installs Scoop from a pinned installer script, which itself downloads Scoop's current master.

## If the schedule stops

GitHub disables scheduled workflows in public repositories after 60 days without repository activity. The `keepalive` workflow re-enables `update.yml` (and itself) monthly, which resets that timer. If both still lapse (for example Actions was turned off), the manifest simply stays at the last published version and nothing breaks; re-enable the workflows in the Actions tab, or run `update` by hand.

`tests/render-manifest.test.sh` runs the script against fake releases, one test per check; `tests/mutate.sh` removes each check in turn and fails if the tests still pass. Both run in the `test` workflow.

## Before the first release

Until corntchap `v0.1.0` exists, the manifest carries an all-zero placeholder `hash` (`000…0`) and installing it fails on purpose. The first `update` run after the release replaces it; the install test is skipped while it is present. The default branch must accept pushes from `github-actions[bot]` (no PR-only branch protection), otherwise the commit step fails.

## Layout

```
bucket/corntchap-cli.json     the manifest (generated fields: version, url, hash)
scripts/render-manifest.sh    release -> manifest, with the checks above
tests/                        script tests + mutation check
.github/workflows/            update.yml (render, test, publish), test.yml (schema, install), keepalive.yml
```

MIT licensed, see `LICENSE`.
