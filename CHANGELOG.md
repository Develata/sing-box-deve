# Changelog

All notable changes to this project are documented in this file.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style: entries are grouped by version and by change type (`Added`, `Changed`, `Fixed`, `Removed`, `Security`). Version numbers follow the repository `version` file and use SemVer-like `major.minor.patch` numbering.

## [Unreleased]

### Added

- Added managed nginx/OpenResty web-front support for domain deployments, with selection order: existing OpenResty → existing nginx → optional official nginx install.
- Added nginx/OpenResty webroot ACME flow for trusted certificate issuance; `acme-auto` no longer uses standalone mode.
- Added `reality-only`, `reality-plus-domain`, and `full` deployment presets, including fail-fast TLS certificate gates for domain-backed protocols.
- Added archive-gateway static site generation for domain camouflage / browser-facing fallback surfaces.
- Added optional Hysteria2 `salamander` obfs support; kept obfs disabled by default and `gecko` gated as experimental/unsupported for current stable flow.
- Added `cfg profile <lite|full>` to switch an installed runtime between resource profiles without hand-editing `runtime.env`.
- Added repo-level pre-push guard mirroring GitHub CI checks.
- Added web-generator schema synchronization checks to prevent frontend/backend option drift.

### Changed

- Changed automatic ACME signing to require nginx/OpenResty webroot mode, preventing TCP 80 conflicts with managed web-front deployments.
- Changed `sb` launcher authority so installed runtime `script_root` wins over incidental current checkout directories.
- Changed default `update` behavior to update script files only; core updates require explicit `--core` or `--all`.
- Changed domain protocol behavior so generated links/configs no longer default to insecure certificate skipping.
- Changed runtime rebuild paths to use shared domain artifact preparation, so certificate/static-site invariants are checked across config rebuild, routing, egress, and protocol changes.
- Changed public protocol surface toward a smaller recommended set: `vless-reality`, `vless-ws`, `shadowsocks-2022`, `naive`, `hysteria2`, `tuic`; `vless-xhttp` remains as xray compatibility.
- Changed README and validation notes to distinguish locally verified CI checks from real-host ACME/nginx/client interoperability limits.

### Fixed

- Fixed nginx.org signing-key verification across `gpg` output variants by parsing fingerprint records directly.
- Fixed nginx config inclusion verification for hosts whose `nginx -T` dump does not include the managed config by absolute path.
- Fixed OS detection before official nginx auto-install.
- Fixed gawk `include` variable collision in OpenResty config patching logic.
- Fixed user-mode uninstall behavior so root-owned global launchers are ignored instead of failing tests.
- Fixed systemd daemon-reload handling under `set -e` so non-systemd/user-mode environments can continue safely.
- Fixed CLI smoke tests to isolate host `sshpass` availability assumptions.
- Fixed runtime edge cases around certificate gates, web-front TCP 443 conflicts, rollback, and generated config validation.

### Removed

- Removed legacy/excess public features from the mainline: SAP Cloud Foundry provider, Workers templates, Psiphon sidecar, SFW Windows packaging, GitLab/TG subscription push, jump port hopping, `set-share`, `set-port-egress`, `anytls`, and `trojan` public inbound generation.
- Removed standalone ACME as the automatic signing path for managed domain presets.

## [v1.0.6]

### Fixed

- Fixed domain-certificate auto-detection under `set -u` so existing local ACME certificates do not trigger an unbound `cert` variable during full/domain installs.

## [v1.0.5]

### Fixed

- Fixed menu options that were displayed but not handled for protocol removal, multi-port removal, and config-center multi-port management; added a menu consistency regression check.

## [v1.0.4]

### Changed

- Changed the default Reality SNI/handshake server from `www.microsoft.com` to `www.bing.com` for new installs.

## [v1.0.3]

### Changed

- Clarified install/update script authority between Git checkouts and persisted script copies.
- Hardened `sb` launcher verification so script updates fail if the launcher points to the wrong target.
- Improved core update rollback behavior and update regression coverage.

## [v1.0.1]

### Changed

- Switched script release versions to plain numeric `major.minor.patch` format.
- Replaced development-suffix version ordering with simple numeric dotted version comparison.

### Added

- Added a regression check for version comparisons used by script self-update.

## [v1.0.0-dev.12]

### Changed

- Updated GitHub Actions checkout usage to `actions/checkout@v6` with least-privilege `contents: read` permissions.
- Hardened container bootstrap fallback downloads with release digest verification for sing-box.
- Expanded CI coverage for container startup scripts, JavaScript syntax, Clash ruleset generation, non-root dry-run, and checksum validation.

## [v1.0.0-dev.9]

### Added

- Added GitHub Pages deployment workflow and root `index.html`.
- Added web-generator theme toggle, UUID generation, and CDN endpoint selection.
- Added service helpers: `sbd_service_daemon_reload`, `sbd_service_unit_exists`, `sbd_service_is_enabled`, `sbd_service_enable_oneshot`, and `sbd_service_disable_oneshot`.

### Changed

- Replaced direct `systemctl`/`journalctl` usage with init-system-aware `sbd_service_*` wrappers for systemd, OpenRC, and nohup dispatch.
- Replaced hardcoded `/etc/sing-box-deve`, `/var/lib/sing-box-deve`, and `/opt/sing-box-deve` paths with runtime path variables.
- Stabilized the regression test environment for CI.

### Fixed

- Fixed ShellCheck warnings that were present in the refactor window.

## [v1.0.0-dev.8]

### Added

- Added `sbd_safe_load_env_file` for safer runtime environment loading.
- Added full regression workflow for MCP-based testing.

### Changed

- Hardened runtime/env loading and rollback consistency.
- Enhanced port mapping and rollback handling.

## [v1.0.0-dev.7]

### Added

- Added panel status alias and expanded install options in CLI usage.
- Added target specifications and engineering constraints to the planning document.

### Changed

- Enhanced argument parsing with required value checks.
- Improved uninstall verification.
- Modularized shell files to respect the repository size gate.

## [v1.0.0-dev.6]

### Added

- Added Psiphon sidecar support with routing, CLI, and config integration.
- Added protocol management menu section.
- Added Git-based update support and uninstall verification.
- Added `ARGO_CDN_ENDPOINTS` support.
- Added rollback functionality for update safety.

### Changed

- Modularized network protocol inbound generation across sing-box and xray.
- Rewrote node management for clearer output and regeneration.
- Refactored update flow with a unified manifest.
- Persisted script installation to a fixed location for reliable `sb` command access.

## [v1.0.0-dev.5]

### Added

- Added cache invalidation handling for version fetching.
- Added v2rayNG support in client share groups.

### Changed

- Enhanced update checksum validation with missing-entry warnings.
- Enhanced Clash Meta config generation.
- Improved bilingual logging across provider scripts.
- Refactored script structure for readability.

## [v1.0.0-dev.4]

### Added

- Added persistent one-line settings management via `settings show/set` and language persistence.
- Added secure-by-default interactive confirmations with Enter-to-default behavior.
- Added version display and update command split: `--script`, `--core`, `--all`.
- Added Argo/WARP diagnostics and richer `doctor` checks.
- Added Serv00 batch JSON validation and batch summary reporting.
- Added static web generator enhancements and examples.
- Added docs index, CI workflow, checksum manifest, and acceptance matrix helper.
- Added outbound upstream proxy mode (`direct`, `socks`, `http`, `https`).
