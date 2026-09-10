#!/usr/bin/env python3
"""Adversarial archive boundary tests; never executes archive content."""
import sys
sys.dont_write_bytecode = True
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile

spec = importlib.util.spec_from_file_location("runtime_archive", Path(__file__).with_name("runtime-archive.py"))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    for index, (name, kind, size) in enumerate([
        ("../escape", tarfile.REGTYPE, 1),
        ("lib/../../escape", tarfile.REGTYPE, 1),
        ("/absolute", tarfile.REGTYPE, 1),
        ("lib/link", tarfile.SYMTYPE, 0),
        ("lib/hard", tarfile.LNKTYPE, 0),
        ("lib/fifo", tarfile.FIFOTYPE, 0),
        ("web-generator/app.js", tarfile.REGTYPE, 1),
        ("lib/huge", tarfile.REGTYPE, runtime.LIMIT_BYTES + 1),
    ]):
        archive = root / f"bad-{index}.tar.gz"
        member = tarfile.TarInfo(f"{runtime.PREFIX}/{name}")
        member.type, member.size, member.linkname = kind, size, "../../outside"
        # Header only is sufficient: guards must reject before reading a payload.
        import gzip
        with gzip.open(archive, "wb") as stream:
            stream.write(member.tobuf())
            stream.write(b"\0" * 1024)
        destination = root / f"stage-{index}"
        destination.mkdir()
        try:
            runtime.extract(archive, destination)
        except (ValueError, tarfile.TarError):
            pass
        else:
            raise AssertionError(f"unsafe member accepted: {name}")
    archive = root / "duplicate.tar.gz"
    with tarfile.open(archive, "w:gz") as stream:
        for _ in range(2):
            member = tarfile.TarInfo(f"{runtime.PREFIX}/version")
            member.size = 1
            stream.addfile(member, io.BytesIO(b"x"))
    destination = root / "duplicate"
    destination.mkdir()
    try:
        runtime.extract(archive, destination)
    except ValueError:
        pass
    else:
        raise AssertionError("duplicate member accepted")
    assert not (root / "escape").exists()
print("[OK] adversarial runtime archive checks passed")
