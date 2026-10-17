#!/usr/bin/env python3
"""Install automation without replacing or restarting the active menu bar app."""
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

try:
    from mcp.server.mcpserver import MCPServer
except ImportError:
    raise SystemExit("This Python needs mcp 2.x installed before registration.")

project = Path(__file__).resolve().parents[1]
source = project / "automation/taurine-control"
destination = Path.home() / ".local/share/taurine/taurine-control"
app = destination.parent / "Taurine.app"
skill = Path.home() / ".codex/skills/taurine-control"
codex = shutil.which("codex")
if not codex:
    raise SystemExit("Codex CLI is required for MCP registration.")

bridge = source / "bin/taurine-control"
running = json.loads(subprocess.check_output([str(bridge), "inspect"], text=True))["apps"]
if any(entry["path"] == str(app) for entry in running):
    raise SystemExit("The automation app is currently running. Do not replace it during an active session.")
if skill.exists() and skill.resolve() != destination / "skills/taurine-control":
    raise SystemExit("An unrelated taurine-control skill already exists; it was not replaced.")

destination.mkdir(parents=True, exist_ok=True)
shutil.copytree(source, destination, dirs_exist_ok=True, copy_function=shutil.copy,
                ignore=shutil.ignore_patterns("__pycache__", ".venv", "*.pyc"))
cached_app = Path.home() / "Library/Caches/com.christianfurr.Taurine/build/Taurine.app"
subprocess.run(["/usr/bin/ditto", "--norsrc", "--noextattr", str(cached_app), str(app)], check=True)
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(destination / "bin/taurine-control")], check=True)
skill.parent.mkdir(parents=True, exist_ok=True)
if not skill.exists():
    skill.symlink_to(destination / "skills/taurine-control", target_is_directory=True)

config = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))) / "config.toml"
if config.exists():
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = config.with_name(f"config.toml.taurine-backup-{stamp}")
    shutil.copyfile(config, backup)
    backup.chmod(0o600)
subprocess.run([codex, "mcp", "add", "taurine", "--", sys.executable, str(destination / "server.py")], check=True)
print(f"Installed skill: {skill}")
print(f"Installed server: {destination / 'server.py'}")
print("Existing menu bar app and watchdog were not restarted or modified.")
