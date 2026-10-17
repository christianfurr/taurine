import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("taurine_control", ROOT / "automation/taurine-control/control.py")
control = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(control)

AWAKE = {"taurine_enabled": True, "system_sleep_disabled": True, "app_pids": [1234],
         "watchdog_pids": [4321], "lid_closed": True, "battery_percent": 78, "on_battery": True}


class AutomationTests(unittest.TestCase):
    def test_status_reads_live_os_outputs(self):
        samples = ["System-wide power settings:\n SleepDisabled\t\t1\n", '{"apps":[{"pid":1234}]}',
                   "4321 0 /Users/test/Applications/Taurine.app/Contents/MacOS/TaurinePower\n",
                   '"AppleClamshellState" = Yes', "Now drawing from 'Battery Power'\n78%; discharging"]
        with patch.object(control, "run", side_effect=samples):
            self.assertEqual(control.status(), AWAKE)

    def test_enable_already_awake_does_not_launch_or_change_anything(self):
        with patch.object(control, "status", return_value=AWAKE), patch.object(control, "run") as run:
            self.assertFalse(control.enable()["changed"])
            run.assert_not_called()

    def test_legacy_caffeine_watchdog_is_recognized(self):
        samples = ["System-wide power settings:\n SleepDisabled\t\t1\n", '{"apps":[{"pid":1234}]}',
                   "4321 0 /Users/test/Applications/Caffeine.app/Contents/MacOS/CaffeinePower\n",
                   '"AppleClamshellState" = Yes', "Now drawing from 'Battery Power'\n78%; discharging"]
        with patch.object(control, "run", side_effect=samples):
            self.assertEqual(control.status(), AWAKE)

    def test_disable_without_explicit_flag_never_reads_or_mutates(self):
        with patch.object(control, "status") as status, patch.object(control.subprocess, "Popen") as spawn:
            with self.assertRaises(ValueError):
                control.disable(confirm_allow_sleep=False)
            status.assert_not_called()
            spawn.assert_not_called()

    def test_dry_run_never_starts_quit_process(self):
        with patch.object(control, "status", return_value=AWAKE), patch.object(control.subprocess, "Popen") as spawn:
            result = control.disable(confirm_allow_sleep=True, dry_run=True)
            self.assertTrue(result["dry_run"])
            self.assertFalse(result["changed"])
            self.assertEqual(result["plan"]["pid"], 1234)
            spawn.assert_not_called()

    def test_real_disable_only_schedules_specific_taurine_quit(self):
        with patch.object(control, "status", return_value=AWAKE), patch.object(control.subprocess, "Popen", return_value=Mock(pid=9876)) as spawn:
            result = control.disable(confirm_allow_sleep=True)
            self.assertTrue(result["disable_scheduled"])
            self.assertNotIn("changed", result)
            self.assertEqual(spawn.call_args.args[0], [str(control.BRIDGE), "disable", "1234", "--confirm-allow-sleep"])
            self.assertEqual(spawn.call_args.kwargs["start_new_session"], True)

    def test_external_sleep_disable_is_not_reset(self):
        external = {**AWAKE, "app_pids": [], "watchdog_pids": [], "taurine_enabled": False}
        with patch.object(control, "status", return_value=external), patch.object(control.subprocess, "Popen") as spawn:
            with self.assertRaises(RuntimeError):
                control.disable(confirm_allow_sleep=True)
            spawn.assert_not_called()

    def test_multiple_instances_never_chooses_arbitrary_target(self):
        with patch.object(control, "status", return_value={**AWAKE, "app_pids": [1, 2]}), patch.object(control.subprocess, "Popen") as spawn:
            with self.assertRaises(RuntimeError):
                control.disable(confirm_allow_sleep=True)
            spawn.assert_not_called()

    def test_enable_reports_pending_until_readback_confirms(self):
        off = {**AWAKE, "system_sleep_disabled": False, "taurine_enabled": False}
        with patch.object(control, "status", return_value=off), patch.object(control, "run", return_value='{"enable_requested":true}'), patch.object(control.time, "sleep"):
            result = control.enable()
            self.assertFalse(result["changed"])
            self.assertTrue(result["enable_requested"])


if __name__ == "__main__":
    unittest.main()
