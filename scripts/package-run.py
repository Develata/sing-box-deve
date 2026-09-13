#!/usr/bin/env python3
"""Bound one package command, retaining its process group through TERM grace."""
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def database_unlocked():
    # Never unlink package locks. Keep both probes held until inspection ends.
    descriptors = []
    try:
        for path in ("/var/lib/dpkg/lock-frontend", "/var/lib/dpkg/lock"):
            fd = os.open(path, os.O_WRONLY | os.O_NOFOLLOW)
            descriptors.append(fd)
            fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    finally:
        for fd in descriptors:
            os.close(fd)


def run(seconds, grace, argv):
    interrupted = 0

    def interrupt(signum, _frame):
        nonlocal interrupted
        interrupted = signum

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, interrupt)
    process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, start_new_session=True)
    deadline = time.monotonic() + seconds
    rc = None
    while not interrupted and time.monotonic() < deadline:
        # WNOWAIT keeps our child PID reserved until group cleanup is finished.
        result = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        if result is not None:
            rc = result.si_status if result.si_code == os.CLD_EXITED else 128 + result.si_status
            if rc == 0 or not group_children(process.pid):
                return process.wait()
            break
        time.sleep(0.1)
    if rc is None:
        rc = 128 + interrupted if interrupted else 124
        print("[ERROR] Package command interrupted" if interrupted else
              "[ERROR] Package manager operation timed out", file=sys.stderr)
    # Signal only the session/group we created. Even when the parent exits on
    # TERM, its un-reaped identity prevents group-ID reuse during this grace.
    os.killpg(process.pid, signal.SIGTERM)
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        time.sleep(min(0.1, max(0, deadline - time.monotonic())))
    os.killpg(process.pid, signal.SIGKILL)
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        print("[ERROR] Package process remains after KILL; database needs attention", file=sys.stderr)
    return rc


def group_children(group):
    if not Path("/proc/self/stat").exists():
        return True  # Best-effort platforms still receive the full bounded grace.
    for directory in Path("/proc").iterdir():
        if not directory.name.isdecimal() or int(directory.name) == group:
            continue
        try:
            fields = (directory / "stat").read_text().rsplit(") ", 1)[1].split()
            if int(fields[2]) == group and fields[0] not in ("Z", "X"):
                return True
        except (FileNotFoundError, ProcessLookupError):
            continue
    return False


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["--check-dpkg-locks"]:
            database_unlocked()
            status = 0
        else:
            seconds, grace = map(int, sys.argv[1:3])
            if seconds <= 0 or grace <= 0 or len(sys.argv) < 4:
                raise ValueError("invalid package deadline/command")
            status = run(seconds, grace, sys.argv[3:])
        sys.exit(status if status >= 0 else 128 - status)
    except (OSError, ValueError, IndexError) as error:
        print(f"[ERROR] Package policy: {error}", file=sys.stderr)
        sys.exit(1)
