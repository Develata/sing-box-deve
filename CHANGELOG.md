# Changelog

## v1.0.0-dev.9

- Replaced all 46 direct `systemctl`/`journalctl` calls with init-system-aware `sbd_service_*` wrappers (systemd / OpenRC / nohup dispatch)
- Replaced 86+ hardcoded `/etc/sing-box-deve`, `/var/lib/sing-box-deve`, `/opt/sing-box-deve` paths with `$SBD_CONFIG_DIR` / `$SBD_STATE_DIR` / `$SBD_INSTALL_DIR` variables
- Added 5 new service helpers: `sbd_service_daemon_reload`, `sbd_service_unit_exists`, `sbd_service_is_enabled`, `sbd_service_enable_oneshot`, `sbd_service_disable_oneshot`
- Fixed all ShellCheck warnings (SC2086, SC2015, SC2034)
- Added GitHub Pages deployment workflow and root `index.html`
- Enhanced web-generator with theme toggle, UUID generation, and CDN endpoint selection
- Stabilized Docker regression test image for CI

## v1.0.0-dev.8

- Hardened runtime/env loading and rollback consistency
- Added `sbd_safe_load_env_file` for safe environment variable loading
- Enhanced port mapping and rollback handling
- Added full regression workflow for MCP-based testing

## v1.0.0-dev.7

- Added multi-port support and jump store functionality (`jump set/show/clear`)
- Added WARP and multi-port jump features to protocol matrix
- Enhanced argument parsing with required value checks
- Improved uninstall verification
- Modularized files over 250 lines (enforced ≤400 lines CI)
- Updated CLI usage with panel status alias and install options
- Updated plan document with target specifications and engineering constraints

## v1.0.0-dev.6

- Added Psiphon sidecar support with routing, CLI, and config integration
- Modularized network protocol inbound generation (sing-box/xray split)
- Rewrote `providers_nodes.sh` for improved node management
- Added protocol management menu section
- Added Git-based update support and uninstall verification
- Added `ARGO_CDN_ENDPOINTS` support for enhanced configuration
- Added rollback functionality for update safety
- Refactored update mechanism with unified file manifest
- Persisted script installation to fixed location for reliable `sb` command access

## v1.0.0-dev.5

- Added port egress mapping functionality (`set-port-egress --map/--clear`)
- Enhanced update script checksum validation with missing entry warnings
- Added cache invalidation handling for version fetching
- Updated client share groups with v2rayng support
- Enhanced clash-meta configuration generation
- Improved logging and bilingual message support across provider scripts
- Refactored code structure for improved readability

## v1.0.0-dev.4

- Added persistent one-line settings management (`settings show/set`, language persistence)
- Added secure-by-default interactive confirmations with Enter-to-default behavior
- Added version display and update command split (`--script`, `--core`, `--all`)
- Added Argo/WARP diagnostics and richer doctor checks
- Added Serv00/SAP batch JSON validation and batch summary reporting
- Added static web generator enhancements and examples
- Added docs split (`Serv00`, `SAP`, `Docker`) and docs index
- Added CI workflow, checksum manifest, acceptance matrix helper script
- Added outbound upstream proxy mode (`direct/socks/http/https`) for egress forwarding
