---
name: taurine-control
description: Control the Taurine macOS menu bar app when the user asks to keep this Mac awake, check its lid or awake state, or turn Taurine off and allow sleep remotely.
---

Use the `taurine` MCP server's `taurine_status`, `taurine_enable`, and `taurine_disable` tools. These control the Mac where the server runs. They do not power off the computer.

Read status first. For “keep my Mac awake” or “turn Taurine on”, call `taurine_enable`. If the Mac is already kept awake, this is a no-op. A new session can require local macOS administrator approval; do not report success until status confirms it.

For an explicit request to turn Taurine off or allow sleep, call `taurine_disable` with `confirm_allow_sleep=true`. This schedules a graceful quit in 3 seconds, restoring the previous system sleep setting. Explain that lid sleep may disconnect remote access and suspend running tasks. A scheduled request is not proof of completion. If still connected, read status to verify afterward. If other software prevents sleep, allowing sleep does not force it.

During setup, maintenance, testing, or when the user says tasks must keep running, only read status, use an already-enabled enable no-op, or preview disable with `dry_run=true`. Never test real disable, quit/restart the active app, signal its watchdog, or write power settings in those circumstances.

If “turn off my Mac” is ambiguous, distinguish allowing sleep from full shutdown. This integration has no shutdown, reboot, or forced-sleep action. Once the Mac sleeps, this MCP cannot wake it by itself.

If the MCP tools are not loaded in the current task, use the installed CLI with the shell tool:

```sh
python3 "$HOME/.local/share/taurine/taurine-control/control.py" status
python3 "$HOME/.local/share/taurine/taurine-control/control.py" enable
python3 "$HOME/.local/share/taurine/taurine-control/control.py" disable --confirm-allow-sleep --dry-run
```

Remove `--dry-run` only for an actual user-authorized request to allow sleep. If that path is missing, report the missing local installation; do not substitute `sudo pmset`, kill processes, or shut down the Mac.
