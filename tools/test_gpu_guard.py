#!/usr/bin/env python3
"""Integration checks use a fake nvidia-smi and CPU-only disposable processes."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "tools/gpu_guard.py"


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.plan = self.base / "plan.json"
        self.counter = self.base / "counter"
        self.log = self.base / "events.jsonl"
        self.marker = self.base / "started"
        fake = self.base / "nvidia-smi"
        fake.write_text("#!/usr/bin/env python3\n" + """
import json, os, pathlib, sys, time
base = pathlib.Path(os.environ['GUARD_TEST_DIR'])
steps = json.loads((base/'plan.json').read_text())
counter = base/'counter'
index = int(counter.read_text()) if counter.exists() else 0
counter.write_text(str(index+1))
value = steps[min(index, len(steps)-1)]
if value == 'fail': sys.exit(1)
if value == 'hang': time.sleep(10)
print(value)
"""
        )
        fake.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.base) + os.pathsep + os.environ["PATH"],
                        GUARD_TEST_DIR=str(self.base))

    def command(self, workload=None, launcher=False):
        if workload is None:
            workload = [sys.executable, "-c", f"from pathlib import Path; Path({str(self.marker)!r}).write_text('yes')"]
        if launcher:
            self.env["REDOT_BIN"] = workload[0]
            return [str(ROOT / "tools/run.sh"), *workload[1:]]
        return [sys.executable, str(GUARD), "--log", str(self.log), "--", *workload]

    def run_guard(self, plan, **kwargs):
        self.plan.write_text(json.dumps(plan))
        return subprocess.run(self.command(**kwargs), env=self.env, capture_output=True,
                              text=True, timeout=8)

    def sleeper(self):
        script = self.base / "workload.py"
        script.write_text("""import os, pathlib, signal, subprocess, sys, time
base = pathlib.Path(sys.argv[1])
signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([sys.executable, '-c',
    'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)'])
(base/'pids.json').write_text(__import__('json').dumps([os.getpid(),child.pid]))
time.sleep(30)
""")
        return [sys.executable, str(script), str(self.base)]

    def assert_stopped(self):
        pids = json.loads((self.base / "pids.json").read_text())
        for pid in pids:
            status = Path(f"/proc/{pid}/stat")
            self.assertTrue(not status.exists() or status.read_text().split(") ")[1][0] == "Z",
                            f"owned process {pid} still running")

    def test_74_allowed_and_exit_code_preserved(self):
        result = self.run_guard(["GPU-test, 74"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.marker.exists())
        result = self.run_guard(["GPU-test, 74"], workload=[sys.executable, "-c", "raise SystemExit(7)"])
        self.assertEqual(result.returncode, 7, result.stderr)

    def test_75_refuses_before_launch(self):
        result = self.run_guard(["GPU-test, 75"])
        self.assertEqual(result.returncode, 86, result.stderr)
        self.assertFalse(self.marker.exists())

    def test_all_gpus_checked(self):
        result = self.run_guard(["GPU-cool, 40\nGPU-hot, 75"])
        self.assertEqual(result.returncode, 86, result.stderr)
        self.assertFalse(self.marker.exists())

    def test_runtime_75_kills_group_even_if_term_ignored(self):
        result = self.run_guard(["GPU-test, 74", "GPU-test, 74", "GPU-test, 75"], workload=self.sleeper())
        self.assertEqual(result.returncode, 86, result.stderr)
        self.assertIn('"event": "thermal_stop"', result.stderr)
        self.assert_stopped()

    def test_telemetry_failure_kills_group(self):
        result = self.run_guard(["GPU-test, 40", "GPU-test, 40", "fail"], workload=self.sleeper())
        self.assertEqual(result.returncode, 87, result.stderr)
        self.assert_stopped()

    def test_missing_changed_invalid_or_hung_sensor_refuses(self):
        for value in ("", "GPU-test, N/A", "GPU-test, nan", "GPU-test, inf", "fail", "hang"):
            with self.subTest(value=value):
                self.counter.unlink(missing_ok=True)
                result = self.run_guard([value])
                self.assertEqual(result.returncode, 87, result.stderr)
                self.assertFalse(self.marker.exists())
        self.counter.unlink(missing_ok=True)
        result = self.run_guard(["GPU-first, 40", "GPU-different, 40"], workload=[sys.executable,"-c","import time; time.sleep(5)"])
        self.assertEqual(result.returncode, 87, result.stderr)

    def test_cannot_raise_limit(self):
        result = subprocess.run([sys.executable, str(GUARD), "--limit-c", "76", "--", "true"],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)

    def test_run_sh_cannot_bypass_hot_preflight(self):
        fake_redot = self.base / "redot"
        fake_redot.write_text(f"#!/bin/sh\ntouch '{self.marker}'\n")
        fake_redot.chmod(0o755)
        result = self.run_guard(["GPU-test, 75"], workload=[str(fake_redot)], launcher=True)
        self.assertEqual(result.returncode, 86, result.stderr)
        self.assertFalse(self.marker.exists())

    def test_signal_stops_owned_group(self):
        self.plan.write_text(json.dumps(["GPU-test, 40"]))
        process = subprocess.Popen(self.command(self.sleeper()), env=self.env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 3
            while not (self.base / "pids.json").exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue((self.base / "pids.json").exists())
            process.send_signal(signal.SIGTERM)
            self.assertEqual(process.wait(timeout=4), 143)
            self.assert_stopped()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    def test_run_sh_optional_log_records_preflight_and_exit(self):
        fake_redot = self.base / "redot"
        fake_redot.write_text(f"#!/bin/sh\ntouch '{self.marker}'\n")
        fake_redot.chmod(0o755)
        self.env["GPU_GUARD_LOG"] = str(self.log)
        result = self.run_guard(["GPU-test, 40"], workload=[str(fake_redot)], launcher=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [json.loads(line)["event"] for line in self.log.read_text().splitlines()]
        self.assertIn("preflight", events)
        self.assertIn("started", events)
        self.assertIn("exited", events)
        self.assertTrue(self.marker.exists())

    def test_killed_watchdog_kills_direct_workload(self):
        self.plan.write_text(json.dumps(["GPU-test, 40"]))
        workload = [sys.executable, "-c", f"import os,time; from pathlib import Path; Path({str(self.marker)!r}).write_text(str(os.getpid())); time.sleep(30)"]
        process = subprocess.Popen(self.command(workload), env=self.env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 3
            while not self.marker.exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue(self.marker.exists())
            pid = int(self.marker.read_text())
            process.kill()
            process.wait(timeout=3)
            time.sleep(.1)
            status = Path(f"/proc/{pid}/stat")
            self.assertTrue(not status.exists() or status.read_text().split(") ")[1][0] == "Z")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    unittest.main(verbosity=2)
