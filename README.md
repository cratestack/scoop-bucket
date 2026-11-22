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

Nobody edits `bucket/corntchap-cli.json` by hand. The `update` workflow runs hourly (and on demand: Actions, update, Run workflow, optionally with a tag) and:

1. asks GitHub for the latest release of `cratestack/corntchap`; no release yet means it exits quietly;
2. downloads that release's `corntchap-cli-windows-x86_64.zip.sha256` (a `<hex>  <file>` line);
3. runs `scripts/render-manifest.sh`, which rewrites `version`, the download `url` and `hash` (everything else, `checkver` and `autoupdate` included, is kept) and refuses anything suspicious (below);
4. commits `corntchap-cli <version>` as `github-actions[bot]` only if the manifest changed, then runs the install test against that commit.

| Check | Effect |
| --- | --- |
| the tag must be exactly `vMAJOR.MINOR.PATCH` | anything else (quotes, `;`, pre-release suffixes, newlines) fails before it reaches the manifest |
| the release must list the windows zip and its `.sha256` as assets | missing asset: fail, nothing is committed |
| the hash must be 64 lowercase hex characters and name the zip | fail |
| the release must not be older than the manifest | exit 10, the manifest is left alone (never a downgrade) |
| the manifest's own current version must be `MAJOR.MINOR.PATCH` | fail (the downgrade check cannot run) |

Values reach the JSON only through `jq --arg`. Runs are serialised (`concurrency: update-manifest`), the job uses only its own `GITHUB_TOKEN` (`contents: write`, scoped to this job), and actions are pinned to major versions.

`checkver` and `autoupdate` stay in the manifest, so Scoop's own `checkver.ps1 -Update` / Excavator work too if you prefer them; the workflow does not depend on Scoop's tooling.

`tests/render-manifest.test.sh` runs the script against fake releases, one test per check; `tests/mutate.sh` removes each check in turn and fails if the tests still pass. The `test` workflow runs both, validates the manifest against [Scoop's schema](https://github.com/ScoopInstaller/Scoop/blob/master/schema.json) (pinned to a commit) and, once the manifest has a real hash, runs `scoop install` on `windows-latest` and checks `corntchap-cli --version`.

## Before the first release

Until corntchap `v0.1.0` exists, the manifest carries an all-zero placeholder `hash` (`000…0`) and installing it fails on purpose. The first `update` run after the release replaces it; the install test is skipped while it is present. The default branch must accept pushes from `github-actions[bot]` (no PR-only branch protection), otherwise the commit step fails.

## Layout

```
bucket/corntchap-cli.json     the manifest (generated fields: version, url, hash)
scripts/render-manifest.sh    release -> manifest, with the checks above
tests/                        script tests + mutation check
.github/workflows/            update.yml (poll + commit), test.yml (schema, install)
```

MIT licensed, see `LICENSE`.
