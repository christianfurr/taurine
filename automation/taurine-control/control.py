"""Narrow controls for the locally installed Taurine app. No shell execution."""

import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parent
BRIDGE = ROOT / "bin" / "taurine-control"


def run(*arguments: str) -> str:
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=10).stdout


def status() -> dict:
    power = run("/usr/bin/pmset", "-g")
    disabled_line = re.search(r"^\s*SleepDisabled\s+([01])\s*$", power, re.MULTILINE)
    disabled = disabled_line is not None and disabled_line[1] == "1"
    apps = json.loads(run(str(BRIDGE), "inspect"))["apps"]
    processes = run("/bin/ps", "-axo", "pid=,uid=,comm=")
    helpers = []
    for line in processes.splitlines():
        fields = line.strip().split(maxsplit=2)
        if len(fields) == 3 and fields[1] == "0" and fields[2].endswith((
            "/Taurine.app/Contents/MacOS/TaurinePower",
            "/Caffeine.app/Contents/MacOS/CaffeinePower",
        )):
            helpers.append(int(fields[0]))
    lid = run("/usr/sbin/ioreg", "-r", "-k", "AppleClamshellState", "-d", "4")
    lid_match = re.search(r'"AppleClamshellState"\s*=\s*(Yes|No)', lid)
    battery = run("/usr/bin/pmset", "-g", "batt")
    percent = re.search(r"(\d+)%;", battery)
    return {
        "taurine_enabled": bool(disabled and apps and helpers),
        "system_sleep_disabled": disabled,
        "app_pids": [app["pid"] for app in apps],
        "watchdog_pids": helpers,
        "lid_closed": None if lid_match is None else lid_match[1] == "Yes",
        "battery_percent": int(percent[1]) if percent else None,
        "on_battery": "'Battery Power'" in battery,
    }


def enable() -> dict:
    before = status()
    if before["system_sleep_disabled"]:
        return {"changed": False, "status": before,
                "message": "Already keeping awake." if before["taurine_enabled"] else "System sleep is already disabled by an existing setting; no change made."}
    requested = json.loads(run(str(BRIDGE), "enable"))
    if "error" in requested:
        raise RuntimeError(requested["error"])
    # Report actual readback separately from an authorization request.
    after = before
    for _ in range(5):
        time.sleep(0.4)
        after = status()
        if after["taurine_enabled"]:
            return {"changed": True, "status": after}
    return {"changed": False, "enable_requested": True, "status": after,
            "message": "Taurine was asked to enable. macOS administrator approval may still be pending; keep-awake is not confirmed."}


def disable(*, confirm_allow_sleep: bool, dry_run: bool = False) -> dict:
    if confirm_allow_sleep is not True:
        raise ValueError("Set confirm_allow_sleep=true only after the user explicitly asks to allow sleep. This may disconnect remote access and suspend tasks.")
    before = status()
    if not before["app_pids"]:
        if before["system_sleep_disabled"]:
            raise RuntimeError("Sleep is disabled without a running Taurine app. No system settings were changed.")
        return {"changed": False, "status": before, "message": "Taurine is already off."}
    if len(before["app_pids"]) != 1:
        raise RuntimeError("Multiple Taurine apps are running. No quit request was sent.")
    plan = {"action": "request_taurine_quit", "pid": before["app_pids"][0],
            "delay_seconds": 3, "may_disconnect_remote_access": True,
            "message": "Quitting Taurine restores its previous sleep setting. This allows sleep; it does not force sleep or shut down the Mac."}
    if dry_run:
        return {"dry_run": True, "changed": False, "plan": plan, "status": before}
    child = subprocess.Popen(
        [str(BRIDGE), "disable", str(plan["pid"]), "--confirm-allow-sleep"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return {"disable_scheduled": True, "request_process_pid": child.pid, "plan": plan,
            "message": "A quit request is scheduled in 3 seconds. Completion is not yet confirmed; the remote connection may drop before readback."}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Control Taurine on this Mac.")
    parser.add_argument("action", choices=["status", "enable", "disable"])
    parser.add_argument("--confirm-allow-sleep", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    options = parser.parse_args()
    try:
        if options.action == "status":
            result = status()
        elif options.action == "enable":
            if options.dry_run:
                result = {"dry_run": True, "changed": False, "status": status()}
            else:
                result = enable()
        else:
            result = disable(confirm_allow_sleep=options.confirm_allow_sleep, dry_run=options.dry_run)
        print(json.dumps(result, indent=2))
    except Exception as error:
        print(json.dumps({"error": str(error)}))
        raise SystemExit(1)
