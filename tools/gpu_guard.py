#!/usr/bin/env python3
"""Run one owned experiment with a fail-closed NVIDIA temperature watchdog.

No driver settings, services or unrelated processes are changed. Linux only.
Use: python3 tools/gpu_guard.py -- command arg ...
"""

import argparse
import csv
import ctypes
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

MAX_C = 75.0
POLL_S = 0.5
QUERY_TIMEOUT_S = 2.0
STOP_GRACE_S = 0.5
THERMAL_EXIT = 86
TELEMETRY_EXIT = 87


class UnsafeGPU(Exception):
    pass


def temperatures():
    """Pin every UUID from preflight; a missing GPU is not a cool GPU."""
    try:
        query = subprocess.run(
            ["nvidia-smi", "--query-gpu=uuid,temperature.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=QUERY_TIMEOUT_S, check=True,
        )
        result = {}
        for row in csv.reader(query.stdout.splitlines()):
            if len(row) != 2 or not row[0].strip().startswith("GPU-"):
                raise ValueError("invalid GPU row")
            uuid, value = row[0].strip(), float(row[1].strip())
            if uuid in result or not math.isfinite(value) or not 0 <= value <= 150:
                raise ValueError("invalid GPU temperature/UUID")
            result[uuid] = value
        if not result:
            raise ValueError("empty GPU telemetry")
        return result
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        raise UnsafeGPU(f"telemetry unavailable: {type(error).__name__}") from error


def assess(readings, expected, limit):
    if set(readings) != expected:
        raise UnsafeGPU("GPU inventory changed or a GPU disappeared")
    return max(readings.values()) >= limit


def stop_group(process):
    # Stop the whole owned process group, including children that ignore TERM.
    # Do not reap the group leader before sending the final signal.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    time.sleep(STOP_GRACE_S)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit-c", type=float, default=MAX_C,
                        help="may lower, never raise, the 75 C ceiling")
    parser.add_argument("--log", type=Path, help="append JSONL samples/events")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not math.isfinite(args.limit_c) or not 0 < args.limit_c <= MAX_C:
        parser.error("supply a command and a limit in (0, 75] C")
    if not sys.platform.startswith("linux"):
        parser.error("this watchdog requires Linux process groups and parent-death signals")
    log = args.log.open("a", buffering=1) if args.log else None

    def event(kind, **fields):
        record = {"time": time.time(), "event": kind, **fields}
        if log:
            log.write(json.dumps(record) + "\n")
        if kind != "sample":
            print("GPU_GUARD " + json.dumps(record), file=sys.stderr, flush=True)

    process = None
    interrupted = 0

    def on_signal(signum, _frame):
        nonlocal interrupted
        interrupted = signum

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, on_signal)

    try:
        readings = temperatures()
        expected = set(readings)
        event("preflight", temperatures_c=readings, limit_c=args.limit_c)
        if assess(readings, expected, args.limit_c):
            event("refused_hot", temperatures_c=readings)
            return THERMAL_EXIT
        if interrupted:
            return 128 + interrupted
        guard_pid = os.getpid()
        libc = ctypes.CDLL(None, use_errno=True)

        def die_with_guard():
            # A hard-killed watchdog must not leave its direct workload running.
            if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
                raise OSError(ctypes.get_errno(), "PR_SET_PDEATHSIG")
            if os.getppid() != guard_pid:
                os.kill(os.getpid(), signal.SIGKILL)

        process = subprocess.Popen(command, start_new_session=True, preexec_fn=die_with_guard)
        # Arguments may contain tokens or private prompts. Never log them.
        event("started", pid=process.pid, executable=Path(command[0]).name, argc=len(command))
        while True:
            if interrupted:
                event("interrupted", signal=interrupted)
                return 128 + interrupted
            # Inspect without reaping: keep the process-group ID owned until
            # finally has killed any surviving descendants.
            status = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            if status is not None:
                result = status.si_status if status.si_code == os.CLD_EXITED else -status.si_status
                event("exited", returncode=result)
                return result if result >= 0 else 128 - result
            started = time.monotonic()
            readings = temperatures()
            event("sample", temperatures_c=readings)
            if assess(readings, expected, args.limit_c):
                event("thermal_stop", temperatures_c=readings, limit_c=args.limit_c)
                return THERMAL_EXIT
            time.sleep(max(0, POLL_S - (time.monotonic() - started)))
    except UnsafeGPU as error:
        event("telemetry_stop", reason=str(error))
        return TELEMETRY_EXIT
    except (OSError, subprocess.SubprocessError) as error:
        event("launch_or_log_error", reason=str(error))
        return TELEMETRY_EXIT
    finally:
        if process is not None:
            stop_group(process)
        if log:
            log.close()


if __name__ == "__main__":
    sys.exit(main())
