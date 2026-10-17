# Operations

## Power session

Taurine uses `/usr/bin/pmset -a disablesleep 1` through a temporary helper launched with macOS administrator authorization. Apple's [pmset source](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m) implements `disablesleep` and prints its state as `SleepDisabled`.

The app and helper use a private Unix socket and verify peer user identities. A system-wide lock excludes overlapping sessions. The helper saves the original sleep setting and restores it on explicit stop, graceful quit, app crash/socket disconnect, a missed 15-second heartbeat, or battery at or below 10% while unplugged.

Only the `disablesleep` setting changes. If the original value was already 1, restoring it leaves sleep disabled. Display sleep and locking stay available. The system-wide setting can persist if the privileged helper itself is forcibly killed or power is lost before cleanup. Manual recovery is `sudo pmset -a disablesleep 0`; this can immediately interrupt a closed-lid session.

## Automation

The local stdio server uses the official Python MCP SDK 2.x. It accepts only status, enable, and disable operations; subprocess arguments are fixed and no shell command string is evaluated. Disable requires an explicit confirmation flag. Its preview mode does not start a quit process. A real request targets one specific Taurine process and requests graceful termination after three seconds. The response confirms scheduling, not completion; the Mac can sleep before readback.

Enable is idempotent when sleep is already disabled. A new privileged session can need local administrator approval. Remote wake, full shutdown, reboot, forced sleep, network provisioning, and login item setup are outside this tool.

Runtime files live under `~/.local/share/taurine/`. The skill is linked from `~/.codex/skills/taurine-control`, and the server is registered as `taurine` using `codex mcp add`. The installer backs up Codex configuration and refuses to overwrite an active automation-ready app.

Keep the virtual environment used for installation: Codex registration stores its Python executable path. Moving or deleting that environment requires reinstalling the integration.

## Legacy compatibility

The native bridge recognizes both `com.christianfurr.Taurine` and the former `com.christianfurr.Caffeine` bundle identifier. Status recognizes both watchdog executable paths. The helper retains the original Caffeine lock filename so old and new sessions cannot race to restore the setting. The new app is installed separately; an active legacy app is not modified or restarted.

## Build and signatures

`scripts/build.sh` compiles the host architecture with a macOS 13 minimum, signs in a temporary folder, verifies the bundle, copies the app into `~/Library/Caches/com.christianfurr.Taurine/build/`, and saves `build/Taurine.zip`.

`scripts/build-automation.sh` also compiles the native bridge. All signatures are local/ad hoc. Release binaries are not Developer ID notarized. Intel builds have not been tested.

## Verification

The helper tests run the actual socket protocol with an in-memory power backend under AddressSanitizer and UndefinedBehaviorSanitizer. They cover parsing, enable/readback/disable, preserving an original disabled setting, disconnect cleanup, heartbeat expiry, partial enable failure, low battery at startup and during a session, cancellation, and invalid commands.

Automation tests mock process creation and cover status parsing, legacy watchdog recognition, idempotent enable, confirmation rejection, safe preview, scheduling a specific process, refusing external setting changes, refusing ambiguous instances, and reporting pending authorization truthfully.

During a live session on October 17, 2026, the OS reported `AppleClamshellState = Yes` and `SleepDisabled 1` while commands continued executing. An actual MCP client initialized the server, discovered the three tools, read status, verified a no-op enable, previewed disable, and verified rejection without confirmation. The active app and watchdog PIDs remained unchanged.

Real remote disable and a new administrator-authorized enable have not been exercised end to end. Fresh remote reconnection, overnight operation, and different Mac models or OS versions have not been verified. These limits apply even if the isolated tests or build are green.

To run the safe live checks against an active session, with the SDK installed:

```sh
python3 tests/verify_mcp.py --server-root automation/taurine-control
```

This expects keep-awake to already be enabled and never tests real disable. Native UI inspection was unavailable during the original build; build/signature verification is not visual UI verification.
