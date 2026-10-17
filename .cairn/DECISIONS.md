# Decisions

- 2026-10-17: Use AppKit and a bundled C watchdog, with no external packages.
- 2026-10-17: Lid closure requires the system sleep setting; idle sleep assertions alone do not cover the requested behavior. Request macOS administrator authorization on enable.
- 2026-10-17: Keep a private local socket open to the watchdog; disconnect, stop, missed heartbeat, or low battery restores the prior setting. Do not install a persistent privileged service.
- 2026-10-17: Leave future skill/MCP control out of this version as requested.
- 2026-10-17: Synced Documents adds FinderInfo metadata to unpacked app bundles, invalidating strict signature checks. Sign outside Documents, save a ZIP in the project, and install in `~/Applications`.
- 2026-10-17: User requested MCP and skill; clarified that off means allow sleep, not shutdown. Do not turn off Caffeine while important Codex tasks run. Install the automation app separately so the active menu app and root watchdog keep their PIDs.
- 2026-10-17: Disable requires an explicit intent flag and has a preview mode. Real disable schedules graceful quit after three seconds so the remote caller can receive the response. Enable still requires macOS approval when starting a new privileged session.
- 2026-10-17: User chose Taurine, after the energy drink ingredient, for public branding and GitHub publication. Keep the current Caffeine installation running; the public bridge recognizes it and the shared watchdog lock remains compatible.
