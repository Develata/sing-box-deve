#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'service.log'
    payload = bytes(range(256)) * 100
    subprocess.run([sys.executable, str(Path(__file__).with_name('bounded-log.py')), str(path), '1024'], input=payload, check=True)
    files = [Path(str(path) + '.2'), Path(str(path) + '.1'), path]
    assert all(p.stat().st_size <= 1024 for p in files)
    assert b''.join(p.read_bytes() for p in files) == payload[-3072:]
    # A second process start preserves the bound and the newest stream suffix.
    subprocess.run([sys.executable, str(Path(__file__).with_name('bounded-log.py')), str(path), '1024'], input=b'latest', check=True)
    assert path.read_bytes() == b'latest'
    assert len(list(Path(directory).iterdir())) == 3
print('[OK] continuous bounded log retention checks passed')
