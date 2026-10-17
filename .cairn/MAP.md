---
verified_at_sha: uncommitted
verified_at: 2026-10-17
---
# Taurine

Native macOS menu bar utility for keeping this Mac reachable with its lid closed.

- `Sources/Taurine.swift`: AppKit status item, native menu, authorization and session lifecycle.
- `Sources/PowerSession.c`: privileged, temporary watchdog; applies and restores only `disablesleep`.
- `Sources/TaurineControl.swift`: native automation bridge; reads instances, requests enable, and schedules graceful quit.
- `scripts/build.sh`: builds and signs a macOS 13+ app bundle.
- `automation/taurine-control/`: local MCP server, CLI, plugin manifests, and reusable skill.
- `scripts/build-automation.sh` and `scripts/install-automation.py`: build and install without restarting the active app.
- `tests/automation_test.py`: isolated automation tests; `tests/verify_mcp.py`: safe live MCP verification.
- `README.md`: operation, limits, recovery, and verification.

Build bundles outside synced Documents in `~/Library/Caches/com.christianfurr.Taurine/build/`;
the project artifact is `build/Taurine.zip`. The installed app belongs in `~/Applications`.

Public source is branded Taurine, with the `taurine` MCP and `taurine-control` skill.
The author's existing `caffeine` MCP/skill and running Caffeine app remain installed
unchanged; publishing never migrates or restarts the active power session. The new
bridge supports both bundle IDs and the helper retains the shared legacy lock.

- `docs/assets/banner.png`: README banner; its generation prompt sits beside it.
- `docs/OPERATIONS.md`: power lifecycle, compatibility, installation, and verification limits.
- `.github/workflows/checks.yml`: macOS build/signature checks and isolated tests.

During maintenance, never disable sleep prevention or restart the active app/watchdog.
Live verification uses status, already-on enable, and disable with `dry_run=true` only.
No web endpoint, shutdown, forced sleep, remote wake, or remote access provisioning is included.
