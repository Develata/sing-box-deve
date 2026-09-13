# Contributing

Thanks for your interest in contributing to `sing-box-deve`.

## Development Notes

- Keep shell scripts POSIX-friendly where practical, and run `bash -n` checks before submitting.
- Preserve security-first defaults (no firewall disable/flush behavior).
- Keep interactive UX clear: explain each choice and allow Enter for default values.

## Verification tools and updates

Use Node.js 24 LTS and a supported stable Python (CI uses Python 3.14). Install
the pinned tools in an isolated environment before running the full suite:

```bash
python3 -m venv /tmp/sbd-verification-venv
source /tmp/sbd-verification-venv/bin/activate
timeout --kill-after=15s 180s python3 -m pip install --disable-pip-version-check \
  --no-input --only-binary=:all: --timeout=15 --retries=2 -r scripts/requirements-ci.txt
bash scripts/install-git-hooks.sh
./scripts/update-checksums.sh
bash scripts/sing-box-deve-pre-push.sh
```

`scripts/requirements-ci.txt` owns the ShellCheck/PyYAML versions. The suite
requires the matching ShellCheck binary so an older distro package cannot
silently omit new rules. It does not install tools from inside the Git hook.
Standalone ShellCheck with the same upstream version is also supported.

GitHub Actions use full commit pins with release-version comments. Dependabot
checks Actions and verification dependencies weekly; minor/patch updates are
grouped and major updates remain separate. Update PRs still require review,
checksum regeneration and the complete suite before merge; no auto-merge is
configured. A bot-only dependency bump will fail the checksum gate until its
updated inventory is included. Review upstream release notes and fix supported
new diagnostics instead of disabling analysis to obtain a green result.
Verified indirect fixture calls and deliberate failure guards may use a
per-function directive with an explanatory comment; keep the rule active elsewhere.

Node/Python major versions live in `.github/actions/setup-verification/action.yml`.
Review them at each new LTS/stable release; CI selects the newest patch within
the selected supported major/minor and never opts into prereleases. Self-hosted
acceptance runners need Actions Runner 2.327.1+ for the Node 24 action runtime.
This tooling policy does not change the deployed core update channel: sing-box
and Xray continue to use latest stable releases, including real config and
traffic validation in the full suite.

Core archive downloads resume after transient transport failures, with at most
three attempts of 300 seconds each. Verified archives occupy fixed per-engine/
architecture slots in `.tools/ci-cores` (override with `SBD_TEST_CORE_CACHE_DIR`).
Every run still fetches latest stable metadata and verifies the expected digest;
a stale or corrupt cache is downloaded again. This cache stores no deployments
and is not included in runtime releases.

CI runs `lint` and `regression` stages in parallel. They share the same script
and test inventory as the default full pre-push command; neither stage alone
replaces it. The `checks` job requires both to succeed. Full Regression and
Publish Runtime Release always execute the default full suite.

## Pull Request Checklist

- Update docs when behavior changes (`README.md`, `docs/V1-SPEC.md`).
- Add or update examples in `examples/` when introducing new config options.
- Run the complete pre-push suite above. For a quick syntax-only check:

```bash
for file in sing-box-deve.sh lib/*.sh providers/*.sh scripts/*.sh; do bash -n "$file"; done
```

## Reporting Issues

- Include OS version, provider mode, command used, and full error output.
- If reporting protocol issues, include the enabled protocol list and relevant redacted settings.
