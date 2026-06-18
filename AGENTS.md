# sing-box-deve repo rules

This repository is a Bash/Node deployment tool. Keep changes conservative, reversible, and verified against the same checks that GitHub Actions runs.

## Before every push

Do not push unless the repo-level pre-push GitHub-CI-equivalent suite passes from the repository root:

```bash
bash scripts/sing-box-deve-pre-push.sh
```

This is mandatory even for small fixes. In particular, always include:

- `bash scripts/test-module-size.sh` — catches the max-400-lines shell-file gate used by GitHub CI;
- shell syntax: `bash -n sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh`;
- shellcheck over `sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh`;
- Node syntax for web-generator files;
- CLI/update/firewall/web schema/ruleset smoke tests;
- checksum regeneration check: `./scripts/update-checksums.sh` followed by a clean `checksums.txt` diff or explicit staged checksum update;
- `git diff --check`.

If a check cannot run locally, record the exact blocker before asking to push. Do not assume GitHub CI will catch it later.

## After every push

After pushing to `main`, inspect the GitHub Actions result instead of assuming the push is healthy:

```bash
gh run list --branch main --limit 5
gh run view <run-id> --log-failed
```

Report whether the relevant workflow is `success`, `failure`, or still `in_progress`/`queued`.

## Hook policy

Install the repository pre-push hook on local checkouts used for development:

```bash
bash scripts/install-git-hooks.sh
```

The hook runs `bash scripts/sing-box-deve-pre-push.sh` before allowing `git push`. Bypass only for emergencies with `SBD_SKIP_PRE_PUSH=1 git push ...`, and explain the reason in the handoff.

## Update/checksum discipline

When adding, deleting, or splitting managed files:

1. update `lib/update_manifest.sh`;
2. run `./scripts/update-checksums.sh`;
3. verify `sha256sum -c checksums.txt`;
4. rerun `bash scripts/sing-box-deve-pre-push.sh` before commit/push.

## Runtime-vs-checkout discipline

- Use `sb ...` for an installed host/runtime.
- Use `./sing-box-deve.sh ...` for the current source checkout.
- Do not make `/usr/local/bin/sb` opportunistically follow the current working directory checkout; the launcher should follow installed runtime `script_root`.
