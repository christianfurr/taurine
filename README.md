<p align="center">
  <img src="docs/assets/banner.png" alt="TAURINE — Lid down. Jobs up." width="100%" />
</p>

<p align="center">
  <a href="https://github.com/christianfurr/taurine/actions/workflows/checks.yml"><img src="https://github.com/christianfurr/taurine/actions/workflows/checks.yml/badge.svg" alt="Build and tests" /></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-191919?style=flat-square&logo=apple&logoColor=F3F0DF" alt="macOS 13 or later" />
  <img src="https://img.shields.io/badge/Swift-native-F05138?style=flat-square&logo=swift&logoColor=white" alt="Native Swift" />
  <img src="https://img.shields.io/badge/MCP-3_tools-D3EE42?style=flat-square&labelColor=191919&color=D3EE42" alt="Three MCP tools" />
  <img src="https://img.shields.io/badge/Codex-skill_ready-D3EE42?style=flat-square&labelColor=191919&color=D3EE42" alt="Codex skill included" />
</p>

<p align="center">
  <b>Your laptop gets to close. Your agents are still on the clock.</b><br />
  A native macOS menu bar app for keeping your Mac awake with the lid down.<br />
  Named after the energy drink ingredient. Built for the one-more-task industrial complex.
</p>

<p align="center">
  <a href="https://github.com/christianfurr/taurine/releases/latest"><b>Download</b></a> ·
  <a href="#build-it-yourself">Build it yourself</a> ·
  <a href="#give-your-agent-the-switch">MCP + skill</a> ·
  <a href="docs/OPERATIONS.md">Under the hood</a>
</p>

---

## The whole pitch

Close the lid. Leave the Mac on a desk. Keep the remote session and the long-running agent job alive.

Taurine lives in the menu bar. Click the lightning bolt, turn it on, and approve the macOS administrator prompt. A filled bolt and **On** appear after the sleep setting is applied and read back. Turn it off when you're done.

| What you get | What it does |
| --- | --- |
| **Lid-closed keep-awake** | Uses the system sleep control, beyond an ordinary idle-sleep assertion. |
| **A real native app** | AppKit menu bar UI, Swift, and a small C watchdog. |
| **Cleanup on exit** | Restores the previous sleep setting on off, quit, app crash, or socket disconnect. |
| **A heartbeat** | Restores the previous setting if the app goes silent for 15 seconds. |
| **A battery floor** | Stops at 10% or below while unplugged. |
| **Agent controls** | Three MCP tools and a reusable Codex skill. Disable has a safe preview. |

The display can turn off. The Mac can stay locked. Keep it ventilated, and turn Taurine off before putting the laptop in a bag.

## Get it running

[Download the Apple Silicon build](https://github.com/christianfurr/taurine/releases/download/v1.1.0/Taurine-macOS-arm64.zip), unzip it, and move **Taurine.app** to Applications. Open it and look for the lightning bolt in the menu bar.

The download is locally signed, **not notarized**. If macOS blocks it, build from source. Requires macOS 13 or later; the published binary is arm64. Intel builds have not been tested.

### Build it yourself

With Apple's Command Line Tools installed:

```sh
git clone https://github.com/christianfurr/taurine.git
cd taurine
./scripts/build.sh
```

The script prints the signed app's path and writes `build/Taurine.zip`. Build output uses the host architecture. Signing happens outside synced Documents folders because file-provider metadata can invalidate an app bundle.

## Give your agent the switch

Install [Codex CLI](https://developers.openai.com/codex/cli/) and Python 3.11 or later. The menu bar app itself has no external packages; the optional MCP server uses the official Python MCP SDK.

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install 'mcp>=2.1.1,<3'
./scripts/build-automation.sh
python scripts/install-automation.py
```

The installer registers the local **taurine** MCP server, installs **$taurine-control**, and backs up the existing Codex configuration. Use a new Codex task to load the tools. The skill has a CLI fallback for tasks whose tool catalog was already loaded.

> “Check Taurine status.”<br />
> “Keep my Mac awake.”<br />
> “Turn Taurine off and allow sleep.”

| Tool | Behavior |
| --- | --- |
| `taurine_status` | Reads the awake setting, app/watchdog state, lid, and battery. |
| `taurine_enable` | Does nothing if already awake; otherwise requests enable and verifies the result. |
| `taurine_disable` | Requires `confirm_allow_sleep=true`. Schedules a graceful quit after three seconds so the reply can reach you first. |

**Try the preview before the real thing:**

```sh
python "$HOME/.local/share/taurine/taurine-control/control.py" status
python "$HOME/.local/share/taurine/taurine-control/control.py" disable \
  --confirm-allow-sleep --dry-run
```

A new awake session can require administrator approval at the Mac. Disabling allows sleep and may suspend your tasks or disconnect remote access. It does not shut down the Mac, force sleep, or wake an already-sleeping machine. A scheduled request is reported as scheduled, not completed.

Existing Caffeine installations are recognized for compatibility. Installation does not restart an active legacy session; the Taurine app is installed separately for a later enable request.

## The part where macOS has opinions

Taurine uses `pmset -a disablesleep 1` through a temporary privileged helper. The helper restores the value it found at startup. It does not install a persistent privileged service or change your other power preferences.

If sleep was already disabled, turning Taurine off preserves that previous state. If the privileged helper itself is killed or the Mac loses power before restoration, the setting can persist. To restore normal sleep manually:

```sh
sudo pmset -a disablesleep 0
```

That command allows sleep immediately. Do not run it while you need a lid-closed session to keep working.

## Checks with receipts

```sh
./scripts/test.sh                 # Watchdog protocol, ASan + UBSan
python3 tests/automation_test.py  # Automation with all writes mocked
```

The GitHub workflow builds and verifies both native binaries and runs the isolated tests. It never enables or disables sleep on the runner.

A live Mac also reported its lid closed and system sleep disabled while remote commands continued to execute. MCP status, already-on enable, disable preview, and rejection of an unconfirmed disable were verified without restarting the active app or watchdog. Real remote disable and a fresh privileged enable have not been exercised end to end. See [verification details](docs/OPERATIONS.md#verification).

---

<p align="center"><sub>Lid down. Jobs up. Energy drink sold separately.</sub></p>
