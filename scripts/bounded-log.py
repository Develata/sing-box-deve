#!/usr/bin/env python3
"""Drain a service pipe into three bounded log files; exit on pipe EOF."""
import os
from pathlib import Path
import sys


def run(path, limit):
    path = Path(path)
    limit = int(limit)
    if limit < 1:
        raise ValueError("log limit must be positive")
    for candidate in (path, Path(str(path) + ".1"), Path(str(path) + ".2")):
        if candidate.is_symlink():
            raise ValueError("refusing log symlink")
    output = None
    try:
        size = path.stat().st_size if path.exists() else 0
        output = path.open("ab", buffering=0)
        while block := os.read(0, 65536):
            while block:
                if size >= limit:
                    output.close()
                    previous = Path(str(path) + ".1")
                    if previous.exists():
                        previous.replace(str(path) + ".2")
                    path.replace(str(path) + ".1")
                    output = path.open("wb", buffering=0)
                    size = 0
                take = min(len(block), limit - size)
                output.write(block[:take])
                block = block[take:]
                size += take
    finally:
        if output is not None:
            output.close()


if __name__ == "__main__":
    try:
        run(*sys.argv[1:])
    except (OSError, ValueError, TypeError) as error:
        print(f"[ERROR] bounded log: {error}", file=sys.stderr)
        sys.exit(1)
